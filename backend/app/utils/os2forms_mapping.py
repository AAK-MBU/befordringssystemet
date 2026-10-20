"""Helper functions for mapping OS2Forms payloads.

This module contains small mapping helpers used when converting raw OS2Forms
submission data into internal API values.

The functions are kept separate from OS2FormsService to make the mapping logic
easier to read, test, and reuse.
"""


def is_checked(value) -> bool:
    """Return True when an OS2Forms checkbox-like value is checked."""

    return str(value).strip() == "1"


# The one form more than one kind of applicant fills in, and therefore the one
# form where "whose name and address is this?" has to be asked.
# See _MIDLERTIDIG_NAVN_FELTER.
_MIDLERTIDIG_WEBFORM = "ny_ansoegning_om_midlertidig_koe"


def get_begrundelse(payload: dict) -> str:
    """Determine the applicant's foundation for applying."""

    begrundelse_fields = {
        "sygdom_funktionsnedsaettelse_handicap": "Sygdom/funktionsnedsaettelse/handicap",
        "trafikfarlig_vej": "Trafikfarlig vej",
        "langt_mellem_skole_og_hjem": "Langt mellem skole og hjem",
    }

    begrundelser = []

    for field_name, label in begrundelse_fields.items():
        if is_checked(payload.get(field_name)):
            begrundelser.append(label)

    return ", ".join(begrundelser)


def get_relation_til_barnet(payload: dict) -> str | None:
    """Determine the applicant's relation to the child/student.

    Args:
        payload:
            Parsed OS2Forms submission data.

    Returns:
        A relation text value, for example:
        - "Forældremyndighed"
        - "Ansøger selv"
        - "Uddannelsesinstitution"
        - A manually entered relation
        - None if no relation can be determined

    Notes:
        The temporary transport form uses different fields than the normal
        application forms, so it has its own mapping logic.
    """

    webform_id = payload.get("webform_id")

    foraeldremyndighed = payload.get(
        "er_du_foraeldremyndighedsindehaver_til_barnet_der_ansoeges_paa_v"
    )

    anden_tilknytning = payload.get("angiv_din_tilknytning_til_barnet")

    hvem_ansoges_der_for = payload.get(
        "hvem_ansoeger_du_om_midlertidig_koersel_for"
    )

    # Temporary transport has its own applicant/relation question.
    if webform_id == _MIDLERTIDIG_WEBFORM:
        if hvem_ansoges_der_for == "Mit barn":
            return "Forældremyndighed"

        if hvem_ansoges_der_for == "Et barn, som jeg ansøger på vegne af":
            return anden_tilknytning

        if hvem_ansoges_der_for == "Mig selv":
            return "Ansøger selv"

        if hvem_ansoges_der_for == "En elev på en uddannelsesinstitution":
            return "Uddannelsesinstitution"

        return None

    # For normal application forms, use the parent custody question first.
    if foraeldremyndighed == "Ja":
        return "Forældremyndighed"

    # If the applicant does not have custody, use their manually entered
    # relation to the child.
    return anden_tilknytning


# Where the student's name and address are written, in the order they must be
# read. The two fast-koersel forms are only ever filled in by a parent, so the
# child's own fields are the only ones they carry: picked from a MitID
# dropdown, or typed in where the child could not be picked.
_NAVN_FELTER = ("barnets_navn_mitid", "barnets_navn_manuelt")
_ADRESSE_FELTER = ("barnets_adresse_mitid", "barnets_adresse_manuelt")

# Midlertidig koersel is filled in by four kinds of applicant, and each writes
# the student to its own pair of fields:
#
#   a parent  - picks the child from a MitID dropdown (barnets_*_mitid) or
#               types the child in (barnets_*_manuelt)
#   a teacher - types the pupil in (elevens_*)
#   the pupil - fills none of the above; the MitID login block (navn_mitid,
#               adresse_mitid) IS the student
#
# That is the same cast of applicants the CPR rule deals with - see
# cpr_extraction.find_cpr in rpa-befordring-kontrol - and the order here
# carries the same hazard. The MitID login block holds whoever is logged in,
# so for a parent navn_mitid and adresse_mitid are the PARENT's. The fields
# that name someone else are therefore read first, and the login block only
# where none of them is filled. Reading adresse_mitid first would put a
# parent's address on the child's bevilling - the place a taxi is dispatched
# to and a letter is sent to.
#
# Kept to this form rather than appended to the two tuples above, for the same
# reason. A fast-koersel submission carrying no child address is broken and
# should stop as a 422 a caseworker can see; falling through to the logged-in
# parent's address would answer it quietly, and wrongly.
_MIDLERTIDIG_NAVN_FELTER = ("elevens_navn", *_NAVN_FELTER, "navn_mitid")
_MIDLERTIDIG_ADRESSE_FELTER = ("elevens_adresse", *_ADRESSE_FELTER, "adresse_mitid")


def _foerste_udfyldte(payload: dict, felter: tuple[str, ...]) -> str | None:
    """The value of the first of `felter` the submission filled in."""

    for felt in felter:
        value = payload.get(felt)

        if isinstance(value, str):
            value = value.strip()

        if value:
            return value

    return None


def _felter_for_formular(
    payload: dict,
    standard: tuple[str, ...],
    midlertidig: tuple[str, ...],
) -> tuple[str, ...]:
    """The field order to read, for the form this submission came from."""

    if payload.get("webform_id") == _MIDLERTIDIG_WEBFORM:
        return midlertidig

    return standard


def get_adresse_for_bevilling(payload: dict) -> str | None:
    """Determine which address should be used for the bevilling.

    Args:
        payload:
            Parsed OS2Forms submission data.

    Returns:
        The address that should be stored on the bevilling.
        Returns None if no address exists in the payload.

    Notes:
        The student's own address is used by default. Which field holds it
        depends on who filled the form in - see _MIDLERTIDIG_ADRESSE_FELTER,
        which is also where the order is explained.

        If the form says the child should be transported to/from another
        address, that other address is used instead.
    """

    adresse = _foerste_udfyldte(
        payload,
        _felter_for_formular(payload, _ADRESSE_FELTER, _MIDLERTIDIG_ADRESSE_FELTER),
    )

    if is_alternate_address(payload):
        return payload.get("barnets_anden_adresse") or adresse

    return adresse


# The exact strings OS2Forms substitutes for a value it holds but will not
# disclose, for a citizen with navne- og adressebeskyttelse.
#
# Matched trimmed and case-insensitively, but otherwise EXACTLY. A loose
# match here would read a real address as withheld and quietly resolve the
# bevilling to the registered one instead — which is the wrong address for a
# family that has just moved. A marker we fail to recognise costs a 422 a
# caseworker can see; one we recognise too eagerly costs a taxi to the wrong
# home. Add new spellings here as they are observed, not by loosening the
# comparison.
_PROTECTED_MARKERS = frozenset({
    "name and address protected",
})


def is_protected_value(value: str | None) -> bool:
    """Is this field the placeholder OS2Forms writes instead of a withheld value?

    True only for the exact markers above. Note what this is NOT: it does not
    mean the value is unknown or unmatched, it means the form deliberately
    held it back. That distinction is what makes it safe to read the value
    from elsewhere — see OS2FormsService._resolve_adresse_id.
    """

    return (value or "").strip().casefold() in _PROTECTED_MARKERS


def is_alternate_address(payload: dict) -> bool:
    """Is the bevilling address deliberately NOT the folkeregisteradresse?

    True where the family ticked "kør til/fra en anden adresse". The address
    on the bevilling is then a different place by design, so anything that
    reasons from the child's registered address — see
    OS2FormsService._folkeregister_adresse_id — has to stand down.
    """

    # OS2Forms checkbox values often arrive as strings.
    # Here, "1" means the checkbox/condition is selected.
    return payload.get("barnet_skal_koeres_til_fra_anden_adresse") == "1"


def get_barn_navn(payload: dict) -> str | None:
    """Determine the student's name from an OS2Forms payload.

    Which field holds it depends on who filled the form in - see
    _MIDLERTIDIG_NAVN_FELTER, which is also where the order is explained.

    Kept in step with get_adresse_for_bevilling deliberately. This is the
    adresseringsnavn on an Elev row created from a submission, and unlike the
    address a name nobody wrote costs no 422: it just produces a student who
    reads as blank everywhere. So a new applicant path has to be added to both
    lists at once, not to the address list alone when an address fails.
    """

    return _foerste_udfyldte(
        payload,
        _felter_for_formular(payload, _NAVN_FELTER, _MIDLERTIDIG_NAVN_FELTER),
    )


def get_hjaelpemiddel_names(payload: dict) -> list[str]:
    """Extract hjaelpemiddel names from the OS2Forms payload.

    Args:
        payload:
            Parsed OS2Forms submission data.

    Returns:
        A list of hjaelpemiddel name strings, or an empty list if none
        were marked or the question was not answered.

    Notes:
        OS2Forms sends multi-value checkbox fields as indexed keys:
            angiv_hjaelpemiddel[0] = 'Kørestol'
            angiv_hjaelpemiddel[1] = 'Rollator'

        The presence question er_der_et_hjaelpemiddel_... must be 'Ja'
        for the list to be considered.
    """

    if payload.get("er_der_et_hjaelpemiddel_der_skal_med_under_koersel_") != "Ja":
        return []

    names = []

    for key, value in payload.items():
        if key.startswith("angiv_hjaelpemiddel[") and value:
            names.append(str(value).strip())

    return names


def get_ansoegningstype(payload: dict) -> str:
    """Determine the application type from the OS2Forms webform ID.

    Args:
        payload:
            Parsed OS2Forms submission data.

    Returns:
        Application type text used internally by the API.

    Notes:
        Unknown webform IDs fall back to "Fast kørsel".
    """

    webform_id = payload.get("webform_id")

    if webform_id == _MIDLERTIDIG_WEBFORM:
        return "Midlertidig kørsel"

    # "Skolebus" is treated as regular "Fast kørsel" - they are the same koersel
    # type; we only distinguish "Fast kørsel" from "Midlertidig kørsel". The
    # skolebus webform therefore falls through to the default below.
    #
    # This value was "Kørsel" until migration 009 renamed it; existing rows were
    # updated at the same time, so both old and new data read "Fast kørsel".
    return "Fast kørsel"


# The three kørselstype checkboxes, in the order the form presents them, and
# the Befordringstype each one means. They are independent: a citizen may tick
# one, two or all three.
#
# The morning/afternoon pair belongs to the kørselstype, not to the
# application — egen befordring and rutekørsel each carry their own. Buskort
# has none at all, which is why its entry is None rather than a pair of field
# names that do not exist.
_KOERSELSTYPE_FELTER: list[tuple[str, str, tuple[str, str] | None]] = [
    (
        "buskort_til_offentlig_transport",
        "Skolerejsekort",
        None,
    ),
    (
        "koerselsgodtgoerelse_for_egen_befordring",
        "Egen befordring",
        (
            "koerselsgodtgoerelse_aflevering_morgen",
            "koerselsgodtgoerelse_afhentning_eftermiddag",
        ),
    ),
    (
        "rutekoersel_med_taxa_minibus",
        "Rutekørsel",
        (
            "rutekoersel_aflevering_morgen",
            "rutekoersel_afhentning_eftermiddag",
        ),
    ),
]

# The skolebus form asks no kørselstype question — submitting it IS the
# request. It asks about morning and afternoon as Ja/Nej radios rather than
# checkboxes.
_SKOLEBUS_WEBFORM = "ansoegning_om_koersel_med_skoleb"
_SKOLEBUS_TIDSPUNKT = ("morgenkoersel", "eftermiddagskoersel")

# The Tidspunkt lookup texts. Matched by the frontend against the lookup list,
# so they have to read exactly as the lookup spells them.
_TIDSPUNKT_MORGEN = "Morgen"
_TIDSPUNKT_EFTERMIDDAG = "Eftermiddag"
_TIDSPUNKT_BEGGE = "Morgen og eftermiddag"

ANSOEGNINGSDATA_VERSION = 1


def _tidspunkt(morgen: bool, eftermiddag: bool) -> str | None:
    """A Tidspunkt label from a morning/afternoon pair.

    None when neither was ticked. That is not the same as "both" and must not
    become a default: the caseworker should choose rather than accept a value
    nobody stated.
    """

    if morgen and eftermiddag:
        return _TIDSPUNKT_BEGGE

    if morgen:
        return _TIDSPUNKT_MORGEN

    if eftermiddag:
        return _TIDSPUNKT_EFTERMIDDAG

    return None


def get_ansoegningsdata(payload: dict) -> dict | None:
    """What the citizen asked for, curated for Bevilling.ansoegningsdata.

    Args:
        payload:
            Parsed OS2Forms submission data.

    Returns:
        A dictionary ready to serialise, or None when the submission states no
        kørselstype at all — there is nothing to prefill from, and an empty
        list would claim otherwise.

    Notes:
        Deliberately narrow. It holds only what the "+ Ny kørselsrække" form
        can be prefilled from, and nothing that duplicates a column the
        bevilling already has:

          * dato_for_foerste_koersel is already Bevilling.foerste_koersel_dato.
            Two sources for one value is how they drift.
          * ugedage are NOT derived. The forms carry a ringetid grid, but a
            school timetable is not a statement of which days kørsel is
            granted for, and the caseworker enters those by hand.
          * tillæg are not here because no form asks: Fast forsæde, Co-driver
            and the rest are decisions, not wishes.

        Checkbox values are read through is_checked, the same "1" convention
        the rest of this module relies on. Nesting does not matter — a field
        three containers deep arrives flat, as angiv_hjaelpemiddel already
        proves from this very branch of this very form.
    """

    webform_id = payload.get("webform_id")

    if webform_id == _SKOLEBUS_WEBFORM:
        morgen_felt, eftermiddag_felt = _SKOLEBUS_TIDSPUNKT

        koerselstyper = [
            {
                "befordringstype": "Skolebus",
                "tidspunkt": _tidspunkt(
                    str(payload.get(morgen_felt, "")).strip() == "Ja",
                    str(payload.get(eftermiddag_felt, "")).strip() == "Ja",
                ),
            }
        ]
    else:
        koerselstyper = []

        for felt, befordringstype, tidspunkt_felter in _KOERSELSTYPE_FELTER:
            if not is_checked(payload.get(felt)):
                continue

            if tidspunkt_felter is None:
                tidspunkt = None
            else:
                morgen_felt, eftermiddag_felt = tidspunkt_felter
                tidspunkt = _tidspunkt(
                    is_checked(payload.get(morgen_felt)),
                    is_checked(payload.get(eftermiddag_felt)),
                )

            koerselstyper.append(
                {"befordringstype": befordringstype, "tidspunkt": tidspunkt}
            )

    if not koerselstyper:
        return None

    return {
        "koerselstyper": koerselstyper,
        "formular": webform_id,
        "version": ANSOEGNINGSDATA_VERSION,
    }


def get_os2forms_id(payload: dict) -> str | None:
    """The OS2Forms submission id, if the caller sent one.

    Args:
        payload:
            Parsed OS2Forms submission data.

    Returns:
        The submission id as a string, or None.

    Notes:
        This is what makes a submission recognisable on a second delivery, so
        a retry updates nothing instead of creating a second bevilling for the
        same family.

        Two spellings are accepted because two callers send it. The
        reconciliation job reads form_id from [RPA].[journalizing].[Forms] and
        sends that name; an OS2Forms remote post handler would send the
        submission's own uuid token. They are the same value.

        Returns None rather than "" for a blank, so the caller's "did they
        send one?" check does not have to repeat the emptiness test.
    """

    for key in ("form_id", "uuid"):
        value = payload.get(key)

        if value:
            return str(value).strip() or None

    return None
