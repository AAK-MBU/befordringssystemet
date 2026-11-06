/**
 * Shared date validation.
 *
 * Native `<input type="date">` accepts years far outside anything meaningful
 * for this domain (HTML allows years up to 275760), so a fat-fingered entry
 * like "202365-01-01" is technically "valid" to the browser. We define a valid
 * date as a real calendar date with an exactly-4-digit year.
 *
 * Note: the bounds passed to the date fields constrain the calendar, but do
 * NOT block a value from being typed or pasted and read back via `bind:value`
 * — these forms submit via JS, so the guard below is what actually stops a bad
 * value from being sent.
 */

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

/**
 * True when `value` is a real calendar date written as `YYYY-MM-DD` with a
 * 4-digit year. Empty/`null`/`undefined` are treated as "not provided" and
 * return `true` (use a separate required-check where a date is mandatory).
 */
export function isValidDate(value: unknown): boolean {
  if (value === null || value === undefined || value === "") {
    return true;
  }

  if (typeof value !== "string" || !ISO_DATE.test(value)) {
    return false;
  }

  // Reject impossible calendar dates (e.g. 2026-02-30). Compare components in
  // UTC so the check is timezone-independent: constructing the date and reading
  // it back must yield the same year/month/day (rollover changes them).
  const [year, month, day] = value.split("-").map(Number);
  const parsed = new Date(Date.UTC(year, month - 1, day));

  return (
    parsed.getUTCFullYear() === year &&
    parsed.getUTCMonth() === month - 1 &&
    parsed.getUTCDate() === day
  );
}

/**
 * Returns the first `[key, value]` whose value is a present-but-invalid date,
 * or `null` if all provided date values are valid. Only keys in `dateKeys`
 * are checked, so non-date fields are ignored.
 */
export function firstInvalidDate(
  payload: Record<string, unknown>,
  dateKeys: string[],
): [string, unknown] | null {
  for (const key of dateKeys) {
    const value = payload[key];

    if (value !== null && value !== undefined && value !== "" && !isValidDate(value)) {
      return [key, value];
    }
  }

  return null;
}

/**
 * The plausible date window for this application, snapped to year boundaries
 * (1 Jan … 31 Dec).
 *
 * The range exists to catch typos — a mistyped year is the common failure, and
 * `isValidDate` alone accepts 1998 or 2071 happily because both are real
 * calendar dates.
 *
 * The forward half is +15 years, not +10, because +10 was narrower than a date
 * this application computes for itself. afstandskriterie_dato runs to the end
 * of the school year in which the student leaves their distance band, and the
 * worst case is a long way out:
 *
 *     skoleaarSlutter   today's year + 1 from August onwards
 *   + (10 - 0)          a børnehaveklasse pupil over 9 km, who qualifies all
 *                       the way to 10. klassetrin
 *   = today's year + 11, on 30 June
 *
 * At +10 the ceiling was 31 December of year + 10, so that pupil's own
 * correctly calculated 30 June of year + 11 was rejected as an implausible
 * year — on a field the caseworker cannot edit their way out of. +15 clears it
 * with room to spare and still catches a four-digit slip, which is the point.
 *
 * Use both halves together at every date input:
 *   - `MIN_DATE` / `MAX_DATE` as the `min`/`max` props on DateInput, which
 *     bound the calendar it opens;
 *   - `isDateOutOfRange` in the submit handler, which is what actually blocks
 *     the value — these forms submit via JS, so the bounds do not stop a
 *     pasted or typed value from being read through `bind:value`.
 *
 * Computed once at module load. A session spanning New Year keeps the window it
 * started with, which is immaterial at this width.
 */
export const MIN_DATE = new Date(new Date().getFullYear() - 10, 0, 1)
  .toISOString()
  .slice(0, 10);

export const MAX_DATE = new Date(new Date().getFullYear() + 15, 11, 31)
  .toISOString()
  .slice(0, 10);

/** True when `value` is present and falls outside MIN_DATE…MAX_DATE. */
export function isDateOutOfRange(value: string | null | undefined): boolean {
  return !!value && (value < MIN_DATE || value > MAX_DATE);
}

/**
 * Returns the first `[key, value]` that is present but outside the plausible
 * range, or `null`. Mirrors `firstInvalidDate` so a caller can run both.
 */
export function firstOutOfRangeDate(
  payload: Record<string, unknown>,
  dateKeys: string[],
): [string, unknown] | null {
  for (const key of dateKeys) {
    const value = payload[key];

    if (typeof value === "string" && isDateOutOfRange(value)) {
      return [key, value];
    }
  }

  return null;
}


/**
 * Today as "YYYY-MM-DD" in LOCAL time.
 *
 * Built from the local calendar parts rather than
 * `new Date().toISOString().slice(0, 10)`, which yields the UTC date — wrong
 * between local midnight and the UTC offset. At 00:30 in Copenhagen that
 * reads as yesterday.
 */
export function iDagISO(): string {
  const nu = new Date();

  return [
    nu.getFullYear(),
    String(nu.getMonth() + 1).padStart(2, "0"),
    String(nu.getDate()).padStart(2, "0"),
  ].join("-");
}

/**
 * The "YYYY-MM-DD" part of a date value, or "" when there is none.
 *
 * Dates reach the frontend as SQL DATE columns serialised to "2026-10-02", and
 * occasionally with a time component. Comparing them as STRINGS is the whole
 * point of this helper: ISO dates order correctly lexicographically, and no
 * timezone is involved.
 *
 * Parsing them into Date objects is what goes wrong. `new Date("2026-10-02")`
 * is specified to parse a date-ONLY string as UTC midnight, while a local
 * midnight built with setHours(0,0,0,0) sits one or two hours earlier in
 * Denmark — so a row starting today compared as "fra > today" and showed as
 * kommende for the whole day.
 */
export function datoDel(value: string | null | undefined): string {
  return value ? String(value).slice(0, 10) : "";
}
