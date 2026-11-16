/**
 * Search rules shared across the frontend, so the searches can't drift apart.
 *
 * Names are stored as one string ("Anna Marie Hansen"), and people search
 * with the names they remember, often without the middle name. A search
 * is therefore split into words, and every word has to match on its own.
 *
 * The global search box does the same in the backend
 * (OverviewService.search_elever). Keep the two in step.
 */

/** At most this many words are used; the global search caps it the same way. */
export const MAKS_SOEGEORD = 5;

/** Splits a search into lower-case words, ignoring extra spaces. */
export function soegeord(q: string): string[] {
  return q.trim().toLowerCase().split(/\s+/).filter(Boolean).slice(0, MAKS_SOEGEORD);
}

/**
 * True when every word in the search starts a word in the name.
 *
 * A word starts at the beginning of the name, after a space, or after a
 * hyphen, so "hansen" finds "Møller-Hansen" while "sen" does not match
 * "Hansen". "anna hansen" finds "Anna Marie Hansen".
 */
export function matcherNavn(navn: string | null | undefined, q: string): boolean {
  const ord = soegeord(q);

  if (ord.length === 0) return true;

  const n = (navn ?? "").toLowerCase();

  return ord.every((o) => n.startsWith(o) || n.includes(` ${o}`) || n.includes(`-${o}`));
}

/**
 * True when every word in the search appears somewhere in the text.
 *
 * Looser than matcherNavn, for the table column filters. They filter
 * addresses, schools and other text as well as names, where matching
 * the middle of a word is expected.
 */
export function indeholderAlleOrd(tekst: string | null | undefined, q: string): boolean {
  const t = (tekst ?? "").toLowerCase();

  return soegeord(q).every((o) => t.includes(o));
}
