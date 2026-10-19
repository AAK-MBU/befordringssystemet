/**
 * How a bevilling's status ranks against another's.
 *
 * One order, used everywhere a student has several bevillinger and something
 * has to pick which one speaks for them: the status on Overblik and on their
 * own page, the order the bevillinger are listed in, and which one opens
 * expanded.
 *
 * It used to be four separate rules that disagreed. Overblik sorted Fejlet
 * sixth; the student page and view_Stamdata asked only "is any of them
 * Aktiv?". A student with a Fejlet bevilling and an expired one was therefore
 * marked Udløbet — the bevilling that needed attention was the one thing not
 * shown.
 *
 * FEJLET RANKS FIRST, above Aktiv. It means the bevilling cannot be acted on
 * — usually two kørselsrækker with overlapping dates, which is why a student
 * who has one often has two. Nothing else about the student matters until it
 * is fixed, so it has to be the status they carry and the row that opens.
 *
 * Mirrored in SQL by view_Stamdata's PrioritizedBevilling. Changing the order
 * here means changing it there; they answer the same question for the same
 * student, and the page would otherwise disagree with the list that links to
 * it.
 */

// Quoted throughout: these are status_tekst VALUES from the Status lookup, not
// identifiers. The Danish letters would be legal unquoted — JavaScript allows
// them in identifiers — but quoting every key says they are data and keeps the
// list looking like the lookup table it mirrors.
const RANG: Record<string, number> = {
  "Fejlet": 0,
  "Aktiv": 1,
  "Kommende": 2,
  "Påbegyndt": 3,
  "Ny": 4,
  "Afslag": 5,
  "Ophørt": 6,
  "Udløbet": 7,
};

/** Unknown statuses sort last, after every known one. */
const UKENDT = 99;

export function statusRang(statusTekst: string | null | undefined): number {
  if (!statusTekst) return UKENDT;

  return RANG[statusTekst.trim()] ?? UKENDT;
}

/**
 * The bevilling that speaks for the student, or undefined when there are none.
 *
 * Ties are left to the caller's existing order — this only decides between
 * different statuses.
 */
export function primaerBevilling<T extends { status_tekst?: string | null }>(
  bevillinger: T[] | null | undefined
): T | undefined {
  return (bevillinger ?? []).reduce<T | undefined>(
    (bedste, bevilling) =>
      bedste === undefined ||
      statusRang(bevilling.status_tekst) < statusRang(bedste.status_tekst)
        ? bevilling
        : bedste,
    undefined
  );
}
