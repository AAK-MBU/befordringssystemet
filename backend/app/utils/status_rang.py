"""How a bevilling's status ranks against another's.

The same order as frontend/src/lib/statusRang.ts and the CASE in
view_Stamdata's PrioritizedBevilling. All three answer one question — which of
a student's bevillinger speaks for them — and a student who is Fejlet on their
own page but Udløbet on Overblik is what it looks like when they disagree.

FEJLET RANKS FIRST, above Aktiv. It means the bevilling cannot be acted on,
usually two kørselsrækker with overlapping dates, which is why a student with
one often has two. Nothing else about the student matters until it is fixed.

Changing the order here means changing it in the other two places.
"""

# Lower is more important.
_RANG = {
    "fejlet": 0,
    "aktiv": 1,
    "kommende": 2,
    "påbegyndt": 3,
    "ny": 4,
    "afslag": 5,
    "ophørt": 6,
    "udløbet": 7,
}

# Unknown statuses rank after every known one, so a value added to the Status
# lookup later sorts last rather than landing silently in the middle.
_UKENDT = 99


def status_rang(status_tekst: str | None) -> int:
    """The rank of a status text. Lower wins.

    Args:
        status_tekst:
            The status as Status.status_tekst spells it. Case and surrounding
            whitespace are ignored.

    Returns:
        0-7 for a known status, 99 otherwise.
    """

    return _RANG.get((status_tekst or "").strip().lower(), _UKENDT)
