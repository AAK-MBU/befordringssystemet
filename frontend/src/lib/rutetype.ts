/**
 * Rutetype classification — "does this kørsel include an afternoon leg?"
 *
 * Rutetype states where a trip starts and ends, which makes the time of day
 * derivable from it. It replaced the Tidspunkt lookup as the source for this
 * question: two columns answering one thing is two rules that can disagree.
 *
 * Matched on the LABEL rather than the id, for the same reason
 * $lib/koerselstype does: ids are per-environment autoincrements, the texts
 * are the business terms.
 */

export type RutetypeOption = { id: number | string; label: string };

/**
 * The rutetyper with no afternoon leg.
 *
 * An allow-list of the exceptions rather than a list of the six, because the
 * exceptions are the small, stable set: every other route ends somewhere
 * other than school, which only happens after school.
 *
 * Neither "Mellem …" type is here — both cover the whole day. That is
 * Befordring's reading of "Mellem skole, klub, og hjem" too, and it does not
 * follow from the name, which lists only afternoon legs. Do not derive this
 * from the place names.
 */
const KUN_MORGEN = ["fra hjem til skole"];

export function labelForRutetype(
  rutetyper: RutetypeOption[] | null | undefined,
  rutetypeId: string | number | null | undefined
): string | undefined {
  if (!rutetypeId) return undefined;

  return (rutetyper ?? []).find(
    (rutetype) => Number(rutetype.id) === Number(rutetypeId)
  )?.label;
}

/**
 * True when the chosen rutetype involves an afternoon leg.
 *
 * An unknown or unset rutetype answers false: the field stays hidden until
 * something has been chosen, rather than appearing and then vanishing.
 */
export function harEftermiddagForRutetype(
  rutetyper: RutetypeOption[] | null | undefined,
  rutetypeId: string | number | null | undefined
): boolean {
  const label = labelForRutetype(rutetyper, rutetypeId);

  if (!label) return false;

  return !KUN_MORGEN.includes(label.trim().toLowerCase());
}
