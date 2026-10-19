from datetime import date, datetime

from sqlalchemy import (
    Boolean,
    Date,
    Float,
    ForeignKey,
    Integer,
    String,
    Unicode,
    UnicodeText,
    text,
)
from sqlalchemy.dialects.mssql import DATETIME2
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


DB_SCHEMA = "befordring"


class Bevilling(Base):
    __tablename__ = "Bevilling"
    __table_args__ = {"schema": DB_SCHEMA}

    bevilling_id: Mapped[int] = mapped_column(
        Integer,
        primary_key=True,
        autoincrement=True,
    )

    cpr_elev: Mapped[str] = mapped_column(
        String(10),
        ForeignKey(f"{DB_SCHEMA}.Elev.cpr"),
        nullable=False,
    )

    # Display identifier: counts within the child (1, 2, 3) rather than across
    # the whole table, so a caseworker is not left wondering where #2 to #12
    # went. bevilling_id remains the real key — this is what the UI labels a
    # bevilling with, nothing more.
    #
    # Assigned once by BevillingService._next_loebenummer and never reassigned:
    # soft-deleted rows keep their number so the gap they leave stays visible,
    # and every note that referenced a number keeps pointing at the same row.
    # Unique per (cpr_elev, loebenummer) — see
    # backend/db/migrations/008_add_bevilling_loebenummer.sql.
    loebenummer: Mapped[int | None] = mapped_column(Integer, nullable=True)

    adresse_id: Mapped[str] = mapped_column(
        Unicode(36),
        ForeignKey(f"{DB_SCHEMA}.Adresse.adresse_id"),
        nullable=False,
    )

    status_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey(f"{DB_SCHEMA}.Status.status_id"),
        nullable=False,
    )

    matrikel_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey(f"{DB_SCHEMA}.Skolematrikel.matrikel_id"),
        nullable=True,
    )

    ungdomsuddannelse_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey(f"{DB_SCHEMA}.Ungdomsuddannelse.ungdomsuddannelse_id"),
        nullable=True,
    )

    hjemmel_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey(f"{DB_SCHEMA}.Hjemmel.hjemmel_id"),
        nullable=True,
    )

    afgoerelsesbrev_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey(f"{DB_SCHEMA}.Afgoerelsesbrev.afgoerelsesbrev_id"),
        nullable=True,
    )

    revurderingsdato: Mapped[date | None] = mapped_column(Date, nullable=True)
    befordringsudvalg: Mapped[date | None] = mapped_column(Date, nullable=True)

    esdh_noegle: Mapped[str | None] = mapped_column(
        Unicode,
        nullable=True,
    )

    # Deep link to the case in GO. Written by rpa-befordring-nightly-runs,
    # which reads the per-case system id from GO's metadata endpoint — it
    # cannot be derived from esdh_noegle. NULL means "not resolved yet", which
    # is what that step selects on. See migration 026.
    esdh_url: Mapped[str | None] = mapped_column(
        Unicode(500),
        nullable=True,
    )

    # What the citizen asked for, as JSON, curated from the submission at
    # creation. Prefills the "+ Ny kørselsrække" form so a caseworker does not
    # retype what the application already said.
    #
    # A list of (befordringstype, tidspunkt), because the three kørselstype
    # checkboxes are independent and two of them carry their own
    # morgen/eftermiddag pair. NULL on everything created by hand, and on
    # everything that predates migration 029. See that migration for why this
    # is a curated subset rather than the raw form_data, and
    # app/utils/os2forms_mapping.py::get_ansoegningsdata for the writer.
    ansoegningsdata: Mapped[str | None] = mapped_column(
        UnicodeText,
        nullable=True,
    )

    # Walking distance from THIS bevilling's address to THIS bevilling's
    # school, in km. Elev.skoleafstand answers the same question for the
    # child's current folkeregisteradresse and current school, which is a
    # different pair whenever an application follows a move or a referral —
    # and that is exactly when a caseworker needs the number.
    #
    # NULL means "not calculated", never zero. Nothing is backfilled: the
    # value is written when a bevilling is created, when its address or school
    # changes, and on the recalculate button, because every row would
    # otherwise cost an OpenRouteService call for a number nobody asked for.
    # See migration 030.
    gaaafstand_km: Mapped[float | None] = mapped_column(Float, nullable=True)

    # The OS2Forms submission this bevilling was created from, as
    # [RPA].[journalizing].[Forms] holds it. NULL on everything a caseworker
    # creates by hand — only submissions carry one.
    #
    # It is what makes "has this application already produced a bevilling?"
    # answerable, which both the create endpoint's duplicate guard and the
    # reconciliation job depend on. A filtered unique index enforces it in the
    # database. See migration 028.
    os2forms_id: Mapped[str | None] = mapped_column(
        Unicode(36),
        nullable=True,
    )

    sagsbehandler_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey(f"{DB_SCHEMA}.Sagsbehandler.sagsbehandler_id"),
        nullable=True,
    )

    ppr_sagsbehandler_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey(f"{DB_SCHEMA}.PPR_Sagsbehandler.ppr_sagsbehandler_id"),
        nullable=True,
    )

    # Who is handling the bevilling's PENDING work — a revurdering or a
    # genbehandling — as opposed to the two fields above, which say who handled
    # the decision the bevilling records.
    #
    # The distinction exists because the two above are set at creation, so by
    # the time a bevilling reaches a worklist they are already filled on nearly
    # every row, and a filled name reads as "somebody has this one". These are
    # NULL until a caseworker claims the case, and NULL is the useful state:
    # it is the only thing on the row that says nobody has started.
    #
    # Strictly separate from the two above, which the afgørelsesbrev prints
    # {sagsbehandler} from: a case changing hands for a revurdering must not
    # rewrite the name on a letter that was already sent. Cleared when the work
    # is signed off — see update_bevilling. See migration 034.
    ansvarlig_sagsbehandler_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey(f"{DB_SCHEMA}.Sagsbehandler.sagsbehandler_id"),
        nullable=True,
    )

    ansvarlig_ppr_sagsbehandler_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey(f"{DB_SCHEMA}.PPR_Sagsbehandler.ppr_sagsbehandler_id"),
        nullable=True,
    )

    ansoegningsdato: Mapped[date | None] = mapped_column(Date, nullable=True)
    sagsbehandlingsdato: Mapped[date | None] = mapped_column(Date, nullable=True)

    relation_til_barnet: Mapped[str | None] = mapped_column(String, nullable=True)
    foerste_koersel_dato: Mapped[date | None] = mapped_column(Date, nullable=True)
    ansoegningstype: Mapped[str] = mapped_column(String, nullable=False)

    afstandskriterie_dato: Mapped[date | None] = mapped_column(Date, nullable=True)
    afstandskriterie_klassetrin: Mapped[int | None] = mapped_column(Integer, nullable=True)

    begrundelse_fra_formular: Mapped[str | None] = mapped_column(String, nullable=True)

    revurderet_af_ppr: Mapped[bool | None] = mapped_column(Boolean, nullable=True)
    revurderet_af_br: Mapped[bool | None] = mapped_column(Boolean, nullable=True)

    # Flag set by usp_recalculate_bevilling_status: the bevilling keeps its real
    # status (Aktiv/Kommende/…) but is marked as needing reassessment.
    revurdering: Mapped[bool | None] = mapped_column(Boolean, nullable=True)

    # System-managed field — written by usp_recalculate_bevilling_status.
    # Explains why the bevilling is in its current status (e.g. skolekode
    # mismatch, approaching revurderingsdato). Cleared automatically when
    # the status resolves to Aktiv or Ophørt.
    statusbemaerkning: Mapped[str | None] = mapped_column(Unicode, nullable=True)

    genbehandling: Mapped[bool | None] = mapped_column(Boolean, nullable=True)
    genbehandling_haandteret: Mapped[bool | None] = mapped_column(Boolean, nullable=True)
    genbehandling_bemaerkning: Mapped[str | None] = mapped_column(Unicode(500), nullable=True)
    genbehandling_haandteret_adresse_id: Mapped[str | None] = mapped_column(Unicode(36), nullable=True)
    genbehandling_haandteret_skolekode: Mapped[int | None] = mapped_column(Integer, nullable=True)

    created_at: Mapped[datetime] = mapped_column(
        DATETIME2,
        nullable=False,
        server_default=text("sysdatetime()"),
    )

    created_by: Mapped[str] = mapped_column(String, nullable=False)

    updated_at: Mapped[datetime] = mapped_column(
        DATETIME2,
        nullable=False,
        server_default=text("sysdatetime()"),
    )

    updated_by: Mapped[str] = mapped_column(String, nullable=False)

    # Lock flag, mirroring Koersel.final. Set when a decision letter is created
    # and togglable by hand afterwards. Like the kørselsrække flag it marks the
    # bevilling as settled rather than making it read-only — see
    # BevillingService.lock_bevilling. Requires the DB column:
    #   ALTER TABLE [befordring].[Bevilling] ADD final BIT NOT NULL DEFAULT 0
    # (see backend/db/migrations/005_add_bevilling_final.sql).
    final: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        server_default=text("0"),
    )

    aktiv: Mapped[bool] = mapped_column(Boolean, nullable=False)

    koerselsraekker = relationship(
        "Koersel",
        back_populates="bevilling",
    )


class Koersel(Base):
    __tablename__ = "Koersel"
    __table_args__ = {"schema": DB_SCHEMA}

    koersel_id: Mapped[int] = mapped_column(
        Integer,
        primary_key=True,
        autoincrement=True,
    )

    bevilling_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey(f"{DB_SCHEMA}.Bevilling.bevilling_id"),
        nullable=False,
    )

    gyldig_fra: Mapped[date] = mapped_column(Date, nullable=False)
    gyldig_til: Mapped[date] = mapped_column(Date, nullable=False)

    # On its way out. Rutetype now says where a trip starts and ends, which
    # makes the time of day derivable rather than a separate choice — only
    # "Fra hjem til skole" is morning, only "Mellem hjem og skole" is both,
    # everything else is afternoon.
    #
    # Nullable since migration 033 so seed data can stop setting it. The
    # kørselsrække form still requires it and every existing row still has
    # one; see that migration for what has to change before the column can
    # go. NOT the same as the tidspunkt recorded in Bevilling.ansoegningsdata,
    # which is what the citizen asked for on the submission.
    tidspunkt_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey(f"{DB_SCHEMA}.Tidspunkt.tidspunkt_id"),
        nullable=True,
    )

    befordringstype_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey(f"{DB_SCHEMA}.Befordringstype.befordringstype_id"),
        nullable=False,
    )

    # Which route the kørsel covers (e.g. home↔school, home↔club). Nullable —
    # befordring is not always strictly between home and school.
    rutetype_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey(f"{DB_SCHEMA}.Rutetype.rutetype_id"),
        nullable=True,
    )

    bevilget_koereafstand_pr_vej: Mapped[float | None] = mapped_column(
        Float,
        nullable=True,
    )

    taxa_id: Mapped[str | None] = mapped_column(String, nullable=True)
    kommentar: Mapped[str | None] = mapped_column(String, nullable=True)

    # Skolerejsekort-specific values, entered on the koerselsrække form.
    # Nullable and type-specific, exactly like taxa_id / bevilget_koereafstand_pr_vej.
    transporttid_i_bus: Mapped[int | None] = mapped_column(Integer, nullable=True)
    skift_med_bus: Mapped[int | None] = mapped_column(Integer, nullable=True)

    # Taxa-specific values, shown for the four taxa kørselstyper (Rutekørsel,
    # Skånekørsel, Solo kørsel, Variabel kørsel). Same pattern as the
    # skolerejsekort pair above: nullable, and cleared when the kørselstype is
    # something else, so a value can never survive a change of type.
    koersel_til_institution: Mapped[bool | None] = mapped_column(Boolean, nullable=True)
    max_minutter_i_transport: Mapped[int | None] = mapped_column(Integer, nullable=True)

    # Egenbefordring-specific: which person receives the kilometre reimbursement.
    # Two mutually exclusive columns — exactly one should be set for egenbefordring:
    #   modtager_id  → FK to Part (øvrig part, manually added on the Parter tab)
    #   modtager_cpr → CPR from Foraelder table (legal guardian / parent)
    # Keeping them separate preserves the strict Foraelder/Part distinction.
    koerselsgodtgoerelse_modtager_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey(f"{DB_SCHEMA}.Part.part_id"),
        nullable=True,
    )
    koerselsgodtgoerelse_modtager_cpr: Mapped[str | None] = mapped_column(
        String(10),
        nullable=True,
    )

    final: Mapped[bool] = mapped_column(Boolean, nullable=False)

    # Soft-delete flag. Rows are hidden (aktiv = 0) rather than hard-deleted so
    # history is preserved. Requires the DB column:
    #   ALTER TABLE [befordring].[Koersel] ADD aktiv BIT NOT NULL DEFAULT 1
    # (see backend/db/migrations/001_add_koersel_aktiv.sql).
    aktiv: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        server_default=text("1"),
    )

    bevilling = relationship(
        "Bevilling",
        back_populates="koerselsraekker",
    )


class BevillingHjaelpemiddelLink(Base):
    __tablename__ = "Bevilling_Hjaelpemiddel_LINK"
    __table_args__ = {"schema": DB_SCHEMA}

    bevilling_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey(f"{DB_SCHEMA}.Bevilling.bevilling_id"),
        primary_key=True,
    )

    hjaelpemiddel_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey(f"{DB_SCHEMA}.Hjaelpemiddel.hjaelpemiddel_id"),
        primary_key=True,
    )


class KoerselKoerselstypeTillaegLink(Base):
    __tablename__ = "Koersel_KoerselstypeTillaeg_LINK"
    __table_args__ = {"schema": DB_SCHEMA}

    koersel_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey(f"{DB_SCHEMA}.Koersel.koersel_id"),
        primary_key=True,
    )

    tillaeg_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey(f"{DB_SCHEMA}.KoerselstypeTillaeg.tillaeg_id"),
        primary_key=True,
    )


class KoerselUgedagLink(Base):
    __tablename__ = "Koersel_Ugedag_LINK"
    __table_args__ = {"schema": DB_SCHEMA}

    koersel_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey(f"{DB_SCHEMA}.Koersel.koersel_id"),
        primary_key=True,
    )

    dag_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey(f"{DB_SCHEMA}.Ugedag.dag_id"),
        primary_key=True,
    )


class Brev(Base):
    """One decision letter that was created for a bevilling.

    Creating a letter queues an ATS work item; it does NOT post anything to the
    parents. This table is what separates the two: a row appears when the letter
    is generated, and `afsendt` is set when a caseworker has actually sent it.
    The Forsendelse page is the worklist of rows where afsendt = 0.

    A bevilling has many of these over time — a påtænkt afslag followed by the
    final afslag, or a bevilling followed by an ophør letter — which is why this
    is its own table rather than a pair of columns on Bevilling.
    """

    __tablename__ = "Brev"
    __table_args__ = {"schema": DB_SCHEMA}

    brev_id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)

    bevilling_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey(f"{DB_SCHEMA}.Bevilling.bevilling_id"),
        nullable=False,
    )

    cpr_elev: Mapped[str] = mapped_column(String(10), nullable=False)

    # ATS work-item reference, e.g. "0101101234_2026-09-15_14_30_05". Nothing
    # reads it yet — stored so the page can later surface whether the RPA
    # actually produced the document.
    reference: Mapped[str | None] = mapped_column(Unicode(100), nullable=True)

    # Snapshots, deliberately not foreign keys: the letter said what it said.
    # Editing the bevilling afterwards must not rewrite history.
    afgoerelsesbrev_tekst: Mapped[str | None] = mapped_column(Unicode(500), nullable=True)
    brev_i_forbindelse_med: Mapped[str | None] = mapped_column(Unicode(100), nullable=True)

    oprettet_tidspunkt: Mapped[datetime] = mapped_column(
        DATETIME2,
        nullable=False,
        server_default=text("sysdatetime()"),
    )
    oprettet_af: Mapped[str | None] = mapped_column(Unicode(200), nullable=True)

    afsendt: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        server_default=text("0"),
    )
    afsendt_tidspunkt: Mapped[datetime | None] = mapped_column(DATETIME2, nullable=True)
    afsendt_af: Mapped[str | None] = mapped_column(Unicode(200), nullable=True)

    aktiv: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        server_default=text("1"),
    )
