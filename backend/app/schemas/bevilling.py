import re
from datetime import date

from pydantic import BaseModel, ConfigDict, Field, model_validator

# A valid date in this system is a real calendar date with an exactly-4-digit
# year written as YYYY-MM-DD. Native date pickers happily accept absurd years
# (HTML allows up to 275760), so this guards the untyped letter payload.
_ISO_DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def _is_valid_iso_date(value: str) -> bool:
    if not _ISO_DATE_RE.match(value):
        return False

    try:
        date.fromisoformat(value)
    except ValueError:
        return False

    return True


class BevillingCreateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    adresse_id: str
    matrikel_id: int | None = None
    ungdomsuddannelse_id: int | None = None
    hjemmel_id: int | None = None
    afgoerelsesbrev_id: int | None = None

    revurderingsdato: date | None = None
    befordringsudvalg: date | None = None
    esdh_noegle: str | None = None
    esdh_url: str | None = None

    # The OS2Forms submission id, so a resubmitted or re-driven form cannot
    # produce a second bevilling. Only the OS2Forms path sets it.
    # Curated submission data, serialised JSON. See migration 029.
    ansoegningsdata: str | None = None
    os2forms_id: str | None = None

    sagsbehandler_id: int | None = None
    ppr_sagsbehandler_id: int | None = None

    ansoegningsdato: date | None = None
    sagsbehandlingsdato: date | None = None
    relation_til_barnet: str | None = None
    foerste_koersel_dato: date | None = None
    ansoegningstype: str | None = None

    afstandskriterie_dato: date | None = None
    afstandskriterie_klassetrin: int | None = None
    begrundelse_fra_formular: str | None = None

    hjaelpemiddel_ids: list[int] = Field(default_factory=list)


class BevillingCreateResponse(BaseModel):
    bevilling_id: int
    status_text: str
    rows_inserted: int


class BevillingUpdateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    status_id: int | None = None
    reset_status: bool = False
    matrikel_id: int | None = None
    ungdomsuddannelse_id: int | None = None
    ansoegningsdato: date | None = None
    sagsbehandlingsdato: date | None = None

    # Editable after creation. A bevilling created from an OS2Forms submission
    # gets no esdh_noegle — the submission does not know the GO case — and
    # until this was here nobody could give it one: not a caseworker, not the
    # API. A bevilling without a key also never gets a link into the case,
    # because the link is resolved FROM the key.
    esdh_noegle: str | None = None

    # The resolved deep link. Written by rpa-befordring-kontrol alongside the
    # key, and by the nightly run as a backstop. It cannot be composed from
    # the key — GO's URL carries a per-case system id — so it is stored rather
    # than derived. See migration 026.
    esdh_url: str | None = None
    adresse_id: str | None = None
    afstandskriterie_dato: date | None = None
    afstandskriterie_klassetrin: int | None = None
    relation_til_barnet: str | None = None
    revurderingsdato: date | None = None
    befordringsudvalg: date | None = None
    hjemmel_id: int | None = None
    afgoerelsesbrev_id: int | None = None
    sagsbehandler_id: int | None = None
    ppr_sagsbehandler_id: int | None = None
    revurderet_af_ppr: bool | None = None
    revurderet_af_br: bool | None = None
    genbehandling_haandteret: bool | None = None

    # Lock flag. Sent on its own by the lock/unlock control, exactly as the
    # kørselsrække lock sends {"final": true} to its own update endpoint.
    final: bool | None = None


class PprSagsbehandlerUpdateRequest(BaseModel):
    """Body for the PPR-sagsbehandler endpoint, which writes nothing else.

    Required rather than optional, and nullable: the field has to be present so
    the caller cannot send an empty body and have it read as "clear it", while
    an explicit null is how the assignment is removed. That is the whole point
    of the endpoint - PPR must be able to take a case off someone as well as
    put one on them.
    """

    model_config = ConfigDict(extra="forbid")

    ppr_sagsbehandler_id: int | None = Field(...)


class AnsvarligUpdateRequest(BaseModel):
    """Body for the two "ansvarlig" endpoints, which write nothing else.

    Required rather than optional, and nullable: an explicit null is how a case
    is released again, so the field has to be present rather than absent — an
    empty body would otherwise read as "release it".
    """

    model_config = ConfigDict(extra="forbid")

    tildelt_id: int | None = Field(...)


class OensketBefordringstypeUpdateRequest(BaseModel):
    """Body for the ønsket kørselstype endpoint, which writes nothing else.

    The value is the Befordringstype LABEL, not an id, because that is how
    Bevilling.ansoegningsdata already spells it — the submission names types by
    text, and this field lives in the same JSON. Validated against the lookup
    by the service, so the label cannot drift into free text.

    Required rather than optional, and nullable: an explicit null is how a
    caseworker takes their reading back off a bevilling, leaving the citizen's
    own ticks showing again.
    """

    model_config = ConfigDict(extra="forbid")

    befordringstype: str | None = Field(...)


class RevurderetAfPprUpdateRequest(BaseModel):
    """Body for the "PPR vurderet" endpoint, which writes nothing else.

    Required rather than optional: the revurdering page toggles the flag both
    ways, so an absent field must not be read as either value.
    """

    model_config = ConfigDict(extra="forbid")

    revurderet_af_ppr: bool = Field(...)


class HjaelpemidlerUpdateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    hjaelpemiddel_ids: list[int] = Field(default_factory=list)


class KoerselsraekkeCreateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    gyldig_fra: date
    gyldig_til: date
    # Optional since migration 033. Rutetype now says where a trip starts and
    # ends, which makes the time of day derivable, and the form no longer
    # asks for it — a required field here would 422 every kørselsrække
    # created without one.
    tidspunkt_id: int | None = None
    befordringstype_id: int
    rutetype_id: int | None = None
    bevilget_koereafstand_pr_vej: float | None = None

    taxa_id: str | None = None
    kommentar: str | None = None
    final: bool = False

    # Skolerejsekort-specific.
    transporttid_i_bus: int | None = None
    skift_med_bus: int | None = None

    # Taxa-specific (Rutekørsel, Skånekørsel, Solo kørsel, Variabel kørsel).
    koersel_til_institution: bool | None = None
    max_minutter_i_transport: int | None = None

    # Egenbefordring-specific: recipient of the kilometre reimbursement.
    # Exactly one should be provided — mutually exclusive.
    koerselsgodtgoerelse_modtager_id: int | None = None   # øvrig part (Part table)
    koerselsgodtgoerelse_modtager_cpr: str | None = None  # foraelder (Foraelder table)

    tillaeg_ids: list[int] = Field(default_factory=list)
    dag_ids: list[int] = Field(default_factory=list)


class KoerselsraekkeCreateResponse(BaseModel):
    koersel_id: int
    rows_inserted: int


class KoerselsraekkeUpdateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    tidspunkt_id: int | None = None
    befordringstype_id: int | None = None
    rutetype_id: int | None = None
    bevilget_koereafstand_pr_vej: float | None = None
    gyldig_fra: date | None = None
    gyldig_til: date | None = None
    taxa_id: str | None = None
    kommentar: str | None = None
    final: bool | None = None

    # Skolerejsekort-specific.
    transporttid_i_bus: int | None = None
    skift_med_bus: int | None = None

    # Taxa-specific (Rutekørsel, Skånekørsel, Solo kørsel, Variabel kørsel).
    koersel_til_institution: bool | None = None
    max_minutter_i_transport: int | None = None

    # Egenbefordring-specific: recipient of the kilometre reimbursement.
    # Exactly one should be provided — mutually exclusive.
    koerselsgodtgoerelse_modtager_id: int | None = None   # øvrig part (Part table)
    koerselsgodtgoerelse_modtager_cpr: str | None = None  # foraelder (Foraelder table)


class KoerselTillaegUpdateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    tillaeg_ids: list[int] = Field(default_factory=list)


class KoerselDageUpdateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    dag_ids: list[int] = Field(default_factory=list)


class LetterCreateRequest(BaseModel):
    model_config = ConfigDict(extra="allow")

    @model_validator(mode="after")
    def _validate_date_fields(self) -> "LetterCreateRequest":
        """Reject any date-named extra field that is not a valid ISO date.

        The letter payload is dynamic (``extra="allow"``), so its date values
        (e.g. ``dato_for_seneste_bevilling``, ``ophoersdato``) arrive as raw
        strings with no type coercion. Any extra field whose name contains
        "dato" must therefore be a real calendar date with a 4-digit year, or
        empty/None.
        """

        extras = self.__pydantic_extra__ or {}

        for key, value in extras.items():
            if "dato" not in key.lower():
                continue

            if value in (None, ""):
                continue

            if not isinstance(value, str) or not _is_valid_iso_date(value):
                raise ValueError(
                    f"Feltet '{key}' skal være en gyldig dato på formen "
                    f"åååå-mm-dd."
                )

        return self
