"""Matching a free-text address from OS2Forms against the Adresse register.

Why this is needed
------------------
The three address fields on the application forms do not all use the same
formatting, because they do not all come from the same place:

    barnets_adresse_manuelt  os2forms_dawa_address         DAWA / DAR
    barnets_anden_adresse    os2forms_dawa_address         DAWA / DAR
    barnets_adresse_mitid    os2forms_mitid_child_address  CPR via MitID
    adresse_mitid            MitID login block             CPR via MitID
    elevens_adresse          filled in by a school employee

The last two only appear on the midlertidig form, which more than one kind of
applicant fills in; os2forms_mapping decides which of the five is read. Of the
two, adresse_mitid comes from the same CPR-via-MitID source as
barnets_adresse_mitid and so carries the same formatting, described below.
elevens_adresse is the one field here whose widget has not been confirmed - if
it turns out to diverge from DAR in some third way, that belongs in the list
of named cases below, not in a rule loosened to absorb it.

The two DAWA fields emit the same DAR string that Adresse.adresse_tekst holds,
so they match exactly. The MitID field does not: it carries CPR's own
formatting, where the floor is zero-padded and the floor and door follow the
house number with no comma and no full stop.

    MitID / CPR     "Rosenhøj Bakke 22 01 th, 8260 Viby J"
    DAR / Adresse   "Rosenhøj Bakke 22, 1. th, 8260 Viby J"

That is one address written two ways, and an exact string comparison rejects
it. It affects every application where the child is picked from the MitID list
AND lives on a floor. Ground-floor and house addresses carry no floor or door
at all, so both sources write them identically and they matched by accident —
which is why this only surfaced once an apartment address came through.

MitID also drops the supplerende bynavn, which DAR keeps:

    MitID / CPR     "Thomas Windings Gade 52, 8200 Aarhus N"
    DAR / Adresse   "Thomas Windings Gade 52, Lisbjerg, 8200 Aarhus N"

So that is a second, independent reason a MitID address fails to match, and it
hits the villages inside an Aarhus postcode rather than the apartments. See
strip_supplerende_bynavn for how far it is safe to ignore the component.

Scope: two observed divergences, and nothing else
-------------------------------------------------
These rules exist to close the two differences that have actually been seen
between a submission and the register:

    1. MitID writes the floor zero-padded and runs it onto the house number
       without the comma and full stop DAR uses.
    2. MitID drops the supplerende bynavn that DAR keeps.

Nothing here is meant to anticipate a third. A mismatch of some other kind
should fail, loudly, as a 422 naming the address — that is how the next class
of difference gets discovered and understood, rather than being quietly
absorbed by a rule broad enough to swallow it. Resist widening these rules to
make one more address resolve; find out what the difference is first.

What this normalisation may and may not do
------------------------------------------
It is deliberately dumb, and should stay that way. It collapses the characters
that only ever differ as punctuation into a single space, and it removes
leading zeros from numbers. It does not expand or abbreviate anything, does not
reorder, does not drop or supply a missing component, and knows nothing about
streets, floors or doors. Every remaining character must be identical for two
addresses to match.

Widening it is a decision to accept a possibly wrong address on a bevilling —
the address a taxi is dispatched to and a letter is sent to. A false negative
costs a caseworker two minutes; a false positive sends a child to the wrong
door. Prefer the false negative.

Why the separators collapse to a space rather than vanishing
------------------------------------------------------------
Deleting them outright looks tidier and is wrong. The separators are what
divide the house number from the floor, so removing them lets the two run
together into one number, and distinct addresses start colliding. Measured
against the Aarhus rows in the register (db/analyse/
adresse_normalisering_kollisioner.sql), deletion collapses:

    Skovvejen 1, 1. 1  /  Skovvejen 11, 1.  /  Skovvejen 111   -> skovvejen111
    Abildgade 2, 3.    /  Abildgade 23                         -> abildgade23
    Anton Rosens Plads 1, b  /  Anton Rosens Plads 1B          -> ...plads1b

Those are different front doors. Keeping one space between the tokens
separates every one of them again, and costs nothing: the MitID and DAR
spellings of the same address differ only in WHICH separator sits between the
tokens and in the zero padding, never in where the token boundaries fall.

The last line matters for the house letter in particular. CPR and DAR both
keep it attached to the number ("22B"), so a letter standing alone as its own
token is a door, not part of the house number — and "1 B" must therefore NOT
match "1B". Collapsing to a space preserves that distinction; deleting the
separators destroys it.
"""

import re

# Characters that differ between the two sources purely as punctuation:
# full stops, commas and any run of whitespace. They carry no meaning of
# their own, but WHERE they fall does, so they collapse to one space rather
# than disappearing.
_SEPARATORS = re.compile(r"[.,\s]+")

# Leading zeros, but only where a digit survives them: "01" -> "1",
# "0022B" -> "22B", "0" -> "0". A token that merely starts with a zero
# without being a number ("0A") is left alone.
_LEADING_ZEROS = re.compile(r"^0+(?=\d)")

# The first digit in the string marks the end of the street name. Everything
# before it is the only part of an address guaranteed to be written the same
# way by both sources, so it is what the indexed prefix seek uses.
_FIRST_DIGIT = re.compile(r"\d")

# The postcode is the four-digit group that follows a comma and is itself
# followed by the town. Anchoring on the comma keeps a house number such as
# "2201" from being read as one.
_POSTNUMMER = re.compile(r",\s*(\d{4})\s+\S")

_DIGIT = re.compile(r"\d")

# A token this long is a place name, not a floor or a door. See
# strip_supplerende_bynavn for why the threshold leans the way it does.
_MIN_BYNAVN_TOKEN = 5


def normalise_adresse(tekst: str | None) -> str:
    """Reduce an address to the form used for comparison.

    Args:
        tekst:
            An address string from either source, or None.

    Returns:
        The address as its tokens, single-space separated, with numeric
        leading zeros removed and case folded. An empty string for empty
        input — callers must treat that as "no address", never as a value
        that can match.

    Examples:
        >>> normalise_adresse("Rosenhøj Bakke 22 01 th, 8260 Viby J")
        'rosenhøj bakke 22 1 th 8260 viby j'
        >>> normalise_adresse("Rosenhøj Bakke 22, 1. th, 8260 Viby J")
        'rosenhøj bakke 22 1 th 8260 viby j'
        >>> normalise_adresse("Skovvejen 1, 1. 1, 8000 Aarhus C")
        'skovvejen 1 1 1 8000 aarhus c'
        >>> normalise_adresse("Skovvejen 111, 8000 Aarhus C")
        'skovvejen 111 8000 aarhus c'
    """

    if not tekst:
        return ""

    # Split on separators, strip zeros per token, then rejoin with exactly one
    # space. The space is load-bearing — see the module docstring. Stripping
    # has to happen per token, because once the tokens are joined there are no
    # boundaries left to find and "22" + "01" reads as the number 2201.
    tokens = _SEPARATORS.split(tekst.strip())

    return " ".join(_LEADING_ZEROS.sub("", token) for token in tokens).casefold()


def lookup_prefix(tekst: str) -> str:
    """The leading substring to seek on in the Adresse index.

    Returns everything before the first digit — the street name — with any
    trailing separator removed, so that it is a literal prefix of the stored
    DAR string regardless of whether the source wrote "Bakke 22" or
    "Bakke, 22".

    Returns an empty string when the address starts with a digit or holds no
    digit at all. Callers must refuse to search on that rather than fall back
    to a wider query: without a usable prefix the only alternative is a
    leading-wildcard scan of roughly four million rows.

    Note the one thing this does not survive: a punctuation difference inside
    the street name itself ("Skt. Pauls Gade" against "Sankt Pauls Gade", or
    even "St. Pauls" against "St Pauls"). The normalisation above would match
    those, but the seek never offers them as candidates, so they come back as
    "not found". Both sources derive their street names from DAR, so this is
    not expected to occur; if it does, it shows up as a caseworker-visible 422
    naming the address, not as a wrong match.
    """

    match = _FIRST_DIGIT.search(tekst)
    prefix = tekst[: match.start()] if match else tekst

    return prefix.strip(" ,.")


def extract_postnummer(tekst: str) -> str | None:
    """The postcode in an address, or None if there is no recognisable one.

    Used only to narrow the candidate rows, never to decide a match. The
    Adresse table is the whole of Denmark, so a street name alone can return
    rows from a dozen towns.
    """

    matches = _POSTNUMMER.findall(tekst)

    return matches[-1] if matches else None


def _is_supplerende_bynavn(component: str) -> bool:
    """Is this comma-separated component a place name rather than a floor/door?

    Strict on purpose, and the asymmetry is the whole point:

    - Mistaking a place name for a floor/door means the component is NOT
      stripped, the address does not match, and a caseworker sees a 422 naming
      it. That is where this already was.
    - Mistaking a floor/door for a place name means the component IS stripped,
      and "Vej 1, 1. th" can then be matched by a submission reading "Vej 1".
      That attaches a bevilling to the wrong flat in the right building.

    Only the first is acceptable, so the test demands positive evidence of a
    place name and treats everything it does not recognise as a floor/door:
    no digit anywhere, and at least one token of five characters or more. No
    DAR floor or door value is five letters long, and no digit appears in a
    Danish place name.

    Measured against the Aarhus rows in the register (part 5 of
    db/analyse/adresse_normalisering_kollisioner.sql), the complete set of
    digit-free floor/door components is:

        st. tv  st. th  st.  kl.  st. mf  kl. tv  kl. th  kl. mf
        st. a   st. b   st. c  st. d  st. e  st. f  st. tha  st. thb
        kl. mftv  th  tv  a  b  d

    — about 25,000 addresses, and this test refuses every one of them. Those
    are precisely the components that would send a submission to the wrong
    flat in the right building if they were stripped.

    The margin is ONE character. The longest door token in that set is
    "mftv", at four. Lowering the threshold to four would strip it. Do not.

    The cost is village names whose every token is shorter than five
    characters, which keep failing to match exactly as they do today. In the
    Aarhus postcodes that is mainly True and Kolt, with Terp, Elev, Ask, Åbo
    and a few smaller ones behind them — roughly 2,750 addresses. Part 5
    lists them in full.
    """

    if _DIGIT.search(component):
        return False

    tokens = [token for token in _SEPARATORS.split(component.strip()) if token]

    return any(len(token) >= _MIN_BYNAVN_TOKEN for token in tokens)


def strip_supplerende_bynavn(tekst: str) -> str | None:
    """Remove the supplerende bynavn from a DAR address, if it has one.

    Args:
        tekst:
            An address string.

    Returns:
        The address without its supplerende bynavn, or None where there is no
        component that can be shown to be one. None means "nothing to relax" —
        callers fall back to the address as given rather than treating it as
        empty.

    Notes:
        A DAR address is comma-delimited and positional:

            vejnavn husnr [, etage. dør] [, supplerende bynavn], postnr by

        The supplerende bynavn, when present, is therefore always the
        second-to-last component. That is the only one this looks at — it
        never touches the street, the floor or the postcode.

        Position alone is not enough, because with three components the
        second-to-last is EITHER the floor/door or the bynavn
        ("Vej 1, 1. th, 8000 Aarhus C" against "Vej 1, Lisbjerg, 8200 Aarhus
        N"). _is_supplerende_bynavn is what separates those, and it refuses
        unless it is sure.

        Dropping the component is sound because DAR does not use it to
        identify an address: the identity is vejnavn, husnr, etage, dør and
        postnr. It is not sound to assume it never distinguishes two rows — a
        postcode can span several villages, and the same street name can occur
        in more than one of them. That case is handled by the caller, which
        accepts a match only when exactly one row produces it and refuses
        otherwise. The relaxation widens what can match; it never picks a
        winner.

    Examples:
        >>> strip_supplerende_bynavn("Thomas Windings Gade 52, Lisbjerg, 8200 Aarhus N")
        'Thomas Windings Gade 52, 8200 Aarhus N'
        >>> strip_supplerende_bynavn("Vej 1, 1. th, 8000 Aarhus C") is None
        True
    """

    parts = tekst.split(",")

    # Fewer than three means street and postcode with nothing between them.
    if len(parts) < 3:
        return None

    if not _is_supplerende_bynavn(parts[-2]):
        return None

    return ",".join(parts[:-2] + parts[-1:])
