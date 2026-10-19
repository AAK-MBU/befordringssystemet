"""Service layer for bevilling-related business logic.

This module contains the main business logic for bevillinger, koerselsraekker,
hjaelpemidler, status calculation, and letter data retrieval.

The service layer sits between the API routers and the database models/views.

General responsibilities:

- Read bevilling data from SQL views
- Create and update bevillinger
- Create and update koerselsraekker
- Update many-to-many link tables
- Calculate and update bevilling status
- Validate business rules
- Prepare letter data for the letter-generation flow

The router should stay thin and delegate most logic to this service.
"""

import json
from datetime import date

from fastapi import HTTPException
from sqlalchemy import delete, select, text, update as sa_update
from sqlalchemy.orm import Session

from app.models.bevilling import (
    Bevilling,
    BevillingHjaelpemiddelLink,
    Koersel,
    KoerselKoerselstypeTillaegLink,
    KoerselUgedagLink,
)
from app.models.adresse import Adresse
from app.models.citizen import Elev, Sagsaktivitet, SagsaktivitetType
from app.models.lookup import (
    Befordringstype,
    PPRSagsbehandler,
    Sagsbehandler,
    Skolematrikel,
    Status,
    Ungdomsuddannelse,
)
from app.utils.afstandskriterie import (
    MIDLERTIDIG_KOERSEL,
    beregn_afstandskriterie_dato,
    beregn_afstandskriterie_klassetrin,
)
from app.utils.distance import walking_distance


class BevillingService:
    """Service class for bevilling-related operations.

    Args:
        db:
            SQLAlchemy database session.

    Notes:
        This service owns the transaction logic for write operations.
        Most create/update methods commit directly unless they receive
        commit=False from another service method.
    """

    def __init__(self, db: Session):
        """Initialize the service with a database session."""

        self.db = db


    def _get_aktivitetstype_id(self, type_kode: str) -> int | None:
        """Look up the SagsaktivitetType.type_id for a given type_kode."""
        if not hasattr(self, "_type_id_cache"):
            self._type_id_cache: dict[str, int | None] = {}
        if type_kode not in self._type_id_cache:
            self._type_id_cache[type_kode] = self.db.execute(
                select(SagsaktivitetType.type_id).where(
                    SagsaktivitetType.type_kode == type_kode
                )
            ).scalar_one_or_none()
        return self._type_id_cache[type_kode]

    def _log_event(
        self,
        cpr: str,
        type_kode: str,
        aktivitetstype: str,
        kommentar: str | None = None,
        relateret_bevilling_id: int | None = None,
        udfoert_af: str = "System",
    ) -> None:
        """Log a case event to Sagsaktivitet.

        Audit logging is best-effort: failures are swallowed so they never
        break the primary write operation.

        Args:
            type_kode: Machine-readable FK to SagsaktivitetType (e.g. "status_opdateret").
            aktivitetstype: Human-readable display label (e.g. "Status sat til Aktiv").
        """

        try:
            self.db.add(Sagsaktivitet(
                cpr=cpr,
                aktivitetstype=aktivitetstype,
                aktivitetstype_id=self._get_aktivitetstype_id(type_kode),
                kommentar=kommentar,
                udfoert_af=udfoert_af,
                relateret_bevilling_id=relateret_bevilling_id,
            ))
            self.db.commit()
        except Exception:
            self.db.rollback()


    def _get_sagsbehandler_name(self, sagsbehandler_id: int | None) -> str | None:
        """Look up a caseworker's display name by ID (None if unset/missing)."""

        if sagsbehandler_id is None:
            return None

        sb = self.db.get(Sagsbehandler, sagsbehandler_id)

        return sb.sagsbehandler_tekst if sb else None


    def _get_ppr_name(self, ppr_id: int | None) -> str | None:
        """Look up a PPR caseworker's display name by ID (None if unset/missing)."""

        if ppr_id is None:
            return None

        ppr = self.db.get(PPRSagsbehandler, ppr_id)

        return ppr.ppr_sagsbehandler_tekst if ppr else None


    def _get_status_result_for_bevilling(
        self,
        rows: list[dict],
        bevilling_id: int,
    ):
        """Find the status procedure result for one specific bevilling."""

        for row in rows:
            if int(row["bevilling_id"]) == bevilling_id:
                return row

        raise HTTPException(
            status_code=404,
            detail=f"Bevilling not found in status result: {bevilling_id}",
        )


    def _execute_recalculate_status_procedure(
        self,
        bevilling_id: int | None = None,
        today: date | None = None,
        dry_run: bool = False,
    ):
        """Run the SQL Server status recalculation procedure.

        Args:
            bevilling_id:
                Optional bevilling ID.

                If provided, only that bevilling is recalculated.
                If None, all bevillinger are recalculated.

            today:
                Optional test date.

                Normally this should be None, so SQL Server uses today's date.

            dry_run:
                If True, the procedure only shows what would happen.
                If False, the procedure updates Bevilling.status_id.

        Returns:
            A list of dictionaries returned by the stored procedure.
        """

        sql = text("""
            EXEC [befordring].[usp_recalculate_bevilling_status]
                @bevilling_id = :bevilling_id,
                @today = :today,
                @dry_run = :dry_run
        """)

        result = self.db.execute(
            sql,
            {
                "bevilling_id": bevilling_id,
                "today": today,
                "dry_run": int(dry_run),
            },
        )

        return self._rows_to_dicts(result)


    def _rows_to_dicts(self, result):
        """
        Convert SQLAlchemy result rows into normal dictionaries.
        """

        return [dict(row) for row in result.mappings().all()]


    def _to_date(self, value):
        """Normalize datetime-like values to date objects.

        Notes:
            SQL Server / SQLAlchemy may return either date or datetime objects
            depending on the column type and query. This helper makes date
            comparison logic more predictable.
        """

        if value is None:
            return None

        if hasattr(value, "date"):
            return value.date()

        return value


    def _validate_int_list(self, values: list[int], field_name: str):
        """
        Validate and de-duplicate a list of integer IDs.

        Notes:
            dict.fromkeys(...) is used as a simple way to remove duplicates
            while keeping the original order.
        """

        unique_values = list(dict.fromkeys(values))

        if any(not isinstance(value, int) for value in unique_values):
            raise HTTPException(
                status_code=400,
                detail=f"All {field_name} must be integers",
            )

        return unique_values


    def _validate_koerselsraekke_dates(self, data: dict):
        """Validate that gyldig_fra is not after gyldig_til.

        Notes:
            If one of the dates is missing, validation is skipped.
            This makes the helper usable for both create and partial update.
        """

        gyldig_fra = self._to_date(data.get("gyldig_fra"))
        gyldig_til = self._to_date(data.get("gyldig_til"))

        if gyldig_fra is None or gyldig_til is None:
            return

        if gyldig_fra > gyldig_til:
            raise HTTPException(
                status_code=400,
                detail={
                    "message": "Gyldig fra kan ikke være efter gyldig til",
                },
            )


    def get_status_id_by_text(self, status_text: str):
        """Get an active status ID from its text value."""

        statement = (
            select(Status.status_id)
            .where(Status.status_tekst == status_text)
            .where(Status.aktiv)
        )

        status_id = self.db.execute(statement).scalar_one_or_none()

        if status_id is None:
            raise HTTPException(
                status_code=500,
                detail=f"Status does not exist: {status_text}",
            )

        return int(status_id)

    def get_bevillinger(
        self,
        view_name: str,
        status: str | None = None,
        exclude_status: str | None = None,
        cpr: str | None = None,
        order_by: dict | None = None,
    ):
        """Get bevillinger from an allowed SQL view.

        Args:
            view_name:
                Name of the SQL view to query.

            status:
                Optional status text filter.

            exclude_status:
                Optional status text to exclude.

            cpr:
                Optional CPR filter.

            order_by:
                Optional sorting config.

                Example:
                    {
                        "key": "created_at",
                        "order_direction": "DESC",
                    }

        Returns:
            A list of bevilling dictionaries.

        Raises:
            HTTPException:
                400 if the requested view, order column, or order direction is
                not allowed.

        Notes:
            The view name and ORDER BY values cannot be parameterized like
            normal SQL values. Therefore they are validated against allow-lists
            before being inserted into the SQL string.
        """

        allowed_views = {
            "[befordring].[view_All_Bevillinger]",
            "[befordring].[view_All_Active_Bevillinger]",
            "[befordring].[view_Student_Bevillinger]",
            "[befordring].[view_New_Applications]",
        }

        if view_name not in allowed_views:
            raise HTTPException(
                status_code=400,
                detail=f"Invalid bevilling view: {view_name}",
            )

        sql = f"""
            SELECT
                *
            FROM
                {view_name}
            WHERE
                1 = 1
        """

        params = {}

        if status:
            sql += " AND status_tekst = :status"
            params["status"] = status

        if exclude_status:
            sql += " AND status_tekst <> :exclude_status"
            params["exclude_status"] = exclude_status

        if cpr:
            sql += " AND cpr_elev = :cpr"
            params["cpr"] = cpr

        if order_by:
            allowed_columns = {
                "status_tekst",
                "cpr_elev",
                "created_at",
                "updated_at",
            }

            allowed_directions = {
                "ASC",
                "DESC",
            }

            key = order_by.get("key")
            direction = order_by.get("order_direction", "ASC").upper()

            if key not in allowed_columns:
                raise HTTPException(
                    status_code=400,
                    detail="Invalid order_by column",
                )

            if direction not in allowed_directions:
                raise HTTPException(
                    status_code=400,
                    detail="Invalid order direction",
                )

            sql += f" ORDER BY {key} {direction}"

        result = self.db.execute(text(sql), params)

        return self._rows_to_dicts(result)


    def get_bevilling(self, bevilling_id: int):
        """Get one bevilling by ID.

        Args:
            bevilling_id:
                ID of the bevilling.

        Returns:
            A bevilling dictionary if found.
            Otherwise None.
        """

        sql = text("""
            SELECT
                *
            FROM
                [befordring].[view_All_Bevillinger]
            WHERE
                bevilling_id = :bevilling_id
        """)

        result = self.db.execute(
            sql,
            {"bevilling_id": bevilling_id},
        )

        records = self._rows_to_dicts(result)

        if not records:
            return None

        return records[0]


    def get_student_bevillinger(self, cpr: str):
        """Get all bevillinger connected to a citizen, with their kørselsrækker.

        Args:
            cpr:
                Citizen CPR.

        Returns:
            A list of bevillinger from view_Student_Bevillinger, each with a
            ``koerselsraekker`` key holding that bevilling's rows.

        Notes:
            Two statements for a student, never one per bevilling. Every caller
            wanted the rækker immediately and fetched them itself, one request
            per bevilling: the sag page did it on every load, and the
            Revurdering and Genbehandling worklists did it for every expanded
            row. Expanding 80 rows that way was roughly a hundred extra
            requests, each taking a connection out of a pool of thirty.

            Same shape as get_revurderinger builds, so a bevilling's rækker
            read identically wherever they come from. It does NOT repeat that
            query's join to Befordringstype: the view already exposes
            befordringstype_tekst, so vbk.* carries it. Selecting bt.* as well
            — which is what the copied-from query does — needs a join that is
            not here, and fails with "The multi-part identifier
            bt.befordringstype_tekst could not be bound".

            There is no per-bevilling endpoint any more. One existed for the
            conversion RPA, which is finished; with the frontend no longer
            fanning out, nothing was left calling it.
        """

        sql = text("""
            SELECT
                *
            FROM
                [befordring].[view_Student_Bevillinger]
            WHERE
                cpr = :cpr
            ORDER BY
                created_at DESC
        """)

        bevillinger = self._rows_to_dicts(self.db.execute(sql, {"cpr": cpr}))

        if not bevillinger:
            return []

        # Scoped by cpr rather than by the ids just read: one parameter instead
        # of a generated IN-list, and the join to Bevilling is needed anyway to
        # keep soft-deleted ones out.
        koersel_sql = text("""
            SELECT
                vbk.*,
                k.final
            FROM
                [befordring].[view_Bevilling_Koerselsraekker] vbk
            INNER JOIN
                [befordring].[Koersel] k
                ON k.koersel_id = vbk.koersel_id
                AND k.aktiv = 1
            INNER JOIN
                [befordring].[Bevilling] b
                ON b.bevilling_id = vbk.bevilling_id
                AND b.aktiv = 1
            WHERE
                b.cpr_elev = :cpr
            ORDER BY
                vbk.bevilling_id,
                vbk.gyldig_til DESC
        """)

        koersler = self._rows_to_dicts(self.db.execute(koersel_sql, {"cpr": cpr}))

        koersel_map: dict = {}

        for koersel in koersler:
            koersel_map.setdefault(koersel["bevilling_id"], []).append(koersel)

        for bevilling in bevillinger:
            bevilling["koerselsraekker"] = koersel_map.get(
                bevilling.get("bevilling_id"), []
            )

        return bevillinger


    def _next_loebenummer(self, cpr: str) -> int:
        """Return the next per-child bevilling number for `cpr`.

        Must be called inside the same transaction as the insert it numbers.

        The UPDLOCK, HOLDLOCK hint takes a key-range lock over this child's rows
        for the rest of the transaction, so two bevillinger created for the same
        child at the same moment cannot both read the same maximum. The range is
        scoped to the one cpr_elev, so creating bevillinger for *different*
        children never blocks — which is the normal case here, and the reason
        this is not a table-level lock.

        The unique index on (cpr_elev, loebenummer) is the backstop: if this
        lock is ever bypassed the second insert fails loudly rather than
        silently handing two bevillinger the same reference number.

        Soft-deleted rows are counted. Their number stays reserved, so the gap
        they leave remains visible and an undelete cannot collide.

        Args:
            cpr:
                CPR of the student the bevilling belongs to.

        Returns:
            1 for a child's first bevilling, otherwise highest existing + 1.
        """

        highest = self.db.execute(
            text(
                """
                SELECT MAX(loebenummer)
                FROM   befordring.Bevilling WITH (UPDLOCK, HOLDLOCK)
                WHERE  cpr_elev = :cpr
                """
            ),
            {"cpr": cpr},
        ).scalar()

        return (highest or 0) + 1


    def beregn_gaaafstand(
        self,
        adresse_id: str | None,
        matrikel_id: int | None,
        ungdomsuddannelse_id: int | None,
    ) -> float | None:
        """Walking distance in km from an address to a school, or None.

        Args:
            adresse_id:
                The bevilling's address.

            matrikel_id:
                The bevilling's skolematrikel, if it has one.

            ungdomsuddannelse_id:
                The bevilling's ungdomsuddannelse, if it has one instead.

        Returns:
            The distance rounded to one decimal, or None where it cannot be
            measured — no address, no school, either of them without
            coordinates, or OpenRouteService failing.

        Notes:
            Pure: it reads, measures and returns. It does NOT load a
            bevilling, assign to one, or commit — callers do that, inside
            whatever transaction they already have.

            That is what lets update_bevilling use it. A measurement there has
            to ride along in the caller's single commit; a helper that
            committed for itself would land the address change, the school
            change and half the audit log mid-flight, and a later failure
            would roll back only what came after it.

            Three of the four callers have no bevilling to load anyway:
            create_bevilling has no row yet, update_bevilling already holds
            one, and GET /bevilling/gaaafstand is asked about a pair that does
            not exist. genberegn_gaaafstand is the only one that starts from
            an id.

            Returns None rather than raising, and every caller writes that
            None straight onto the bevilling. A distance is a convenience for
            the caseworker, and an unreachable routing API must never be the
            reason a save fails or an application cannot be registered. The
            card shows "ikke beregnet" and offers the button again.

            foot-walking, matching Elev.skoleafstand: the afstandskriterie is
            about how far the child would have to walk, and the two numbers
            sit side by side in the UI. One decimal for the same reason —
            citizen_service.genberegn_skole rounds there too, and two sources
            for one kind of number must agree.
        """

        if adresse_id is None:
            return None

        adresse = self.db.get(Adresse, adresse_id)

        if adresse is None or adresse.latitude is None or adresse.longitude is None:
            return None

        if matrikel_id is not None:
            skole = self.db.get(Skolematrikel, matrikel_id)
        elif ungdomsuddannelse_id is not None:
            skole = self.db.get(Ungdomsuddannelse, ungdomsuddannelse_id)
        else:
            return None

        if skole is None or skole.latitude is None or skole.longitude is None:
            return None

        try:
            distance_km, _ = walking_distance(
                adresse.latitude,
                adresse.longitude,
                skole.latitude,
                skole.longitude,
            )
        except Exception:
            return None

        return round(distance_km, 1)


    def genberegn_gaaafstand(
        self,
        bevilling_id: int,
        only_if_missing: bool = False,
    ) -> dict:
        """Re-measure one bevilling's walking distance and store it.

        Args:
            bevilling_id:
                The bevilling to measure.

            only_if_missing:
                Where True, a bevilling that already has a distance is left
                untouched and its stored value returned. Letter generation
                passes True; the button does not.

        Returns:
            {"gaaafstand_km": float | None, "besked": str | None}. besked
            names what stopped a measurement and is None on success.

        Raises:
            HTTPException 404:
                Where the bevilling does not exist.

        Notes:
            This is the refresh button on the bevilling card, and nothing
            else. It is NOT part of editing a bevilling: update_bevilling
            re-measures on its own whenever the address or school changes,
            using beregn_gaaafstand inside its own transaction. Changing an
            address in the form already does the right thing without ever
            reaching this method.

            It commits for itself because it IS its own user action — a click
            with nothing else to save.

            It exists for the two cases where nobody is editing anything:

              - A bevilling from before migration 030. Nothing was
                backfilled, so every older row is NULL.
              - One whose measurement failed at the time, because
                OpenRouteService was unreachable.

            Neither can be fixed by opening the bevilling and saving it: the
            automatic re-measurement is gated on the address/school pair
            actually CHANGING, so an unchanged pair saves without measuring
            anything. Without this button those rows would stay NULL for ever.

            only_if_missing exists for the one other caller: letter
            generation, which prints the distance and so has to fill a NULL
            before building the payload. It must NOT re-measure a value that
            is already there — ORS being unreachable at that moment would
            replace a good figure with NULL and print a blank in an
            afgørelsesbrev, and it would also overwrite a number the
            caseworker had just refreshed and checked.

            Writes None as readily as a number. Where the address or school
            has since lost its coordinates, "ikke beregnet" is the honest
            answer — a distance left over from a previous address reads as
            current.

            Deliberately does NOT touch afstandskriterie_dato or
            _klassetrin. Once saved those are a caseworker's decision, and a
            recalculate button should not move a criterion date underneath
            them because a routing API answered differently today. The create
            and edit forms recompute both from the new distance when the
            caseworker next saves.
        """

        bevilling = self.db.get(Bevilling, bevilling_id)

        if bevilling is None:
            raise HTTPException(
                status_code=404,
                detail=f"Bevilling not found: {bevilling_id}",
            )

        if only_if_missing and bevilling.gaaafstand_km is not None:
            return {"gaaafstand_km": bevilling.gaaafstand_km, "besked": None}

        gaaafstand = self.beregn_gaaafstand(
            bevilling.adresse_id,
            bevilling.matrikel_id,
            bevilling.ungdomsuddannelse_id,
        )

        bevilling.gaaafstand_km = gaaafstand
        self.db.commit()

        if gaaafstand is not None:
            return {"gaaafstand_km": gaaafstand, "besked": None}

        if bevilling.matrikel_id is None and bevilling.ungdomsuddannelse_id is None:
            besked = "Bevillingen har ingen skole, så afstanden kan ikke beregnes."
        else:
            besked = (
                "Afstanden kunne ikke beregnes. Tjek at både adressen og "
                "skolen har koordinater."
            )

        return {"gaaafstand_km": None, "besked": besked}


    def _apply_afstandskriterie_defaults(
        self,
        cpr: str,
        new_bevilling_data: dict,
    ) -> None:
        """Fill in afstandskriterie_dato / _klassetrin where the caller sent none.

        Both are derived from the student's elevklassetrin and the bevilling's
        own walking distance — see app/utils/afstandskriterie.py, which mirrors
        the TypeScript the create and edit forms use. Mutates
        new_bevilling_data in place.

        Silent no-op in four cases, all of them correct rather than a failure:
        the caller supplied the field (their value wins), the bevilling is
        midlertidig kørsel (granted on a different basis, so the fields do not
        apply and the form hides them), the student has no klassetrin that maps
        to a band — an ungdomsuddannelse elev, or an Elev row the nightly
        import has not filled in yet — or the distance could not be measured.

        Notes:
            The DISTANCE comes from this bevilling, the KLASSETRIN from the
            elev. That split is deliberate.

            These two fields answer "how long does this situation keep meeting
            the distance criterion", and the situation is the one the bevilling
            describes: its address and its school. Elev.skoleafstand measures
            the child's current folkeregisteradresse against the school their
            current data resolves to, and an application that follows a move or
            a referral is precisely the case where those are a different pair.
            Deriving the criterion from them answered a question nobody asked.

            Klassetrin has no such problem — a child is in one class, and the
            Elev row is the only place it is recorded.

            Where the distance could not be measured both fields stay NULL,
            which is the same outcome as before for a student whose
            skoleafstand was missing. A caseworker fills them in by hand, or
            presses recalculate and saves again.
        """

        if new_bevilling_data.get("ansoegningstype") == MIDLERTIDIG_KOERSEL:
            return

        has_dato = new_bevilling_data.get("afstandskriterie_dato") is not None
        has_klassetrin = (
            new_bevilling_data.get("afstandskriterie_klassetrin") is not None
        )

        if has_dato and has_klassetrin:
            return

        elev = self.db.get(Elev, cpr)

        if elev is None:
            return

        # Already measured by the caller of this method, so no second routing
        # call. None is a legitimate value and simply leaves both fields unset.
        gaaafstand = new_bevilling_data.get("gaaafstand_km")

        if not has_klassetrin:
            klassetrin = beregn_afstandskriterie_klassetrin(
                elev.elevklassetrin, gaaafstand
            )

            if klassetrin is not None:
                new_bevilling_data["afstandskriterie_klassetrin"] = klassetrin

        if not has_dato:
            dato = beregn_afstandskriterie_dato(
                elev.elevklassetrin, gaaafstand
            )

            if dato is not None:
                new_bevilling_data["afstandskriterie_dato"] = dato

    def create_bevilling(
        self,
        cpr: str,
        new_bevilling_data: dict,
        status_text: str = "Ny",
        udfoert_af: str = "System",
    ):
        """Create a new bevilling.

        Args:
            cpr:
                Citizen CPR.

            new_bevilling_data:
                Dictionary with fields for the Bevilling model.

                May optionally contain hjaelpemiddel_ids. These are removed
                from the dictionary before creating the Bevilling object,
                because they belong in a link table.

            status_text:
                Initial status text. Defaults to "Ny".

        Returns:
            Dictionary containing created bevilling ID, status text, and row
            count.

        Notes:
            This method manages its own transaction.

            self.db.flush() is used before committing so SQLAlchemy generates
            the new bevilling_id. That ID is needed when inserting rows in the
            hjaelpemiddel link table.
        """

        # hjaelpemiddel_ids are not columns on Bevilling itself.
        # They are handled separately through the link table.
        hjaelpemiddel_ids = new_bevilling_data.pop("hjaelpemiddel_ids", [])

        # Validate required fields before attempting a DB insert.
        # The schema allows None for all fields so we check here and return
        # a clear 422 instead of letting the DB raise a constraint violation.
        required_fields = {
            "adresse_id": "Adresse for bevilling",
        }

        missing = [
            label
            for field, label in required_fields.items()
            if not new_bevilling_data.get(field)
        ]

        if missing:
            raise HTTPException(
                status_code=422,
                detail={
                    "message": f"Udfyld venligst følgende felter: {', '.join(missing)}",
                },
            )

        # Measure the bevilling's own address-to-school walking distance, so
        # the afstandskriterie below is derived from THIS application rather
        # than from the child's current stamdata. Returns None on any failure
        # — a routing API being down must not stop an application being
        # registered — and None simply leaves the criterion fields unset.
        new_bevilling_data["gaaafstand_km"] = self.beregn_gaaafstand(
            new_bevilling_data.get("adresse_id"),
            new_bevilling_data.get("matrikel_id"),
            new_bevilling_data.get("ungdomsuddannelse_id"),
        )

        # Derive the afstandskriterie fields the caller did not send.
        #
        # The create/edit form derives these in the browser so a caseworker can
        # see and override the suggestion before saving, which covers every
        # bevilling made through the UI. A bevilling posted straight to the API
        # — the conversion RPA does exactly that — passes through no form, and
        # both fields were left NULL until someone opened the bevilling for
        # editing and saved it again.
        #
        # Only fills what is absent: a value the caller sent was chosen
        # deliberately and is never overwritten.
        self._apply_afstandskriterie_defaults(cpr, new_bevilling_data)

        try:
            bevilling = Bevilling(
                **new_bevilling_data,
                cpr_elev=cpr,
                status_id=self.get_status_id_by_text(status_text),
                aktiv=True,
                # Numbered inside this transaction so a concurrent create for
                # the same child cannot claim the same number.
                loebenummer=self._next_loebenummer(cpr),
                created_by="system",
                updated_by="system",
            )

            self.db.add(bevilling)

            # Flush so bevilling.bevilling_id is available before commit.
            self.db.flush()

            if hjaelpemiddel_ids:
                self.update_bevilling_hjaelpemidler(
                    bevilling_id=bevilling.bevilling_id,
                    hjaelpemiddel_ids=hjaelpemiddel_ids,
                    commit=False,
                )

            status_result = self.recalculate_bevilling_status(
                bevilling_id=bevilling.bevilling_id,
                commit=False,
            )

            self.db.commit()
            self.db.refresh(bevilling)

            result = {
                "bevilling_id": bevilling.bevilling_id,
                "loebenummer": bevilling.loebenummer,
                "status_text": status_result["status_text"],
                "status_reason": status_result.get("status_reason"),
                "rows_inserted": 1,
                "status": status_result,
            }

        except Exception:
            self.db.rollback()
            raise

        self._log_event(
            cpr=cpr,
            type_kode="bevilling_oprettet",
            aktivitetstype="Bevilling oprettet",
            kommentar=(
                f"Bevilling {bevilling.loebenummer} "
                f"(ID: {bevilling.bevilling_id}) — Status: Ny"
            ),
            relateret_bevilling_id=bevilling.bevilling_id,
            udfoert_af=udfoert_af,
        )

        return result


    def create_koerselsraekke(
        self,
        bevilling_id: int,
        new_koerselsraekke_data: dict,
        udfoert_af: str = "System",
    ):
        """Create a new koerselsraekke for a bevilling.

        Args:
            bevilling_id:
                ID of the bevilling the row belongs to.

            new_koerselsraekke_data:
                Dictionary with fields for the Koersel model.

                May optionally contain:
                - tillaeg_ids
                - dag_ids

        Returns:
            Dictionary containing created koersel_id and row count.

        Notes:
            This method also recalculates the bevilling status after creating
            the koerselsraekke.

            The link tables for tillaeg and dage are updated inside the same
            transaction by passing commit=False.
        """

        # These values belong to link tables, not directly on the Koersel model.
        tillaeg_ids = new_koerselsraekke_data.pop("tillaeg_ids", [])
        dag_ids = new_koerselsraekke_data.pop("dag_ids", [])

        self._validate_koerselsraekke_dates(new_koerselsraekke_data)

        bevilling = self.db.get(Bevilling, bevilling_id)
        if bevilling is None:
            raise HTTPException(
                status_code=404,
                detail=f"Bevilling not found: {bevilling_id}",
            )
        cpr = bevilling.cpr_elev

        try:
            koerselsraekke_values = {
                **new_koerselsraekke_data,
                "bevilling_id": bevilling_id,
                "kommentar": new_koerselsraekke_data.get("kommentar") or "",
                "final": new_koerselsraekke_data.get("final") or False,
            }

            koersel = Koersel(**koerselsraekke_values)

            self.db.add(koersel)

            # Flush so koersel.koersel_id is available for link-table inserts.
            self.db.flush()

            if tillaeg_ids:
                self.update_koerselsraekke_tillaeg(
                    koersel_id=koersel.koersel_id,
                    tillaeg_ids=tillaeg_ids,
                    commit=False,
                )

            if dag_ids:
                self.update_koerselsraekke_dage(
                    koersel_id=koersel.koersel_id,
                    dag_ids=dag_ids,
                    commit=False,
                )

            status_result = self.recalculate_bevilling_status(
                bevilling_id=bevilling_id,
                commit=False,
            )

            self.db.commit()
            self.db.refresh(koersel)

            result = {
                "koersel_id": koersel.koersel_id,
                "rows_inserted": 1,
                "status": status_result,
            }

        except Exception:
            self.db.rollback()
            raise

        self._log_event(
            cpr=cpr,
            type_kode="koerselsraekke_oprettet",
            aktivitetstype="Kørselsrække oprettet",
            kommentar=f"Koersel ID: {koersel.koersel_id} — {koersel.gyldig_fra} til {koersel.gyldig_til}",
            relateret_bevilling_id=bevilling_id,
            udfoert_af=udfoert_af,
        )

        return result


    def update_bevilling(self, bevilling_id: int, bevilling_data: dict, udfoert_af: str = "System"):
        """Update an existing bevilling.

        Args:
            bevilling_id:
                ID of the bevilling to update.

            bevilling_data:
                Dictionary containing only the fields that should be updated.

        Returns:
            Dictionary containing row count and updated field names.

        Raises:
            HTTPException:
                400 if no fields were provided.
                404 if the bevilling does not exist.

        Notes:
            After updating the bevilling, the status is recalculated because
            fields such as dates, sagsbehandler, or related values may affect
            the current status.
        """

        reset_status = bevilling_data.pop("reset_status", False)

        if not bevilling_data and not reset_status:
            raise HTTPException(
                status_code=400,
                detail="No fields provided for update",
            )

        bevilling = self.db.get(Bevilling, bevilling_id)

        if bevilling is None:
            raise HTTPException(
                status_code=404,
                detail=f"Bevilling not found: {bevilling_id}",
            )

        # Capture the fields we audit BEFORE mutating so _log_bevilling_update_events
        # can detect what actually changed.
        cpr = bevilling.cpr_elev
        old_values = {
            "sagsbehandler_id": bevilling.sagsbehandler_id,
            "ppr_sagsbehandler_id": bevilling.ppr_sagsbehandler_id,
            "revurderet_af_ppr": bevilling.revurderet_af_ppr,
            "revurderet_af_br": bevilling.revurderet_af_br,
            # Captured before reset_status can overwrite it, so the status log
            # only fires when the status genuinely changed from the user's view.
            "status_id": bevilling.status_id,
        }

        ophoert_status_id = self.get_status_id_by_text("Ophørt")
        was_ophoert = bevilling.status_id == ophoert_status_id

        # Afslag gets the same treatment as Ophørt, and for the same reason:
        # usp_recalculate_bevilling_status preserves both statuses as-is
        # (see its CASE on 'afslag', 'ophørt'), so the recalculation can report
        # rows_updated = 0 and the generic status_opdateret log branch never
        # fires. Without a dedicated event the transition leaves no trace.
        afslag_status_id = self.get_status_id_by_text("Afslag")
        was_afslag = bevilling.status_id == afslag_status_id

        # Locking cascades to the kørselsrækker, so the pre-state is needed to
        # fire that only on the false -> true transition.
        was_final = bevilling.final

        # Signing off the pending work releases whoever was handling it. Both
        # captured before mutating, so the release fires on the TRANSITION and
        # not on every later save of an already-signed-off bevilling — which
        # would wipe a fresh assignment if the case came back.
        was_revurderet_af_br = bevilling.revurderet_af_br
        was_genbehandling_haandteret = bevilling.genbehandling_haandteret

        # The genbehandling mismatch compares the bevilling against the elev, so
        # a sign-off acknowledges that specific PAIR. Captured before mutating so
        # the block below can tell whether the bevilling half of it moved.
        gb_matrikel_before = bevilling.matrikel_id
        gb_adresse_before = bevilling.adresse_id

        # The three inputs to gaaafstand_km. Captured before mutating so the
        # distance is only re-measured when one of them actually moved — an
        # OpenRouteService call on every save of an unrelated field would be
        # a request per keystroke-correction, for an unchanged answer.
        afstand_input_before = (
            bevilling.adresse_id,
            bevilling.matrikel_id,
            bevilling.ungdomsuddannelse_id,
        )

        try:
            for field_name, value in bevilling_data.items():
                setattr(bevilling, field_name, value)

            afstand_input_after = (
                bevilling.adresse_id,
                bevilling.matrikel_id,
                bevilling.ungdomsuddannelse_id,
            )

            if afstand_input_after != afstand_input_before:
                # Assigned, not committed: this rides along in the single
                # commit at the end of this method, so a later failure rolls
                # the distance back with everything else. This is the whole
                # reason beregn_gaaafstand is a pure function rather than part
                # of genberegn_gaaafstand, which commits for itself.
                #
                # Overwrites whatever was there, including with None. A
                # bevilling moved to an address or school we cannot measure
                # must not keep showing the distance to the old one — a stale
                # number reads as current and is worse than none.
                bevilling.gaaafstand_km = self.beregn_gaaafstand(*afstand_input_after)

            if reset_status:
                # Setting to "Ny" before the SP runs removes Afslag/Ophørt
                # protection so the SP can freely recalculate the correct status.
                bevilling.status_id = self.get_status_id_by_text("Ny")

            # Ending a bevilling is a case-processing act: it is handled today,
            # and there is nothing left to reassess.
            #
            # Deliberately a TRANSITION, not "status is Ophørt". Firing on every
            # save of an already-ended bevilling would overwrite the real
            # processing date with today's every time someone corrected a typo.
            #
            # Only revurderingsdato is cleared here. The `revurdering` flag is
            # owned by usp_recalculate_bevilling_status, which computes
            # needs_revurdering = 0 for any bevilling whose status is Ophørt —
            # the recalculation below therefore clears the flag on its own, and
            # writing it here would just be overwritten.
            ophoert_transition = (
                not was_ophoert and bevilling.status_id == ophoert_status_id
            )

            afslag_transition = (
                not was_afslag and bevilling.status_id == afslag_status_id
            )

            if ophoert_transition:
                cleared_revurderingsdato = bevilling.revurderingsdato
                bevilling.sagsbehandlingsdato = date.today()
                bevilling.revurderingsdato = None

            # Refusing a bevilling is a case-processing act in the same way
            # ending one is: it is handled today, and there is nothing left to
            # reassess. Mirrors the Ophørt block above, including being a
            # TRANSITION rather than "status is Afslag" — see its comment.
            if afslag_transition:
                afslag_cleared_revurderingsdato = bevilling.revurderingsdato
                bevilling.sagsbehandlingsdato = date.today()
                bevilling.revurderingsdato = None

            # Genbehandling sign-off: snapshot the elev values the caseworker
            # actually reviewed, so the SP can tell a NEW drift apart from the
            # one that was just acknowledged.
            if bevilling_data.get("genbehandling_haandteret") is True:
                elev = self.db.get(Elev, bevilling.cpr_elev)

                if not elev:
                    raise HTTPException(
                        status_code=500,
                        detail="Kan ikke registrere genbehandling: elev ikke fundet i stamdata.",
                    )

                # Writing NULL for a dimension is safe only when the SP would not
                # flag it — but if both are NULL no snapshot can be written at
                # all, and the SP's IS NULL re-flag condition would fire on the
                # very next run and silently undo the sign-off.
                if elev.adresse_id is not None:
                    bevilling.genbehandling_haandteret_adresse_id = elev.adresse_id

                if elev.skolekode is not None:
                    bevilling.genbehandling_haandteret_skolekode = elev.skolekode

                if elev.adresse_id is None and elev.skolekode is None:
                    raise HTTPException(
                        status_code=500,
                        detail=(
                            "Kan ikke registrere genbehandling: eleven har hverken "
                            "adresse eller skolekode registreret, så kvitteringen "
                            "kan ikke gemmes."
                        ),
                    )

            # Changing the bevilling's school or address invalidates an earlier
            # genbehandling sign-off: the caseworker approved the old pairing,
            # not this one.
            #
            # usp_recalculate_bevilling_status only re-flags when the ELEV side
            # drifts from the snapshot (it has no record of the bevilling side),
            # so without this a school changed after sign-off would never
            # re-enter genbehandling. Clearing the snapshot makes the SP's
            # "... IS NULL" entry condition fire on the recalculation below.
            #
            # update_bevilling is the only path that writes these two fields on
            # an existing bevilling — os2forms sets them at creation only.
            if (
                bevilling.matrikel_id != gb_matrikel_before
                or bevilling.adresse_id != gb_adresse_before
            ):
                bevilling.genbehandling_haandteret = None
                bevilling.genbehandling_haandteret_adresse_id = None
                bevilling.genbehandling_haandteret_skolekode = None

            # Only the "who has it right now" answer is retired. The
            # bevilling's own sagsbehandler_id / ppr_sagsbehandler_id were
            # never touched by the assignment in the first place.
            if (
                bevilling.revurderet_af_br is True and not was_revurderet_af_br
            ) or (
                bevilling.genbehandling_haandteret is True
                and not was_genbehandling_haandteret
            ):
                bevilling.ansvarlig_sagsbehandler_id = None
                bevilling.ansvarlig_ppr_sagsbehandler_id = None

            bevilling.updated_by = "frontend"

            self.db.flush()

            status_result = self.recalculate_bevilling_status(
                bevilling_id=bevilling_id,
                commit=False,
            )

            self.db.commit()

            result = {
                "rows_updated": 1,
                "updated_fields": list(bevilling_data.keys()),
                "status": status_result,
            }

        except Exception:
            self.db.rollback()
            raise

        # Locking the bevilling cascades to its kørselsrækker, so both levels
        # settle together. Only on the false -> true transition, and only
        # one way: unlocking the bevilling deliberately does NOT unlock the
        # rækker, because a letter has been written against them.
        #
        # After the commit rather than inside it: lock_koerselsraekker commits
        # for itself, and calling it mid-transaction would land the status
        # change and half the audit trail early.
        if not was_final and bevilling_data.get("final") is True:
            self.lock_koerselsraekker(bevilling_id)

        self._log_bevilling_update_events(
            cpr, bevilling_id, bevilling_data, old_values, status_result, udfoert_af
        )

        # Logged explicitly rather than left to _log_bevilling_update_events:
        # that only fires when the status SP reports a changed row, and setting
        # the status to Ophørt by hand can leave the SP with nothing to change.
        # Clearing revurderingsdato discards a date nobody can recover, so it
        # should be visible in the sagsforløb either way.
        if ophoert_transition:
            self._log_event(
                cpr,
                type_kode="bevilling_ophoert",
                aktivitetstype="Bevilling sat til Ophørt",
                kommentar=(
                    "Sagsbehandlingsdato sat til i dag"
                    + (
                        f" — revurderingsdato ({cleared_revurderingsdato}) blev fjernet"
                        if cleared_revurderingsdato
                        else ""
                    )
                ),
                relateret_bevilling_id=bevilling_id,
                udfoert_af=udfoert_af,
            )

        if afslag_transition:
            self._log_event(
                cpr,
                type_kode="bevilling_afslag",
                aktivitetstype="Bevilling sat til Afslag",
                kommentar=(
                    "Sagsbehandlingsdato sat til i dag"
                    + (
                        f" — revurderingsdato ({afslag_cleared_revurderingsdato}) blev fjernet"
                        if afslag_cleared_revurderingsdato
                        else ""
                    )
                ),
                relateret_bevilling_id=bevilling_id,
                udfoert_af=udfoert_af,
            )

        return result


    _STATUS_KOMMENTAR: dict[str, str] = {
        "Påbegyndt": "Sagsbehandler tilføjet",
        "Aktiv": "Bevillingsperioden er startet",
        "Kommende": "Bevillingsperioden er endnu ikke startet",
        "Udløbet": "Bevillingsperioden er udløbet",
    }

    def _log_bevilling_update_events(
        self,
        cpr: str,
        bevilling_id: int,
        new_data: dict,
        old_values: dict,
        status_result: dict,
        udfoert_af: str = "System",
    ) -> None:
        """Emit Sagsaktivitet events for the meaningful changes in an update.

        Logs caseworker/PPR reassignments, PPR/BR revurdering toggles, and
        status transitions. Each event is only logged when the value actually
        changed relative to old_values.
        """

        if "sagsbehandler_id" in new_data and new_data["sagsbehandler_id"] != old_values["sagsbehandler_id"]:
            name = self._get_sagsbehandler_name(new_data["sagsbehandler_id"])
            self._log_event(
                cpr,
                type_kode="sagsbehandler_opdateret",
                aktivitetstype="Sagsbehandler opdateret",
                kommentar=f"Sagsbehandler sat til {name}" if name else None,
                relateret_bevilling_id=bevilling_id,
                udfoert_af=udfoert_af,
            )

        if "ppr_sagsbehandler_id" in new_data and new_data["ppr_sagsbehandler_id"] != old_values["ppr_sagsbehandler_id"]:
            name = self._get_ppr_name(new_data["ppr_sagsbehandler_id"])
            self._log_event(
                cpr,
                type_kode="ppr_ansvarlig_opdateret",
                aktivitetstype="PPR ansvarlig opdateret",
                kommentar=f"PPR ansvarlig sat til {name}" if name else None,
                relateret_bevilling_id=bevilling_id,
                udfoert_af=udfoert_af,
            )

        if "revurderet_af_ppr" in new_data and new_data["revurderet_af_ppr"] != old_values["revurderet_af_ppr"]:
            is_set = new_data["revurderet_af_ppr"]
            self._log_event(
                cpr,
                type_kode="ppr_revurderet" if is_set else "ppr_revurderet_fjernet",
                aktivitetstype="PPR Revurderet" if is_set else "PPR revurderet fjernet",
                relateret_bevilling_id=bevilling_id,
                udfoert_af=udfoert_af,
            )

        if "revurderet_af_br" in new_data and new_data["revurderet_af_br"] != old_values["revurderet_af_br"]:
            is_set = new_data["revurderet_af_br"]
            self._log_event(
                cpr,
                type_kode="br_revurderet" if is_set else "br_revurderet_fjernet",
                aktivitetstype="BR Revurderet" if is_set else "BR revurderet fjernet",
                relateret_bevilling_id=bevilling_id,
                udfoert_af=udfoert_af,
            )

        # Only log a status event when the status actually changed from what it
        # was before this update. When reset_status=True temporarily sets the DB
        # to "Ny", the SP always reports rows_updated=1 even if the real status
        # stays the same (e.g. Aktiv → reset to Ny → SP recalculates Aktiv).
        # Comparing against old_values["status_id"] catches that case.
        sp_changed = status_result.get("rows_updated", 0) > 0
        real_change = status_result.get("status_id") != old_values.get("status_id")
        if sp_changed and real_change:
            new_status = status_result["status_text"]
            self._log_event(
                cpr,
                type_kode="status_opdateret",
                aktivitetstype=f"Status sat til {new_status}",
                kommentar=status_result.get("status_reason") or self._STATUS_KOMMENTAR.get(new_status),
                relateret_bevilling_id=bevilling_id,
                udfoert_af=udfoert_af,
            )


    def set_sagsbehandlingsdato(
        self,
        bevilling_id: int,
        on_date: date | None = None,
    ) -> date:
        """Stamp the bevilling's sagsbehandlingsdato.

        Called when a caseworker creates a letter: the case is considered
        processed on the day the decision letter is generated, so the date is
        set automatically (defaults to today).

        The status engine does not read sagsbehandlingsdato, so this does NOT
        trigger a status recalculation.

        Args:
            bevilling_id:
                ID of the bevilling to stamp.
            on_date:
                Date to set. Defaults to today when omitted.

        Returns:
            The date that was written.

        Raises:
            HTTPException:
                404 if the bevilling does not exist.
        """

        bevilling = self.db.get(Bevilling, bevilling_id)

        if bevilling is None:
            raise HTTPException(
                status_code=404,
                detail=f"Bevilling not found: {bevilling_id}",
            )

        stamped = on_date or date.today()

        bevilling.sagsbehandlingsdato = stamped
        bevilling.updated_by = "letter_engine"

        self.db.commit()

        return stamped


    def lock_koerselsraekker(self, bevilling_id: int) -> int:
        """Lock every open kørselsrække on a bevilling.

        Called when a caseworker creates a decision letter: the letter states
        the kørsler that were granted, so those rows should no longer be edited
        casually afterwards. Locking is the same `final` flag the lock button on
        each row sets, applied to the whole bevilling at once.

        Already-locked rows are left alone — the WHERE clause skips them, so a
        second letter on the same bevilling is a no-op rather than a pointless
        rewrite. Soft-deleted rows are skipped too: they are invisible
        everywhere else, so locking them would mean nothing.

        Note that `final` does not make a row read-only. The UI still allows
        editing a locked row behind a confirmation, and update_koerselsraekke
        deliberately has no `final` guard. The flag marks a row as settled, it
        does not freeze it.

        Args:
            bevilling_id:
                ID of the bevilling whose kørselsrækker should be locked.

        Returns:
            The number of rows that were newly locked. Zero is a normal
            outcome: the bevilling may have no kørselsrækker, or they may all
            be locked already.
        """

        # NB: use `== True` / `== False` (not `.is_(...)`) — on SQL Server
        # `.is_(True)` renders as `aktiv IS 1`, which is invalid T-SQL (IS only
        # allows NULL). Same reason as in part_service.get_parts.
        statement = (
            sa_update(Koersel)
            .where(
                Koersel.bevilling_id == bevilling_id,
                Koersel.aktiv == True,  # noqa: E712
                Koersel.final == False,  # noqa: E712
            )
            .values(final=True)
        )

        result = self.db.execute(statement)

        self.db.commit()

        return result.rowcount


    def lock_bevilling(self, bevilling_id: int) -> bool:
        """Lock a bevilling, mirroring lock_koerselsraekker one level up.

        Called when a decision letter is created: the letter states what was
        granted, so the bevilling is settled alongside its kørselsrækker.

        Sets the flag directly rather than going through update_bevilling,
        which would also run usp_recalculate_bevilling_status. Creating a
        letter is not a reason to recalculate a status, and the paired
        lock_koerselsraekker does not either. The *manual* lock and unlock do go
        through update_bevilling, exactly as the manual kørselsrække lock goes
        through update_koerselsraekke.

        Args:
            bevilling_id:
                ID of the bevilling to lock.

        Returns:
            True if this call locked it, False if it was already locked. A
            missing bevilling also returns False rather than raising — the
            caller in create_letter has already 404'd on it via
            set_sagsbehandlingsdato.
        """

        bevilling = self.db.get(Bevilling, bevilling_id)

        if bevilling is None or bevilling.final:
            return False

        bevilling.final = True

        self.db.commit()

        return True


    def update_koerselsraekke(
        self,
        koersel_id: int,
        koerselsraekke_data: dict,
        udfoert_af: str = "System",
    ):
        """Update an existing koerselsraekke.

        Args:
            koersel_id:
                ID of the koerselsraekke to update.

            koerselsraekke_data:
                Dictionary containing only the fields to update.

        Returns:
            Dictionary containing koersel_id, row count, and updated fields.

        Raises:
            HTTPException:
                404 if the koerselsraekke does not exist.

        Notes:
            If no fields are provided, no update is performed and rows_updated
            is returned as 0.
        """

        if not koerselsraekke_data:
            return {
                "koersel_id": koersel_id,
                "rows_updated": 0,
                "updated_fields": [],
            }

        koersel = self.db.get(Koersel, koersel_id)

        if koersel is None:
            raise HTTPException(
                status_code=404,
                detail=f"Kørselsrække not found: {koersel_id}",
            )

        # NB: no `final` edit-guard — a finalized (locked) kørselsrække can be
        # reopened and edited (see the "Lås"/reopen flow in the frontend), so
        # updates to final rows are allowed here on purpose.

        # Validate the final date range by combining existing dates with any
        # new date values supplied in the update payload.
        dates_to_validate = {
            "gyldig_fra": koerselsraekke_data.get("gyldig_fra", koersel.gyldig_fra),
            "gyldig_til": koerselsraekke_data.get("gyldig_til", koersel.gyldig_til),
        }

        self._validate_koerselsraekke_dates(dates_to_validate)

        try:
            for field_name, value in koerselsraekke_data.items():
                setattr(koersel, field_name, value)

            self.db.flush()

            status_result = self.recalculate_bevilling_status(
                bevilling_id=koersel.bevilling_id,
                commit=False,
            )

            self.db.commit()

            return {
                "koersel_id": koersel_id,
                "rows_updated": 1,
                "updated_fields": list(koerselsraekke_data.keys()),
                "status": status_result,
            }

        except Exception:
            self.db.rollback()
            raise


    def set_ansvarlig(
        self,
        bevilling_id: int,
        felt: str,
        tildelt_id: int | None,
    ):
        """Claim, reassign or release the bevilling's pending work.

        Args:
            bevilling_id:
                ID of the bevilling.

            felt:
                Either "sagsbehandler" or "ppr_sagsbehandler".

            tildelt_id:
                The person taking it on, or None to release it.

        Returns:
            Dictionary with the bevilling id, the field written and its value.

        Raises:
            HTTPException:
                400 if the field name is not one of the two.
                404 if the bevilling does not exist.

        Notes:
            Touches ONLY the ansvarlig column. The bevilling's own
            sagsbehandler_id / ppr_sagsbehandler_id are deliberately left
            alone: view_Letter_BevillingData resolves {sagsbehandler} on the
            afgørelsesbrev from sagsbehandler_id, so writing it here would
            change the name printed on a letter that has already been sent,
            or is about to be, because somebody picked the case up for a
            revurdering. The two answer different questions and the letter
            needs the first one.

            Deliberately not routed through update_bevilling. That method
            recalculates status, re-measures gaaafstand and writes audit events
            for a dozen fields — none of which an assignment should trigger,
            and one of which (status) reads sagsbehandler_id.
        """

        FELTER = {
            "sagsbehandler": "ansvarlig_sagsbehandler_id",
            "ppr_sagsbehandler": "ansvarlig_ppr_sagsbehandler_id",
        }

        if felt not in FELTER:
            raise HTTPException(
                status_code=400,
                detail=f"Ukendt felt: {felt}",
            )

        ansvarlig_felt = FELTER[felt]

        bevilling = self.db.get(Bevilling, bevilling_id)

        if bevilling is None:
            raise HTTPException(
                status_code=404,
                detail=f"Bevilling not found: {bevilling_id}",
            )

        setattr(bevilling, ansvarlig_felt, tildelt_id)

        self.db.commit()

        return {
            "bevilling_id": bevilling_id,
            "felt": ansvarlig_felt,
            "tildelt_id": tildelt_id,
        }


    def set_oensket_befordringstype(
        self,
        bevilling_id: int,
        befordringstype: str | None,
    ):
        """Record which kørselstype the application is being treated as asking for.

        Args:
            bevilling_id:
                ID of the bevilling.

            befordringstype:
                A Befordringstype label, or None to take the reading back off
                and let the citizen's own ticks show again.

        Returns:
            Dictionary with the bevilling id and the value now stored.

        Raises:
            HTTPException:
                404 if the bevilling does not exist.
                400 if the label is not an active Befordringstype.

        Notes:
            Stored inside Bevilling.ansoegningsdata rather than in a column of
            its own, under a key beside the citizen's ticks:

                {"koerselstyper": [...],            <- what they ticked
                 "oensket_befordringstype": "..."}  <- what we read it as

            koerselstyper is deliberately left alone. The forms let a citizen
            tick one, two or all three types, and a parent who ticks several
            is often a parent who does not know which to ask for — which is
            the very case this field exists to resolve. Collapsing the list to
            the caseworker's answer would resolve it by destroying the
            question, and "they asked for rutekørsel, we are treating it as
            skånekørsel" is a sentence the case has to be able to tell.

            A bevilling created by hand has no ansoegningsdata at all. One is
            started here rather than refused: the field is about how the case
            is being read, and a case entered by hand is still read.
        """

        bevilling = self.db.get(Bevilling, bevilling_id)

        if bevilling is None:
            raise HTTPException(
                status_code=404,
                detail=f"Bevilling not found: {bevilling_id}",
            )

        if befordringstype is not None:
            befordringstype = befordringstype.strip()

            # Validated against the lookup, not accepted as free text: the
            # value is displayed as a kørselstype and has to mean the same
            # thing as the one on a kørselsrække.
            gyldig = self.db.scalar(
                select(Befordringstype.befordringstype_tekst).where(
                    Befordringstype.befordringstype_tekst == befordringstype,
                    Befordringstype.aktiv == True,  # noqa: E712
                )
            )

            if gyldig is None:
                raise HTTPException(
                    status_code=400,
                    detail=f"Ukendt befordringstype: {befordringstype}",
                )

            befordringstype = gyldig

        try:
            data = json.loads(bevilling.ansoegningsdata or "{}")
        except ValueError:
            # Unreadable JSON is not a reason to refuse the edit. Nothing
            # can be preserved from it, so it is started over.
            data = {}

        # Valid JSON that is not an object — a list, a bare string — would
        # survive json.loads and then break on the first dict operation.
        if not isinstance(data, dict):
            data = {}

        if befordringstype is None:
            data.pop("oensket_befordringstype", None)
        else:
            data["oensket_befordringstype"] = befordringstype

        # An empty object would claim the application said something. Nothing
        # left to hold means the column goes back to NULL.
        bevilling.ansoegningsdata = (
            json.dumps(data, ensure_ascii=False) if data else None
        )

        self.db.commit()

        return {
            "bevilling_id": bevilling_id,
            "oensket_befordringstype": befordringstype,
        }


    def update_bevilling_hjaelpemidler(
        self,
        bevilling_id: int,
        hjaelpemiddel_ids: list[int],
        commit: bool = True,
    ):
        """Replace hjaelpemiddel links for a bevilling.

        Args:
            bevilling_id:
                ID of the bevilling.

            hjaelpemiddel_ids:
                New list of hjaelpemiddel IDs.

            commit:
                Whether this method should commit immediately.

        Returns:
            Dictionary containing bevilling_id, inserted IDs, and row count.

        Notes:
            This method replaces all existing links:

            1. Delete existing links for the bevilling.
            2. Insert the new set of links.

            Passing an empty list is valid and means all hjaelpemidler are
            removed from the bevilling.
        """

        unique_ids = self._validate_int_list(
            values=hjaelpemiddel_ids,
            field_name="hjaelpemiddel_ids",
        )

        self.db.execute(
            delete(BevillingHjaelpemiddelLink)
            .where(BevillingHjaelpemiddelLink.bevilling_id == bevilling_id)
        )

        for hjaelpemiddel_id in unique_ids:
            self.db.add(
                BevillingHjaelpemiddelLink(
                    bevilling_id=bevilling_id,
                    hjaelpemiddel_id=hjaelpemiddel_id,
                )
            )

        if commit:
            self.db.commit()

        return {
            "bevilling_id": bevilling_id,
            "hjaelpemiddel_ids": unique_ids,
            "rows_inserted": len(unique_ids),
        }


    def update_koerselsraekke_tillaeg(
        self,
        koersel_id: int,
        tillaeg_ids: list[int],
        commit: bool = True,
    ):
        """Replace tillaeg links for a koerselsraekke.

        Args:
            koersel_id:
                ID of the koerselsraekke.

            tillaeg_ids:
                New list of tillaeg IDs.

            commit:
                Whether this method should commit immediately.

        Returns:
            Dictionary containing koersel_id, inserted IDs, and row count.
        """

        unique_ids = self._validate_int_list(
            values=tillaeg_ids,
            field_name="tillaeg_ids",
        )

        self.db.execute(
            delete(KoerselKoerselstypeTillaegLink)
            .where(KoerselKoerselstypeTillaegLink.koersel_id == koersel_id)
        )

        for tillaeg_id in unique_ids:
            self.db.add(
                KoerselKoerselstypeTillaegLink(
                    koersel_id=koersel_id,
                    tillaeg_id=tillaeg_id,
                )
            )

        if commit:
            self.db.commit()

        return {
            "koersel_id": koersel_id,
            "tillaeg_ids": unique_ids,
            "rows_inserted": len(unique_ids),
        }


    def update_koerselsraekke_dage(
        self,
        koersel_id: int,
        dag_ids: list[int],
        commit: bool = True,
    ):
        """Replace weekday links for a koerselsraekke.

        Args:
            koersel_id:
                ID of the koerselsraekke.

            dag_ids:
                New list of weekday IDs.

            commit:
                Whether this method should commit immediately.

        Returns:
            Dictionary containing koersel_id, inserted IDs, and row count.
        """

        unique_ids = self._validate_int_list(
            values=dag_ids,
            field_name="dag_ids",
        )

        self.db.execute(
            delete(KoerselUgedagLink)
            .where(KoerselUgedagLink.koersel_id == koersel_id)
        )

        for dag_id in unique_ids:
            self.db.add(
                KoerselUgedagLink(
                    koersel_id=koersel_id,
                    dag_id=dag_id,
                )
            )

        if commit:
            self.db.commit()

        return {
            "koersel_id": koersel_id,
            "dag_ids": unique_ids,
            "rows_inserted": len(unique_ids),
        }


    def delete_bevilling(self, bevilling_id: int, udfoert_af: str = "System"):
        """Soft-delete a bevilling and all its kørselsrækker.

        Sets aktiv=False on the bevilling and all related Koersel rows so that
        history is preserved in the database. Soft-deleted records are excluded
        from all normal queries and the frontend.

        Args:
            bevilling_id:
                ID of the bevilling to soft-delete.

        Returns:
            Dictionary containing deleted row count.

        Raises:
            HTTPException:
                404 if the bevilling does not exist or is already deleted.
        """

        bevilling = self.db.get(Bevilling, bevilling_id)

        if bevilling is None or not bevilling.aktiv:
            raise HTTPException(
                status_code=404,
                detail=f"Bevilling not found: {bevilling_id}",
            )

        cpr = bevilling.cpr_elev

        # Soft-delete all related koerselsrækker in the same transaction.
        self.db.execute(
            sa_update(Koersel)
            .where(Koersel.bevilling_id == bevilling_id)
            .values(aktiv=False)
        )

        bevilling.aktiv = False
        bevilling.updated_by = udfoert_af
        self.db.commit()

        self._log_event(
            cpr,
            type_kode="bevilling_slettet",
            aktivitetstype="Bevilling slettet",
            kommentar=f"Bevilling ID: {bevilling_id}",
            relateret_bevilling_id=bevilling_id,
            udfoert_af=udfoert_af,
        )

        return {
            "rows_deleted": 1,
        }


    def delete_koerselsraekke(self, koersel_id: int, udfoert_af: str = "System"):
        """Soft-delete a single kørselsrække.

        Sets aktiv=False so history is preserved. The row is excluded from all
        normal queries and the frontend after deletion.

        Args:
            koersel_id:
                ID of the kørselsrække to soft-delete.

        Returns:
            Dictionary containing deleted row count.

        Raises:
            HTTPException:
                404 if the kørselsrække does not exist or is already deleted.
        """

        koersel = self.db.get(Koersel, koersel_id)

        if koersel is None or not koersel.aktiv:
            raise HTTPException(
                status_code=404,
                detail=f"Kørselsrække not found: {koersel_id}",
            )

        bevilling_id = koersel.bevilling_id
        cpr = koersel.bevilling.cpr_elev

        koersel.aktiv = False
        self.db.commit()

        self._log_event(
            cpr,
            type_kode="koerselsraekke_slettet",
            aktivitetstype="Kørselsrække slettet",
            kommentar=f"Koersel ID: {koersel_id}, Bevilling ID: {bevilling_id}",
            relateret_bevilling_id=bevilling_id,
            udfoert_af=udfoert_af,
        )

        return {
            "rows_deleted": 1,
        }


    def calculate_bevilling_status_id(self, bevilling_id: int):
        """Calculate the correct status ID for a bevilling using the SQL procedure."""

        if self.db.get(Bevilling, bevilling_id) is None:
            raise HTTPException(
                status_code=404,
                detail=f"Bevilling not found: {bevilling_id}",
            )

        rows = self._execute_recalculate_status_procedure(
            bevilling_id=bevilling_id,
            dry_run=True,
        )

        result = self._get_status_result_for_bevilling(
            rows=rows,
            bevilling_id=bevilling_id,
        )

        return int(result["calculated_status_id"])


    def get_bevillinger_uden_esdh(self, maks_antal: int = 200):
        """Bevillinger missing their ESDH key, their link, or both.

        Args:
            maks_antal:
                Upper bound on the number of rows returned.

        Returns:
            A list of dictionaries with bevilling_id, cpr_elev, esdh_noegle
            and created_at, oldest first.

        Notes:
            Serves rpa-befordring-kontrol, which looks the case up in GO and
            writes both back. A bevilling created from an OS2Forms submission
            has no key — the submission does not know the GO case — and the
            link is derived FROM the key, so without one it gets neither.

            EITHER being missing qualifies. A bevilling can end up with a key
            but no link: kontrol writes the key even when GO's metadata call
            fails, deliberately, because a missing link is cosmetic while a
            missing key means the bevilling has no case at all. Selecting only
            on the key left those waiting for the nightly run — which is the
            wait moving this work here was meant to remove.

            esdh_noegle comes back so the caller can tell the two cases apart:
            with a key in hand there is no need to look the case up again, only
            to resolve its URL.

            Soft-deleted bevillinger are excluded: there is no point resolving
            a case for a bevilling nobody will open.

            Oldest first, so a backlog drains in the order it built up rather
            than the newest rows crowding out the ones that have waited
            longest. The cap exists because this is called on a schedule and
            every row it returns costs a GO lookup.
        """

        sql = text("""
            SELECT TOP (:maks_antal)
                b.bevilling_id,
                b.cpr_elev,
                b.esdh_noegle,
                b.created_at
            FROM
                [befordring].[Bevilling] b
            WHERE
                b.aktiv = 1
            AND (
                    NULLIF(LTRIM(RTRIM(b.esdh_noegle)), '') IS NULL
                 OR NULLIF(LTRIM(RTRIM(b.esdh_url)), '') IS NULL
                )
            ORDER BY
                b.created_at ASC, b.bevilling_id ASC
        """)

        result = self.db.execute(sql, {"maks_antal": maks_antal})

        return self._rows_to_dicts(result)


    def recalculate_bevilling_status(self, bevilling_id: int, commit: bool = True,):
        """Recalculate and save the status for a bevilling.

        Notes:
            The actual status logic lives in the SQL stored procedure.

            This method is mainly responsible for:
                - calling the procedure for one bevilling
                - preserving Python-side error handling
                - optionally committing the transaction
        """

        if self.db.get(Bevilling, bevilling_id) is None:
            raise HTTPException(
                status_code=404,
                detail=f"Bevilling not found: {bevilling_id}",
            )

        try:
            rows = self._execute_recalculate_status_procedure(
                bevilling_id=bevilling_id,
                dry_run=False,
            )

            result = self._get_status_result_for_bevilling(
                rows=rows,
                bevilling_id=bevilling_id,
            )

            new_status_id = int(result["calculated_status_id"])

            if commit:
                self.db.commit()

            return {
                "bevilling_id": bevilling_id,
                "status_id": new_status_id,
                "status_text": result["calculated_status_text"],
                "status_reason": result.get("status_reason"),
                "rows_updated": int(result["status_will_change"]),

                # Optional, but useful:
                # shows other bevillinger for same CPR that were recalculated too.
                "status_results": rows,
            }

        except Exception:
            if commit:
                self.db.rollback()

            raise


    def get_letter_data(self, bevilling_id: int):
        """Get all data needed for letter generation.

        Args:
            bevilling_id:
                ID of the bevilling.

        Returns:
            A dictionary with main letter data and a nested list of
            koerselsraekker.

        Raises:
            HTTPException:
                404 if no letter data exists for the bevilling.

        Notes:
            The result is prepared for the letter-generation worker.

            The main data comes from view_Letter_BevillingData.
            The nested koerselsraekker come from view_Letter_Koerselsraekker.
        """

        main_sql = text("""
            SELECT
                *
            FROM
                [befordring].[view_Letter_BevillingData]
            WHERE
                bevilling_id = :bevilling_id
        """)

        main_result = self.db.execute(
            main_sql,
            {"bevilling_id": bevilling_id},
        )

        main_records = self._rows_to_dicts(main_result)

        if not main_records:
            raise HTTPException(
                status_code=404,
                detail=f"Bevilling not found: {bevilling_id}",
            )

        letter_data = main_records[0]

        koersel_sql = text("""
            SELECT
                *
            FROM
                [befordring].[view_Letter_Koerselsraekker]
            WHERE
                bevilling_id = :bevilling_id
            ORDER BY
                gyldig_fra,
                gyldig_til,
                -- Befordring's order for rækker whose dates are identical.
                -- A TIE-BREAK below the dates, not a replacement for them:
                -- it only decides which of two rækker covering the same
                -- period is printed first. NULL last, so the retiring
                -- rutetyper fall to the bottom rather than to the top.
                CASE WHEN rutetype_sortering IS NULL THEN 1 ELSE 0 END,
                rutetype_sortering,
                koersel_id
        """)

        koersel_result = self.db.execute(
            koersel_sql,
            {"bevilling_id": bevilling_id},
        )

        koersel_records = self._rows_to_dicts(koersel_result)

        # Nest the related koerselsraekker inside the main letter data object.
        # This makes the payload easier for the letter worker/template engine
        # to consume.
        #
        # NB: this is an explicit whitelist, not a pass-through. A column added
        # to view_Letter_Koerselsraekker does NOT reach the letter until it is
        # listed here too — it is read from the database and then dropped, with
        # no error anywhere. Add both, or the RPA sees the field as missing.
        letter_data["koerselsraekker"] = [
            {
                "koersel_id": row.get("koersel_id"),
                "koerselstype_key": row.get("koerselstype_key"),
                "koerselstype": row.get("koerselstype"),
                "dage": row.get("dage"),
                "taxa_id": row.get("taxa_id"),
                "tidspunkt": row.get("tidspunkt"),
                # Lowercased by the view — it sits mid-sentence in the
                # afgørelse. Added alongside tidspunkt rather than replacing
                # it: the skabelon still reads {tidspunkt}, and both can be
                # available until the template is switched over.
                "rutetype": row.get("rutetype"),
                "bevilling_fra": row.get("bevilling_fra"),
                "bevilling_til": row.get("bevilling_til"),
                "koerselstype_tillaeg": row.get("koerselstype_tillaeg"),
                "bevilget_koereafstand_pr_vej": row.get("bevilget_koereafstand_pr_vej"),
                "transporttid_i_bus": row.get("transporttid_i_bus"),
                "skift_med_bus": row.get("skift_med_bus"),
                # Taxa-specific. koersel_til_institution arrives from the view
                # already resolved to "Ja"/"Nej"/None — the letter engine gates
                # the SFO block (blok 4) on it.
                "koersel_til_institution": row.get("koersel_til_institution"),
                "max_minutter_i_transport": row.get("max_minutter_i_transport"),
                # Egenbefordring-specific: who the godtgørelse is paid to,
                # resolved to name and CPR rather than the id. Both are needed
                # — the letter names the person and quotes their CPR.
                "koerselsgodtgoerelse_modtager": row.get("koerselsgodtgoerelse_modtager"),
                "koerselsgodtgoerelse_modtager_cpr": row.get("koerselsgodtgoerelse_modtager_cpr"),
            }
            for row in koersel_records
        ]

        return letter_data
