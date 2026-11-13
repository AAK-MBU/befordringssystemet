<script lang="ts">
  import { invalidateAll } from "$app/navigation";
  import ReadOnlyNotice from "$lib/components/ReadOnlyNotice.svelte";
  import DataTable, { type DataTableColumn } from "$lib/components/DataTable.svelte";
  import { backendFetch } from "$lib/client/backendFetch";
  import { formatDanishDate, getStatusBadgeClass, formatCpr } from "$lib/tableColumnConfig";
  import { isMidlertidigKoersel } from "$lib/lookupFilters";

  export let data;

  $: ansoegninger = data.ansoegninger ?? [];
  $: sagsbehandlere = data.sagsbehandlere ?? [];
  $: pprSagsbehandlere = data.pprSagsbehandlere ?? [];
  $: koerselstyper = data.koerselstyper ?? [];
  // Layout data flows into page data, so the signed-in user is available here.
  // can_edit is resolved by the backend from EDIT_ROLES — see GET /me.
  $: canEdit = data.user?.can_edit ?? false;
  // Wider than canEdit: PPR Medarbejder ("user-read") may set the PPR column
  // and nothing else on the row. See PPR_ASSIGN_ROLES and require_ppr_assign.
  $: canAssignPpr = data.user?.can_act_as_ppr ?? false;

  let assignError: string | null = null;

  $: overOneWeek = ansoegninger.filter(a => (daysSince(a.ansoegningsdato) ?? 0) >= 7).length;
  $: overTwoWeeks = ansoegninger.filter(a => (daysSince(a.ansoegningsdato) ?? 0) >= 10).length;

  let quickFilter: null | 'over7' | 'over10' = null;

  $: displayedAnsoegninger = quickFilter === 'over10'
    ? ansoegninger.filter(a => (daysSince(a.ansoegningsdato) ?? 0) >= 10)
    : quickFilter === 'over7'
    ? ansoegninger.filter(a => (daysSince(a.ansoegningsdato) ?? 0) >= 7)
    : ansoegninger;

  async function handleDropdownChange(event: Event) {
    const target = event.target as HTMLSelectElement;
    if (!target.dataset.bevillingId || !target.dataset.field) return;

    const bevillingId = target.dataset.bevillingId;
    const field = target.dataset.field;

    // Ønsket kørselstype is the one column whose value is a LABEL rather than
    // an id: it is stored inside ansoegningsdata, which names types the way
    // the submission does. Number() on it would send NaN.
    const erTekstfelt = field === "oensket_befordringstype";

    const value = target.value === ""
      ? null
      : erTekstfelt ? target.value : Number(target.value);

    // A <select> shows the new option the moment it is picked, before anything
    // has been saved. If the write is refused the displayed value is a lie, so
    // put it back — otherwise the page claims an assignment that does not exist
    // until the next reload silently undoes it.
    const revert = () => {
      target.value = target.dataset.current ?? "";
    };

    assignError = null;

    // The PPR column has its own endpoint so that PPR Medarbejder can use it;
    // the general PUT stays behind require_edit and would refuse them.
    //
    // Ønsket kørselstype has its own for a different reason: it is a key
    // inside a JSON column, so the general PUT cannot set it without being
    // handed the whole document.
    const path =
      field === "ppr_sagsbehandler_id"
        ? `/bevilling/${bevillingId}/ppr_sagsbehandler`
        : erTekstfelt
        ? `/bevilling/${bevillingId}/oensket_befordringstype`
        : `/bevilling/${bevillingId}`;

    const body = erTekstfelt ? { befordringstype: value } : { [field]: value };

    const res = await backendFetch(path, {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });

    if (!res.ok) {
      revert();

      let message = "Tildelingen kunne ikke gemmes";

      try {
        const body = await res.json();
        const detail = body?.detail?.message ?? body?.detail;

        if (typeof detail === "string") {
          message = detail;
        }
      } catch {
        // Keep the fallback; a non-JSON body has nothing better to offer.
      }

      assignError = message;
      console.error(`Failed to update bevilling ${bevillingId}:`, res.status, message);

      return;
    }

    await invalidateAll();
  }

  function daysSince(dateStr: string | null | undefined): number | null {
    if (!dateStr) return null;
    const diff = Date.now() - new Date(dateStr).getTime();
    return Math.floor(diff / (1000 * 60 * 60 * 24));
  }

  function waitingLabel(days: number | null): string {
    if (days === null) return "—";
    if (days === 0) return "I dag";
    if (days === 1) return "1 dag";
    return `${days} dage`;
  }

  function waitingBadgeStyle(days: number | null): string {
    if (days === null) return "background:#e5e7eb;color:#6b7280;";
    if (days >= 10) return "background:#fee2e2;color:#dc2626;";
    if (days >= 7)  return "background:#fef9c3;color:#ca8a04;";
    return "background:#dbeafe;color:#1d4ed8;";
  }

  function rowUrgencyStyle(row: any): string {
    const days = daysSince(row.ansoegningsdato);
    if (days === null) return "";
    if (days >= 10) return "box-shadow: inset 4px 0 0 #dc2626;";
    if (days >= 7)  return "box-shadow: inset 4px 0 0 #ca8a04;";
    return "box-shadow: inset 4px 0 0 #3b82f6;";
  }

  function buildSelect(
    bevillingId: number,
    field: string,
    currentId: number | null,
    options: { id: number; label: string }[],
    placeholder: string,
    // Which permission governs this column. Defaults to the general one.
    tilladt: boolean = canEdit
  ): string {
    const opts = options
      .map(o => `<option value="${o.id}" ${currentId === o.id ? "selected" : ""}>${o.label}</option>`)
      .join("");

    // data-current lets a refused change be put back where it was.
    // The disabled attribute is a courtesy, not a control: require_edit on the
    // backend is what actually refuses the write.
    return `<select
      data-bevilling-id="${bevillingId}"
      data-field="${field}"
      data-current="${currentId ?? ""}"
      ${tilladt ? "" : "disabled"}
      ${tilladt ? "" : 'title="Du har ikke rettigheder til at ændre tildeling"'}
      class="w-full border border-gray-300 rounded px-2 py-1 text-sm bg-white focus:border-blue-400 focus:outline-none disabled:bg-gray-100 disabled:text-gray-400 disabled:cursor-not-allowed"
    >
      <option value="">${placeholder}</option>
      ${opts}
    </select>`;
  }

  // --- Ønsket kørselstype -------------------------------------------------
  //
  // Lives in Bevilling.ansoegningsdata, which holds both halves of the
  // question: "koerselstyper" is the list the citizen ticked (the form's three
  // checkboxes are independent, so it IS a list), and
  // "oensket_befordringstype" is the one a caseworker has decided the case
  // should be read as asking for.
  //
  // The second wins where it exists. Where it does not, the ticked types show
  // instead, greyed — which is what makes a multi-tick legible rather than a
  // problem: an application asking for three things looks undecided, because
  // it is.

  function parseAnsoegningsdata(raw: string | null | undefined): any {
    if (!raw) return null;

    try {
      return JSON.parse(raw);
    } catch {
      // Malformed JSON is nothing the caseworker can act on, and the column
      // still has to render. Treated as "nothing applied for".
      return null;
    }
  }

  function ansoegteTyper(row: any): string[] {
    const data = parseAnsoegningsdata(row.ansoegningsdata);
    const typer = data?.koerselstyper ?? [];

    return typer
      .map((t: any) => t?.befordringstype)
      .filter((t: any): t is string => typeof t === "string" && t.length > 0);
  }

  function valgtType(row: any): string | null {
    return parseAnsoegningsdata(row.ansoegningsdata)?.oensket_befordringstype ?? null;
  }

  function buildTypeSelect(row: any): string {
    const valgt = valgtType(row);
    const ansoegt = ansoegteTyper(row);

    const opts = koerselstyper
      .map((o: any) => `<option value="${o.label}" ${valgt === o.label ? "selected" : ""}>${o.label}</option>`)
      .join("");

    const select = `<select
      data-bevilling-id="${row.bevilling_id}"
      data-field="oensket_befordringstype"
      data-current="${valgt ?? ""}"
      ${canEdit ? "" : "disabled"}
      ${canEdit ? "" : 'title="Du har ikke rettigheder til at ændre ønsket kørselstype"'}
      class="w-full border border-gray-300 rounded px-2 py-1 text-sm bg-white focus:border-blue-400 focus:outline-none disabled:bg-gray-100 disabled:text-gray-400 disabled:cursor-not-allowed"
    >
      <option value="">— Vælg —</option>
      ${opts}
    </select>`;

    // The ticked types are worth showing in exactly two cases: nothing has
    // been decided yet, and the decision differs from what was asked for.
    // Where the two agree there is nothing to compare, and repeating the
    // value under itself would cost every row a second line for no reading.
    const visAnsoegt =
      ansoegt.length > 0 && (valgt === null || !(ansoegt.length === 1 && ansoegt[0] === valgt));

    if (!visAnsoegt) return select;

    return `${select}<span class="block mt-0.5 text-xs text-gray-500">Ansøgt: ${ansoegt.join(", ")}</span>`;
  }

  $: columns = [
    {
      key: "adresseringsnavn",
      label: "Navn",
      render: (row: any) => `
        <a href="/sag/${row.cpr_elev}" class="text-sky-600 font-medium hover:underline">
          ${row.adresseringsnavn ?? ""}
        </a>
      `
    },
    {
      key: "ansoegningsdato",
      label: "Ventetid",
      filterable: false,
      render: (row: any) => {
        const days = daysSince(row.ansoegningsdato);
        return `<span style="display:inline-block;padding:2px 10px;border-radius:9999px;font-size:0.75rem;font-weight:600;${waitingBadgeStyle(days)}">${waitingLabel(days)}</span>`;
      }
    },
    {
      key: "status_tekst",
      label: "Status",
      filterType: "select",
      multiSelect: true,
      render: (row: any) => {
        const status = row.status_tekst ?? "";
        return `<span class="inline-block px-2 py-0.5 rounded text-xs font-medium ${getStatusBadgeClass(status)}">${status}</span>`;
      }
    },
    {
      key: "cpr_elev",
      label: "CPR",
      render: (row: any) => formatCpr(row.cpr_elev)
    },
    {
      key: "esdh_noegle",
      label: "Sags-ID",
      // The key keeps linking to the student page: this table has no row
      // click and the CPR column is plain text, so it is the only way in.
      // GO gets its own small link beside it rather than taking the one that
      // already carries the navigation.
      render: (row: any) => {
        const internt = `<a href="/sag/${row.cpr_elev}" class="text-sky-600 hover:underline">${row.esdh_noegle ?? ""}</a>`;

        return row.esdh_url
          ? `${internt} <a href="${encodeURI(row.esdh_url)}" target="_blank" rel="noopener noreferrer"
                title="Åbn sagen i GO" class="ml-1 text-xs text-gray-500 hover:underline">GO</a>`
          : internt;
      }
    },
    {
      key: "ansoegningsdato",
      label: "Ansøgningsdato",
      render: (row: any) => formatDanishDate(row.ansoegningsdato)
    },
    {
      key: "foerste_koersel_dato",
      label: "Ønsket startdato",
      render: (row: any) => formatDanishDate(row.foerste_koersel_dato)
    },
    {
      key: "oensket_koerselstype",
      label: "Ønsket kørselstype",
      filterType: "select",
      multiSelect: true,
      // Filtered on what the row effectively says — the caseworker's reading
      // where there is one, otherwise each ticked type on its own, so the
      // dropdown offers types rather than combinations. A row nobody has
      // decided and nobody applied under is findable as "Ikke angivet".
      filterValues: (row: any) => {
        const valgt = valgtType(row);
        if (valgt) return [valgt];

        const ansoegt = ansoegteTyper(row);
        return ansoegt.length > 0 ? ansoegt : ["Ikke angivet"];
      },
      render: (row: any) => buildTypeSelect(row)
    },
    {
      key: "ansoegningstype",
      label: "Midlertidig kørsel",
      filterType: "select",
      multiSelect: true,
      // "Kørsel" holding "Fast kørsel"/"Midlertidig kørsel" read as a question
      // about the kørselstype rather than about the ansøgningstype. Asked as a
      // yes/no it cannot: almost everything is Nej, so the few Ja rows are the
      // information, and they are the ones given the colour.
      //
      // filterValues, not just render: the filter dropdown is built from it
      // too, so it offers Ja/Nej instead of the raw values behind them.
      filterValues: (row: any) => [isMidlertidigKoersel(row.ansoegningstype) ? "Ja" : "Nej"],
      render: (row: any) =>
        isMidlertidigKoersel(row.ansoegningstype)
          ? `<span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-semibold bg-amber-100 text-amber-800 border border-amber-300">Ja</span>`
          : `<span class="text-gray-400">Nej</span>`
    },
    {
      key: "sagsbehandler",
      label: "Sagsbehandler",
      filterType: "select",
      multiSelect: true,
      render: (row: any) => buildSelect(
        row.bevilling_id,
        "sagsbehandler_id",
        row.sagsbehandler_id,
        sagsbehandlere,
        "— Vælg —"
      )
    },
    {
      key: "ppr_sagsbehandler_tekst",
      label: "PPR sagsbehandler",
      filterType: "select",
      multiSelect: true,
      render: (row: any) => buildSelect(
        row.bevilling_id,
        "ppr_sagsbehandler_id",
        row.ppr_sagsbehandler_id,
        pprSagsbehandlere,
        "— Vælg —",
        canAssignPpr
      )
    },
  ] satisfies DataTableColumn[];
</script>



<section>

  <ReadOnlyNotice />

  <div class="flex items-center justify-between mb-5 flex-wrap gap-3">
    <div>
      <h1 class="text-2xl font-bold text-gray-900">Nye ansøgninger</h1>
      <p class="text-sm text-gray-500 mt-0.5">Ansøgninger der afventer behandling</p>
    </div>
  </div>

  
  {#if assignError}
    <div class="mb-6 flex items-start gap-3 rounded-lg border border-red-200 bg-red-50 px-4 py-3">
      <p class="text-sm text-red-700 flex-1">{assignError}</p>
      <button
        type="button"
        class="text-sm font-medium text-red-700 hover:underline shrink-0"
        on:click={() => (assignError = null)}
      >
        Luk
      </button>
    </div>
  {/if}


  <!-- Summary card -->
  <div class="bg-white border border-gray-300 rounded-lg shadow px-6 py-5 mb-5 flex items-center gap-8">
    <button type="button"
      class="flex flex-col items-center rounded px-2 py-1 -mx-2 -my-1 transition-colors min-w-[10rem]"
      class:hover:bg-gray-100={quickFilter !== null}
      class:cursor-pointer={quickFilter !== null}
      class:cursor-default={quickFilter === null}
      on:click={() => { if (quickFilter !== null) quickFilter = null; }}>
      <p class="text-3xl font-bold text-gray-900">{ansoegninger.length}</p>
      <p class="text-xs uppercase tracking-widest text-gray-400 mt-1.5">Afventer</p>
    </button>

    <div class="h-10 w-px bg-gray-200"></div>

    <button type="button"
      class="flex flex-col items-center hover:bg-amber-50 transition-colors rounded px-2 py-1 -mx-2 -my-1 min-w-[10rem]"
      class:ring-2={quickFilter === 'over7'}
      class:ring-amber-400={quickFilter === 'over7'}
      on:click={() => { quickFilter = quickFilter === 'over7' ? null : 'over7'; }}>
      <p class="text-3xl font-bold" style={overOneWeek > 0 ? 'color:#ca8a04;' : 'color:#9ca3af;'}>{overOneWeek}</p>
      <p class="text-xs uppercase tracking-widest text-gray-400 mt-1.5">Venter over 7 dage</p>
    </button>

    <div class="h-10 w-px bg-gray-200"></div>

    <button type="button"
      class="flex flex-col items-center hover:bg-red-50 transition-colors rounded px-2 py-1 -mx-2 -my-1 min-w-[10rem]"
      class:ring-2={quickFilter === 'over10'}
      class:ring-red-400={quickFilter === 'over10'}
      on:click={() => { quickFilter = quickFilter === 'over10' ? null : 'over10'; }}>
      <p class="text-3xl font-bold" style={overTwoWeeks > 0 ? 'color:#dc2626;' : 'color:#9ca3af;'}>{overTwoWeeks}</p>
      <p class="text-xs uppercase tracking-widest text-gray-400 mt-1.5">Venter over 10 dage</p>
    </button>
  </div>


  {#if ansoegninger.length === 0}

    <!-- Empty state -->
    <div class="bg-white border border-gray-300 rounded-lg shadow px-6 py-16 text-center">
      <div class="w-12 h-12 rounded-full bg-green-100 flex items-center justify-center mx-auto mb-4">
        <svg class="w-6 h-6 text-green-600" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" d="M5 13l4 4L19 7" />
        </svg>
      </div>
      <p class="text-gray-700 font-semibold">Ingen nye ansøgninger</p>
      <p class="text-sm text-gray-400 mt-1">Alle ansøgninger er behandlet.</p>
    </div>

  {:else}

    <!-- svelte-ignore a11y-no-static-element-interactions -->
    <div
      class="bg-white border border-gray-300 rounded-lg overflow-hidden shadow-sm mb-6"
      on:change={handleDropdownChange}
    >
      <DataTable
        data={displayedAnsoegninger}
        columns={columns}
        filterable={true}
        rowStyle={rowUrgencyStyle}
      />
    </div>

  {/if}

</section>
