"""Service layer for overview/dashboard data.

This module contains read operations used by the overview/dashboard part of
the application.

The service is responsible for:

- Fetching active bevillinger
- Fetching non-active bevillinger
- Fetching reassessments/revurderinger
- Fetching new applications

Some overview data comes from BevillingService, while other overview data is
read directly from dedicated overview tables.
"""

from datetime import datetime

from sqlalchemy import text
from sqlalchemy.orm import Session

from app.services.bevilling_service import BevillingService
from app.utils.status_rang import status_rang


class OverviewService:
    """Service class for overview-related database reads.

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
            This helper is useful when reading from raw SQL tables/views using
            self.db.execute(text(...)).
        """

        return [dict(row) for row in result.mappings().all()]


    def _map_bevilling_overview_record(self, bevilling: dict):
        """Map a full bevilling record into a smaller overview object.

        Args:
            bevilling:
                Dictionary containing bevilling data from a SQL view.

        Returns:
            A simplified dictionary for overview/table display.

        Notes:
            The database views may return many more fields than the frontend
            needs in the overview.

            This method limits the response to the fields currently used by
            the overview UI.
        """

        return {
            "navn": bevilling.get("adresseringsnavn"),
            "cpr": bevilling.get("cpr_elev"),
            "status": bevilling.get("status_tekst"),
            "esdh_noegle": bevilling.get("esdh_noegle"),
            "esdh_url": bevilling.get("esdh_url"),
            "sagsbehandler": bevilling.get("sagsbehandler"),
            "ppr_sagsbehandler": bevilling.get("ppr_sagsbehandler_tekst"),
            "revurdering": bevilling.get("revurdering"),
            "skole_navn": bevilling.get("skole_navn"),
        }


    def _read_overview_table(self, table_name: str, order_direction: str = "ASC"):
        """Read all rows from an allowed overview table.

        Args:
            table_name:
                Fully qualified SQL Server table name.

        Returns:
            A list of table rows as dictionaries.

        Raises:
            ValueError:
                If the requested table name is not allowed.

        Notes:
            Table names cannot be safely parameterized like normal SQL values.

            Because the table name is inserted directly into the SQL string,
            it must be validated against an allow-list first.
        """

        allowed_tables = {
            "[befordring].[view_New_Applications]",
        }

        if table_name not in allowed_tables:
            raise ValueError(f"Invalid overview table: {table_name}")

        sql = text(f"""
            SELECT
                *
            FROM
                {table_name}
            ORDER BY
                ansoegningsdato {order_direction}
        """)

        result = self.db.execute(sql)

        return self._rows_to_dicts(result)


    def _koerselstyper_pr_bevilling(self):
        """Map every bevilling to the kørselstyper on its kørselsrækker.

        Returns:
            A dictionary of ``{bevilling_id: [kørselstype, ...]}``, with the
            labels de-duplicated and alphabetically sorted.

        Notes:
            The overview shows one row per student, and that row should say
            what kind of kørsel the student actually has right now. A bevilling
            can hold several kørselsrækker with different validity periods, so
            "right now" means the rækker whose period covers today.

            Where a bevilling has no currently valid række — a Kommende one
            whose period has not started, an Udløbet one whose period has
            ended — the column would otherwise be blank for every such row.
            Those rows fall back to all of the bevilling's kørselsrækker, so
            the column always says something about the bevilling on screen.

            One query covers every bevilling. Asking per student would mean a
            query per row on a page that lists the whole municipality.
        """

        sql = text("""
            SELECT
                k.bevilling_id,
                bt.befordringstype_tekst,
                CASE
                    WHEN (k.gyldig_fra IS NULL OR k.gyldig_fra <= CAST(GETDATE() AS date))
                     AND (k.gyldig_til IS NULL OR k.gyldig_til >= CAST(GETDATE() AS date))
                    THEN 1
                    ELSE 0
                END AS er_aktuel
            FROM
                [befordring].[Koersel] k
            INNER JOIN
                [befordring].[Befordringstype] bt
                ON bt.befordringstype_id = k.befordringstype_id
            WHERE
                k.aktiv = 1
                AND k.bevilling_id IS NOT NULL
        """)

        aktuelle: dict = {}
        alle: dict = {}

        for row in self._rows_to_dicts(self.db.execute(sql)):
            bevilling_id = row["bevilling_id"]
            tekst = (row["befordringstype_tekst"] or "").strip()

            if not tekst:
                continue

            alle.setdefault(bevilling_id, set()).add(tekst)

            if row["er_aktuel"]:
                aktuelle.setdefault(bevilling_id, set()).add(tekst)

        return {
            bevilling_id: sorted(aktuelle.get(bevilling_id) or typer)
            for bevilling_id, typer in alle.items()
        }


    def get_alle_bevillinger(self):
        """Get all bevillinger for the overview, one row per student.

        Each student is shown once. The displayed bevilling is the
        highest-ranking one by status — see app.utils.status_rang — with the
        most recently created breaking a tie. Each record also carries ``bevilling_count`` — how
        many bevillinger the student has in total — and ``koerselstyper``, the
        kørselstyper on that bevilling's currently valid kørselsrækker.

        Returns:
            A list of simplified bevilling records, one per student.
        """

        service = BevillingService(db=self.db)

        records = service.get_bevillinger(
            view_name="[befordring].[view_All_Bevillinger]",
        )

        # Selection priority per student: by STATUS RANK, then the most
        # recently created. Comparing tuples element-wise gives exactly that —
        # rank wins first, created_at breaks ties. The middle "has date" flag
        # keeps None created_at out of a raw datetime compare.
        #
        # Negated because the comparison below takes the LARGEST key while a
        # lower rank is the more important status.
        #
        # Was a plain "is it Aktiv", which is why a student with a Fejlet
        # bevilling and a newer expired one showed as Udløbet here while their
        # own page said Fejlet — and why they were missing from the Fejlede
        # bevillinger panel, which filters these same rows.
        def selection_key(record: dict):
            created = record.get("created_at")
            return (
                -status_rang(record.get("status_tekst")),
                created is not None,
                created or datetime.min,
            )

        koerselstyper = self._koerselstyper_pr_bevilling()

        chosen: dict = {}
        counts: dict = {}

        for record in records:
            cpr = record.get("cpr_elev")
            counts[cpr] = counts.get(cpr, 0) + 1

            if cpr not in chosen or selection_key(record) >= selection_key(chosen[cpr]):
                chosen[cpr] = record

        result = []
        for cpr, record in chosen.items():
            overview = self._map_bevilling_overview_record(record)
            overview["bevilling_count"] = counts[cpr]
            overview["koerselstyper"] = koerselstyper.get(
                record.get("bevilling_id"), []
            )
            result.append(overview)

        return result


    def get_active_bevillinger(self):
        """Get active bevillinger for the overview.

        Returns:
            A list of simplified active bevilling records.

        Notes:
            The full bevilling data is fetched through BevillingService.
            Each record is then mapped into a smaller overview format.
        """

        service = BevillingService(db=self.db)

        records = service.get_bevillinger(
            view_name="[befordring].[view_All_Active_Bevillinger]",
        )

        return [
            self._map_bevilling_overview_record(record)
            for record in records
        ]


    def get_fejlede_bevillinger(self):
        """Get bevillinger with status Fejlet for the overview.

        Returns:
            A list of simplified bevilling records where status is Fejlet.
        """

        service = BevillingService(db=self.db)

        records = service.get_bevillinger(
            view_name="[befordring].[view_All_Bevillinger]",
            status="Fejlet",
        )

        return [
            self._map_bevilling_overview_record(record)
            for record in records
        ]


    @staticmethod
    def _escape_like(value: str) -> str:
        """Neutralise LIKE wildcards in user input.

        Without this a caseworker typing "%" matches every student in the
        municipality. Bracket-escaping avoids needing an ESCAPE clause; "["
        must be handled first or it would re-escape the brackets added after.
        """

        return (
            value.replace("[", "[[]")
            .replace("%", "[%]")
            .replace("_", "[_]")
        )

    def search_elever(self, q: str):
        """Search students by CPR or name, for the global search box.

        Args:
            q:
                Search string. Must be at least 2 characters.

        Returns:
            Up to 20 students, each with ``cpr_elev`` and ``adresseringsnavn``.

        Notes:
            Reads [Elev] directly rather than view_Stamdata. The view ranks every
            bevilling through a ROW_NUMBER() window before its WHERE applies, so
            searching it made each keystroke sort the whole bevilling table to
            fetch two columns that sit on Elev anyway. With Elev holding every
            student in the municipality (30-50k) that cost is not affordable.

            Digits and text are handled as separate statements so each can use an
            index:

            * CPR is matched as a prefix, which seeks the primary key. Nobody
              searches a CPR by its middle digits.
            * Names are matched as a WORD prefix — "starts with" OR "contains a
              word starting with" — because adresseringsnavn is stored as
              "Fornavn Efternavn" and searching by surname has to work. The
              second pattern keeps a leading wildcard, so it scans; an index on
              adresseringsnavn keeps that scan narrow. If it ever gets too slow,
              a full-text index with CONTAINS(..., '"q*"') is the proper fix.
        """

        query = (q or "").strip()

        if len(query) < 2:
            return []

        digits = "".join(ch for ch in query if ch.isdigit())

        # A CPR may be typed with or without its hyphen.
        if digits and not any(ch.isalpha() for ch in query):
            sql = text("""
                SELECT TOP 20
                    e.cpr AS cpr_elev,
                    e.adresseringsnavn
                FROM
                    [befordring].[Elev] e
                WHERE
                    e.cpr LIKE :prefix
                ORDER BY
                    e.cpr
            """)

            params = {"prefix": f"{self._escape_like(digits)}%"}

        else:
            escaped = self._escape_like(query)

            sql = text("""
                SELECT TOP 20
                    e.cpr AS cpr_elev,
                    e.adresseringsnavn
                FROM
                    [befordring].[Elev] e
                WHERE
                    e.adresseringsnavn LIKE :prefix
                    OR e.adresseringsnavn LIKE :word_prefix
                ORDER BY
                    e.adresseringsnavn
            """)

            params = {"prefix": f"{escaped}%", "word_prefix": f"% {escaped}%"}

        result = self.db.execute(sql, params)

        return self._rows_to_dicts(result)


    def get_koerselsgodtgoerelse_modtagere(self):
        """Everyone currently receiving kørselsgodtgørelse for egenbefordring.

        The monthly list a caseworker messages. One row per person — the same
        parent can receive for several children, and they only need telling
        once — with the children they receive for aggregated alongside.

        "Currently" is evaluated in the view against today's date, so the list
        reflects whoever is receiving at the moment it is generated.

        Returns:
            A list of dicts, sorted by name.
        """

        sql = text("""
            SELECT
                *
            FROM
                [befordring].[view_Koerselsgodtgoerelse_Modtagere]
            ORDER BY
                modtager_navn
        """)

        result = self.db.execute(sql)

        return self._rows_to_dicts(result)


    def get_revurderinger(self):
        """Get bevillinger with status Revurdering, with nested koerselsraekker.

        Returns:
            List of bevilling dicts, each with a 'koerselsraekker' key containing
            a list of that bevilling's koersel rows.
        """

        bev_sql = text("""
            SELECT
                *
            FROM
                [befordring].[view_Revurderinger]
            ORDER BY
                revurderingsdato ASC
        """)

        bevillinger = self._rows_to_dicts(self.db.execute(bev_sql))

        if not bevillinger:
            return []

        koersel_sql = text("""
            SELECT
                vbk.*,
                k.final,
                bt.befordringstype_tekst
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
            LEFT JOIN
                [befordring].[Befordringstype] bt
                ON bt.befordringstype_id = k.befordringstype_id
            WHERE
                b.revurdering = 1
            ORDER BY
                vbk.bevilling_id,
                vbk.gyldig_til DESC
        """)

        koersler = self._rows_to_dicts(self.db.execute(koersel_sql))

        koersel_map: dict = {}
        for k in koersler:
            bid = k["bevilling_id"]
            koersel_map.setdefault(bid, []).append(k)

        for b in bevillinger:
            b["koerselsraekker"] = koersel_map.get(b.get("bevilling_id"), [])

        return bevillinger


    def get_genbehandlinger(self):
        """Get bevillinger flagged for genbehandling, with nested koerselsraekker.

        Returns:
            List of bevilling dicts, each with a 'koerselsraekker' key containing
            a list of that bevilling's koersel rows.
        """

        bev_sql = text("""
            SELECT
                *
            FROM
                [befordring].[view_Genbehandling]
            ORDER BY
                bevilling_id ASC
        """)

        bevillinger = self._rows_to_dicts(self.db.execute(bev_sql))

        if not bevillinger:
            return []

        koersel_sql = text("""
            SELECT
                vbk.*,
                k.final,
                bt.befordringstype_tekst
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
            LEFT JOIN
                [befordring].[Befordringstype] bt
                ON bt.befordringstype_id = k.befordringstype_id
            WHERE
                b.genbehandling = 1
            ORDER BY
                vbk.bevilling_id,
                vbk.gyldig_til DESC
        """)

        koersler = self._rows_to_dicts(self.db.execute(koersel_sql))

        koersel_map: dict = {}
        for k in koersler:
            bid = k["bevilling_id"]
            koersel_map.setdefault(bid, []).append(k)

        for b in bevillinger:
            b["koerselsraekker"] = koersel_map.get(b.get("bevilling_id"), [])

        return bevillinger


    def get_new_applications(self):
        """Get new applications overview data.

        Returns:
            Rows from DATA_NYE_ANSOEGNINGER as dictionaries.

        Notes:
            This reads from a dedicated overview table instead of going through
            BevillingService.
        """

        return self._read_overview_table(
            table_name="[befordring].[view_New_Applications]",
            order_direction="ASC"
        )


    def get_worklist_counts(self) -> dict:
        """How many rows each worklist holds, for the badges in the nav.

        Returns:
            {"nye": int, "revurderinger": int, "genbehandlinger": int,
             "forsendelser": int}

        Notes:
            The nav used to get these by fetching all four worklists in full
            and taking .length — four complete datasets, including
            get_revurderinger's nested kørselsrækker query and the object graph
            built on top of it, to render four small numbers.

            That is a layout load, so it runs again on every invalidateAll, and
            this codebase calls that in 37 places: every bevilling save, every
            kørselsrække edit, every comment, every "PPR vurderet" tick re-read
            all four lists end to end. During an incident on 2026-10-08 those
            four endpoints were timing out alongside everything else, competing
            for the same 30 connections.

            One statement rather than four, so the badges cost a single
            connection out of the pool instead of four. The counts come from
            the same views the lists themselves read, so a badge cannot
            disagree with the page it links to — which is the thing that would
            otherwise rot as the view definitions change.
        """

        sql = text("""
            SELECT
                (SELECT COUNT(*) FROM [befordring].[view_New_Applications]) AS nye,
                (SELECT COUNT(*) FROM [befordring].[view_Revurderinger])    AS revurderinger,
                (SELECT COUNT(*) FROM [befordring].[view_Genbehandling])    AS genbehandlinger,
                (SELECT COUNT(*) FROM [befordring].[view_Forsendelse])      AS forsendelser
        """)

        row = self.db.execute(sql).mappings().first()

        # A missing row cannot happen with scalar subqueries, but a badge is
        # not worth a 500: zeros read as "nothing waiting", which is the safe
        # thing for a number nobody acts on directly.
        if row is None:
            return {
                "nye": 0,
                "revurderinger": 0,
                "genbehandlinger": 0,
                "forsendelser": 0,
            }

        return {key: int(value or 0) for key, value in row.items()}

