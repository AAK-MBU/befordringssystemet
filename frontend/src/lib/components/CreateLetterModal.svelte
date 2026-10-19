<script lang="ts">
  // The single "Opret brev" modal. Both the student page and the revurdering
  // page mount this, so the fields, the validation and the payload can only
  // ever be one thing — they used to be two divergent copies, and the
  // revurdering copy silently omitted koersel_startdato and
  // dato_for_seneste_bevilling from the queued letter.
  //
  // The caller supplies only what genuinely differs — which student, which
  // bevillinger — and reacts to `created` to refresh its own view.

  import { createEventDispatcher } from "svelte";
  import { afgoerelsesbrevKategori } from "$lib/lookupFilters";

  import { backendFetch } from "$lib/client/backendFetch";
  import { MIN_DATE, MAX_DATE, iDagISO, firstInvalidDate, firstOutOfRangeDate } from "$lib/dates";
  import { bevillingLabel } from "$lib/bevillingLabel";

  export let open = false;
  export let cpr = "";
  export let bevillinger: any[] = [];

  // Set when the form is the whole page rather than a modal over one — the
  // separate "opret brev" window. See CreateBevillingModal for the reasoning.
  export let standalone = false;

  const dispatch = createEventDispatcher();

  let selectedLetterBevillingId = "";
  let letterType = "";
  let koerselStartdato = "";
  // "Seneste bevilling" is by definition one that already exists, so a
  // future date is always a typo. Capped on the input AND validated, since
  // a date input's max only constrains the picker, not a typed value.
  const iDag = iDagISO();

  let datoForSenesteBevilling = "";
  let befordringsudvalgResultat = "";
  let tidligereAfgoerelseDato = "";
  let ophoersdato = "";
  let creatingLetter = false;

  // Shown as a red bar above the fields instead of a browser alert, so the
  // message sits next to the form it is about and the modal stays put.
  let errorMessage: string | null = null;

  // Non-null once the letter is queued. The form is then replaced by a
  // confirmation panel — see handleCreateLetter for why the modal does not
  // just close.
  let successReference: string | null = null;

  $: selectedBevilling = (bevillinger ?? []).find(
    (bevilling: any) => String(bevilling.bevilling_id) === selectedLetterBevillingId
  );

  $: harBefordringsudvalg =
    selectedBevilling?.befordringsudvalg !== null &&
    selectedBevilling?.befordringsudvalg !== undefined &&
    selectedBevilling?.befordringsudvalg !== "";

  $: erOphoert = selectedBevilling?.status_tekst === "Ophørt";

  // An afslag grants no kørsel, so there is no date on which it starts.
  //
  // Verified against the template: not one of the ten afslag or påtænkt-afslag
  // entries in block 2.1 references {koersel_startdato}, so requiring it asked
  // the caseworker for a value no letter would ever print — and left them
  // unable to produce a rejection at all.
  //
  // Classified from the AFGØRELSESBREV rather than the bevilling's status:
  // the letter decides its own content, and the status may still be Ny while
  // the rejection is being written. afgoerelsesbrevKategori also handles
  // "Påtænkt afslag", which does not begin with the word.
  $: erAfslag =
    afgoerelsesbrevKategori(selectedBevilling?.afgoerelsesbrev_tekst) === "afslag";

  // The letter's "startdato for kørsel" is the day the kørsel actually begins:
  // the earliest gyldig_fra across the bevilling's kørselsrækker. ISO dates
  // compare correctly as strings, so no Date parsing is needed. Soft-deleted
  // rækker are already filtered out by view_Bevilling_Koerselsraekker.
  function earliestGyldigFra(bevilling: any): string {
    const datoer: string[] = (bevilling?.koerselsraekker ?? [])
      .map((koersel: any) => koersel?.gyldig_fra)
      .filter(Boolean)
      .map((dato: string) => String(dato).slice(0, 10));

    return datoer.length === 0
      ? ""
      : datoer.reduce((tidligste, dato) => (dato < tidligste ? dato : tidligste));
  }

  // Prefill on a *change of bevilling* only. The caller reloads its data after
  // a letter is created, which rebuilds selectedBevilling without the id
  // changing — a bare assignment would wipe a date typed by hand.
  let prefilledStartdatoFor = "";
  $: if (selectedLetterBevillingId !== prefilledStartdatoFor) {
    prefilledStartdatoFor = selectedLetterBevillingId;
    koerselStartdato = earliestGyldigFra(selectedBevilling);
  }

  function resetForm() {
    selectedLetterBevillingId = "";
    letterType = "";
    koerselStartdato = "";
    datoForSenesteBevilling = "";
    befordringsudvalgResultat = "";
    tidligereAfgoerelseDato = "";
    ophoersdato = "";
    prefilledStartdatoFor = "";
    errorMessage = null;
    successReference = null;
  }

  // Clear on the way *in*, so a modal reopened after a cancel never shows the
  // previous student's answers.
  let wasOpen = false;
  $: if (open !== wasOpen) {
    wasOpen = open;
    if (open) resetForm();
  }

  function close() {
    open = false;
    resetForm();
  }

  // Every field is required except dato_for_seneste_bevilling — and a field
  // that is not shown is not required, which is why each conditional check
  // repeats the same flag that gates its markup.
  function firstValidationError(): string | null {
    if (!selectedLetterBevillingId) return "Vælg en bevilling";
    if (!letterType) return "Vælg hvad brevet er i forbindelse med";
    if (!erAfslag && !koerselStartdato) return "Angiv startdato for kørsel";
    if (harBefordringsudvalg && !befordringsudvalgResultat) return "Vælg resultat af befordringsudvalgsmøde";
    if (erOphoert && !ophoersdato) return "Vælg ophørsdato";

    const invalidDate = firstInvalidDate(
      {
        koersel_startdato: koerselStartdato,
        dato_for_seneste_bevilling: datoForSenesteBevilling,
        dato_for_tidligere_afgoerelse: tidligereAfgoerelseDato,
        ophoersdato,
      },
      [
        "koersel_startdato",
        "dato_for_seneste_bevilling",
        "dato_for_tidligere_afgoerelse",
        "ophoersdato",
      ],
    );

    if (invalidDate) return "Angiv en gyldig dato (åååå-mm-dd).";

    // Separate from the check above: a mistyped year like 2071 is a perfectly
    // real calendar date, so isValidDate accepts it. The min/max attributes
    // bound the picker but do not stop a typed or pasted value being read via
    // bind:value — this is what actually blocks it.
    const outOfRange = firstOutOfRangeDate(
      {
        koersel_startdato: koerselStartdato,
        dato_for_seneste_bevilling: datoForSenesteBevilling,
        dato_for_tidligere_afgoerelse: tidligereAfgoerelseDato,
        ophoersdato,
      },
      [
        "koersel_startdato",
        "dato_for_seneste_bevilling",
        "dato_for_tidligere_afgoerelse",
        "ophoersdato",
      ],
    );

    if (outOfRange) {
      return `Dato er ugyldig — kontrollér årstallet (skal være mellem ${MIN_DATE.slice(0, 4)} og ${MAX_DATE.slice(0, 4)}).`;
    }

    if (datoForSenesteBevilling && datoForSenesteBevilling > iDag) {
      return "Dato for seneste bevilling må ikke ligge i fremtiden.";
    }

    return null;
  }

  async function handleCreateLetter() {
    errorMessage = firstValidationError();

    if (errorMessage) return;

    creatingLetter = true;

    const payload = {
      brev_i_forbindelse_med: letterType,
      koersel_startdato: koerselStartdato || null,
      dato_for_seneste_bevilling: datoForSenesteBevilling || null,
      befordringsudvalg_resultat: harBefordringsudvalg ? befordringsudvalgResultat : null,
      dato_for_tidligere_afgoerelse: (harBefordringsudvalg && tidligereAfgoerelseDato) || null,
      ophoersdato: erOphoert ? ophoersdato : null,
    };

    try {
      const response = await backendFetch(
        `/bevilling/create_letter/${cpr}/${selectedLetterBevillingId}`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(payload),
        }
      );

      if (!response.ok) {
        let message = "Kunne ikke oprette brev";

        try {
          const errorData = await response.json();
          message = errorData?.detail?.message ?? errorData?.detail ?? message;
        } catch {
          // Keep fallback message
        }

        errorMessage = message;
        return;
      }

      const result = await response.json();
      const bevillingId = Number(selectedLetterBevillingId);

      // Deliberately not close(): the ATS reference appears nowhere else in the
      // app, so closing on success would throw away the only chance to read it.
      // The body swaps to a confirmation panel and Luk does the closing.
      successReference = result.reference;

      dispatch("created", { cpr, bevillingId, reference: result.reference });
    } finally {
      creatingLetter = false;
    }
  }

  const labelClass = "block text-sm font-medium text-gray-700";
  const fieldClass = "mt-1.5 w-full border border-gray-300 rounded px-3 py-2 text-sm";
</script>

<svelte:window
  on:keydown={(e) => {
    // Not in standalone mode: there Escape would close the whole window and
    // take the half-filled form with it, which is not what someone reaching
    // for Escape in a window on another screen expects.
    if (open && !standalone && e.key === "Escape") close();
  }}
/>

{#if open}
  <div
    class={standalone
      ? "min-h-screen bg-white"
      : "fixed inset-0 z-50 flex items-center justify-center bg-black/40"}
    role="presentation"
  >
    <div
      class={standalone ? "w-full bg-white" : "w-[560px] bg-white rounded-lg shadow-2xl"}
      role="dialog"
      aria-modal="true"
      aria-label="Opret brev"
      tabindex="-1"
    >

      <div class="px-8 py-5 border-b border-gray-200 rounded-t-lg" style="background-color: #6d28d9;">
        <h2 class="text-lg font-bold text-white">Opret brev</h2>
        <p class="mt-0.5 text-sm" style="color: rgba(255,255,255,0.7);">
          {successReference ? "Brevet er oprettet" : "Vælg bevilling og brevtype"}
        </p>
      </div>

      {#if successReference}
        <div class="p-8">
          <div class="flex gap-3 rounded border border-green-200 bg-green-50 px-4 py-3" role="status">
            <svg class="mt-0.5 h-5 w-5 shrink-0 text-green-600" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24" aria-hidden="true">
              <path stroke-linecap="round" stroke-linejoin="round" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
            <div>
              <p class="text-sm font-medium text-green-900">Brevet er sat i kø</p>
              <p class="mt-1 text-sm text-green-800">
                Det står nu under Forsendelse, indtil det markeres som afsendt.
              </p>
              <p class="mt-2 text-xs text-green-700">
                Reference
                <span class="ml-1 font-mono select-all">{successReference}</span>
              </p>
            </div>
          </div>
        </div>

        <div class="flex justify-end border-t border-gray-200 px-8 py-5 bg-gray-50 rounded-b-lg">
          <button
            type="button"
            class="px-5 py-2 text-sm font-medium bg-purple-600 hover:bg-purple-700 text-white rounded transition-colors"
            on:click={close}
          >
            Luk
          </button>
        </div>
      {:else}
      <div class="p-8 space-y-5">
        {#if errorMessage}
          <div class="px-3 py-2 text-sm text-red-700 bg-red-50 border border-red-200 rounded" role="alert">
            {errorMessage}
          </div>
        {/if}

        <label class={labelClass}>
          Vælg bevilling *
          <select class={fieldClass} bind:value={selectedLetterBevillingId}>
            <option value="">Vælg bevilling</option>
            {#each bevillinger ?? [] as bevilling}
              <option value={String(bevilling.bevilling_id)}>
                {bevillingLabel(bevilling)} – {bevilling.status_tekst ?? "Ukendt status"}
              </option>
            {/each}
          </select>
        </label>

        <label class={labelClass}>
          Brevet er i forbindelse med en: *
          <select class={fieldClass} bind:value={letterType}>
            <option value="">Vælg</option>
            <option value="ansøgning">Ansøgning</option>
            <option value="revurdering">Revurdering</option>
            <option value="midlertidig kørsel">Midlertidig kørsel</option>
          </select>
        </label>

        <label class={labelClass}>
          Startdato for kørsel {erAfslag ? "" : "*"}
          <input type="date" min={MIN_DATE} max={MAX_DATE} class={fieldClass} bind:value={koerselStartdato} />
          <span class="mt-1 block text-xs font-normal text-gray-500">
            {erAfslag
              ? "Bruges ikke i et afslag — der bevilges ingen kørsel."
              : "Udfyldes automatisk med den tidligste \"gyldig fra\" på bevillingens kørselsrækker."}
          </span>
        </label>

        <label class={labelClass}>
          Dato for seneste bevilling
          <input type="date" min={MIN_DATE} max={iDag} class={fieldClass} bind:value={datoForSenesteBevilling} />
        </label>

        {#if harBefordringsudvalg}
          <label class={labelClass}>
            Resultat af befordringsudvalgsmøde *
            <select class={fieldClass} bind:value={befordringsudvalgResultat}>
              <option value="">Vælg</option>
              <option value="Befordringsudvalg: Afslag / fastholdelse">Befordringsudvalg: Afslag / fastholdelse</option>
              <option value="Befordringsudvalg: Ændring i bevilling">Befordringsudvalg: Ændring i bevilling</option>
            </select>
          </label>
          <label class={labelClass}>
            Nuværende bevilling fortsætter til
            <input type="date" min={MIN_DATE} max={MAX_DATE} class={fieldClass} bind:value={tidligereAfgoerelseDato} />
          </label>
        {/if}

        {#if erOphoert}
          <label class={labelClass}>
            Ophørsdato *
            <input type="date" min={MIN_DATE} max={MAX_DATE} class={fieldClass} bind:value={ophoersdato} />
          </label>
        {/if}
      </div>

      <div class="flex justify-end gap-3 border-t border-gray-200 px-8 py-5 bg-gray-50 rounded-b-lg">
        <button
          type="button"
          class="px-5 py-2 text-sm font-medium border border-gray-300 rounded hover:bg-white transition-colors"
          on:click={close}
        >
          Annullér
        </button>
        <button
          type="button"
          class="px-5 py-2 text-sm font-medium bg-purple-600 hover:bg-purple-700 text-white rounded transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
          disabled={creatingLetter}
          on:click={handleCreateLetter}
        >
          {creatingLetter ? "Opretter..." : "Opret brev"}
        </button>
      </div>
      {/if}

    </div>
  </div>
{/if}
