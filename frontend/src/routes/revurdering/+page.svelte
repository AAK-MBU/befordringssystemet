  <script lang="ts">
    import { invalidateAll } from "$app/navigation";
    import { backendFetch } from "$lib/client/backendFetch";
    import { formatDanishDate, getStatusBadgeClass, formatCpr, getBefordringstypeBadgeClass } from "$lib/tableColumnConfig";
    import BevillingTable from "$lib/components/BevillingTable.svelte";
    import CreateBevillingModal from "$lib/components/CreateBevillingModal.svelte";
    import CreateLetterModal from "$lib/components/CreateLetterModal.svelte";
    import ReadOnlyNotice from "$lib/components/ReadOnlyNotice.svelte";
  import Elevoplysninger from "$lib/components/Elevoplysninger.svelte";
  import { sorterBevillinger } from "$lib/bevillingSortering";
  import { iBatches } from "$lib/batching";
  import AnsvarligSelect from "$lib/components/AnsvarligSelect.svelte";
    import { matcherFilter, filterTilQuery, daysUntil, aktiveKoerselstyper, IKKE_TILDELT, type RevurderingFilter } from "$lib/revurderingFilter";

    export let data;

    // can_edit is resolved by the backend from EDIT_ROLES (see GET /me), so
    // the UI cannot drift from what require_edit actually enforces.
    $: canEdit = data.user?.can_edit ?? false;

    $: revurderinger        = data.revurderinger        ?? [];
    $: koerselstyper        = data.koerselstyper        ?? [];
    $: tidspunkter          = data.tidspunkter          ?? [];
    $: hjemler              = data.hjemler              ?? [];
    $: afgoerelsesbreve     = data.afgoerelsesbreve     ?? [];
    $: koerselstypeTillaeg  = data.koerselstypeTillaeg  ?? [];
    $: dage                 = data.dage                 ?? [];
    $: statuser             = data.statuser             ?? [];
    $: skolematrikler       = data.skolematrikler       ?? [];
    $: sagsbehandlere       = data.sagsbehandlere       ?? [];
    $: pprSagsbehandlere    = data.pprSagsbehandlere    ?? [];
    $: hjaelpemidler        = data.hjaelpemidler        ?? [];
    $: ungdomsuddannelser   = data.ungdomsuddannelser   ?? [];
    $: rutetyper            = data.rutetyper            ?? [];

    $: lookupOptions = {
      koerselstyper, tidspunkter, koerselstypeTillaeg, dage,
      statuser, skolematrikler, hjemler, afgoerelsesbreve,
      sagsbehandlere, pprSagsbehandlere, hjaelpemidler, ungdomsuddannelser,
      rutetyper,
    };

    let selectedSkole = "";
    let selectedSagsbehandler = "";
    let selectedPprSagsbehandler = "";
    let selectedKoerselstype = "";

    let filterFromDate = "";
    let filterToDate = "";
    let quickFilter: null | "overskredet" | "inden30" = null;

    $: uniqueSkoler            = [...new Set(revurderinger.map((b: any) => b.skole_navn).filter(Boolean))].sort() as string[];
    $: uniqueSagsbehandlere    = [...new Set(revurderinger.map((b: any) => b.ansvarlig_sagsbehandler_tekst).filter(Boolean))].sort() as string[];
    $: uniquePprSagsbehandlere = [...new Set(revurderinger.map((b: any) => b.ansvarlig_ppr_sagsbehandler_tekst).filter(Boolean))].sort() as string[];
    $: uniqueKoerselstyper     = [...new Set(
      revurderinger.flatMap((b: any) => aktiveKoerselstyper(b))
    )].sort() as string[];

    // One object, so the predicate and the export URL are built from exactly
    // the same state.
    $: aktivtFilter = {
      skole: selectedSkole,
      sagsbehandler: selectedSagsbehandler,
      pprSagsbehandler: selectedPprSagsbehandler,
      koerselstype: selectedKoerselstype,
      fraDato: filterFromDate,
      tilDato: filterToDate,
      hurtigfilter: quickFilter ?? "",
    } satisfies RevurderingFilter;

    // Filtered through $lib/revurderingFilter rather than inline, because the
    // CSV export applies the SAME function server side. A second copy of these
    // rules would drift, and the failure would be silent — the file would hold
    // a different set of cases than the screen, with no way to tell which was
    // right.
    $: filteredRevurderinger = revurderinger.filter((b: any) => matcherFilter(b, aktivtFilter));

    // The export mirrors the current view, so the query carries the filter.
    $: eksportUrl = (() => {
      const query = filterTilQuery(aktivtFilter);
      return `/revurdering/revurderinger.csv${query ? `?${query}` : ""}`;
    })();

    $: anyFilterActive = !!(selectedSkole || selectedSagsbehandler || selectedPprSagsbehandler
                            || selectedKoerselstype || filterFromDate
                            || filterToDate || quickFilter);

    $: overskredet    = revurderinger.filter((b: any) => (daysUntil(b.revurderingsdato) ?? 0) < 0).length;
    $: indenFor30Dage = revurderinger.filter((b: any) => { const d = daysUntil(b.revurderingsdato); return d !== null && d >= 0 && d <= 30; }).length;

    function urgencyColor(revurderingsdato: string | null): string {
      const d = daysUntil(revurderingsdato);
      if (d === null) return "#6b7280";
      if (d < 0)     return "#dc2626";
      if (d <= 30)   return "#ca8a04";
      return "#3b82f6";
    }

    function urgencyLabel(revurderingsdato: string | null): string {
      const d = daysUntil(revurderingsdato);
      if (d === null) return "Ingen dato";
      if (d < 0)     return `${Math.abs(d)} dage overskredet`;
      if (d === 0)   return "I dag";
      if (d === 1)   return "I morgen";
      return `Om ${d} dage`;
    }

    let expandedIds = new Set<number>();

    // Which rows have their comment section open. Kept next to
    // expandedIds because the two move together — see toggleExpand.
    let expandedCommentsBevIds = new Set<number>();

    // Parties per citizen, loaded lazily alongside aktiviteter and bevillinger
    // when a row is expanded. Needed by the egenbefordring kørselsrække, which
    // names one of them as the recipient of the kilometre reimbursement.
    let parterByCpr: Record<string, any[]> = {};

    async function loadParter(cpr: string) {
      const res = await backendFetch(`/part/${cpr}/recipients`);

      if (!res.ok) return;

      parterByCpr[cpr] = await res.json();
      parterByCpr = { ...parterByCpr };
    }

    function toggleExpand(id: number) {
      if (expandedIds.has(id)) {
        expandedIds.delete(id);
        // Forget the comment state on collapse, so re-opening the row starts
        // from the default again rather than remembering a close from before.
        expandedCommentsBevIds.delete(id);
      } else {
        expandedIds.add(id);
        // Kommentarerne er svære at få øje på, når de ligger foldet sammen i
        // en i forvejen stor række, så de åbnes sammen med den. Toggle-knappen
        // virker stadig bagefter — den her sætter kun udgangspunktet.
        expandedCommentsBevIds.add(id);
        const bev = revurderinger.find((r: any) => r.bevilling_id === id);
        if (bev) {
          if (!aktiviteterByCpr[bev.cpr_elev]) loadAktiviteter(bev.cpr_elev);
          if (!bevillingerByCpr[bev.cpr_elev]) loadBevillinger(bev.cpr_elev);
          if (!parterByCpr[bev.cpr_elev]) loadParter(bev.cpr_elev);
        }
      }
      expandedIds = new Set(expandedIds);
      expandedCommentsBevIds = new Set(expandedCommentsBevIds);
    }

    // True while "Udvid alle" is still loading, so the button can say so and
    // cannot be pressed again into the same queue.
    let udvider = false;

    async function expandAll() {
      if (udvider) return;

      // The rows open immediately. Only the loading is paced — a caseworker
      // should see the list expand at once, not watch it fill in.
      expandedIds = new Set(filteredRevurderinger.map((b: any) => b.bevilling_id));
      // Udvid alle åbner også kommentarerne — samme regel som en enkelt række.
      expandedCommentsBevIds = new Set(expandedIds);

      // A few students at a time. Unbounded, this fired three requests per row
      // — and loading one student's bevillinger fans out again, one request per
      // bevilling — so 80 rows meant roughly 400 requests at once. The API's
      // connection pool holds 30; the rest queued until they timed out, and
      // because the pool is shared it returned 500s to other users too.
      // See $lib/batching.
      udvider = true;

      try {
        await iBatches(filteredRevurderinger, async (bev: any) => {
          await Promise.all([
            aktiviteterByCpr[bev.cpr_elev] ? null : loadAktiviteter(bev.cpr_elev),
            bevillingerByCpr[bev.cpr_elev] ? null : loadBevillinger(bev.cpr_elev),
            parterByCpr[bev.cpr_elev] ? null : loadParter(bev.cpr_elev),
          ]);
        });
      } finally {
        udvider = false;
      }
    }

    function collapseAll() {
      expandedIds = new Set();
      expandedCommentsBevIds = new Set();
    }

    $: allExpanded = filteredRevurderinger.length > 0 && filteredRevurderinger.every((b: any) => expandedIds.has(b.bevilling_id));

    function emptyToNull(value: any) { return value === "" ? null : value; }
    function numberOrNull(value: any) { return value === "" ? null : Number(value); }

    async function handleSaveBevilling(bevillingId: number, updates: any): Promise<string | null> {
      const { hjaelpemiddel_ids, ...bevillingUpdates } = updates;
      const res = await backendFetch(`/bevilling/${bevillingId}`, {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(bevillingUpdates),
      });
      if (!res.ok) {
        let message = "Kunne ikke gemme bevilling";
        try { const err = await res.json(); message = err?.detail?.message ?? err?.detail ?? message; } catch { /* keep fallback */ }
        return message;
      }
      await backendFetch(`/bevilling/${bevillingId}/hjaelpemidler`, {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ hjaelpemiddel_ids: hjaelpemiddel_ids ?? [] }),
      });
      await invalidateAll();
      return null;
    }

    async function handleSaveKoerselsraekke(koerselId: number, updates: any): Promise<string | null> {
      const { tillaeg_ids, dag_ids, ...rest } = updates;
      const r1 = await backendFetch(`/bevilling/koerselsraekke/${koerselId}`, {
        method: "PUT", headers: { "Content-Type": "application/json" }, body: JSON.stringify(rest),
      });
      if (!r1.ok) {
        let message = "Kunne ikke gemme kørselsrække";
        try { const err = await r1.json(); message = err?.detail?.message ?? err?.detail ?? message; } catch { /* keep fallback */ }
        return message;
      }
      const r2 = await backendFetch(`/bevilling/koerselsraekke/${koerselId}/tillaeg`, {
        method: "PUT", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ tillaeg_ids: tillaeg_ids ?? [] }),
      });
      if (!r2.ok) return "Kørselsrække gemt, men tillæg kunne ikke gemmes";
      const r3 = await backendFetch(`/bevilling/koerselsraekke/${koerselId}/dage`, {
        method: "PUT", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ dag_ids: dag_ids ?? [] }),
      });
      if (!r3.ok) return "Kørselsrække gemt, men dage kunne ikke gemmes";
      await invalidateAll();
      return null;
    }

    async function handleCreateKoerselsraekke(bevillingId: number, updates: any): Promise<string | null> {
      const res = await backendFetch(`/bevilling/create_koerselsraekke/${bevillingId}`, {
        method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(updates),
      });
      if (!res.ok) {
        let message = "Kunne ikke oprette kørselsrække";
        try { const err = await res.json(); message = err?.detail?.message ?? err?.detail ?? message; } catch { /* keep fallback */ }
        return message;
      }
      await invalidateAll();
      return null;
    }

    async function handleFinalizeKoerselsraekke(koerselId: number): Promise<string | null> {
      const res = await backendFetch(`/bevilling/koerselsraekke/${koerselId}`, {
        method: "PUT", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ final: true }),
      });
      if (!res.ok) {
        let message = "Kunne ikke afslutte kørselsrækken";
        try { const err = await res.json(); message = err?.detail ?? message; } catch { /* keep fallback */ }
        return message;
      }
      await invalidateAll();
      return null;
    }



    // Its own endpoint, not the general PUT: that one is behind require_edit
    // and PPR Medarbejder ("user-read") cannot reach it. See require_ppr.
    //
    // Returns the failure message rather than swallowing it. It used to only
    // console.error, so a refused write looked exactly like a successful one —
    // the dialog closed and the tick never appeared.
    async function togglePpr(
      bevillingId: number, cpr: string, current: boolean | null
    ): Promise<string | null> {
      const res = await backendFetch(`/bevilling/${bevillingId}/revurderet_af_ppr`, {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ revurderet_af_ppr: !current }),
      });

      if (!res.ok) {
        let message = "Vurderingen kunne ikke gemmes";

        try {
          const body = await res.json();
          const detail = body?.detail?.message ?? body?.detail;
          if (typeof detail === "string") message = detail;
        } catch { /* keep fallback */ }

        console.error("Failed to update revurderet_af_ppr:", res.status, message);
        return message;
      }

      await loadAktiviteter(cpr);
      await invalidateAll();
      return null;
    }

    type VurderingConfirm = {
      bevillingId: number;
      cpr: string;
      current: boolean | null;
      esdhNoegle?: string | null;
      esdhUrl?: string | null;
    };

    let brConfirmFor: VurderingConfirm | null = null;
    let pprConfirmFor: VurderingConfirm | null = null;
    let pprConfirmError: string | null = null;

    // The case link is carried into the dialog rather than looked up when it
    // renders: approving removes the row from this page, so the link has to be
    // offered while the case is still in front of the caseworker.
    function openBrConfirm(bev: any, current: boolean | null) {
      if (current) { toggleBr(bev.bevilling_id, bev.cpr_elev, current); return; }
      brConfirmFor = {
        bevillingId: bev.bevilling_id, cpr: bev.cpr_elev, current,
        esdhNoegle: bev.esdh_noegle, esdhUrl: bev.esdh_url,
      };
    }

    function openPprConfirm(bev: any, current: boolean | null) {
      if (current) { togglePpr(bev.bevilling_id, bev.cpr_elev, current); return; }
      pprConfirmError = null;
      pprConfirmFor = {
        bevillingId: bev.bevilling_id, cpr: bev.cpr_elev, current,
        esdhNoegle: bev.esdh_noegle, esdhUrl: bev.esdh_url,
      };
    }

    async function toggleBr(bevillingId: number, cpr: string, current: boolean | null) {
      const res = await backendFetch(`/bevilling/${bevillingId}`, {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ revurderet_af_br: !current }),
      });
      if (!res.ok) { console.error("Failed to update revurderet_af_br:", res.status); return; }
      await loadAktiviteter(cpr);
      await invalidateAll();
    }

    let aktiviteterByCpr: Record<string, any[]> = {};
    let loadingAktiviteterCpr = new Set<string>();

    async function loadAktiviteter(cpr: string) {
      loadingAktiviteterCpr.add(cpr);
      loadingAktiviteterCpr = new Set(loadingAktiviteterCpr);
      try {
        const res = await backendFetch(`/aktivitet/${cpr}`);
        if (res.ok) {
          aktiviteterByCpr[cpr] = await res.json();
          aktiviteterByCpr = { ...aktiviteterByCpr };
        }
      } finally {
        loadingAktiviteterCpr.delete(cpr);
        loadingAktiviteterCpr = new Set(loadingAktiviteterCpr);
      }
    }


    let copiedCpr: string | null = null;

    async function copyCpr(cpr: string, e: Event) {
      e.stopPropagation();
      await navigator.clipboard.writeText(cpr.replace(/\D/g, ''));
      copiedCpr = cpr;
      setTimeout(() => { copiedCpr = null; }, 1500);
    }

    function toggleComments(bevillingId: number) {
      if (expandedCommentsBevIds.has(bevillingId)) {
        expandedCommentsBevIds.delete(bevillingId);
      } else {
        expandedCommentsBevIds.add(bevillingId);
      }
      expandedCommentsBevIds = new Set(expandedCommentsBevIds);
    }

    let showCommentModal = false;
    let commentModalCpr = "";
    let commentModalBevillingId: number | null = null;
    let newComment = "";
    let savingComment = false;

    let inlineComments: Record<number, string> = {};
    let savingInlineCommentIds = new Set<number>();

    async function saveInlineComment(cpr: string, bevillingId: number) {
      const kommentar = (inlineComments[bevillingId] ?? "").trim();
      if (!kommentar) return;
      savingInlineCommentIds.add(bevillingId);
      savingInlineCommentIds = new Set(savingInlineCommentIds);
      try {
        const res = await backendFetch(`/aktivitet/${cpr}`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ aktivitetstype: "Kommentar", kommentar, udfoert_af: null, relateret_bevilling_id: bevillingId }),
        });
        if (res.ok) {
          inlineComments = { ...inlineComments, [bevillingId]: "" };
          await loadAktiviteter(cpr);
        }
      } finally {
        savingInlineCommentIds.delete(bevillingId);
        savingInlineCommentIds = new Set(savingInlineCommentIds);
      }
    }

    function openCommentModal(cpr: string, bevillingId: number) {
      commentModalCpr = cpr;
      commentModalBevillingId = bevillingId;
      newComment = "";
      showCommentModal = true;
    }

    async function saveComment() {
      const kommentar = newComment.trim();
      if (!kommentar) return;
      savingComment = true;
      try {
        const res = await backendFetch(`/aktivitet/${commentModalCpr}`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            aktivitetstype: "Kommentar",
            kommentar,
            udfoert_af: null,
            relateret_bevilling_id: commentModalBevillingId,
          }),
        });
        if (res.ok) {
          newComment = "";
          showCommentModal = false;
          await loadAktiviteter(commentModalCpr);
          await invalidateAll();
        }
      } finally {
        savingComment = false;
      }
    }

    let bevillingerByCpr: Record<string, any[]> = {};
    let loadingBevillingerCpr = new Set<string>();

    async function loadBevillinger(cpr: string) {
      loadingBevillingerCpr.add(cpr);
      loadingBevillingerCpr = new Set(loadingBevillingerCpr);
      try {
        // One request. The endpoint nests koerselsraekker itself — this used
        // to fetch them one bevilling at a time, which on an expanded worklist
        // was around a hundred extra requests against a pool of thirty.
        const res = await backendFetch(`/bevilling/get_student_bevillinger/${cpr}`);
        if (!res.ok) return;
        const bevillinger = await res.json();
        // Same order as the sag page — active bevilling first. See
        // $lib/bevillingSortering for why the API order is not enough.
        bevillingerByCpr[cpr] = sorterBevillinger(bevillinger);
        bevillingerByCpr = { ...bevillingerByCpr };
      } finally {
        loadingBevillingerCpr.delete(cpr);
        loadingBevillingerCpr = new Set(loadingBevillingerCpr);
      }
    }

    let showCreateBevillingModal = false;
    let bevillingModalCpr = "";
    // Captured when the modal opens: the modal sits outside the row loop, so the
    // student's klassetrin has to be carried across with the cpr.
    let bevillingModalElevklassetrin: string | null = null;
    let createBevillingModalMode: 'kopi' | 'tom' | null = null;

    function openCreateBevillingModal(
      cpr: string,
      mode: 'kopi' | 'tom',
      elevklassetrin: string | null = null
    ) {
      bevillingModalCpr = cpr;
      bevillingModalElevklassetrin = elevklassetrin;
      createBevillingModalMode = mode;
      showCreateBevillingModal = true;
    }

    let showCreateLetterModal = false;
    let letterModalCpr = "";

    function openCreateLetterModal(cpr: string) {
      letterModalCpr = cpr;
      showCreateLetterModal = true;
    }

  </script>


<svelte:window on:keydown={(e) => {
  if (e.key !== 'Escape') return;
  if (showCreateBevillingModal) { showCreateBevillingModal = false; }
  if (showCommentModal) { showCommentModal = false; }
  if (pprConfirmFor) { pprConfirmFor = null; }
  if (brConfirmFor) { brConfirmFor = null; }
}} />


{#if pprConfirmFor}
  <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/40" role="dialog" aria-modal="true" tabindex="-1">
    <div class="bg-white rounded-xl shadow-2xl w-full max-w-md overflow-hidden">
      <div class="flex items-center justify-between px-5 py-4" style="background:#032A42;">
        <h3 class="text-sm font-semibold text-white">PPR vurderet</h3>
        <button type="button" aria-label="Luk" class="text-white/70 hover:text-white" on:click={() => (pprConfirmFor = null)}>
          <svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>
      </div>
      <div class="px-5 py-5 text-sm text-gray-700 space-y-3">
        <p>Sørg for at du er helt færdig med vurderingen før du godkender.</p>
        {#if pprConfirmFor.esdhUrl}
          <a
            href={pprConfirmFor.esdhUrl}
            target="_blank"
            rel="noopener noreferrer"
            class="inline-flex items-center gap-2 text-sky-600 hover:underline font-medium"
          >
            <svg class="w-4 h-4 shrink-0" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24" aria-hidden="true">
              <path stroke-linecap="round" stroke-linejoin="round" d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" />
            </svg>
            Åbn sagen i GO{pprConfirmFor.esdhNoegle ? ` (${pprConfirmFor.esdhNoegle})` : ""}
          </a>
        {:else if pprConfirmFor.esdhNoegle}
          <p class="text-xs text-gray-500">
            Sags-ID {pprConfirmFor.esdhNoegle} — linket er ikke slået op endnu.
          </p>
        {/if}
        <p class="font-semibold text-gray-900">Sagen er vurderet</p>
        {#if pprConfirmError}
          <p class="text-sm text-red-600 bg-red-50 border border-red-200 rounded px-3 py-2">
            {pprConfirmError}
          </p>
        {/if}
      </div>
      <div class="flex justify-end gap-2 px-5 py-4 border-t border-gray-100">
        <button type="button" class="px-4 py-2 text-sm font-medium text-gray-600 bg-gray-100 hover:bg-gray-200 rounded-lg" on:click={() => (pprConfirmFor = null)}>Annullér</button>
        <button type="button" class="px-4 py-2 text-sm font-medium text-white bg-green-600 hover:bg-green-700 rounded-lg"
          on:click={async () => {
            if (!pprConfirmFor) return;
            pprConfirmError = await togglePpr(
              pprConfirmFor.bevillingId, pprConfirmFor.cpr, pprConfirmFor.current
            );
            // Only close on success — closing on a refusal is what made this
            // look like nothing happened at all.
            if (!pprConfirmError) pprConfirmFor = null;
          }}>Godkend</button>
      </div>
    </div>
  </div>
{/if}


{#if brConfirmFor}
  <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/40" role="dialog" aria-modal="true" tabindex="-1">
    <div class="bg-white rounded-xl shadow-2xl w-full max-w-md overflow-hidden">
      <div class="flex items-center justify-between px-5 py-4" style="background:#032A42;">
        <h3 class="text-sm font-semibold text-white">BR vurderet</h3>
        <button type="button" aria-label="Luk" class="text-white/70 hover:text-white" on:click={() => (brConfirmFor = null)}>
          <svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>
      </div>
      <div class="px-5 py-5 text-sm text-gray-700 space-y-3">
        <p>Sagen forsvinder fra denne side når du godkender vurderingen. Sørg derfor for at du er helt færdig med vurderingen og har oprettet brev.</p>
        <!-- Tilbydes FØR godkendelse, ikke efter: sagen forsvinder fra siden,
             så snart vurderingen er godkendt, og så er linket væk med den.
             En almindelig <a target="_blank"> frem for en popup — browseren
             åbner fanen, og sagsbehandleren beholder dialogen. -->
        {#if brConfirmFor.esdhUrl}
          <a
            href={brConfirmFor.esdhUrl}
            target="_blank"
            rel="noopener noreferrer"
            class="inline-flex items-center gap-2 text-sky-600 hover:underline font-medium"
          >
            <svg class="w-4 h-4 shrink-0" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24" aria-hidden="true">
              <path stroke-linecap="round" stroke-linejoin="round" d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" />
            </svg>
            Åbn sagen i GO{brConfirmFor.esdhNoegle ? ` (${brConfirmFor.esdhNoegle})` : ""}
          </a>
        {:else if brConfirmFor.esdhNoegle}
          <p class="text-xs text-gray-500">
            Sags-ID {brConfirmFor.esdhNoegle} — linket er ikke slået op endnu.
          </p>
        {/if}
        <p class="font-semibold text-gray-900">Sagen er vurderet</p>
      </div>
      <div class="flex justify-end gap-2 px-5 py-4 border-t border-gray-100">
        <button type="button" class="px-4 py-2 text-sm font-medium text-gray-600 bg-gray-100 hover:bg-gray-200 rounded-lg" on:click={() => (brConfirmFor = null)}>Annullér</button>
        <button type="button" class="px-4 py-2 text-sm font-medium text-white bg-green-600 hover:bg-green-700 rounded-lg"
          on:click={async () => { if (brConfirmFor) { await toggleBr(brConfirmFor.bevillingId, brConfirmFor.cpr, brConfirmFor.current); brConfirmFor = null; } }}>Godkend</button>
      </div>
    </div>
  </div>
{/if}


{#if showCreateBevillingModal && bevillingModalCpr && createBevillingModalMode}
  <CreateBevillingModal
    cpr={bevillingModalCpr}
    mode={createBevillingModalMode}
    existingBevillinger={bevillingerByCpr[bevillingModalCpr] ?? []}
    elevklassetrin={bevillingModalElevklassetrin}
    parter={parterByCpr[bevillingModalCpr] ?? []}
    {lookupOptions}
    on:created={async () => { showCreateBevillingModal = false; await loadBevillinger(bevillingModalCpr); await invalidateAll(); }}
    on:cancel={() => { showCreateBevillingModal = false; }}
  />
{/if}


<!-- Create letter modal (shared with the student page) -->
<CreateLetterModal
  bind:open={showCreateLetterModal}
  cpr={letterModalCpr}
  bevillinger={bevillingerByCpr[letterModalCpr] ?? []}
  on:created={async (e) => { await loadAktiviteter(e.detail.cpr); await invalidateAll(); }}
/>

{#if showCommentModal}
  <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/40" role="presentation">
    <div class="w-full max-w-md bg-white rounded-lg shadow-2xl" role="dialog" aria-modal="true" tabindex="-1">
      <div class="px-6 py-4 border-b border-gray-200" style="background-color: #032A42;">
        <h2 class="text-base font-bold text-white">Tilføj kommentar</h2>
      </div>
      <div class="p-6">
        <textarea rows="4" class="w-full border border-gray-300 rounded px-3 py-2 text-sm resize-none focus:border-blue-400 focus:ring-0"
          placeholder="Skriv kommentar..." bind:value={newComment}></textarea>
      </div>
      <div class="flex justify-end gap-3 border-t border-gray-200 px-6 py-4 bg-gray-50 rounded-b-lg">
        <button type="button" class="px-4 py-2 text-sm font-medium border border-gray-300 rounded hover:bg-gray-50 transition-colors"
          on:click={() => { showCommentModal = false; }}>Annullér</button>
        <button type="button" disabled={savingComment || !newComment.trim()}
          class="px-4 py-2 text-sm font-medium text-white rounded transition-colors disabled:opacity-50"
          style="background-color: #032A42;"
          on:click={saveComment}>
          {savingComment ? "Gemmer..." : "Gem kommentar"}
        </button>
      </div>
    </div>
  </div>
{/if}


<section>

  <ReadOnlyNotice />

  <div class="flex items-center justify-between mb-5 flex-wrap gap-3">
    <div>
      <h1 class="text-2xl font-bold text-gray-900">Revurdering</h1>
      <p class="text-sm text-gray-500 mt-0.5">Bevillinger der afventer revurdering</p>
    </div>

    <div class="flex items-center gap-4 flex-wrap">

      {#if uniqueSkoler.length > 0}
        <select class="min-w-[180px] border border-gray-300 rounded pl-2 pr-6 py-1 text-xs text-gray-700 focus:border-blue-400 focus:ring-0 bg-white" bind:value={selectedSkole}>
          <option value="">Alle skoler ({revurderinger.length})</option>
          {#each uniqueSkoler as skole}
            {@const count = revurderinger.filter((b: any) => b.skole_navn === skole).length}
            <option value={skole}>{skole} ({count})</option>
          {/each}
        </select>
      {/if}

      {#if revurderinger.length > 0}
        <select class="min-w-[160px] border border-gray-300 rounded pl-2 pr-6 py-1 text-xs text-gray-700 focus:border-blue-400 focus:ring-0 bg-white" bind:value={selectedSagsbehandler}>
          <option value="">Alle ansvarlige</option>
          <option value={IKKE_TILDELT}>Ikke tildelt ({revurderinger.filter((b: any) => !b.ansvarlig_sagsbehandler_tekst).length})</option>
          {#each uniqueSagsbehandlere as navn}
            {@const count = revurderinger.filter((b: any) => b.ansvarlig_sagsbehandler_tekst === navn).length}
            <option value={navn}>{navn} ({count})</option>
          {/each}
        </select>
      {/if}

      {#if revurderinger.length > 0}
        <select class="min-w-[160px] border border-gray-300 rounded pl-2 pr-6 py-1 text-xs text-gray-700 focus:border-blue-400 focus:ring-0 bg-white" bind:value={selectedPprSagsbehandler}>
          <option value="">Alle PPR-ansvarlige</option>
          <option value={IKKE_TILDELT}>Ikke tildelt ({revurderinger.filter((b: any) => !b.ansvarlig_ppr_sagsbehandler_tekst).length})</option>
          {#each uniquePprSagsbehandlere as navn}
            {@const count = revurderinger.filter((b: any) => b.ansvarlig_ppr_sagsbehandler_tekst === navn).length}
            <option value={navn}>{navn} ({count})</option>
          {/each}
        </select>
      {/if}

      {#if uniqueKoerselstyper.length > 0}
        <select class="min-w-[160px] border border-gray-300 rounded pl-2 pr-6 py-1 text-xs text-gray-700 focus:border-blue-400 focus:ring-0 bg-white" bind:value={selectedKoerselstype}>
          <option value="">Alle kørselstyper</option>
          {#each uniqueKoerselstyper as type}
            {@const count = revurderinger.filter((b: any) =>
              aktiveKoerselstyper(b).includes(type)
            ).length}
            <option value={type}>{type} ({count})</option>
          {/each}
        </select>
      {/if}

      <div class="flex items-center gap-1.5">
        <span class="text-xs text-gray-500 whitespace-nowrap">Dato fra</span>
        <input type="date" bind:value={filterFromDate} class="border border-gray-300 rounded px-2 py-1 text-xs text-gray-700 focus:border-blue-400 focus:ring-0 bg-white" />
        <span class="text-xs text-gray-500">til</span>
        <input type="date" bind:value={filterToDate} class="border border-gray-300 rounded px-2 py-1 text-xs text-gray-700 focus:border-blue-400 focus:ring-0 bg-white" />
      </div>

      {#if anyFilterActive}
        <button type="button"
          class="text-xs font-medium text-gray-500 hover:text-red-600 flex items-center gap-1 transition-colors whitespace-nowrap"
          on:click={() => { selectedSkole = ""; selectedSagsbehandler = ""; selectedPprSagsbehandler = ""; selectedKoerselstype = ""; filterFromDate = ""; filterToDate = ""; quickFilter = null; }}>
          <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
          </svg>
          Nulstil filtre
        </button>
      {/if}

      {#if filteredRevurderinger.length > 0}
        <button type="button"
          class="text-xs font-medium text-sky-700 hover:underline whitespace-nowrap disabled:text-gray-400 disabled:no-underline disabled:cursor-wait"
          disabled={udvider}
          on:click={() => allExpanded ? collapseAll() : expandAll()}>
          {udvider ? 'Henter…' : allExpanded ? 'Fold alle' : 'Udvid alle'}
        </button>
      {/if}

      <span class="text-sm font-bold text-gray-500">
        {filteredRevurderinger.length}{anyFilterActive ? ` / ${revurderinger.length}` : ''} sager
      </span>

      <!-- A plain <a download>, not a fetch + Blob: the link carries the
           session cookie on its own and the browser owns the save dialog.
           The href carries the current filter, so the file matches the list
           on screen — the count beside it is what the download contains. -->
      <a
        href={eksportUrl}
        download
        class="inline-flex items-center gap-2 px-3 py-1.5 text-sm border border-gray-300 rounded bg-white hover:bg-gray-50 text-gray-700"
        title={anyFilterActive
          ? "Hent de viste sager som CSV"
          : "Hent alle sager som CSV"}
      >
        <svg class="w-4 h-4 text-green-600" fill="currentColor" viewBox="0 0 20 20" aria-hidden="true">
          <path fill-rule="evenodd" d="M3 17a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1zm3.293-7.707a1 1 0 011.414 0L9 10.586V3a1 1 0 112 0v7.586l1.293-1.293a1 1 0 111.414 1.414l-3 3a1 1 0 01-1.414 0l-3-3a1 1 0 010-1.414z" clip-rule="evenodd" />
        </svg>
        {anyFilterActive ? "Hent viste (CSV)" : "Hent alle (CSV)"}
      </a>

    </div>
  </div>


  <div class="bg-white border border-gray-300 rounded-lg shadow px-6 py-5 mb-5 flex items-center gap-8">
    <button type="button"
      class="flex flex-col items-center rounded px-2 py-1 -mx-2 -my-1 transition-colors min-w-[10rem]"
      class:hover:bg-gray-100={quickFilter !== null}
      class:cursor-pointer={quickFilter !== null}
      class:cursor-default={quickFilter === null}
      on:click={() => { if (quickFilter !== null) quickFilter = null; }}>
      <p class="text-3xl font-bold text-gray-900">{revurderinger.length}</p>
      <p class="text-xs uppercase tracking-widest text-gray-400 mt-1.5">Sager</p>
    </button>
    <div class="h-10 w-px bg-gray-200"></div>
    <button type="button"
      class="flex flex-col items-center hover:bg-red-50 transition-colors rounded px-2 py-1 -mx-2 -my-1 min-w-[10rem]"
      class:ring-2={quickFilter === 'overskredet'}
      class:ring-red-400={quickFilter === 'overskredet'}
      on:click={() => { quickFilter = quickFilter === 'overskredet' ? null : 'overskredet'; }}>
      <p class="text-3xl font-bold" style={overskredet > 0 ? 'color:#dc2626;' : 'color:#9ca3af;'}>{overskredet}</p>
      <p class="text-xs uppercase tracking-widest text-gray-400 mt-1.5">Overskredet</p>
    </button>
    <div class="h-10 w-px bg-gray-200"></div>
    <button type="button"
      class="flex flex-col items-center hover:bg-yellow-50 transition-colors rounded px-2 py-1 -mx-2 -my-1 min-w-[10rem]"
      class:ring-2={quickFilter === 'inden30'}
      class:ring-yellow-400={quickFilter === 'inden30'}
      on:click={() => { quickFilter = quickFilter === 'inden30' ? null : 'inden30'; }}>
      <p class="text-3xl font-bold" style={indenFor30Dage > 0 ? 'color:#ca8a04;' : 'color:#9ca3af;'}>{indenFor30Dage}</p>
      <p class="text-xs uppercase tracking-widest text-gray-400 mt-1.5">Inden for 30 dage</p>
    </button>
  </div>


  {#if filteredRevurderinger.length === 0}

    <div class="bg-white border border-gray-300 rounded-lg shadow px-6 py-16 text-center">
      {#if anyFilterActive}
        <div class="w-12 h-12 rounded-full bg-gray-100 flex items-center justify-center mx-auto mb-4">
          <svg class="w-6 h-6 text-gray-400" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
          </svg>
        </div>
        <p class="text-gray-700 font-semibold">Ingen sager matcher de valgte filtre</p>
        <p class="text-sm text-gray-400 mt-1">Fjern alle filtre på én gang ved at trykke <span class="font-medium text-gray-500">Nulstil filtre</span> i øverste højre hjørne.</p>
      {:else}
        <div class="w-12 h-12 rounded-full bg-green-100 flex items-center justify-center mx-auto mb-4">
          <svg class="w-6 h-6 text-green-600" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" d="M5 13l4 4L19 7" />
          </svg>
        </div>
        <p class="text-gray-700 font-semibold">Ingen sager til revurdering</p>
        <p class="text-sm text-gray-400 mt-1">Alle bevillinger er opdaterede.</p>
      {/if}
    </div>

  {:else}

    <div>

      {#each filteredRevurderinger as bev, i}

        {@const color = urgencyColor(bev.revurderingsdato)}
        {@const label = urgencyLabel(bev.revurderingsdato)}
        {@const isExpanded = expandedIds.has(bev.bevilling_id)}
        {@const activeKoerselstyper = [...new Set(aktiveKoerselstyper(bev))]}

        <div class="overflow-hidden transition-colors {isExpanded ? 'border border-gray-300 bg-gray-100 rounded-lg shadow-md my-2' : 'border border-gray-200 bg-white' + (i > 0 ? ' -mt-px' : '')}">

          <div
            class="flex items-center gap-3 px-4 py-3 cursor-pointer hover:bg-gray-50 transition-colors select-none"
            style="border-left: 3px solid {color};"
            on:click={() => toggleExpand(bev.bevilling_id)}
            role="button"
            tabindex="0"
            on:keydown={(e) => e.key === 'Enter' && toggleExpand(bev.bevilling_id)}
          >

            <svg class="w-4 h-4 text-gray-400 shrink-0 transition-transform duration-150 {isExpanded ? 'rotate-90' : ''}"
              fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" d="M9 5l7 7-7 7" />
            </svg>

            <div class="min-w-0 w-64 shrink-0 flex flex-col justify-center">
              <div class="flex items-center gap-2 flex-wrap">
                <a href="/sag/{bev.cpr_elev}" class="font-semibold text-sky-700 hover:underline text-sm whitespace-nowrap" on:click|stopPropagation>
                  {bev.adresseringsnavn ?? "—"}
                </a>
                <div class="flex items-center gap-1">
                  <span class="text-gray-400 text-xs whitespace-nowrap">{formatCpr(bev.cpr_elev)}</span>
                  <button type="button" class="text-gray-300 hover:text-gray-500 transition-colors" title="Kopiér CPR"
                    on:click={(e) => copyCpr(bev.cpr_elev, e)}>
                    {#if copiedCpr === bev.cpr_elev}
                      <svg class="w-3 h-3 text-green-500" fill="none" stroke="currentColor" stroke-width="2.5" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M5 13l4 4L19 7" />
                      </svg>
                    {:else}
                      <svg class="w-3 h-3" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z" />
                      </svg>
                    {/if}
                  </button>
                </div>
              </div>
              {#if bev.skole_navn}
                <span class="lg:hidden text-gray-500 text-[13px] mt-0.5 mb-1 leading-snug">{bev.skole_navn}</span>
              {/if}
              {#if activeKoerselstyper.length > 0}
                <div class="flex items-center gap-1 mt-1 flex-wrap">
                  {#each activeKoerselstyper as type}
                    <span class="px-2 py-0.5 rounded text-[11px] font-medium {getBefordringstypeBadgeClass(type as string)}">{type}</span>
                  {/each}
                </div>
              {/if}
            </div>

            <div class="hidden lg:flex flex-1 items-center min-w-0 overflow-hidden px-2">
              <!-- leading-[26px] på værdierne: rækken er items-center, og en
                   <select> er 26px høj (text-sm 20px + py-0.5 + kant), mens en
                   tekstlinje er 20px. Uden samme højde centreres kolonnerne
                   hver for sig, og etiketterne over dropdownsene kom til at
                   ligge et par pixels højere end de øvrige. -->
              <!-- Skolen står først: PPR læser rækken som navn, skole, klasseart,
                   klassebetegnelse, når de forbereder møder ude på skolerne.
                   Det er elevens indskrevne skole — se skole_navn i viewet. -->
              <div class="flex flex-col min-w-0 min-w-[110px] w-[160px]">
                <span class="text-[10px] font-bold uppercase tracking-wider text-gray-400 leading-none mb-0.5">Skole</span>
                <span class="text-sm text-gray-600 truncate leading-[26px]" title={bev.skole_navn ?? ""}>{bev.skole_navn ?? "—"}</span>
              </div>
              <div class="flex flex-col min-w-0 min-w-[80px] w-[130px]">
                <span class="text-[10px] font-bold uppercase tracking-wider text-gray-400 leading-none mb-0.5">Klasseart</span>
                <span class="text-sm text-gray-600 truncate leading-[26px]">{bev.klasseart ?? "—"}</span>
              </div>
              <!-- Klassebetegnelse (4X, MOB1, 9-10X), ikke klassetrin. De tre er
                   hver sit begreb hos Befordring: klasseart, klassetrin
                   (personligt) og klassebetegnelse. Derfor ingen fallback til
                   klassetrin — en trinværdi under denne etiket er netop den
                   forveksling, etiketten skal fjerne. Klassetrin står i
                   Elevdata, når rækken foldes ud. -->
              <div class="flex flex-col min-w-0 min-w-[80px] w-[110px]">
                <span class="text-[10px] font-bold uppercase tracking-wider text-gray-400 leading-none mb-0.5">Klassebetegnelse</span>
                <span class="text-sm text-gray-600 truncate leading-[26px]">{bev.klassebetegnelse ?? "—"}</span>
              </div>
              <!-- Tildelingen, ikke bevillingens egne sagsbehandlerfelter. De to
                   er fyldt ud på stort set alle rækker fra oprettelsen, og et
                   udfyldt navn læses som "nogen har den her" — hvilket næsten
                   aldrig passer. Disse to er tomme, indtil nogen tager sagen,
                   og tomheden er hele pointen. Se migration 034. -->
              <div class="flex flex-col min-w-0 min-w-[110px] w-[150px] pr-2"
                   role="presentation" on:click|stopPropagation>
                <AnsvarligSelect
                  bevillingId={bev.bevilling_id}
                  valgt={bev.ansvarlig_sagsbehandler_id ?? null}
                  muligheder={sagsbehandlere}
                  felt="sagsbehandler"
                  label="Ansvarlig nu"
                  efterGem={() => { if (bevillingerByCpr[bev.cpr_elev]) loadBevillinger(bev.cpr_elev); }}
                />
              </div>
              <div class="flex flex-col min-w-0 min-w-[110px] w-[150px] pr-2"
                   role="presentation" on:click|stopPropagation>
                <AnsvarligSelect
                  bevillingId={bev.bevilling_id}
                  valgt={bev.ansvarlig_ppr_sagsbehandler_id ?? null}
                  muligheder={pprSagsbehandlere}
                  felt="ppr_sagsbehandler"
                  label="PPR-ansvarlig nu"
                  efterGem={() => { if (bevillingerByCpr[bev.cpr_elev]) loadBevillinger(bev.cpr_elev); }}
                />
              </div>
              <div class="flex flex-col min-w-0 min-w-[90px] w-[110px]">
                <span class="text-[10px] font-bold uppercase tracking-wider text-gray-400 leading-none mb-0.5">Revurderingsdato</span>
                <span class="text-sm text-gray-600 truncate leading-[26px]">{formatDanishDate(bev.revurderingsdato) ?? "—"}</span>
              </div>
              <div class="flex flex-col min-w-0 min-w-[90px] w-[110px]">
                <span class="text-[10px] font-bold uppercase tracking-wider text-gray-400 leading-none mb-0.5">Udløbsdato</span>
                <span class="text-sm text-gray-600 truncate leading-[26px]">{formatDanishDate(bev.seneste_gyldig_til)}</span>
              </div>
              {#if bev.statusbemaerkning}
                <div class="flex flex-col min-w-0 flex-1 pl-2 border-l border-amber-200 ml-2">
                  <span class="text-[10px] font-bold uppercase tracking-wider text-amber-500 leading-none mb-0.5">Årsag</span>
                  <span class="text-sm text-amber-700 truncate leading-[26px]" title={bev.statusbemaerkning}>{bev.statusbemaerkning}</span>
                </div>
              {/if}
            </div>

            <div class="flex items-center gap-2 shrink-0">
              <span class="text-[11px] font-semibold px-2 py-0.5 rounded-full whitespace-nowrap" style="background:{color}18; color:{color};">
                {label}
              </span>
            </div>

            <div class="shrink-0 flex items-center gap-1.5">
              <button type="button" title="PPR vurderet"
                class="flex items-center gap-1.5 border-2 rounded px-3 py-1.5 text-xs font-medium transition-all whitespace-nowrap
                  {bev.revurderet_af_ppr ? 'bg-green-600 border-green-600 text-white shadow-sm' : 'bg-white border-gray-300 text-gray-500 hover:border-green-400 hover:text-green-600'}"
                on:click|stopPropagation={() => openPprConfirm(bev, bev.revurderet_af_ppr)}>
                <div class="w-3.5 h-3.5 rounded border flex items-center justify-center shrink-0
                  {bev.revurderet_af_ppr ? 'bg-white/20 border-white/60' : 'border-gray-300'}">
                  {#if bev.revurderet_af_ppr}
                    <svg class="w-2.5 h-2.5 text-white" fill="none" stroke="currentColor" stroke-width="3" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" d="M5 13l4 4L19 7" />
                    </svg>
                  {/if}
                </div>
                PPR vurderet
              </button>

              <button type="button" title="BR vurderet"
                class="flex items-center gap-1.5 border-2 rounded px-3 py-1.5 text-xs font-medium transition-all whitespace-nowrap
                  {bev.revurderet_af_br ? 'bg-green-600 border-green-600 text-white shadow-sm' : 'bg-white border-gray-300 text-gray-500 hover:border-green-400 hover:text-green-600'}"
                on:click|stopPropagation={() => openBrConfirm(bev, bev.revurderet_af_br)}>
                <div class="w-3.5 h-3.5 rounded border flex items-center justify-center shrink-0
                  {bev.revurderet_af_br ? 'bg-white/20 border-white/60' : 'border-gray-300'}">
                  {#if bev.revurderet_af_br}
                    <svg class="w-2.5 h-2.5 text-white" fill="none" stroke="currentColor" stroke-width="3" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" d="M5 13l4 4L19 7" />
                    </svg>
                  {/if}
                </div>
                BR vurderet
              </button>
            </div>

          </div>


          {#if isExpanded}
            {@const commentsOpen = expandedCommentsBevIds.has(bev.bevilling_id)}
            <div class="border-t border-gray-100" style="border-left: 3px solid {color};">

              {#if bev.statusbemaerkning}
                <div class="px-6 py-3 bg-amber-50 border-b border-amber-200 flex items-start gap-2.5">
                  <svg class="w-4 h-4 text-amber-500 shrink-0 mt-0.5" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M12 9v2m0 4h.01M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z" />
                  </svg>
                  <div>
                    <p class="text-[10px] font-bold uppercase tracking-wider text-amber-600 mb-0.5">Årsag til revurdering</p>
                    <p class="text-sm text-amber-900">{bev.statusbemaerkning}</p>
                  </div>
                </div>
              {/if}

              <div class="bg-gray-100">
                <div class="px-6 py-2.5 flex items-center justify-between gap-3">
                  <div class="flex items-center gap-2">
                    <p class="text-[10px] font-bold uppercase tracking-wider text-gray-500">Elevdata</p>
                    <span class="text-gray-300 text-[10px]">|</span>
                    <a href="/sag/{bev.cpr_elev}" class="flex items-center gap-0.5 text-xs font-medium text-sky-600 hover:text-sky-800 transition-colors">
                      Gå til sag
                      <svg class="w-3 h-3" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M9 5l7 7-7 7" />
                      </svg>
                    </a>
                  </div>
                </div>
                <div class="px-4 pb-3">
                  <div class="bg-white border border-gray-300 rounded-lg shadow overflow-hidden">
                    <div class="px-6 py-5">
                      <!-- Rækken sendes som den er: de tre views staver
                           felterne ens, så der er intet at oversætte. -->
                      <Elevoplysninger titel={null} elev={bev} {skolematrikler} />
                    </div>
                  </div>
                </div>
              </div>

              <div class="border-t border-gray-200 bg-blue-50">
                <div class="px-6 py-2.5 flex items-center gap-3 cursor-pointer select-none transition-colors hover:bg-blue-100 {commentsOpen ? 'border-b border-blue-200' : ''}"
                  role="button" tabindex="0"
                  on:click={() => toggleComments(bev.bevilling_id)}
                  on:keydown={(e) => e.key === 'Enter' && toggleComments(bev.bevilling_id)}>
                  <svg class="w-4 h-4 text-blue-400 shrink-0 transition-transform duration-150 {commentsOpen ? 'rotate-180' : ''}" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7" />
                  </svg>
                  <div class="flex items-center gap-2">
                    <p class="text-[10px] font-bold uppercase tracking-wider text-blue-700">Kommentarer</p>
                    <svg class="w-3.5 h-3.5 text-blue-400 shrink-0" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z" />
                    </svg>
                    <span class="text-blue-300 text-[10px]">|</span>
                    <a href="/sag/{bev.cpr_elev}#sagsforloeb" class="flex items-center gap-0.5 text-xs font-medium text-sky-600 hover:text-sky-800 transition-colors" on:click|stopPropagation>
                      Sagsforløb
                      <svg class="w-3 h-3" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M9 5l7 7-7 7" />
                      </svg>
                    </a>
                  </div>
                </div>

                {#if commentsOpen}
                  <div class="px-6 py-3">
                    {#if loadingAktiviteterCpr.has(bev.cpr_elev)}
                      <p class="text-xs text-gray-400 italic">Henter kommentarer...</p>
                    {:else}
                      {@const comments = (aktiviteterByCpr[bev.cpr_elev] ?? []).filter((a: any) => a.aktivitetstype === 'Kommentar').slice(0, 3)}
                      {#if comments.length > 0}
                        <div class="space-y-2 mb-3">
                          {#each comments as akt}
                            <div class="border-l-4 border-l-blue-400 bg-white rounded-r px-2.5 py-2 shadow-sm">
                              <div class="flex items-center justify-between gap-2 mb-0.5">
                                <span class="text-[11px] font-medium text-gray-700">{akt.udfoert_af ?? "System"}</span>
                                <span class="text-[10px] text-gray-400 whitespace-nowrap">{new Date(akt.oprettet_tidspunkt).toLocaleString("da-DK")}</span>
                              </div>
                              {#if akt.kommentar}
                                <p class="text-xs text-gray-600 whitespace-pre-wrap break-words">{akt.kommentar}</p>
                              {/if}
                            </div>
                          {/each}
                        </div>
                      {/if}
                      <div class="mt-1 flex items-end gap-2">
                        <textarea class="flex-1 border border-gray-300 rounded px-3 py-2 text-sm resize-none focus:border-blue-400 focus:ring-0 bg-white"
                          rows="2" placeholder="Skriv kommentar..." bind:value={inlineComments[bev.bevilling_id]}></textarea>
                        <button type="button"
                          class="px-3 text-xs font-medium bg-blue-600 hover:bg-blue-700 text-white rounded transition-colors disabled:opacity-40 disabled:cursor-not-allowed shrink-0 self-stretch"
                          disabled={savingInlineCommentIds.has(bev.bevilling_id) || !(inlineComments[bev.bevilling_id]?.trim())}
                          on:click={() => saveInlineComment(bev.cpr_elev, bev.bevilling_id)}>
                          {savingInlineCommentIds.has(bev.bevilling_id) ? "Gemmer..." : "Gem kommentar"}
                        </button>
                      </div>
                    {/if}
                  </div>
                {/if}
              </div>

              <div class="border-t-2 border-gray-300 bg-gray-100">
                <div class="px-6 py-2.5 border-b border-gray-300 flex items-center justify-between gap-3 flex-wrap">
                  <p class="text-[10px] font-bold uppercase tracking-wider text-gray-500">Bevillinger</p>
                  <div class="flex items-center gap-2">
                    <button type="button"
                      disabled={!canEdit || !(bevillingerByCpr[bev.cpr_elev]?.length > 0)}
                      class="px-3 py-1.5 text-xs font-medium text-white rounded transition-colors whitespace-nowrap disabled:opacity-40 disabled:cursor-not-allowed"
                      style="background-color: #032A42;"
                      on:click={() => openCreateBevillingModal(bev.cpr_elev, 'kopi', bev.elevklassetrin ?? null)}>
                      + Ny bevilling fra kopi
                    </button>
                    <button type="button"
                      disabled={!canEdit}
                      class="px-3 py-1.5 text-xs font-medium text-white rounded transition-colors whitespace-nowrap disabled:opacity-40 disabled:cursor-not-allowed"
                      style="background-color: #032A42;"
                      on:click={() => openCreateBevillingModal(bev.cpr_elev, 'tom', bev.elevklassetrin ?? null)}>
                      + Ny bevilling fra tom
                    </button>
                    <button type="button"
                      disabled={!canEdit}
                      class="px-3 py-1.5 text-xs font-medium bg-purple-600 hover:bg-purple-700 text-white rounded transition-colors flex items-center gap-1 whitespace-nowrap disabled:opacity-40 disabled:cursor-not-allowed"
                      on:click={() => openCreateLetterModal(bev.cpr_elev)}>
                      <svg class="w-3 h-3" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
                      </svg>
                      + Opret brev
                    </button>
                  </div>
                </div>

                <div class="px-6 py-4">
                  {#if loadingBevillingerCpr.has(bev.cpr_elev)}
                    <p class="text-xs text-gray-400 italic">Henter bevillinger...</p>
                  {:else if bevillingerByCpr[bev.cpr_elev]}
                    <BevillingTable
                      bevillinger={bevillingerByCpr[bev.cpr_elev]}
                      lookupOptions={lookupOptions}
                      parter={parterByCpr[bev.cpr_elev] ?? []}
                      alwaysShowKoerselsraekker={true}
                      onSaveBevilling={async (id, updates) => {
                        const error = await handleSaveBevilling(id, updates);
                        if (!error) await loadBevillinger(bev.cpr_elev);
                        return error;
                      }}
                      onCreateKoerselsraekke={async (id, updates) => {
                        const error = await handleCreateKoerselsraekke(id, updates);
                        if (!error) await loadBevillinger(bev.cpr_elev);
                        return error;
                      }}
                      onSaveKoerselsraekke={async (id, updates) => {
                        const error = await handleSaveKoerselsraekke(id, updates);
                        if (!error) await loadBevillinger(bev.cpr_elev);
                        return error;
                      }}
                      onFinalizeKoerselsraekke={async (id) => {
                        const error = await handleFinalizeKoerselsraekke(id);
                        if (!error) await loadBevillinger(bev.cpr_elev);
                        return error;
                      }}
                    />
                  {:else}
                    <p class="text-xs text-gray-400 italic">Ingen bevillinger fundet.</p>
                  {/if}
                </div>
              </div>

            </div>
          {/if}

        </div>

      {/each}

    </div>

  {/if}

</section>