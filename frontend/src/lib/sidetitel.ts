/**
 * The browser tab title for a route.
 *
 * Set once in +layout.svelte rather than per page. A <title> that only some
 * routes declare is sticky: <svelte:head> replaces what a route sets, so a
 * route that sets nothing keeps whatever the last one left behind. Landing on
 * Overblik or on a student's sag from Nye ansøgninger kept saying "Nye
 * ansøgninger" for exactly that reason.
 *
 * It is not only cosmetic. The browser names a copied link after the title, so
 * a sag sent to a colleague arrived labelled as the list it was opened from.
 *
 * The specific part comes first because that is the half that survives: a tab
 * truncates from the end, and so does a pasted link in a narrow column.
 */

const APP = "Befordring";

/** Route id -> title. Keep in step with `tabs` in +layout.svelte. */
const FASTE_TITLER: Record<string, string> = {
  "/": "Overblik",
  "/nye-ansoegninger": "Nye ansøgninger",
  "/revurdering": "Revurdering",
  "/genbehandling": "Genbehandling",
  "/forsendelse": "Forsendelse",
  "/min-side": "Min side",
  "/links": "Links",
};

/**
 * Routes about one student. The value is the action, or "" for the sag itself;
 * the student is named by the caller, since only the page knows who it is.
 */
const SAGS_HANDLINGER: Record<string, string> = {
  "/sag/[cpr]": "",
  "/sag/[cpr]/opret-bevilling": "Opret bevilling",
  "/sag/[cpr]/opret-brev": "Opret brev",
};

export function sidetitel(
  routeId: string | null | undefined,
  sag?: { navn?: string | null; cpr?: string | null },
): string {
  const fast = routeId ? FASTE_TITLER[routeId] : undefined;

  if (fast) return `${fast} – ${APP}`;

  if (routeId && routeId in SAGS_HANDLINGER) {
    // Falls back to the CPR while stamdata is still loading - /sag/[cpr] runs
    // client-side only, so the first render has no name yet.
    const hvem =
      (sag?.navn ?? "").trim() || (sag?.cpr ?? "").trim() || "Sag";

    const handling = SAGS_HANDLINGER[routeId];

    return handling
      ? `${handling} – ${hvem} – ${APP}`
      : `${hvem} – ${APP}`;
  }

  return APP;
}
