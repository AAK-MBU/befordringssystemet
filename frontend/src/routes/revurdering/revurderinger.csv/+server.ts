import { filterFraQuery, matcherFilter, daysUntil, aktiveKoerselstyper } from "$lib/revurderingFilter";
import { csvCpr, csvResponse, type CsvColumn } from "$lib/server/csv";
import { backendUserFetcher } from "$lib/server/backendApi";

import type { RequestHandler } from "./$types";


/**
 * CSV of the cases due for revurdering.
 *
 * Honours the page's filters, which arrive as query parameters. The predicate
 * itself is NOT reimplemented here — $lib/revurderingFilter.matcherFilter is
 * the same function the page filters with, so the file always contains exactly
 * the rows the caseworker was looking at. A second copy of those rules would
 * drift, and silently: the export would simply hold a different set of cases
 * than the screen showed, with no way to tell which was right.
 */

const COLUMNS: CsvColumn[] = [
  { key: "adresseringsnavn", header: "Navn" },
  // cpr_elev, not cpr — that is what view_Revurderinger exposes.
  { key: "cpr_elev", header: "CPR", format: csvCpr },
  { key: "skole_navn", header: "Skole" },
  { key: "folkeregister_adresse", header: "Folkeregisteradresse" },
  { key: "elevklassetrin", header: "Klassetrin" },
  { key: "gaaafstand_km", header: "Gåafstand (km)" },
  { key: "revurderingsdato", header: "Revurderingsdato" },
  {
    key: "revurderingsdato",
    header: "Dage til revurdering",
    // Negative where the date has passed. Spelled out as a column so the file
    // can be sorted on urgency without the reader doing date arithmetic.
    format: (value) => daysUntil(value as string) ?? "",
  },
  // Sidste dag en af bevillingens kørselsrækker dækker. Se view_Revurderinger.
  { key: "seneste_gyldig_til", header: "Udløbsdato" },
  // Four name columns, because two different questions are being answered.
  // The ansvarlig pair is who has the revurdering now — what the page's
  // filters work on — and is empty until somebody claims it. The bevilling
  // pair is who handled the decision the bevilling records.
  { key: "ansvarlig_sagsbehandler_tekst", header: "Ansvarlig nu" },
  { key: "ansvarlig_ppr_sagsbehandler_tekst", header: "PPR-ansvarlig nu" },
  { key: "sagsbehandler_tekst", header: "Sagsbehandler (bevilling)" },
  { key: "ppr_sagsbehandler_tekst", header: "PPR sagsbehandler (bevilling)" },
  { key: "status_tekst", header: "Status" },
  { key: "afstandskriterie_dato", header: "Afstandskriterie dato" },
  {
    key: "koerselsraekker",
    header: "Kørselstyper",
    // Through the same helper the page filters and the badges use, so the
    // file never lists a different set of types than the screen showed.
    format: (_value, row) =>
      [...new Set(aktiveKoerselstyper(row))].join(", "),
  },
];


export const GET: RequestHandler = async (event) => {
  const api = backendUserFetcher(event);

  const res = await api("/overview/revurderinger");

  if (!res.ok) {
    console.error("Failed to fetch revurderinger:", res.status);

    return new Response("Kunne ikke hente revurderinger", { status: 502 });
  }

  const rows: Record<string, unknown>[] = await res.json();
  const filter = filterFraQuery(event.url.searchParams);

  return csvResponse(
    rows.filter((row) => matcherFilter(row, filter)),
    COLUMNS,
    "revurderinger"
  );
};
