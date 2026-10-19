<script lang="ts">
  import { afstandsMargin, formatAfstandsMargin } from "$lib/afstandskriterie";

  /**
   * A student's stamdata, rendered identically wherever it appears.
   *
   * Written once because it is shown in three places — the student's own page,
   * and the expanded row on Revurdering and Genbehandling — and the three had
   * drifted: the worklists were showing a partial set with six BEVILLING
   * fields mixed in under the heading "Elevdata", while the card on the
   * student page showed ten actual elev fields. Adding the missing columns
   * would have matched them for a day; one component keeps them matched.
   *
   * Takes the row as it comes off the view. view_Stamdata, view_Revurderinger
   * and view_Genbehandling all spell these fields the same way, so there is
   * nothing to map and therefore nothing to map wrongly — a mistranslated
   * field name would show an empty box rather than raise anything.
   *
   * They did not always agree: view_Stamdata said adresse_tekst and
   * skoleafstand where the other two said folkeregister_adresse and
   * gaaafstand_km. Aligning the views was the fix; this component only works
   * because they now match, so renaming a column here means renaming it in all
   * three.
   *
   * The recalculate button is a slot, not a prop: it writes and reloads, and
   * only the student's page has anywhere sensible to put the result. The
   * worklists pass nothing and the control is simply absent.
   */

  /** A row from any of the three views. Missing fields render as "—". */
  export let elev: Record<string, any> | null = null;

  $: sagsId = elev?.esdh_noegle ?? null;
  $: sagsUrl = elev?.esdh_url ?? null;
  $: folkeregisteradresse = elev?.folkeregister_adresse ?? null;
  $: skolekode = elev?.skolekode ?? null;
  // view_Stamdata resolves the school name under two keys depending on type.
  $: skoleNavn = elev?.skole_navn ?? elev?.skolematrikel ?? null;
  // Only view_Stamdata computes this; the worklist views have no equivalent.
  $: skoleType = elev?.skole_type ?? null;
  $: gaaafstandKm = elev?.gaaafstand_km ?? null;
  $: klasseart = elev?.klasseart ?? null;
  $: klassebetegnelse = elev?.klassebetegnelse ?? null;
  $: elevklassetrin = elev?.elevklassetrin ?? null;
  $: institution = elev?.institution ?? null;
  $: bopaelsdistrikt = elev?.bopaelsdistrikt ?? null;

  /** Skolematrikel lookup, used to name the skolekode. Optional. */
  export let skolematrikler: any[] = [];

  /** Heading above the grid. Null renders no heading. */
  export let titel: string | null = "Elevoplysninger";

  /**
   * Skolens navn uden matriklen.
   *
   * Matrikler, der deler skolekode, deler navnet før parentesen og adskiller
   * sig kun på afdelingen — "Kaløvigskolen (Bredevej)", "(Sanatorievej)",
   * "(Skovager)". Skolekoden siger, hvilken SKOLE eleven er indskrevet på,
   * ikke hvilken matrikel, så en afdeling her ville påstå noget, ingen har
   * registreret.
   *
   * Det rettede to ting på én gang: navnet sættes i parentes efter koden, så
   * en matrikel gav "751020 (Kaløvigskolen (Bredevej))" med parentes i
   * parentes — og hvilken af de tre der vandt, afhang af rækkefølgen i
   * opslaget, fordi de alle skriver til samme nøgle nedenfor. Nu klipper de
   * ned til den samme værdi, så det er uden betydning.
   */
  function skoleNavnUdenMatrikel(navn: string): string {
    const parentes = navn.indexOf("(");

    return (parentes === -1 ? navn : navn.slice(0, parentes)).trim();
  }

  $: skoleNavnByKode = new Map<string, string>(
    (skolematrikler ?? [])
      .filter((m: any) => m?.skolekode != null && m?.label)
      .map((m: any) => [
        String(m.skolekode).trim(),
        skoleNavnUdenMatrikel(String(m.label)),
      ]),
  );

  $: skolekodeNavn = skoleNavnByKode.get(String(skolekode ?? "").trim());

  // Derived, not passed: the same rule should flag the same student wherever
  // they are shown. Within 500 m of the afstandskriterie for their klassetrin,
  // either side — a recalculation could move them across it.
  $: margin = afstandsMargin(elevklassetrin, gaaafstandKm);
</script>

{#if titel}
  <div class="mb-6">
    <h2 class="font-semibold text-gray-800">{titel}</h2>
  </div>
{/if}

<div class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-5 gap-x-6 gap-y-5">

  <div>
    <p class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1.5">Sags-ID</p>
    <!-- Linket kommer fra bevillingen, som sags-id'et selv gør. Uden
         esdh_url er der intet at linke til, og nøglen vises som før. -->
    {#if sagsId && sagsUrl}
      <a
        href={sagsUrl}
        target="_blank"
        rel="noopener noreferrer"
        title="Åbn sagen i GO"
        class="inline-block px-2 py-0.5 rounded bg-slate-100 text-sky-600 hover:bg-slate-200 hover:underline text-xs font-mono font-medium"
      >{sagsId}</a>
    {:else}
      <span class="inline-block px-2 py-0.5 rounded bg-slate-100 text-slate-700 text-xs font-mono font-medium">
        {sagsId ?? "—"}
      </span>
    {/if}
  </div>

  <div>
    <p class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1.5">Folkeregisteradresse</p>
    <p class="text-sm text-gray-800 break-words" title={folkeregisteradresse ?? ""}>{folkeregisteradresse ?? "—"}</p>
  </div>

  <div>
    <p class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1.5">Skolekode</p>
    <p class="text-sm text-gray-800">
      {skolekode || "—"}{#if skolekode && skolekodeNavn}<span
          class="ml-1 text-gray-500">({skolekodeNavn})</span
        >{/if}
    </p>
  </div>

  <div>
    <p class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1.5">Skole</p>
    <p class="text-sm text-gray-800 break-words" title={skoleNavn ?? ""}>{skoleNavn ?? "—"}</p>
    {#if skoleType}
      <span class="inline-block mt-1 px-1.5 py-0.5 rounded text-[10px] font-medium bg-slate-100 text-slate-600">
        {skoleType}
      </span>
    {/if}
  </div>

  <div>
    <div class="flex items-center gap-1.5 mb-1.5">
      <p class="text-[10px] font-bold uppercase tracking-wider text-gray-500">Gåafstand (km)</p>
      <slot name="genberegn" />
    </div>
    <p class="text-sm text-gray-800">{gaaafstandKm ?? "—"}</p>

    <slot name="genberegn-besked" />

    {#if margin}
      <p
        class="mt-1 inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[11px] font-medium bg-red-50 text-red-900 border border-red-500"
        title="Afstanden ligger tæt på afstandskriteriet for elevens klassetrin"
      >
        <svg class="w-3 h-3 shrink-0" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" d="M12 9v2m0 4h.01M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z" />
        </svg>
        Tæt på grænsen — {formatAfstandsMargin(margin)}
      </p>
    {/if}
  </div>

  <div>
    <p class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1.5">Klasseart</p>
    <p class="text-sm text-gray-800">{klasseart ?? "—"}</p>
  </div>

  <div>
    <p class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1.5">Klassebetegnelse</p>
    <p class="text-sm text-gray-800">{klassebetegnelse ?? "—"}</p>
  </div>

  <div>
    <p class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1.5">Personligt klassetrin</p>
    <p class="text-sm text-gray-800">{elevklassetrin ?? "—"}</p>
  </div>

  <div>
    <p class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1.5">Institution</p>
    <p class="text-sm text-gray-800">{institution ?? "—"}</p>
  </div>

  <div>
    <p class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1.5">Bopælsdistrikt</p>
    <p class="text-sm text-gray-800">{bopaelsdistrikt ?? "—"}</p>
  </div>

</div>
