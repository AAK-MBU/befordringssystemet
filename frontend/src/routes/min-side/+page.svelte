<script lang="ts">
  import { onMount } from 'svelte';
  import { invalidateAll } from "$app/navigation";
  import { backendFetch } from "$lib/client/backendFetch";
  import { formatCpr, getBefordringstypeBadgeClass, getStatusBadgeClass } from "$lib/tableColumnConfig";
  import BevillingTable from "$lib/components/BevillingTable.svelte";
  import CreateBevillingModal from "$lib/components/CreateBevillingModal.svelte";
  import CreateLetterModal from "$lib/components/CreateLetterModal.svelte";
  import ReadOnlyNotice from "$lib/components/ReadOnlyNotice.svelte";
  import Elevoplysninger from "$lib/components/Elevoplysninger.svelte";
  import { sorterBevillinger } from "$lib/bevillingSortering";
  import { statusRang } from "$lib/statusRang";

  export let data;

  $: canEdit = data.user?.can_edit ?? false;

  $: minSide           = data.minSide           ?? [];
  $: koerselstyper       = data.koerselstyper       ?? [];
  $: tidspunkter         = data.tidspunkter         ?? [];
  $: hjemler             = data.hjemler             ?? [];
  $: afgoerelsesbreve    = data.afgoerelsesbreve    ?? [];
  $: koerselstypeTillaeg = data.koerselstypeTillaeg ?? [];
  $: dage                = data.dage                ?? [];
  $: statuser            = data.statuser            ?? [];
  $: skolematrikler      = data.skolematrikler      ?? [];
  $: sagsbehandlere      = data.sagsbehandlere      ?? [];
  $: pprSagsbehandlere   = data.pprSagsbehandlere   ?? [];
  $: hjaelpemidler       = data.hjaelpemidler       ?? [];
  $: ungdomsuddannelser  = data.ungdomsuddannelser  ?? [];
  $: rutetyper           = data.rutetyper           ?? [];

  $: lookupOptions = {
    koerselstyper, tidspunkter, koerselstypeTillaeg, dage,
    statuser, skolematrikler, hjemler, afgoerelsesbreve,
    sagsbehandlere, pprSagsbehandlere, hjaelpemidler, ungdomsuddannelser,
    rutetyper,
  };

  // ── Role toggle ──────────────────────────────────────────────────────────────
  $: hasSagsbehandlerCases = minSide.some((b: any) => b.user_rolle === 'sagsbehandler' || b.user_rolle === 'begge');
  $: hasPprCases           = minSide.some((b: any) => b.user_rolle === 'ppr'            || b.user_rolle === 'begge');
  $: showRolleToggle       = hasSagsbehandlerCases && hasPprCases;

  let aktivRolle: 'sagsbehandler' | 'ppr' = 'sagsbehandler';

  $: rolleFiltreret = !showRolleToggle
    ? minSide
    : minSide.filter((b: any) => b.user_rolle === aktivRolle || b.user_rolle === 'begge');

  // ── Tabs ──────────────────────────────────────────────────────────────────────
  let aktiveTab: 'opdateringer' | 'afventer' | 'alle' = 'opdateringer';
  let inkluderAktiviteter = false;
  let visAfsluttede       = false;

  let dateFrom = (() => { const d = new Date(); d.setDate(d.getDate() - 7); return d.toISOString().split('T')[0]; })();
  let dateTo   = new Date().toISOString().split('T')[0];

  function inDateRange(dateStr: string | null | undefined, from: string, to: string): boolean {
    if (!dateStr) return false;
    if (!from || !to) return true;
    const d = dateStr.slice(0, 10);
    return d >= from && d <= to;
  }

  const AFVENTER_STATUSER   = ['Påbegyndt', 'Fejlet', 'Aktiv + Revurdering', 'Aktiv + Genbehandling'];
  const AFSLUTTEDE_STATUSER = ['Afslag', 'Ophørt', 'Udløbet'];

  function statusLabel(b: any): string {
    if (b.status_tekst === 'Aktiv' && b.revurdering)   return 'Aktiv + Revurdering';
    if (b.status_tekst === 'Aktiv' && b.genbehandling) return 'Aktiv + Genbehandling';
    return b.status_tekst ?? '';
  }

  // Pre-computed tab counts (always reflect current date range + toggles)
  $: antalOpdateringer = rolleFiltreret.filter((b: any) => {
    const harKommentar = inDateRange(b.seneste_kommentar_dato, dateFrom, dateTo);
    const harAktivitet = inkluderAktiviteter && inDateRange(b.seneste_aktivitet_dato, dateFrom, dateTo);
    return harKommentar || harAktivitet;
  }).length;
  $: antalAfventer = rolleFiltreret.filter((b: any) => AFVENTER_STATUSER.includes(statusLabel(b))).length;
  $: antalAlle     = rolleFiltreret.filter((b: any) => !AFSLUTTEDE_STATUSER.includes(statusLabel(b))).length;

  $: tabFiltreret = (() => {
    if (aktiveTab === 'opdateringer') {
      return rolleFiltreret.filter((b: any) => {
        const harKommentar = inDateRange(b.seneste_kommentar_dato, dateFrom, dateTo);
        const harAktivitet = inkluderAktiviteter && inDateRange(b.seneste_aktivitet_dato, dateFrom, dateTo);
        return harKommentar || harAktivitet;
      });
    }
    if (aktiveTab === 'afventer') {
      return rolleFiltreret.filter((b: any) => AFVENTER_STATUSER.includes(statusLabel(b)));
    }
    // alle
    return visAfsluttede
      ? rolleFiltreret
      : rolleFiltreret.filter((b: any) => !AFSLUTTEDE_STATUSER.includes(statusLabel(b)));
  })();

  function sorterTab(items: any[]): any[] {
    if (aktiveTab === 'opdateringer') {
      return [...items].sort((a, b) => {
        const getT = (x: any) => inkluderAktiviteter
          ? Math.max(
              x.seneste_kommentar_dato ? new Date(x.seneste_kommentar_dato).getTime() : 0,
              x.seneste_aktivitet_dato  ? new Date(x.seneste_aktivitet_dato).getTime()  : 0,
            )
          : (x.seneste_kommentar_dato ? new Date(x.seneste_kommentar_dato).getTime() : 0);
        return getT(b) - getT(a);
      });
    }
    if (aktiveTab === 'afventer') {
      // Rangeringen kommer fra $lib/statusRang, ikke fra en liste her. Den
      // her var en fjerde privat statusorden i kodebasen — den sagde
      // tilfældigvis også Fejlet først, men intet holdt den i sync med de
      // øvrige fem, og det er præcis sådan de driver fra hinanden.
      //
      // revurdering/genbehandling er en forfining INDEN FOR Aktiv: begge er
      // rang 1, så de skilles ad bagefter. Revurdering før genbehandling,
      // som den tidligere liste også havde dem.
      const flagRang = (x: any) =>
        x.status_tekst === 'Aktiv' && x.genbehandling ? 1 : 0;

      return [...items].sort((a, b) => {
        const ua = statusRang(a.status_tekst);
        const ub = statusRang(b.status_tekst);
        if (ua !== ub) return ua - ub;

        const fa = flagRang(a);
        const fb = flagRang(b);
        if (fa !== fb) return fa - fb;
        return (a.adresseringsnavn ?? '').localeCompare(b.adresseringsnavn ?? '', 'da');
      });
    }
    // alle — alphabetical
    return [...items].sort((a, b) =>
      (a.adresseringsnavn ?? '').localeCompare(b.adresseringsnavn ?? '', 'da')
    );
  }

  // ── Search + filters ─────────────────────────────────────────────────────────
  let searchQuery              = '';
  let selectedSkole            = '';
  let selectedKoerselstype     = '';
  let selectedAndenSagsbehandler = '';

  // When searching, look across all cases (not just the current tab)
  $: displayBase = searchQuery.trim() ? rolleFiltreret : tabFiltreret;

  $: uniqueSkoler             = [...new Set(tabFiltreret.map((b: any) => b.skole_navn).filter(Boolean))].sort() as string[];
  $: uniqueKoerselstyper      = [...new Set(tabFiltreret.flatMap((b: any) => b.koerselstyper ?? []))].sort() as string[];
  $: andenSagsbehandlerLabel  = aktivRolle === 'sagsbehandler' ? 'PPR sagsbehandler' : 'Sagsbehandler';
  $: uniqueAndenSagsbehandler = aktivRolle === 'sagsbehandler'
    ? [...new Set(tabFiltreret.map((b: any) => b.ppr_sagsbehandler_tekst).filter(Boolean))].sort() as string[]
    : [...new Set(tabFiltreret.map((b: any) => b.sagsbehandler_tekst).filter(Boolean))].sort() as string[];
  
  $: filtered = displayBase.filter((b: any) => {
    if (!matcherSoeg(b, searchQuery)) return false;
    if (selectedSkole && b.skole_navn !== selectedSkole) return false;
    if (selectedKoerselstype && !(b.koerselstyper ?? []).includes(selectedKoerselstype)) return false;
    if (selectedAndenSagsbehandler) {
      const felt = aktivRolle === 'sagsbehandler' ? b.ppr_sagsbehandler_tekst : b.sagsbehandler_tekst;
      if (felt !== selectedAndenSagsbehandler) return false;
    }
    return true;
  });

  $: sorted = sorterTab(filtered);

  $: anyFilterActive = !!(searchQuery.trim() || selectedSkole || selectedKoerselstype || selectedAndenSagsbehandler);

  function nulstilFiltre() {
    searchQuery            = '';
    selectedSkole          = '';
    selectedKoerselstype   = '';
    selectedAndenSagsbehandler = '';
    gemPraeferencer();
  }

  // ── localStorage ──────────────────────────────────────────────────────────────
  function gemPraeferencer() {
    try {
      localStorage.setItem('min_side_prefs', JSON.stringify({
        aktiveTab, inkluderAktiviteter, visAfsluttede,
        selectedSkole, selectedKoerselstype, selectedAndenSagsbehandler,
        aktivRolle, dateFrom, dateTo,
      }));
    } catch { /* quota exceeded or private browsing — safe to ignore */ }
  }

  $: { aktiveTab; inkluderAktiviteter; visAfsluttede; selectedSkole; selectedKoerselstype;
    selectedAndenSagsbehandler; aktivRolle; dateFrom; dateTo;
    if (typeof window !== 'undefined') gemPraeferencer();
  }

  onMount(() => {
    try {
      const saved = JSON.parse(localStorage.getItem('min_side_prefs') ?? '{}');
      if (saved.aktiveTab)                                aktiveTab              = saved.aktiveTab;
      if (typeof saved.inkluderAktiviteter === 'boolean') inkluderAktiviteter    = saved.inkluderAktiviteter;
      if (typeof saved.visAfsluttede === 'boolean')       visAfsluttede          = saved.visAfsluttede;
      if (saved.selectedSkole)                            selectedSkole          = saved.selectedSkole;
      if (saved.selectedKoerselstype)                     selectedKoerselstype   = saved.selectedKoerselstype;
      if (saved.selectedAndenSagsbehandler)               selectedAndenSagsbehandler = saved.selectedAndenSagsbehandler;
      if (saved.aktivRolle && showRolleToggle)            aktivRolle             = saved.aktivRolle;
      if (saved.dateFrom)                                 dateFrom               = saved.dateFrom;
      if (saved.dateTo)                                   dateTo                 = saved.dateTo;
    } catch { /* corrupt storage — ignore */ }
  });

  // ── Activity border color (mirrors Sagsforløb feedStyle) ─────────────────────
  function aktivitetBorderColor(type: string | null | undefined): string {
    if (!type) return 'border-l-gray-300';
    if (type === 'Bevilling sat til Afslag') return 'border-l-red-500';
    if (type === 'Bevilling sat til Ophørt') return 'border-l-gray-500';
    return 'border-l-gray-300';
  }

  function aktivitetBgColor(type: string | null | undefined): string {
    if (type === 'Bevilling sat til Afslag') return 'bg-red-50';
    return 'bg-gray-50';
  }

  function formatDatoTid(dateStr: string | null | undefined): string {
    if (!dateStr) return '';
    return new Date(dateStr).toLocaleString('da-DK', { dateStyle: 'short', timeStyle: 'short' });
  }

  function formatDatoKort(dateStr: string | null | undefined): string {
    if (!dateStr) return '';
    return new Date(dateStr).toLocaleString('da-DK', { day: '2-digit', month: '2-digit', year: '2-digit', hour: '2-digit', minute: '2-digit' });
  }

  // ── Row expand / collapse ─────────────────────────────────────────────────────
  let expandedIds             = new Set<number>();
  let expandedCommentsBevIds  = new Set<number>();

  function toggleExpand(id: number) {
    if (expandedIds.has(id)) {
      expandedIds.delete(id);
      expandedCommentsBevIds.delete(id);
    } else {
      expandedIds.add(id);
      expandedCommentsBevIds.add(id);
      const bev = minSide.find((r: any) => r.bevilling_id === id);
      if (bev) {
        if (!aktiviteterByCpr[bev.cpr_elev]) loadAktiviteter(bev.cpr_elev);
        if (!bevillingerByCpr[bev.cpr_elev]) loadBevillinger(bev.cpr_elev);
        if (!parterByCpr[bev.cpr_elev])      loadParter(bev.cpr_elev);
      }
    }
    expandedIds            = new Set(expandedIds);
    expandedCommentsBevIds = new Set(expandedCommentsBevIds);
  }

  function toggleComments(bevillingId: number) {
    if (expandedCommentsBevIds.has(bevillingId)) expandedCommentsBevIds.delete(bevillingId);
    else                                          expandedCommentsBevIds.add(bevillingId);
    expandedCommentsBevIds = new Set(expandedCommentsBevIds);
  }

  // ── Lazy data loaders ─────────────────────────────────────────────────────────
  let aktiviteterByCpr: Record<string, any[]>  = {};
  let loadingAktiviteterCpr                    = new Set<string>();

  async function loadAktiviteter(cpr: string) {
    loadingAktiviteterCpr.add(cpr);
    loadingAktiviteterCpr = new Set(loadingAktiviteterCpr);
    try {
      const res = await backendFetch(`/aktivitet/${cpr}`);
      if (res.ok) { aktiviteterByCpr[cpr] = await res.json(); aktiviteterByCpr = { ...aktiviteterByCpr }; }
    } finally {
      loadingAktiviteterCpr.delete(cpr);
      loadingAktiviteterCpr = new Set(loadingAktiviteterCpr);
    }
  }

  let bevillingerByCpr: Record<string, any[]> = {};
  let loadingBevillingerCpr                   = new Set<string>();

  async function loadBevillinger(cpr: string) {
    loadingBevillingerCpr.add(cpr);
    loadingBevillingerCpr = new Set(loadingBevillingerCpr);
    try {
      const res = await backendFetch(`/bevilling/get_student_bevillinger/${cpr}`);
      if (!res.ok) return;
      bevillingerByCpr[cpr] = sorterBevillinger(await res.json());
      bevillingerByCpr = { ...bevillingerByCpr };
    } finally {
      loadingBevillingerCpr.delete(cpr);
      loadingBevillingerCpr = new Set(loadingBevillingerCpr);
    }
  }

  let parterByCpr: Record<string, any[]> = {};

  async function loadParter(cpr: string) {
    const res = await backendFetch(`/part/${cpr}/recipients`);
    if (!res.ok) return;
    parterByCpr[cpr] = await res.json();
    parterByCpr = { ...parterByCpr };
  }

  // ── Inline comments ───────────────────────────────────────────────────────────
  let inlineComments: Record<number, string> = {};
  let savingInlineCommentIds                  = new Set<number>();

  async function saveInlineComment(cpr: string, bevillingId: number) {
    const kommentar = (inlineComments[bevillingId] ?? '').trim();
    if (!kommentar) return;
    savingInlineCommentIds.add(bevillingId);
    savingInlineCommentIds = new Set(savingInlineCommentIds);
    try {
      const res = await backendFetch(`/aktivitet/${cpr}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ aktivitetstype: 'Kommentar', kommentar, udfoert_af: null, relateret_bevilling_id: bevillingId }),
      });
      if (res.ok) {
        inlineComments = { ...inlineComments, [bevillingId]: '' };
        await loadAktiviteter(cpr);
        await invalidateAll();
      }
    } finally {
      savingInlineCommentIds.delete(bevillingId);
      savingInlineCommentIds = new Set(savingInlineCommentIds);
    }
  }

  // ── CPR copy ─────────────────────────────────────────────────────────────────
  let copiedCpr: string | null = null;

  async function copyCpr(cpr: string, e: Event) {
    e.stopPropagation();
    await navigator.clipboard.writeText(cpr.replace(/\D/g, ''));
    copiedCpr = cpr;
    setTimeout(() => { copiedCpr = null; }, 1500);
  }

  // ── Search ────────────────────────────────────────────────────────────────────
  function matcherSoeg(b: any, q: string): boolean {
    if (!q.trim()) return true;
    const norm = q.trim().toLowerCase();

    if (norm.startsWith('#')) {
      const bidQuery  = norm.slice(1);
      const exactMode = q.trimStart().endsWith(' ');
      const bid       = String(b.bevilling_id ?? '');
      return exactMode ? bid === bidQuery : bid.startsWith(bidQuery);
    }

    const navn       = (b.adresseringsnavn ?? '').toLowerCase();
    const normDigits = norm.replace(/\D/g, '');
    const cpr        = (b.cpr_elev ?? '').replace(/\D/g, '');
    return navn.includes(norm) || (normDigits.length > 0 && cpr.includes(normDigits));
  }

  // ── Bevilling save handlers ───────────────────────────────────────────────────
  async function handleSaveBevilling(bevillingId: number, updates: any): Promise<string | null> {
    const { hjaelpemiddel_ids, ...bevillingUpdates } = updates;
    const res = await backendFetch(`/bevilling/${bevillingId}`, {
      method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(bevillingUpdates),
    });
    if (!res.ok) {
      let message = 'Kunne ikke gemme bevilling';
      try { const err = await res.json(); message = err?.detail?.message ?? err?.detail ?? message; } catch { /* keep fallback */ }
      return message;
    }
    await backendFetch(`/bevilling/${bevillingId}/hjaelpemidler`, {
      method: 'PUT', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ hjaelpemiddel_ids: hjaelpemiddel_ids ?? [] }),
    });
    await invalidateAll();
    return null;
  }

  async function handleSaveKoerselsraekke(koerselId: number, updates: any): Promise<string | null> {
    const { tillaeg_ids, dag_ids, ...rest } = updates;
    const r1 = await backendFetch(`/bevilling/koerselsraekke/${koerselId}`, {
      method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(rest),
    });
    if (!r1.ok) {
      let message = 'Kunne ikke gemme kørselsrække';
      try { const err = await r1.json(); message = err?.detail?.message ?? err?.detail ?? message; } catch { /* keep fallback */ }
      return message;
    }
    const r2 = await backendFetch(`/bevilling/koerselsraekke/${koerselId}/tillaeg`, {
      method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ tillaeg_ids: tillaeg_ids ?? [] }),
    });
    if (!r2.ok) return 'Kørselsrække gemt, men tillæg kunne ikke gemmes';
    const r3 = await backendFetch(`/bevilling/koerselsraekke/${koerselId}/dage`, {
      method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ dag_ids: dag_ids ?? [] }),
    });
    if (!r3.ok) return 'Kørselsrække gemt, men dage kunne ikke gemmes';
    await invalidateAll();
    return null;
  }

  async function handleCreateKoerselsraekke(bevillingId: number, updates: any): Promise<string | null> {
    const res = await backendFetch(`/bevilling/create_koerselsraekke/${bevillingId}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(updates),
    });
    if (!res.ok) {
      let message = 'Kunne ikke oprette kørselsrække';
      try { const err = await res.json(); message = err?.detail?.message ?? err?.detail ?? message; } catch { /* keep fallback */ }
      return message;
    }
    await invalidateAll();
    return null;
  }

  async function handleFinalizeKoerselsraekke(koerselId: number): Promise<string | null> {
    const res = await backendFetch(`/bevilling/koerselsraekke/${koerselId}`, {
      method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ final: true }),
    });
    if (!res.ok) {
      let message = 'Kunne ikke afslutte kørselsrækken';
      try { const err = await res.json(); message = err?.detail ?? message; } catch { /* keep fallback */ }
      return message;
    }
    await invalidateAll();
    return null;
  }

  // ── Modals ────────────────────────────────────────────────────────────────────
  let showCreateBevillingModal    = false;
  let bevillingModalCpr           = '';
  let bevillingModalElevklassetrin: string | null = null;
  let createBevillingModalMode: 'kopi' | 'tom' | null = null;

  function openCreateBevillingModal(cpr: string, mode: 'kopi' | 'tom', elevklassetrin: string | null = null) {
    bevillingModalCpr            = cpr;
    bevillingModalElevklassetrin = elevklassetrin;
    createBevillingModalMode     = mode;
    showCreateBevillingModal     = true;
  }

  let showCreateLetterModal = false;
  let letterModalCpr        = '';

  function openCreateLetterModal(cpr: string) {
    letterModalCpr        = cpr;
    showCreateLetterModal = true;
  }
</script>


<svelte:window on:keydown={(e) => {
  if (e.key !== 'Escape') return;
  if (showCreateBevillingModal) { showCreateBevillingModal = false; }
}} />


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

<CreateLetterModal
  bind:open={showCreateLetterModal}
  cpr={letterModalCpr}
  bevillinger={bevillingerByCpr[letterModalCpr] ?? []}
  on:created={async (e) => { await loadAktiviteter(e.detail.cpr); await invalidateAll(); }}
/>


<section>

  <ReadOnlyNotice />

  <!-- Page header + filter bar -->
  <div class="flex items-center justify-between mb-5 flex-wrap gap-3">
    <div>
      <h1 class="text-2xl font-bold text-gray-900">Min side</h1>
      <p class="text-sm text-gray-500 mt-0.5">Dine tildelte bevillinger — {rolleFiltreret.length} i alt</p>
    </div>
    
    <div class="flex items-center gap-4 flex-wrap"></div>

    <!-- Search -->
    <div class="relative">
      <svg class="absolute left-2.5 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-gray-400 pointer-events-none"
        fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
      </svg>
      <input type="text" placeholder="Navn, CPR eller #ID…"
        class="pl-8 pr-3 py-1 border border-gray-300 rounded text-xs text-gray-700 focus:border-violet-400 focus:ring-0 bg-white w-52"
        bind:value={searchQuery} />
    </div>

    {#if uniqueSkoler.length > 0}
      <select class="min-w-[160px] border border-gray-300 rounded pl-2 pr-6 py-1 text-xs text-gray-700 focus:border-violet-400 focus:ring-0 bg-white"
        bind:value={selectedSkole}>
        <option value="">Alle skoler</option>
        {#each uniqueSkoler as skole}
          {@const count = tabFiltreret.filter((b: any) => b.skole_navn === skole).length}
          <option value={skole}>{skole} ({count})</option>
        {/each}
      </select>
    {/if}

    {#if uniqueAndenSagsbehandler.length > 0}
      <select class="min-w-[160px] border border-gray-300 rounded pl-2 pr-6 py-1 text-xs text-gray-700 focus:border-violet-400 focus:ring-0 bg-white"
        bind:value={selectedAndenSagsbehandler}>
        <option value="">Alle {andenSagsbehandlerLabel.toLowerCase()}e</option>
        {#each uniqueAndenSagsbehandler as sb}
          {@const count = tabFiltreret.filter((b: any) =>
            (aktivRolle === 'sagsbehandler' ? b.ppr_sagsbehandler_tekst : b.sagsbehandler_tekst) === sb
          ).length}
          <option value={sb}>{sb} ({count})</option>
        {/each}
      </select>
    {/if}

    {#if uniqueKoerselstyper.length > 0}
      <select class="min-w-[160px] border border-gray-300 rounded pl-2 pr-6 py-1 text-xs text-gray-700 focus:border-violet-400 focus:ring-0 bg-white"
        bind:value={selectedKoerselstype}>
        <option value="">Alle kørselstyper</option>
        {#each uniqueKoerselstyper as type}
          {@const count = tabFiltreret.filter((b: any) => (b.koerselstyper ?? []).includes(type)).length}
          <option value={type}>{type} ({count})</option>
        {/each}
      </select>
    {/if}

    <!-- Date range -->
    <div class="flex items-center gap-1.5">
      <span class="text-xs text-gray-500 whitespace-nowrap">Periode:</span>
      <input type="date"
        class="border border-gray-300 rounded px-2 py-1 text-xs text-gray-700 focus:border-violet-400 focus:ring-0 bg-white"
        bind:value={dateFrom} />
      <span class="text-xs text-gray-400">–</span>
      <input type="date"
        class="border border-gray-300 rounded px-2 py-1 text-xs text-gray-700 focus:border-violet-400 focus:ring-0 bg-white"
        bind:value={dateTo} />
      <button type="button"
        class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full bg-gray-100 text-gray-500 hover:bg-gray-200 text-xs transition-colors whitespace-nowrap"
        on:click={() => {
          dateFrom = (() => { const d = new Date(); d.setDate(d.getDate() - 7); return d.toISOString().split('T')[0]; })();
          dateTo   = new Date().toISOString().split('T')[0];
        }}>
        <svg class="w-3 h-3 shrink-0" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
          <circle cx="12" cy="12" r="10" />
          <path stroke-linecap="round" stroke-linejoin="round" d="M12 6v6l4 2" />
        </svg>
        Seneste 7 dage
      </button>
    </div>

    {#if anyFilterActive}
      <button type="button"
        class="text-xs font-medium text-gray-500 hover:text-red-600 flex items-center gap-1 transition-colors whitespace-nowrap"
        on:click={nulstilFiltre}>
        <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
        </svg>
        Nulstil filtre
      </button>
    {/if}

    <span class="text-sm font-bold text-gray-500 whitespace-nowrap">
      {sorted.length}{anyFilterActive || searchQuery.trim() ? ` / ${tabFiltreret.length}` : ''} sager
    </span>

    </div>


  <!-- Tab bar + Inkl. sagsaktiviteter + role toggle -->
  <div class="border-b border-gray-200">
    <div class="flex items-center">

      <nav class="flex -mb-px">
        <button type="button"
          class="px-5 py-3 text-sm font-medium border-b-2 transition-colors flex items-center gap-2
            {aktiveTab === 'opdateringer'
              ? 'border-violet-500 text-violet-700'
              : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'}"
          on:click={() => aktiveTab = 'opdateringer'}>
          Opdateringer
          <span class="px-1.5 py-0.5 rounded-full text-[10px] font-semibold tabular-nums
            {aktiveTab === 'opdateringer' ? 'bg-violet-100 text-violet-700' : 'bg-gray-100 text-gray-500'}">
            {antalOpdateringer}
          </span>
        </button>

        <button type="button"
          class="px-5 py-3 text-sm font-medium border-b-2 transition-colors flex items-center gap-2
            {aktiveTab === 'afventer'
              ? 'border-amber-500 text-amber-700'
              : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'}"
          on:click={() => aktiveTab = 'afventer'}>
          Afventer
          <span class="px-1.5 py-0.5 rounded-full text-[10px] font-semibold tabular-nums
            {aktiveTab === 'afventer' ? 'bg-amber-100 text-amber-700' : 'bg-gray-100 text-gray-500'}">
            {antalAfventer}
          </span>
        </button>

        <button type="button"
          class="px-5 py-3 text-sm font-medium border-b-2 transition-colors flex items-center gap-2
            {aktiveTab === 'alle'
              ? 'border-gray-600 text-gray-800'
              : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'}"
          on:click={() => aktiveTab = 'alle'}>
          Alle sager
          <span class="px-1.5 py-0.5 rounded-full text-[10px] font-semibold tabular-nums
            {aktiveTab === 'alle' ? 'bg-gray-200 text-gray-700' : 'bg-gray-100 text-gray-500'}">
            {antalAlle}
          </span>
        </button>
      </nav>

      <!-- Inkl. sagsaktiviteter — always visible, right after tabs -->  
      <button type="button"
        class="ml-3 mb-px inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-medium border transition-colors
          {inkluderAktiviteter
            ? 'bg-violet-100 border-violet-300 text-violet-700'
            : 'bg-white border-gray-300 text-gray-500 hover:border-gray-400'}"
        on:click={() => inkluderAktiviteter = !inkluderAktiviteter}>
        {#if inkluderAktiviteter}
          <svg class="w-3 h-3 shrink-0" fill="none" stroke="currentColor" stroke-width="2.5" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" d="M5 13l4 4L19 7" />
          </svg>
        {/if}
        Inkl. sagsaktiviteter
      </button>

      <div class="flex-1"></div>

      <!-- Role toggle — far right on tab line -->
      {#if showRolleToggle}
        <div class="mb-px flex rounded-lg overflow-hidden border border-gray-300 text-xs font-medium">
          <button type="button"
            class="px-4 py-1.5 transition-colors {aktivRolle === 'sagsbehandler' ? 'text-white' : 'bg-white text-gray-600 hover:bg-gray-50'}"
            style={aktivRolle === 'sagsbehandler' ? 'background:#7c3aed;' : ''}
            on:click={() => { aktivRolle = 'sagsbehandler'; selectedAndenSagsbehandler = ''; }}>
            Sagsbehandler
          </button>
          <button type="button"
            class="px-4 py-1.5 border-l border-gray-300 transition-colors {aktivRolle === 'ppr' ? 'text-white' : 'bg-white text-gray-600 hover:bg-gray-50'}"
            style={aktivRolle === 'ppr' ? 'background:#7c3aed;' : ''}
            on:click={() => { aktivRolle = 'ppr'; selectedAndenSagsbehandler = ''; }}>
            PPR ansvarlig
          </button>
        </div>
      {/if}

    </div>
  </div>


  <!-- Tab description -->
  <div class="py-2 px-1 border-b border-gray-100 mb-4 flex items-center gap-3 flex-wrap">
    {#if aktiveTab === 'opdateringer'}
      <p class="text-xs text-gray-400 italic">Sager med nye kommentarer i den valgte periode, alle typer status. Default periode er seneste uge. Sorteret efter nyeste kommentar (eller sagsaktivitet) først</p>
    {:else if aktiveTab === 'afventer'}
      <p class="text-xs text-gray-400 italic">Sager der afventer handling. Dvs. sager med status Fejlet, Påbegyndt, Revurdering (Aktiv), og Genbehandling (Aktiv). Sorteret efter status</p>
    {:else}
      <p class="text-xs text-gray-400 italic">Alle dine tildelte sager. Afsluttede sager (status: udløbet, ophørt, afslag) er som udgangspunkt skjult i visningen. Alfabetisk sorteret </p>
      <button type="button"
        class="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-medium border transition-colors
          {visAfsluttede
            ? 'bg-gray-200 border-gray-400 text-gray-700'
            : 'bg-white border-gray-300 text-gray-500 hover:border-gray-400'}"
        on:click={() => visAfsluttede = !visAfsluttede}>
        {#if visAfsluttede}
          <svg class="w-3 h-3 shrink-0" fill="none" stroke="currentColor" stroke-width="2.5" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" d="M5 13l4 4L19 7" />
          </svg>
        {/if}
        Vis afsluttede
      </button>
    {/if}

  </div>


  <!-- Empty state -->
  {#if sorted.length === 0}

    <div class="bg-white border border-gray-300 rounded-lg shadow px-6 py-16 text-center">
      {#if aktiveTab === 'opdateringer'}
        <div class="w-12 h-12 rounded-full bg-violet-100 flex items-center justify-center mx-auto mb-4">
          <svg class="w-6 h-6 text-violet-400" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 12.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z" />
          </svg>
        </div>
        <p class="text-gray-700 font-semibold">Ingen opdateringer i perioden</p>
        <p class="text-sm text-gray-400 mt-1">Ingen af dine sager har {inkluderAktiviteter ? 'aktivitet' : 'kommentarer'} inden for den valgte periode.</p>
      {:else if aktiveTab === 'afventer'}
        <div class="w-12 h-12 rounded-full bg-amber-100 flex items-center justify-center mx-auto mb-4">
          <svg class="w-6 h-6 text-amber-500" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
        </div>
        <p class="text-gray-700 font-semibold">Ingen sager afventer handling</p>
        <p class="text-sm text-gray-400 mt-1">Du har ingen sager med status Påbegyndt, Fejlet, Revurdering eller Genbehandling.</p>
      {:else}
        <div class="w-12 h-12 rounded-full bg-gray-100 flex items-center justify-center mx-auto mb-4">
          <svg class="w-6 h-6 text-gray-400" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2" />
          </svg>
        </div>
        {#if anyFilterActive}
          <p class="text-gray-700 font-semibold">Ingen sager matcher filtret</p>
          <p class="text-sm text-gray-400 mt-1">Fjern filtre ved at trykke <span class="font-medium text-gray-500">Nulstil filtre</span>.</p>
        {:else}
          <p class="text-gray-700 font-semibold">Ingen sager fundet</p>
          <p class="text-sm text-gray-400 mt-1">Enten er din e-mail ikke tilknyttet en sagsbehandlerrolle, eller du har ingen aktive sager i øjeblikket.</p>
        {/if}
      {/if}
    </div>


  <!-- Case list -->
  {:else}

    <div>

      {#each sorted as bev, i}

        {@const isExpanded         = expandedIds.has(bev.bevilling_id)}
        {@const commentsOpen       = expandedCommentsBevIds.has(bev.bevilling_id)}
        {@const activeKoerselstyper = bev.koerselstyper ?? []}
        {@const harKommentar       = !!bev.seneste_kommentar}
        {@const antalNye           = bev.kommentar_antal_7_dage ?? 0}
        {@const visAktivitetEntry  = inkluderAktiviteter && !!bev.seneste_aktivitet_type && bev.seneste_aktivitet_type !== 'Kommentar'}
        {@const modpartLabel       = aktivRolle === 'sagsbehandler' ? 'PPR' : 'BR'}
        {@const modpartNavn        = aktivRolle === 'sagsbehandler' ? bev.ppr_sagsbehandler_tekst : bev.sagsbehandler_tekst}

        <div class="overflow-hidden transition-all {isExpanded
          ? 'border border-gray-300 bg-gray-100 rounded-lg shadow-md my-2'
          : 'border border-gray-200 bg-white' + (i > 0 ? ' -mt-px' : '')}">

          <!-- ── Collapsed card ── -->
          <div
            class="flex items-start gap-3 px-4 py-3 cursor-pointer hover:bg-gray-50 transition-colors select-none"
            style="border-left: 3px solid #7c3aed;"
            on:click={() => toggleExpand(bev.bevilling_id)}
            role="button" tabindex="0"
            on:keydown={(e) => e.key === 'Enter' && toggleExpand(bev.bevilling_id)}
          >

            <!-- Chevron -->
            <svg class="w-4 h-4 text-gray-400 shrink-0 mt-1 transition-transform duration-150 {isExpanded ? 'rotate-90' : ''}"
              fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" d="M9 5l7 7-7 7" />
            </svg>

            <!-- Card body: column row + comment section stacked -->
            <div class="flex-1 min-w-0">

              <!-- Column row -->
              <div class="flex items-start gap-0">

                <!-- Name column: name + CPR, then Sagsforløb link -->
                <div class="min-w-0 w-64 shrink-0 flex flex-col justify-start pr-3">
                  <div class="flex items-center gap-2 flex-wrap">
                    <a href="/sag/{bev.cpr_elev}"
                      class="font-semibold text-sky-700 hover:underline text-sm whitespace-nowrap"
                      on:click|stopPropagation>
                      {bev.adresseringsnavn ?? '—'}
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
                            <path stroke-linecap="round" stroke-linejoin="round" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"/>
                          </svg>
                        {/if}
                      </button>
                    </div>
                  </div>
                  <div class="flex items-center gap-1.5 mt-1" on:click|stopPropagation role="presentation">
                    <a href="/sag/{bev.cpr_elev}#sagsforloeb"
                      class="text-[11px] font-medium text-sky-600 hover:text-sky-800 flex items-center gap-0.5 transition-colors">
                      Sagsforløb
                      <svg class="w-3 h-3" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M9 5l7 7-7 7" />
                      </svg>
                    </a>
                    {#if antalNye > 1}
                      <span class="px-1.5 py-0.5 rounded-full text-[10px] font-semibold bg-blue-100 text-blue-700 flex items-center gap-0.5">
                        <svg class="w-2.5 h-2.5" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" d="M8 10h.01M12 10h.01M16 10h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z" />
                        </svg>
                        {antalNye} nye
                      </span>
                    {/if}
                  </div>
                </div>

                <!-- Flex columns: School | Status | Transport | Counterpart -->
                <div class="hidden lg:flex flex-1 items-center min-w-0 overflow-hidden pl-4">

                  <div class="flex flex-col min-w-0 flex-1">
                    <span class="text-[9px] font-bold uppercase tracking-wider text-gray-400 leading-none mb-1">Skole</span>
                    <span class="text-xs text-gray-600 truncate">{bev.skole_navn ?? '—'}</span>
                  </div>

                  <div class="flex flex-col min-w-0 flex-1">
                    <span class="text-[9px] font-bold uppercase tracking-wider text-gray-400 leading-none mb-1">Status</span>
                    <div class="flex items-center gap-1 flex-wrap">
                      <span class="px-1.5 py-0.5 rounded text-[11px] font-medium {getStatusBadgeClass(bev.status_tekst)}">{bev.status_tekst ?? '—'}</span>
                      {#if bev.revurdering}
                        <span class="px-1.5 py-0.5 rounded text-[11px] font-medium bg-orange-100 text-orange-700">Revurdering</span>
                      {/if}
                      {#if bev.genbehandling}
                        <span class="px-1.5 py-0.5 rounded text-[11px] font-medium bg-rose-100 text-rose-700">Genbehandling</span>
                      {/if}
                    </div>
                  </div>

                  <div class="flex flex-col min-w-0 flex-1">
                    <span class="text-[9px] font-bold uppercase tracking-wider text-gray-400 leading-none mb-1">Kørselstype</span>
                    <div class="flex items-center gap-1 flex-wrap">
                      {#if activeKoerselstyper.length > 0}
                        {#each activeKoerselstyper as type}
                          <span class="px-1.5 py-0.5 rounded text-[11px] font-medium {getBefordringstypeBadgeClass(type)}">{type}</span>
                        {/each}
                      {:else}
                        <span class="text-xs text-gray-400">—</span>
                      {/if}
                    </div>
                  </div>

                  <div class="flex flex-col min-w-0 flex-1">
                    <span class="text-[9px] font-bold uppercase tracking-wider text-gray-400 leading-none mb-1">{modpartLabel} sagsbehandler</span>
                    <span class="text-xs text-gray-600 truncate">{modpartNavn ?? '—'}</span>
                  </div>

                </div>

                <!-- Gå til sag -->
                <div class="shrink-0 pl-3" on:click|stopPropagation role="presentation">
                  <a href="/sag/{bev.cpr_elev}"
                    class="text-[11px] font-medium text-sky-600 hover:text-sky-800 whitespace-nowrap flex items-center gap-0.5 transition-colors">
                    Gå til sag
                    <svg class="w-3 h-3" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" d="M9 5l7 7-7 7" />
                    </svg>
                  </a>
                </div>

              </div>

              <!-- Comment / activity section -->
              <div class="mt-2 space-y-1.5" on:click|stopPropagation role="presentation">Z

                {#if harKommentar}
                  <div class="border-l-4 border-l-blue-500 bg-blue-50 rounded-r px-2.5 py-1.5 shadow-sm">
                    <div class="flex items-center gap-2">
                      <span class="text-[11px] font-semibold text-blue-700">Kommentar</span>
                      <span class="text-[10px] tabular-nums text-gray-400 whitespace-nowrap shrink-0">{formatDatoKort(bev.seneste_kommentar_dato)}</span>
                    </div>
                    <p class="text-[11px] text-gray-600 line-clamp-2 leading-snug mt-0.5">
                      <span class="font-semibold text-gray-700">{bev.seneste_kommentar_forfatter ?? 'System'}:</span>
                      {' '}{bev.seneste_kommentar}
                    </p>
                  </div>
                {/if}

                {#if visAktivitetEntry}
                  <div class="border-l-4 {aktivitetBorderColor(bev.seneste_aktivitet_type)} {aktivitetBgColor(bev.seneste_aktivitet_type)} rounded-r px-2.5 py-1.5 shadow-sm">
                    <div class="flex items-center gap-2">
                      <span class="text-[11px] font-medium text-gray-600">{bev.seneste_aktivitet_type}</span>
                      <span class="text-[10px] tabular-nums text-gray-400 whitespace-nowrap shrink-0">{formatDatoKort(bev.seneste_aktivitet_dato)}</span>
                    </div>
                  </div>
                {/if}

                {#if !harKommentar && !visAktivitetEntry}
                  <span class="text-[11px] text-gray-400 italic">Ingen kommentarer</span>
                {/if}

              </div>

            </div>
          </div>


          <!-- ── Expanded section ── -->
          {#if isExpanded}
            <div class="border-t border-gray-100" style="border-left: 3px solid #7c3aed;">

              {#if bev.statusbemaerkning}
                <div class="px-6 py-3 bg-amber-50 border-b border-amber-200 flex items-start gap-2.5">
                  <svg class="w-4 h-4 text-amber-500 shrink-0 mt-0.5" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M12 9v2m0 4h.01M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z" />
                  </svg>
                  <div>
                    <p class="text-[10px] font-bold uppercase tracking-wider text-amber-600 mb-0.5">Årsag til flag</p>
                    <p class="text-sm text-amber-900">{bev.statusbemaerkning}</p>
                  </div>
                </div>
              {/if}

              <div class="bg-gray-100">
                <div class="px-6 py-2.5 flex items-center gap-3">
                  <p class="text-[10px] font-bold uppercase tracking-wider text-gray-500">Elevdata</p>
                  <span class="text-gray-300 text-[10px]">|</span>
                  <a href="/sag/{bev.cpr_elev}" class="flex items-center gap-0.5 text-xs font-medium text-sky-600 hover:text-sky-800 transition-colors">
                    Gå til sag
                    <svg class="w-3 h-3" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" d="M9 5l7 7-7 7" />
                    </svg>
                  </a>
                </div>
                <div class="px-4 pb-3">
                  <div class="bg-white border border-gray-300 rounded-lg shadow overflow-hidden">
                    <div class="px-6 py-5">
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
                  <svg class="w-4 h-4 text-blue-400 shrink-0 transition-transform duration-150 {commentsOpen ? 'rotate-180' : ''}"
                    fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7" />
                  </svg>
                  <div class="flex items-center gap-2">
                    <p class="text-[10px] font-bold uppercase tracking-wider text-blue-700">Kommentarer</p>
                    <svg class="w-3.5 h-3.5 text-blue-400 shrink-0" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 12.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z" />
                    </svg>
                    <span class="text-blue-300 text-[10px]">|</span>
                    <a href="/sag/{bev.cpr_elev}#sagsforloeb"
                      class="flex items-center gap-0.5 text-xs font-medium text-sky-600 hover:text-sky-800 transition-colors"
                      on:click|stopPropagation>
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
                                <span class="text-[11px] font-medium text-gray-700">{akt.udfoert_af ?? 'System'}</span>
                                <span class="text-[10px] tabular-nums text-gray-400 whitespace-nowrap">
                                  {formatDatoKort(akt.oprettet_tidspunkt)}
                                </span>
                              </div>
                              {#if akt.kommentar}
                                <p class="text-xs text-gray-600 whitespace-pre-wrap break-words">{akt.kommentar}</p>
                              {/if}
                            </div>
                          {/each}
                        </div>
                      {/if}
                      <div class="mt-1 flex items-end gap-2">
                        <textarea
                          class="flex-1 border border-gray-300 rounded px-3 py-2 text-sm resize-none focus:border-blue-400 focus:ring-0 bg-white"
                          rows="2" placeholder="Skriv kommentar..."
                          bind:value={inlineComments[bev.bevilling_id]}></textarea>
                        <button type="button"
                          class="px-3 text-xs font-medium bg-blue-600 hover:bg-blue-700 text-white rounded transition-colors disabled:opacity-40 disabled:cursor-not-allowed shrink-0 self-stretch"
                          disabled={savingInlineCommentIds.has(bev.bevilling_id) || !(inlineComments[bev.bevilling_id]?.trim())}
                          on:click={() => saveInlineComment(bev.cpr_elev, bev.bevilling_id)}>
                          {savingInlineCommentIds.has(bev.bevilling_id) ? 'Gemmer...' : 'Gem'}
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
                      {lookupOptions}
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