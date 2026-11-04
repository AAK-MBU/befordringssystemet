"""Service layer for citizen-related business logic.

This module contains database operations related to citizens/students.

The service is responsible for:

- Fetching citizen stamdata
- Fetching parent/guardian data
- Re-deriving a single student's school and walking distance on demand

Stamdata itself is maintained by external systems and is read-only here. The
two derived columns are not: matrikel_id and skoleafstand are computed by this
application's own nightly run, and genberegn_skole() is that same computation
applied to one student.
"""

from fastapi import HTTPException
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.models.citizen import Elev
from app.utils.distance import walking_distance


class CitizenService:
    """Service class for citizen-related operations.

    Args:
        db:
            SQLAlchemy database session.
    """

    def __init__(self, db: Session):
        """Initialize the service with a database session."""

        self.db = db


    def _rows_to_dicts(self, result):
        """Convert SQLAlchemy result rows into normal dictionaries.

        Args:
            result:
                SQLAlchemy result object.

        Returns:
            A list of dictionaries.

        Notes:
            This is useful when reading from SQL views using raw SQL.
        """

        return [dict(row) for row in result.mappings().all()]


    def get_stamdata(self, cpr: str):
        """Get stamdata for a citizen/student.

        Args:
            cpr:
                CPR number of the citizen/student.

        Returns:
            A dictionary containing stamdata if found.
            Otherwise None.

        Notes:
            Data is read from view_Stamdata, not directly from the Elev table.
            This means the returned object may contain joined/calculated fields
            that are not present directly on the Elev model.
        """

        sql = text("""
            SELECT
                *
            FROM
                [befordring].[view_Stamdata]
            WHERE
                cpr = :cpr
        """)

        result = self.db.execute(sql, {"cpr": cpr})
        records = self._rows_to_dicts(result)

        # No stamdata was found for this CPR.
        if not records:
            return None

        # CPR should identify one citizen/student, so return the first row.
        return records[0]


    def create_elev(self, elev_data: dict) -> dict:
        """Create an Elev record for a citizen if one does not exist.

        Args:
            elev_data:
                Dictionary matching ElevCreateRequest fields.

        Returns:
            {"cpr": str, "created": bool} — created=False if the Elev already existed.

        Notes:
            adresse_id is the LOIS AdresseId (DAR GUID). The caller (RPA
            conversion bot) resolves it via LOIS at queue time — see
            queue_handler.py — and ensures the corresponding Adresse row
            exists via POST /adresse/create before calling this endpoint.
            No address record is created here.
        """
        existing = self.db.get(Elev, elev_data["cpr"])
        if existing:
            return {"cpr": existing.cpr, "created": False}

        elev = Elev(
            cpr=elev_data["cpr"],
            adresseringsnavn=elev_data.get("adresseringsnavn"),
            navne_adresse_beskyttelse=elev_data.get("navne_adresse_beskyttelse", False),
            adresse_id=elev_data.get("adresse_id"),
            matrikel_id=elev_data.get("matrikel_id"),
            skolekode=elev_data.get("skolekode", 0),
            skoleafstand=elev_data.get("skoleafstand", 0.0),
            klasseart=elev_data.get("klasseart", ""),
            elevklassetrin=elev_data.get("elevklassetrin", ""),
            klassebetegnelse=elev_data.get("klassebetegnelse", ""),
            institution=elev_data.get("institution", ""),
            bopaelsdistrikt=elev_data.get("bopaelsdistrikt", ""),
        )
        self.db.add(elev)
        self.db.commit()

        return {"cpr": elev.cpr, "created": True}


    def get_parent_data(self, cpr: str):
        """Get parent/guardian data for a citizen/student.

        Args:
            cpr:
                CPR number of the citizen/student.

        Returns:
            A list of parent/guardian records.

        Notes:
            Data is read from view_ParentData.

            The result is ordered by:
            1. foraelderrolle_sortering
            2. adresseringsnavn

            This gives the frontend a stable and predictable display order.
        """

        sql = text("""
            SELECT
                adresseringsnavn,
                cpr_foraelder,
                adresse_tekst,
                relation,
                navne_adresse_beskyttelse,
                maa_vide_barns_adresse
            FROM
                [befordring].[view_ParentData]
            WHERE
                cpr_elev = :cpr
            ORDER BY
                foraelderrolle_sortering,
                adresseringsnavn
        """)

        result = self.db.execute(sql, {"cpr": cpr})

        return self._rows_to_dicts(result)


    def genberegn_skole(self, cpr: str):
        """Re-derive one student's school and walking distance, now.

        Args:
            cpr:
                CPR number of the student.

        Returns:
            A dictionary with the resulting matrikel_id, ungdomsuddannelse_id,
            skoleafstand and a Danish ``besked`` describing what happened.

        Raises:
            HTTPException:
                404 if the student is not in Elev, 502 if the distance API
                could not be reached.

        Notes:
            The two steps the nightly run performs, in the same order, plus
            one it deliberately does not:

              1. usp_sync_elev_matrikel_from_bevilling derives the school from
                 the student's bevillinger. Narrowed to this one student by
                 @cpr; the rules are the procedure's, not repeated here.

             1b. Where that leaves no school at all, the student's own
                 skolekode is used — but only where it names exactly one
                 Skolematrikel. See _entydig_matrikel_fra_skolekode.

                 This step is unique to the button. The nightly run could do
                 it for every student in the municipality, and that is the
                 reason it does not: it would resolve tens of thousands of
                 students and queue a distance lookup for each. Here it is one
                 student, asked for by a caseworker looking at them.

              2. The walking distance from the student's address to that
                 school, written to skoleafstand.

            Step 1 is authoritative and may CLEAR the school where no bevilling
            qualifies — a stale school being worse than none. Where step 1b
            cannot help either, there is nothing to measure, and the caller is
            told which of the two situations they are in.

            Only after a successful measurement is kraever_genberegning
            cleared, so a student whose distance could not be calculated is
            still picked up by the nightly run.
        """

        elev = self.db.get(Elev, cpr)

        if elev is None:
            raise HTTPException(
                status_code=404,
                detail=f"Ingen elev fundet med CPR {cpr}",
            )

        # Step 1 — derive the school. Committed before the HTTP call below, so
        # no transaction is held open across a network request. That is the
        # same mistake the nightly run made against this very table, where it
        # escalated to a table lock and took the application down with it.
        self.db.execute(
            text("EXEC [befordring].[usp_sync_elev_matrikel_from_bevilling] @cpr = :cpr"),
            {"cpr": cpr},
        ).close()
        self.db.commit()

        self.db.refresh(elev)

        # Step 1b — the student has no bevilling to derive from, or none that
        # qualifies. Where their own skolekode names exactly one school, that
        # is answer enough; this is the case the nightly run deliberately does
        # not chase, because resolving every such student in the municipality
        # would queue tens of thousands of distance lookups nobody asked for.
        # Asked for one student, by a caseworker looking at them, it is cheap
        # and it is the number they came for.
        #
        # The sync procedure above will not undo it: it leaves a matrikel whose
        # skolekode matches the student's own. A real school change still wipes
        # it, from usp_upsert_elev_from_stg, before this ever runs again.
        if elev.matrikel_id is None and elev.ungdomsuddannelse_id is None:
            matrikel_id = self._entydig_matrikel_fra_skolekode(elev)

            if matrikel_id is not None:
                elev.matrikel_id = matrikel_id
                self.db.commit()
                self.db.refresh(elev)

        koordinater = self._skole_koordinater(elev)

        if koordinater is None:
            # Two different situations, and a caseworker can act on only one of
            # them, so they are not told the same thing.
            if elev.matrikel_id is None and elev.ungdomsuddannelse_id is None:
                besked = self._aarsag_til_manglende_skole(elev)
            else:
                besked = (
                    "Elevens skole mangler koordinater, så afstanden kan "
                    "ikke beregnes."
                )

            return {
                "matrikel_id": elev.matrikel_id,
                "ungdomsuddannelse_id": elev.ungdomsuddannelse_id,
                "skoleafstand": elev.skoleafstand,
                "besked": besked,
            }

        adresse = self._adresse_koordinater(elev)

        if adresse is None:
            return {
                "matrikel_id": elev.matrikel_id,
                "ungdomsuddannelse_id": elev.ungdomsuddannelse_id,
                "skoleafstand": elev.skoleafstand,
                "besked": "Elevens adresse mangler koordinater, så afstanden kan ikke beregnes.",
            }

        skole_lat, skole_lon = koordinater
        adresse_lat, adresse_lon = adresse

        # Step 2 — measure. foot-walking, because skoleafstand feeds the
        # afstandskriterie, which is about how far the child would have to walk.
        try:
            distance_km, _ = walking_distance(adresse_lat, adresse_lon, skole_lat, skole_lon)
        except Exception as e:
            raise HTTPException(status_code=502, detail=f"Distance API error: {e}")

        # One decimal, matching what the nightly run stores. It reaches the
        # same ORS call through /bevilling/calculate_walking_distance, which
        # rounds there; this service calls walking_distance() directly and so
        # has to round for itself. Two sources for one column must agree, or
        # the button and the night quietly disagree about the same student.
        elev.skoleafstand = round(distance_km, 1)
        elev.kraever_genberegning = False

        self.db.commit()
        self.db.refresh(elev)

        return {
            "matrikel_id": elev.matrikel_id,
            "ungdomsuddannelse_id": elev.ungdomsuddannelse_id,
            "skoleafstand": elev.skoleafstand,
            "besked": None,
        }


    def _entydig_matrikel_fra_skolekode(self, elev: Elev) -> int | None:
        """The student's school, resolved from their skolekode alone.

        Only where the skolekode matches EXACTLY ONE Skolematrikel row. Several
        rows means the school has several sites, and choosing between them is
        the decision a bevilling exists to record — guessing one would be the
        confidently wrong answer the whole derivation is built to avoid.

        Elev.skolekode is the data worker's load and is the authority on which
        school the child attends — usp_sync_elev_matrikel_from_bevilling says so
        itself, and uses it to reject a bevilling that disagrees. Where it
        points at a single site there is nothing left to decide, so a student
        with no bevilling at all can still be given a school.

        Returns:
            The matrikel_id, or None when the skolekode is missing, unknown or
            matches more than one row.
        """

        if not elev.skolekode:
            return None

        sql = text("""
            SELECT   matrikel_id
            FROM     [befordring].[Skolematrikel]
            WHERE    skolekode = :skolekode
        """)

        rows = self.db.execute(sql, {"skolekode": elev.skolekode}).fetchall()

        return rows[0][0] if len(rows) == 1 else None


    def _aarsag_til_manglende_skole(self, elev: Elev) -> str:
        """Why no school could be derived for this student, in their own case.

        The button used to answer this with one fixed sentence — "Eleven har
        ingen bevilling at udlede fra, og skolekoden peger ikke på præcis én
        skolematrikel" — which is only ever true for one of the ways the
        derivation can come back empty, and is a flat untruth for a student
        who plainly does have a bevilling. A caseworker reading it goes
        looking for a missing bevilling that is sitting right there on the
        screen.

        The derivation has two steps and each can fail for its own reason, so
        the answer is worked out rather than asserted:

          1. usp_sync_elev_matrikel_from_bevilling takes the school from a
             QUALIFYING bevilling. Folkeskole qualifies only when the
             bevilling's matrikel belongs to the student's OWN skolekode — the
             data worker's load is the authority on which school the child
             attends, and a bevilling that disagrees must not supply a school.
             That one rule accounts for the two most common failures here: the
             student has no skolekode to check against, or the check fails.

          1b. Failing that, the student's own skolekode is used, but only
             where it names exactly one Skolematrikel.

        Each branch below names the field that is actually missing or wrong,
        because that is the field someone has to go and fix.
        """

        skolekode = elev.skolekode or None

        row = self.db.execute(
            text("""
                SELECT
                    COUNT(*)                                            AS antal,
                    SUM(CASE WHEN b.matrikel_id IS NOT NULL
                             THEN 1 ELSE 0 END)                         AS med_skole,
                    SUM(CASE WHEN b.matrikel_id IS NOT NULL
                              AND sm.skolekode = :skolekode
                             THEN 1 ELSE 0 END)                         AS matcher_skolekode,
                    SUM(CASE WHEN b.matrikel_id IS NULL
                              AND b.ungdomsuddannelse_id IS NULL
                             THEN 1 ELSE 0 END)                         AS uden_skole
                FROM      [befordring].[Bevilling] b
                LEFT JOIN [befordring].[Skolematrikel] sm
                       ON sm.matrikel_id = b.matrikel_id
                WHERE     b.aktiv = 1
                AND       b.cpr_elev = :cpr
            """),
            {"cpr": elev.cpr, "skolekode": skolekode},
        ).mappings().first()

        antal = (row["antal"] or 0) if row else 0
        med_skole = (row["med_skole"] or 0) if row else 0
        matcher = (row["matcher_skolekode"] or 0) if row else 0
        uden_skole = (row["uden_skole"] or 0) if row else 0

        # No bevilling at all — the only case the old sentence described. The
        # skolekode half is still worked out, because "ingen bevilling" alone
        # does not tell a caseworker why step 1b did not save it.
        if antal == 0:
            return (
                "Ingen skole kunne udledes. Eleven har ingen bevilling at udlede "
                f"fra, og {self._skolekode_aarsag(skolekode)}."
            )

        # A bevilling names a school, but the student has no skolekode to check
        # it against. This is the case the old message got wrong, and the one
        # that now also raises genbehandling — see migration 036.
        if med_skole > 0 and skolekode is None:
            return (
                "Ingen skole kunne udledes. Bevillingen har en skole, men eleven "
                "har ingen skolekode i stamdata, så de to kan ikke sammenholdes. "
                "Skolen på bevillingen bruges først, når elevens skolekode er "
                "registreret."
            )

        # The check ran and failed: the bevilling points at a school the
        # student is not registered at. Deliberately not "the bevilling is
        # wrong" — the skolekode may be the stale one — so it states the
        # disagreement and leaves the judgement to the caseworker.
        if med_skole > 0 and matcher == 0:
            return (
                "Ingen skole kunne udledes. Skolen på bevillingen hører til en "
                f"anden skolekode end elevens ({skolekode}), så den bruges ikke. "
            )

        # Every bevilling is blank on both school fields.
        if uden_skole == antal:
            return (
                "Ingen skole kunne udledes. Eleven har en bevilling, men der er "
                f"ingen skole registreret på den, og {self._skolekode_aarsag(skolekode)}."
            )

        return (
            "Ingen skole kunne udledes fra elevens bevillinger, og "
            f"{self._skolekode_aarsag(skolekode)}."
        )


    def _skolekode_aarsag(self, skolekode: int | None) -> str:
        """Why step 1b could not resolve a school from the skolekode alone.

        A clause, not a sentence — the callers above join it onto their own.
        """

        if skolekode is None:
            return "eleven har ingen skolekode i stamdata"

        antal = self.db.execute(
            text("""
                SELECT   COUNT(*) AS antal
                FROM     [befordring].[Skolematrikel]
                WHERE    skolekode = :skolekode
            """),
            {"skolekode": skolekode},
        ).scalar()

        if not antal:
            return f"elevens skolekode ({skolekode}) findes ikke blandt skolematriklerne"

        if antal > 1:
            return (
                f"elevens skolekode ({skolekode}) dækker {antal} skolematrikler, "
                "så den peger ikke på én bestemt skole"
            )

        # Exactly one match, so step 1b should have resolved it. Reaching here
        # means the matrikel exists but something else stopped it.
        return f"elevens skolekode ({skolekode}) kunne ikke slås op"


    def _skole_koordinater(self, elev: Elev):
        """Coordinates of the student's derived school, or None.

        None covers both "no school was derived" and "the school has no
        coordinates" — the Skolematrikel rows added by hand carry NULL until
        someone fills them in, and sending those to the distance API produces
        a 502 that reads like an outage.
        """

        if elev.matrikel_id is not None:
            sql = text("""
                SELECT latitude, longitude
                FROM   [befordring].[Skolematrikel]
                WHERE  matrikel_id = :id
            """)
            params = {"id": elev.matrikel_id}
        elif elev.ungdomsuddannelse_id is not None:
            sql = text("""
                SELECT latitude, longitude
                FROM   [befordring].[Ungdomsuddannelse]
                WHERE  ungdomsuddannelse_id = :id
            """)
            params = {"id": elev.ungdomsuddannelse_id}
        else:
            return None

        row = self.db.execute(sql, params).mappings().first()

        if row is None or row["latitude"] is None or row["longitude"] is None:
            return None

        return float(row["latitude"]), float(row["longitude"])


    def _adresse_koordinater(self, elev: Elev):
        """Coordinates of the student's registered address, or None."""

        if elev.adresse_id is None:
            return None

        row = self.db.execute(
            text("""
                SELECT latitude, longitude
                FROM   [befordring].[Adresse]
                WHERE  adresse_id = :id
            """),
            {"id": elev.adresse_id},
        ).mappings().first()

        if row is None or row["latitude"] is None or row["longitude"] is None:
            return None

        return float(row["latitude"]), float(row["longitude"])
