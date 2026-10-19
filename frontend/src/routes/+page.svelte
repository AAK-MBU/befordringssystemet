<script lang="ts">
  import DataTable, { type DataTableColumn } from "$lib/components/DataTable.svelte";
  import { getStatusBadgeClass, formatCpr, revurderingPillHtml } from "$lib/tableColumnConfig";
  import { statusRang } from "$lib/statusRang";

  export let data;



  const columns: DataTableColumn[] = [
    {
      key: "navn",
      label: "Navn",
      filterType: "text",
      render: (row) => `
        <a href="/sag/${row.cpr}" class="text-sky-600 font-medium hover:underline">
          ${row.navn ?? ""}
        </a>
      `
    },
    {
      key: "cpr",
      label: "CPR",
      filterType: "text",
      render: (row: any) => formatCpr(row.cpr)
    },
    {
      key: "status",
      label: "Status",
      filterType: "select",
      multiSelect: true,
      render: (row) => `
        <span class="inline-block px-2 py-0.5 rounded text-xs font-medium ${getStatusBadgeClass(row.status)}">
          ${row.status ?? ""}
        </span>${revurderingPillHtml(row)}
      `
    },
    {
      key: "esdh_noegle",
      label: "Sags-ID",
      filterType: "text",
      // The href was "#" — a link that went nowhere. It now opens the case in
      // GO, where the nightly run has resolved a URL for it, and renders as
      // plain text where it has not.
      render: (row) => {
        const noegle = row.esdh_noegle ?? "";

        return row.esdh_url
          ? `<a href="${encodeURI(row.esdh_url)}" target="_blank" rel="noopener noreferrer"
                title="Åbn sagen i GO" class="text-sky-600 hover:underline">${noegle}</a>`
          : `<span class="text-gray-500">${noegle}</span>`;
      }
    },
    {
      key: "skole_navn",
      label: "Skole",
      filterType: "select",
      multiSelect: true
    },
    {
      key: "koerselstyper",
      label: "Kørselstype",
      filterType: "select",
      multiSelect: true,
      // A bevilling can hold several kørselsrækker with different types, so
      // the cell is a list rather than a single value. filterValues makes the
      // dropdown offer each type on its own instead of one option per
      // combination that happens to occur.
      filterValues: (row: any) => row.koerselstyper ?? [],
      render: (row: any) => {
        const typer: string[] = row.koerselstyper ?? [];

        if (typer.length === 0) {
          return `<span class="text-gray-400">—</span>`;
        }

        return `<div class="flex flex-wrap gap-1">${typer
          .map(
            (type) => `<span class="inline-block px-2 py-0.5 rounded text-xs font-medium bg-slate-100 text-slate-700 border border-slate-200">${type}</span>`
          )
          .join("")}</div>`;
      }
    },
    {
      key: "sagsbehandler",
      label: "Sagsbehandler",
      filterType: "select",
      multiSelect: true
    },
    {
      key: "ppr_sagsbehandler",
      label: "PPR ansvarlig",
      filterType: "select",
      multiSelect: true
    },
  ];

  // Shared with the student page, bevillingslisten and view_Stamdata — see
  // $lib/statusRang. This table used to carry its own order, which ranked
  // Fejlet sixth, so a student needing attention sorted below expired ones.
  $: sortedBevillinger = [...(data.bevillinger ?? [])].sort(
    (a, b) => statusRang(a.status) - statusRang(b.status)
  );

  $: totalCount = sortedBevillinger.length;

  // Bound from DataTable, which owns the filtering. The heading says "Alle
  // bevillinger" only while that is true.
  let visteBevillinger = 0;
  let bevillingFiltreAktive = false;
  $: fejledeBevillinger = sortedBevillinger.filter((b: any) => b.status === "Fejlet");

</script>


<section>

  <!-- Page header -->
  <div class="flex items-start justify-between mb-6">
    <div>
      <h1 class="text-2xl font-bold text-gray-900">Overblik</h1>
      <p class="text-sm text-gray-500 mt-0.5">Bevillingsoversigt - Aarhus Kommune</p>
    </div>
    <button
      type="button"
      class="inline-flex items-center gap-2 px-4 py-2 text-sm border border-gray-300 rounded bg-white hover:bg-gray-50 shadow-sm text-gray-700"
    >
      <svg class="w-4 h-4 text-green-600" fill="currentColor" viewBox="0 0 20 20">
        <path fill-rule="evenodd" d="M3 17a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1zm3.293-7.707a1 1 0 011.414 0L9 10.586V3a1 1 0 112 0v7.586l1.293-1.293a1 1 0 111.414 1.414l-3 3a1 1 0 01-1.414 0l-3-3a1 1 0 010-1.414z" clip-rule="evenodd" />
      </svg>
      Eksporter Excel
    </button>
  </div>


  <!-- Fejlede bevillinger alert panel — shown whenever any bevilling has status Fejlet -->
  {#if fejledeBevillinger.length > 0}
    <div class="mb-6">
      <div class="flex items-center gap-2.5 mb-3 px-3 py-2 bg-red-50 rounded-lg border border-red-200 shadow-sm">
        <h2 class="font-semibold text-red-800">Fejlede bevillinger</h2>
        <span class="ml-auto inline-flex items-center justify-center min-w-[1.5rem] h-6 px-2 rounded-full text-white text-xs font-bold bg-red-600">
          {fejledeBevillinger.length}
        </span>
      </div>
      <div class="bg-white border border-red-200 rounded-lg overflow-hidden shadow-sm">
        <table class="w-full text-sm text-gray-700 border-collapse">
          <thead>
            <tr class="text-left text-white bg-red-600">
              <th class="px-4 py-3 font-semibold whitespace-nowrap min-w-36">Navn</th>
              <th class="px-4 py-3 font-semibold whitespace-nowrap min-w-36">CPR</th>
              <th class="px-4 py-3 font-semibold whitespace-nowrap min-w-36">Sags-ID</th>
              <th class="px-4 py-3 font-semibold whitespace-nowrap min-w-36">Kørselstype</th>
            </tr>
          </thead>
          <tbody>
            {#each fejledeBevillinger as bev (bev.cpr)}
              <tr class="border-t border-red-100 hover:bg-red-50">
                <td class="px-4 py-3 whitespace-nowrap">
                  <a href="/sag/{bev.cpr}" class="font-medium text-sky-700 hover:underline">
                    {bev.navn ?? "—"}
                  </a>
                </td>
                <td class="px-4 py-3 whitespace-nowrap">{formatCpr(bev.cpr)}</td>
                <td class="px-4 py-3 whitespace-nowrap">
                  <a href="/sag/{bev.cpr}" class="text-sky-600 hover:underline font-mono">{bev.esdh_noegle ?? "—"}</a>
                </td>
                <td class="px-4 py-3 whitespace-nowrap">
                  {#if (bev.koerselstyper ?? []).length > 0}
                    <div class="flex flex-wrap gap-1">
                      {#each bev.koerselstyper as type}
                        <span class="inline-block px-2 py-0.5 rounded text-xs font-medium bg-white text-red-800 border border-red-200">
                          {type}
                        </span>
                      {/each}
                    </div>
                  {:else}
                    <span class="text-gray-400">—</span>
                  {/if}
                </td>
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
    </div>
  {/if}

  <!-- All bevillinger -->
  <div class="mb-6">
    <div class="flex items-center gap-2.5 mb-3 px-3 py-2 bg-white rounded-lg border border-gray-300 shadow-sm">
      <h2 class="font-semibold text-gray-700">
        {bevillingFiltreAktive ? "Filtrerede bevillinger" : "Alle bevillinger"}
      </h2>
      <div class="ml-auto flex items-center gap-1.5">
        <span
          class="inline-flex items-center justify-center min-w-[1.5rem] h-6 px-2 rounded-full text-white text-xs font-bold"
          style="background-color: #032A42;"
        >
          {bevillingFiltreAktive ? visteBevillinger : totalCount}
        </span>
        {#if bevillingFiltreAktive}
          <span class="text-xs text-gray-500 whitespace-nowrap">af {totalCount}</span>
        {/if}
      </div>
    </div>
    <div class="bg-white border border-gray-300 rounded-lg overflow-hidden shadow-sm">
      <DataTable
        data={sortedBevillinger}
        columns={columns}
        filterable={true}
        bind:filteredCount={visteBevillinger}
        bind:filtersActive={bevillingFiltreAktive}
      />
    </div>
  </div>

</section>