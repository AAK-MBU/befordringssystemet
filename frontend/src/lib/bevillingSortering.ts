import { statusRang } from "$lib/statusRang";

/**
 * The order a student's bevillinger are shown in.
 *
 * By status rank first — see $lib/statusRang — then by the latest gyldig_til
 * across their kørselsrækker, descending. Bevillinger with no kørselsrækker
 * sort to the bottom.
 *
 * Status trumps a future or more recently created one, because the top of the
 * list is the bevilling a caseworker is actually working on: a broken one
 * first, otherwise the one deciding what the child is driven by today. The API returns them in `created_at DESC`, which
 * is neither that order nor a total one: created_at has no tiebreaker, so two
 * bevillinger created in the same transaction ("+ Ny bevilling fra kopi") can
 * come back either way round.
 *
 * Lives here rather than in $lib/server/sagData so the pages that fetch
 * client-side can use the same function. It used to sit in sagData alone,
 * which meant the sag page showed the active bevilling first while the
 * revurdering and genbehandling panels showed the newest — the same student,
 * two different orders, on the page where the active one matters most.
 */

type MedKoerselsraekker = {
  status_tekst?: string | null;
  koerselsraekker?: { gyldig_til?: string | null }[] | null;
};

/** The last day any of a bevilling's kørselsrækker covers, "" when it has none. */
function senesteGyldigTil(bevilling: MedKoerselsraekker): string {
  return (bevilling.koerselsraekker ?? []).reduce(
    (max: string, raekke) => {
      const til = raekke?.gyldig_til ?? "";
      return til > max ? til : max;
    },
    ""
  );
}

// Was "is it Aktiv", which put a Fejlet bevilling below an expired one. The
// full order lives in $lib/statusRang, so this list and the status the student
// is marked with cannot disagree.

export function sorterBevillinger<T extends MedKoerselsraekker>(
  bevillinger: T[]
): T[] {
  return [...bevillinger].sort((a, b) => {
    const rangDiff = statusRang(a.status_tekst) - statusRang(b.status_tekst);

    if (rangDiff !== 0) {
      return rangDiff;
    }

    // ISO dates, so a string comparison is a date comparison.
    return senesteGyldigTil(b).localeCompare(senesteGyldigTil(a));
  });
}
