<script lang="ts">
  import { onMount } from "svelte";
  import { invalidateAll } from "$app/navigation";

  import { backendFetch } from "$lib/client/backendFetch";
  import { primaerBevilling } from "$lib/statusRang";

  import ReadOnlyNotice from "$lib/components/ReadOnlyNotice.svelte";
  import DataTable, { type DataTableColumn } from "$lib/components/DataTable.svelte";
  import BevillingTable from "$lib/components/BevillingTable.svelte";
  import ParterTable from "$lib/components/ParterTable.svelte";
  import CreateBevillingModal from "$lib/components/CreateBevillingModal.svelte";
  import CreateLetterModal from "$lib/components/CreateLetterModal.svelte";
  import { bevillingLabel, bevillingLabelWithStatus } from "$lib/bevillingLabel";
  import { erEgenKommentar } from "$lib/kommentarEjer";
  import Elevoplysninger from "$lib/components/Elevoplysninger.svelte";
  import { aabnSagVindue } from "$lib/client/sagVindue";
  import { lytPaaSagBesked } from "$lib/sagKanal";
  import {
    getStatusBadgeClass,
    formatCpr,
  } from "$lib/tableColumnConfig";

  export let data;

  // can_edit is resolved by the backend from EDIT_ROLES (see GET /me), so the
  // UI cannot drift from what require_edit actually enforces.
  $: canEdit = data.user?.can_edit ?? false;
  // Deleting a comment is governed by authorship, not by a role — see
  // erEgenKommentar and the delete endpoint. Everything else on this page
  // still follows canEdit.
  $: brugerNavn = data.user?.name ?? null;

  // Non-null when the student's measured distance sits within 500 m of the
  // afstandskriterie for their klassetrin — see $lib/afstandskriterie.


  // -----------------------------
  // Page state
  // -----------------------------

  // Genberegning af skole + skoleafstand. Both columns are normally derived by
  // the nightly run, so a student registered today has neither — and a letter
  // cannot be produced without them.
  let genberegnerSkole = false;
  let genberegnBesked: string | null = null;
  let genberegnFejl: string | null = null;

  async function genberegnSkole() {
    genberegnerSkole = true;
    genberegnBesked = null;
    genberegnFejl = null;

    try {
      const response = await backendFetch(
        `/citizen/stamdata/${data.cpr}/genberegn_skole`,
        { method: "POST" }
      );

      if (!response.ok) {
        let message = "Kunne ikke genberegne skole og afstand";

        try {
          const errorData = await response.json();
          message = errorData?.detail?.message ?? errorData?.detail ?? message;
        } catch {
          // Keep the fallback message — an unparseable body is still a failure.
        }

        genberegnFejl = message;
        return;
      }

      // A successful call can still have nothing to measure: no bevilling
      // qualifies, or a coordinate is missing. The backend says which, and
      // that is worth showing rather than leaving the field silently unchanged.
      const resultat = await response.json();
      genberegnBesked = resultat?.besked ?? null;

      await invalidateAll();
    } catch (fejl) {
      genberegnFejl = "Kunne ikke genberegne skole og afstand";
      console.error(fejl);
    } finally {
      genberegnerSkole = false;
    }
  }

  let showCreateLetterModal = false;

  let { stamdata, parents, parter, recipients, bevillinger, lookupOptions, aktiviteter } = data;

  // The aktivitet feed persists only relateret_bevilling_id, so the løbenummer
  // is looked up from the bevillinger already on the page.
  //
  // Built as a reactive map rather than a lookup function called from the
  // template: Svelte derives a template expression's dependencies from the
  // identifiers it can see, so a helper's read of `bevillinger` would not be
  // one, and the badges would keep their first-render labels after a reload.
  $: bevillingLabelById = new Map<number, string>(
    (bevillinger ?? []).map((b: any) => [b.bevilling_id, bevillingLabel(b)])
  );

  // Skolekode -> school name, so the code on this page can be read without
  // knowing all fifty by heart. It matters most on a genbehandling case:
  // the flag says the bevilling's skolekode does not match the student's,
  // and comparing a bare number against a school name is not a comparison
  // anyone can make at a glance.
  //
  // Built from the skolematrikel lookup, whose labels carry the site in
  // parentheses — "Kaløvigskolen (Sanatorievej)". The site is dropped: one
  // skolekode covers every site of a school, so naming one of them here
  // would be wrong for the students at the others.
  //
  // Same reason as the map above for being reactive rather than a helper
  // function: Svelte cannot see a helper's read of lookupOptions, so the
  // name would keep its first-render value after a reload.
  $: skoleNavnByKode = new Map<string, string>(
    (lookupOptions?.skolematrikler ?? [])
      .filter((m: any) => m?.skolekode != null && m?.label)
      .map((m: any) => [
        String(m.skolekode).trim(),
        String(m.label).split("(")[0].trim()
      ])
  );

  $: skolekodeNavn = skoleNavnByKode.get(String(stamdata?.skolekode ?? "").trim());

  const initialHash = window.location.hash.slice(1);
  const validTabs = ["elev", "parter", "sagsforloeb"];
  let activeTab = validTabs.includes(initialHash) ? initialHash : "elev";

  function switchTab(tab: string) {
    activeTab = tab;
    history.replaceState(null, "", `${window.location.pathname}${window.location.search}#${tab}`);
  }

  $: initial = (stamdata?.adresseringsnavn ?? "?").charAt(0).toUpperCase();
  // The warning names the specific parents, so the caseworker does not have to
  // cross-reference the parter table to see who the restriction applies to.
  $: parentsCannotKnowAddress = (parents ?? []).filter(
    (parent: any) => parent.maa_vide_barns_adresse === false
  );
  $: anyParentCannotKnowAddress = parentsCannotKnowAddress.length > 0;
  $: restrictedParentCprList = parentsCannotKnowAddress
    .map((parent: any) => formatCpr(parent.cpr_foraelder))
    .join(", ");

  $: anyPprRevurderet = (bevillinger as any[]).some((b) => b.revurderet_af_ppr);
  $: anyBrRevurderet  = (bevillinger as any[]).some((b) => b.revurderet_af_br);
  $: anyRevurdering   = (bevillinger as any[]).some((b) => b.revurdering);

  // The status of the highest-ranking bevilling — see $lib/statusRang. Was
  // "if any is Aktiv, show Aktiv, otherwise take the first", which meant a
  // student with a Fejlet bevilling and an expired one was marked Udløbet.
  $: displayStatus =
    primaerBevilling(bevillinger as any[])?.status_tekst
      ?? stamdata?.status_tekst
      ?? null;

  // Derive age from the first 6 digits of the CPR (DDMMYY).
  // Century: if YY <= current two-digit year the person was born this century,
  // otherwise last century. Correct for all school-age children.
  function ageFromCpr(cpr: string): number | null {
    if (!cpr || cpr.length < 10) return null;
    const dd  = parseInt(cpr.slice(0, 2), 10);
    const mm  = parseInt(cpr.slice(2, 4), 10);
    const yy  = parseInt(cpr.slice(4, 6), 10);
    const now = new Date();
    const century   = yy <= (now.getFullYear() % 100) ? 2000 : 1900;
    const birthDate = new Date(century + yy, mm - 1, dd);
    let age = now.getFullYear() - birthDate.getFullYear();
    if (
      now.getMonth() < birthDate.getMonth() ||
      (now.getMonth() === birthDate.getMonth() && now.getDate() < birthDate.getDate())
    ) age--;
    return isNaN(age) ? null : age;
  }

  $: studentAge = ageFromCpr(stamdata?.cpr ?? "");

  let showCreateBevillingModal = false;
  let createBevillingMode: 'kopi' | 'tom' = 'kopi';

  // Creating a bevilling happens in its own browser window, so the caseworker
  // can keep the case on screen while filling the form in. The in-page modal
  // stays as the fallback for a browser that refuses to open one.
  function opretBevilling(mode: 'kopi' | 'tom') {
    const sti = `/sag/${data.cpr}/opret-bevilling${mode === 'kopi' ? '?mode=kopi' : ''}`;

    // Named per student and mode, so a second click focuses the window that is
    // already open rather than discarding a half-filled form.
    if (aabnSagVindue(sti, `opret-bevilling-${data.cpr}-${mode}`)) {
      return;
    }

    createBevillingMode = mode;
    showCreateBevillingModal = true;
  }

  function opretBrev() {
    // Narrower than the bevilling window: the letter form is a single column.
    if (aabnSagVindue(`/sag/${data.cpr}/opret-brev`, `opret-brev-${data.cpr}`, { bredde: 660 })) {
      return;
    }

    showCreateLetterModal = true;
  }

  // A bevilling or brev created in that other window leaves this page showing
  // a list without it. Reload when the other window says it saved.
  onMount(() => lytPaaSagBesked(data.cpr, () => invalidateAll()));


  $: if (data) {
    stamdata = data.stamdata;
    parents = data.parents;
    parter = data.parter;
    recipients = data.recipients;
    bevillinger = data.bevillinger;
    lookupOptions = data.lookupOptions;
    aktiviteter = data.aktiviteter;
  }


  // -----------------------------
  // Sagsaktivitet (Sagsforløb tab)
  // -----------------------------

  let nyKommentar = "";
  let savingKommentar = false;
  let kommentarError: string | null = null;

  // Which bevilling the comment belongs to, or "" for a general case note.
  //
  // The genbehandling and revurdering pages have always sent this — there the
  // bevilling is implicit, because the caseworker comments from its card. On
  // this page there is no such context, so it has to be chosen.
  let kommentarBevillingId: string = "";

  async function saveKommentar() {
    if (!nyKommentar.trim()) {
      return;
    }

    savingKommentar = true;
    kommentarError = null;

    try {
      const response = await backendFetch(`/aktivitet/${stamdata.cpr}`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json"
        },
        body: JSON.stringify({
          aktivitetstype: "Kommentar",
          kommentar: nyKommentar,
          udfoert_af: null,
          // null rather than "" — the column is a nullable int, and the feed
          // badge keys off "is it set", not "is it truthy".
          relateret_bevilling_id: kommentarBevillingId
            ? Number(kommentarBevillingId)
            : null,
        })
      });

      if (!response.ok) {
        kommentarError = "Kunne ikke gemme kommentar";
        return;
      }

      nyKommentar = "";
      kommentarBevillingId = "";

      await invalidateAll();
    } finally {
      savingKommentar = false;
    }
  }

  // Comment deletion is permanent — Sagsaktivitet has no aktiv flag, so there
  // is no soft-delete to fall back on and no undo. Hence the two-step confirm
  // rather than a single click, matching how kørselsrækker are deleted.
  let confirmingDeleteAktivitetId: number | null = null;
  let deletingAktivitet = false;
  let deleteAktivitetError: string | null = null;

  async function doDeleteKommentar() {
    if (deletingAktivitet || confirmingDeleteAktivitetId === null) {
      return;
    }

    const aktivitetId = confirmingDeleteAktivitetId;

    deletingAktivitet = true;
    deleteAktivitetError = null;

    try {
      const response = await backendFetch(`/aktivitet/kommentar/${aktivitetId}`, {
        method: "DELETE"
      });

      if (!response.ok) {
        // The backend distinguishes "this row is not a comment" from "it is
        // not yours", and says so in Danish either way — so show its message
        // rather than a generic one. The second should be unreachable from
        // here, since the button only appears on your own comments, but the
        // backend is what decides and a stale page could still get there.
        let message = "Kunne ikke slette kommentaren";

        try {
          const errorData = await response.json();
          message = errorData?.detail?.message ?? errorData?.detail ?? message;
        } catch {
          // Keep the fallback message.
        }

        // Keep the dialog open so the reason is read where it was triggered.
        deleteAktivitetError = message;
        return;
      }

      confirmingDeleteAktivitetId = null;

      await invalidateAll();
    } finally {
      deletingAktivitet = false;
    }
  }

  function getDisplayLabel(aktivitet: any): string {
    const kode: string = aktivitet.type_kode ?? "";
    const type: string = aktivitet.aktivitetstype ?? "";
    if (kode === "status_opdateret" || type.startsWith("Status sat til ")) return "Status opdateret";
    const map: Record<string, string> = {
      ppr_revurderet:         "PPR vurderet",
      br_revurderet:          "BR vurderet",
      ppr_revurderet_fjernet: "PPR vurderet fjernet",
      br_revurderet_fjernet:  "BR vurderet fjernet",
    };
    return map[kode] ?? type;
  }

  function getCategory(aktivitet: any): string {
    return getDisplayLabel(aktivitet);
  }

  function feedStyle(aktivitet: any): { border: string; icon: string; badgeBg: string; badgeText: string; cardBg: string } {
    const kode: string = aktivitet.type_kode ?? "";
    const type: string = aktivitet.aktivitetstype ?? "";
    if (kode === "ppr_revurderet" || kode === "br_revurderet") {
      return { border: "border-l-green-500", icon: "check",    badgeBg: "bg-green-100",  badgeText: "text-green-800",  cardBg: "bg-gray-50" };
    }
    if (kode === "ppr_revurderet_fjernet" || kode === "br_revurderet_fjernet") {
      return { border: "border-l-gray-300",  icon: "xmark",    badgeBg: "bg-gray-100",   badgeText: "text-gray-600",   cardBg: "bg-gray-50" };
    }
    if (kode === "kommentar" || type === "Kommentar") {
      return { border: "border-l-blue-500",  icon: "chat",     badgeBg: "bg-blue-500",   badgeText: "text-white",      cardBg: "bg-blue-50" };
    }
    if (kode === "brev_oprettet" || type === "Brev oprettet" || kode === "brev_afsendt") {
      return { border: "border-l-gray-300",  icon: "envelope", badgeBg: "bg-gray-100",   badgeText: "text-gray-600",   cardBg: "bg-gray-50" };
    }
    if (kode === "status_opdateret" || type.startsWith("Status sat til ")) {
      return { border: "border-l-gray-300",  icon: "status",   badgeBg: "bg-gray-100",   badgeText: "text-gray-600",   cardBg: "bg-gray-50" };
    }
    if (kode === "bevilling_ophoert" || type === "Bevilling sat til Ophørt") {
      return { border: "border-l-gray-500",  icon: "xmark",    badgeBg: "bg-gray-200",   badgeText: "text-gray-700",   cardBg: "bg-gray-50" };
    }
    if (kode === "bevilling_afslag" || type === "Bevilling sat til Afslag") {
      return { border: "border-l-red-500",   icon: "xmark-red", badgeBg: "bg-red-100",   badgeText: "text-red-800",    cardBg: "bg-gray-50" };
    }
    return   { border: "border-l-gray-300",  icon: "gear",     badgeBg: "bg-gray-100",   badgeText: "text-gray-600",   cardBg: "bg-gray-50" };
  }

  // "14.09.2026, 10.05" — the default da-DK toLocaleString appends seconds
  // ("10.05.00"), which is noise in a feed and widens the metadata row for no
  // information. An unparseable value is returned as-is rather than rendered
  // as "Invalid Date".
  function formatAktivitetTidspunkt(value: string | null | undefined): string {
    if (!value) return "";

    const parsed = new Date(value);

    if (Number.isNaN(parsed.getTime())) return String(value);

    return parsed.toLocaleString("da-DK", {
      day: "2-digit",
      month: "2-digit",
      year: "numeric",
      hour: "2-digit",
      minute: "2-digit",
    });
  }

  // Feed filters
  let filterTypes: string[] = [];
  let filterFra = "";
  let filterTil = "";
  let filterUdfoertAf: string[] = [];
  let filterBevillingIds: number[] = [];
  let openDropdown: "type" | "sender" | "bevilling" | null = null;
  let sortAsc = false;

  const feedMinDate = new Date(new Date().getFullYear() - 10, new Date().getMonth(), new Date().getDate()).toISOString().slice(0, 10);
  const feedMaxDate = new Date(new Date().getFullYear() + 10, new Date().getMonth(), new Date().getDate()).toISOString().slice(0, 10);

  $: uniqueCategories = [...new Set<string>((aktiviteter ?? []).map((a: any) => getCategory(a)))].sort((a: string, b: string) => a.localeCompare(b, "da"));
  $: uniqueSenders = [...new Set<string>((aktiviteter ?? []).map((a: any) => a.udfoert_af ?? "").filter(Boolean))].sort((a: string, b: string) => a.localeCompare(b, "da"));
  // Bevillinger referenced by at least one activity, newest first. Built from
  // the feed rather than from `bevillinger` so the dropdown never offers a
  // bevilling that would filter the list down to nothing.
  //
  // Labelled with bevillingLabelById (the same "Bevilling 2" the badge shows),
  // falling back to the system id for a bevilling that has since been deleted
  // but whose activities remain.
  $: bevillingFilterOptions = [
    ...new Set<number>(
      (aktiviteter ?? [])
        .map((a: any) => a.relateret_bevilling_id)
        .filter((id: any): id is number => id !== null && id !== undefined)
    ),
  ]
    .sort((a, b) => b - a)
    .map((id) => ({ id, label: bevillingLabelById.get(id) ?? `Bevilling #${id}` }));

  $: feedHasActiveFilters = filterTypes.length > 0 || filterFra !== "" || filterTil !== "" || filterUdfoertAf.length > 0 || filterBevillingIds.length > 0;

  $: filteredAktiviteter = (() => {
    const list = (aktiviteter ?? []).filter((a: any) => {
      if (filterTypes.length > 0 && !filterTypes.includes(getCategory(a))) return false;
      if (filterFra) {
        const ts = new Date(a.oprettet_tidspunkt);
        const fra = new Date(filterFra);
        if (ts < fra) return false;
      }
      if (filterTil) {
        const ts = new Date(a.oprettet_tidspunkt);
        const til = new Date(filterTil);
        til.setHours(23, 59, 59, 999);
        if (ts > til) return false;
      }
      if (filterUdfoertAf.length > 0 && !filterUdfoertAf.includes(a.udfoert_af ?? "")) return false;
      if (filterBevillingIds.length > 0 && !filterBevillingIds.includes(a.relateret_bevilling_id)) return false;
      return true;
    });
    return sortAsc ? [...list].reverse() : list;
  })();

  function clearFeedFilters() {
    filterTypes = [];
    filterFra = "";
    filterTil = "";
    filterUdfoertAf = [];
    filterBevillingIds = [];
  }




  // -----------------------------
  // Table columns
  // -----------------------------

  const parentColumns: DataTableColumn[] = [
    {
      key: "adresseringsnavn",
      label: "Navn"
    },
    {
      key: "cpr_foraelder",
      label: "CPR-nummer",
      render: (row) => formatCpr(row.cpr_foraelder)
    },
    {
      key: "adresse_tekst",
      label: "Folkeregisteradresse"
    },
    {
      key: "relation",
      label: "Relation"
    },
    {
      key: "navne_adresse_beskyttelse",
      label: "Navne- og adressebeskyttelse",
      render: (row) => row.navne_adresse_beskyttelse ? "Ja" : "Nej"
    },
    {
      key: "maa_vide_barns_adresse",
      label: "Må vide barnets adresse",
      filterable: false,
      render: (row: any) => {
        const val: boolean = row.maa_vide_barns_adresse;
        return `<span class="text-[11px] font-semibold px-2.5 py-0.5 rounded-full border whitespace-nowrap ${val ? 'bg-green-100 border-green-300 text-green-700' : 'bg-red-50 border-red-500 text-red-900'}">${val ? 'Ja' : 'Nej'}</span>`;
      }
    }
  ];




  // -----------------------------
  // Small helpers
  // -----------------------------

  function emptyToNull(value: any) {
    if (value === "") {
      return null;
    }

    return value;
  }


  function numberOrNull(value: any) {
    if (value === "") {
      return null;
    }

    return Number(value);
  }


  // -----------------------------
  // Bevilling handlers
  // -----------------------------

  async function handleSaveBevilling(bevillingId: number, updates: any): Promise<string | null> {
    const { hjaelpemiddel_ids, ...bevillingUpdates } = updates;

    const bevillingResponse = await backendFetch(`/bevilling/${bevillingId}`, {
      method: "PUT",
      headers: {
        "Content-Type": "application/json"
      },
      body: JSON.stringify(bevillingUpdates)
    });

    if (!bevillingResponse.ok) {
      let message = "Kunne ikke gemme bevilling";

      try {
        const errorData = await bevillingResponse.json();

        message =
          errorData?.detail?.message ??
          errorData?.detail ??
          message;
      } catch {
        // Keep fallback message if backend response is not JSON
      }

      return message;
    }

    const hjaelpemidlerResponse = await backendFetch(
      `/bevilling/${bevillingId}/hjaelpemidler`,
      {
        method: "PUT",
        headers: {
          "Content-Type": "application/json"
        },
        body: JSON.stringify({
          hjaelpemiddel_ids: hjaelpemiddel_ids ?? []
        })
      }
    );

    if (!hjaelpemidlerResponse.ok) {
      return "Bevilling blev gemt, men hjælpemidler kunne ikke gemmes";
    }

    await invalidateAll();

    switchTab("elev");

    return null;
  }


  // -----------------------------
  // Kørselsrække handlers
  // -----------------------------

  async function handleCreateKoerselsraekke(bevillingId: number, updates: any): Promise<string | null> {
    const {
      tillaeg_ids,
      dag_ids,
      ...koerselsraekkeData
    } = updates;

    const response = await backendFetch(
      `/bevilling/create_koerselsraekke/${bevillingId}`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json"
        },
        body: JSON.stringify({
          ...koerselsraekkeData,
          tillaeg_ids: tillaeg_ids ?? [],
          dag_ids: dag_ids ?? []
        })
      }
    );

    if (!response.ok) {
      let message = "Kunne ikke oprette kørselsrække";
      try {
        const errorData = await response.json();
        message = errorData?.detail?.message ?? errorData?.detail ?? message;
      } catch { /* keep fallback */ }
      return message;
    }

    await invalidateAll();

    switchTab("elev");

    return null;
  }


  async function handleFinalizeKoerselsraekke(koerselId: number): Promise<string | null> {
    const response = await backendFetch(`/bevilling/koerselsraekke/${koerselId}`, {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ final: true })
    });

    if (!response.ok) {
      let message = "Kunne ikke afslutte kørselsrækken";
      try {
        const err = await response.json();
        message = err?.detail ?? message;
      } catch { /* keep fallback */ }
      return message;
    }

    await invalidateAll();
    return null;
  }


  async function handleSetBevillingLock(
    bevillingId: number,
    final: boolean
  ): Promise<string | null> {
    // Same route the kørselsrække lock uses one level down: the plain update
    // endpoint with only the flag in the body.
    const response = await backendFetch(`/bevilling/${bevillingId}`, {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ final })
    });

    if (!response.ok) {
      let message = final
        ? "Kunne ikke låse bevillingen"
        : "Kunne ikke låse bevillingen op";
      try {
        const err = await response.json();
        message = err?.detail ?? message;
      } catch { /* keep fallback */ }
      return message;
    }

    await invalidateAll();
    return null;
  }


  async function handleSaveKoerselsraekke(koerselId: number, updates: any): Promise<string | null> {
    const {
      tillaeg_ids,
      dag_ids,
      ...koerselsraekkeUpdates
    } = updates;

    const response = await backendFetch(`/bevilling/koerselsraekke/${koerselId}`, {
      method: "PUT",
      headers: {
        "Content-Type": "application/json"
      },
      body: JSON.stringify(koerselsraekkeUpdates)
    });

    if (!response.ok) {
      let message = "Kunne ikke gemme kørselsrække";

      try {
        const errorData = await response.json();

        message =
          errorData?.detail?.message ??
          errorData?.detail ??
          message;
      } catch {
        // Keep fallback message
      }

      return message;
    }

    const tillaegResponse = await backendFetch(
      `/bevilling/koerselsraekke/${koerselId}/tillaeg`,
      {
        method: "PUT",
        headers: {
          "Content-Type": "application/json"
        },
        body: JSON.stringify({
          tillaeg_ids: tillaeg_ids ?? []
        })
      }
    );

    if (!tillaegResponse.ok) {
      return "Kørselsrække blev gemt, men kørselstype tillæg kunne ikke gemmes";
    }

    const dageResponse = await backendFetch(
      `/bevilling/koerselsraekke/${koerselId}/dage`,
      {
        method: "PUT",
        headers: {
          "Content-Type": "application/json"
        },
        body: JSON.stringify({
          dag_ids: dag_ids ?? []
        })
      }
    );

    if (!dageResponse.ok) {
      return "Kørselsrække blev gemt, men dage kunne ikke gemmes";
    }

    await invalidateAll();

    switchTab("elev");

    return null;
  }


  async function handleDeleteBevilling(bevillingId: number): Promise<string | null> {
    const response = await backendFetch(`/bevilling/${bevillingId}`, {
      method: "DELETE"
    });

    if (!response.ok) {
      let message = "Kunne ikke slette bevilling";
      try {
        const errorData = await response.json();
        message = errorData?.detail?.message ?? errorData?.detail ?? message;
      } catch { /* keep fallback */ }
      return message;
    }

    await invalidateAll();
    return null;
  }


  /**
   * Re-measure one bevilling's walking distance to its own school.
   *
   * Returns a Danish message when nothing could be measured, null on success.
   * The backend answers 200 with gaaafstand_km: null in that case rather than
   * an error status — not being able to route between two points is an
   * outcome, not a failed request, and it has already written the null.
   */
  async function handleGenberegnGaaafstand(bevillingId: number): Promise<string | null> {
    const response = await backendFetch(`/bevilling/${bevillingId}/genberegn_gaaafstand`, {
      method: "POST"
    });

    if (!response.ok) {
      let message = "Kunne ikke genberegne gåafstanden";
      try {
        const errorData = await response.json();
        message = errorData?.detail?.message ?? errorData?.detail ?? message;
      } catch { /* keep fallback */ }
      return message;
    }

    const data = await response.json();

    await invalidateAll();

    return data?.besked ?? null;
  }


  async function handleDeleteKoerselsraekke(koerselId: number): Promise<string | null> {
    const response = await backendFetch(`/bevilling/koerselsraekke/${koerselId}`, {
      method: "DELETE"
    });

    if (!response.ok) {
      let message = "Kunne ikke slette kørselsrække";
      try {
        const errorData = await response.json();
        message = errorData?.detail?.message ?? errorData?.detail ?? message;
      } catch { /* keep fallback */ }
      return message;
    }

    await invalidateAll();
    return null;
  }
</script>

<svelte:window
  on:keydown={(e) => {
    if (e.key !== 'Escape') return;
    if (openDropdown) { openDropdown = null; return; }
    if (showCreateBevillingModal) { showCreateBevillingModal = false; }
  }}
  on:click={(e) => {
    if (openDropdown && !(e.target as Element)?.closest?.('.feed-filter-dropdown')) {
      openDropdown = null;
    }
  }}
/>

<section>

  <ReadOnlyNotice />

  <!-- Protection warning -->
  {#if stamdata?.navne_adresse_beskyttelse}
    <div class="mb-4 rounded-lg border-l-4 border-red-500 bg-red-50 p-4 text-red-900">
      <p class="mt-0.5 text-xs">Vær opmærksom på at barnet har navne- og/eller adressebeskyttelse.</p>
    </div>
  {/if}

  <!-- Parent address restriction warning -->
  {#if anyParentCannotKnowAddress}
    <div class="mb-4 rounded-lg border-l-4 border-red-500 bg-red-50 p-4 text-red-900">
      <p class="mt-0.5 text-xs">
        {restrictedParentCprList} har fået frataget deres rettigheder til at se oplysninger om
        {formatCpr(stamdata?.cpr)}, og I må derfor <strong>ikke</strong> på nogen måde videregive
        oplysninger om barnet til forældrene.
      </p>
    </div>
  {/if}


  <!-- Person header card -->
  <div class="bg-white border border-gray-300 rounded-lg shadow px-4 md:px-6 py-5 mb-4 flex flex-col md:flex-row md:items-center gap-4 md:gap-0 justify-between">

    <div class="flex items-center gap-4">
      <!-- Avatar -->
      <div
        class="w-12 h-12 rounded-full flex items-center justify-center text-white font-bold text-xl shrink-0"
        style="background-color: #4a6e8a;"
      >
        {initial}
      </div>

      <div>
        <div class="flex items-center gap-2.5">
          <h1 class="text-xl font-bold text-gray-900">{stamdata?.adresseringsnavn ?? ""}</h1>
          {#if displayStatus}
            <span class="inline-block px-2 py-0.5 rounded text-xs font-medium {getStatusBadgeClass(displayStatus)}">
              {displayStatus}
            </span>
          {/if}
          {#if anyRevurdering}
            <span class="ml-1.5 inline-block px-2 py-0.5 rounded text-xs font-medium bg-yellow-100 text-yellow-700">
              Revurdering
            </span>
          {/if}
        </div>
        <p class="text-sm text-gray-500 mt-0.5">
          <span class="font-mono">{formatCpr(stamdata?.cpr)}</span>
          {#if studentAge !== null}
            <span class="mx-1.5 text-gray-300">·</span>{studentAge} år
          {/if}
        </p>
      </div>
    </div>

    <!-- Tab buttons -->
    <div class="flex gap-2 shrink-0">
      <button
        type="button"
        class="px-4 py-2 text-sm font-medium rounded border transition-colors"
        style={activeTab === "elev"
          ? "background-color: #032A42; color: #ffffff; border-color: #032A42;"
          : "background-color: #ffffff; color: #374151; border-color: #d1d5db;"}
        on:click={() => switchTab("elev")}
      >
        Elev
      </button>

      <button
        type="button"
        class="px-4 py-2 text-sm font-medium rounded border transition-colors"
        style={activeTab === "parter"
          ? "background-color: #032A42; color: #ffffff; border-color: #032A42;"
          : "background-color: #ffffff; color: #374151; border-color: #d1d5db;"}
        on:click={() => switchTab("parter")}
      >
        Parter
      </button>

      <button
        type="button"
        class="px-4 py-2 text-sm font-medium rounded border transition-colors"
        style={activeTab === "sagsforloeb"
          ? "background-color: #032A42; color: #ffffff; border-color: #032A42;"
          : "background-color: #ffffff; color: #374151; border-color: #d1d5db;"}
        on:click={() => switchTab("sagsforloeb")}
      >
        Sagsforløb
      </button>
    </div>

  </div>


  <!-- ELEV TAB -->
  {#if activeTab === "elev"}

    <!-- Elevoplysninger card -->
    <div class="bg-white border border-gray-300 rounded-lg shadow px-4 md:px-6 py-5 mb-4">

      <!-- Definitionen bor i komponenten, som Revurderings- og
           Genbehandlingssiden deler. Genberegn-knappen bliver her: den skriver
           og genindlæser, og det er kun på elevens egen side, resultatet har et
           sted at lande. -->
      <Elevoplysninger elev={stamdata} skolematrikler={lookupOptions?.skolematrikler ?? []}>
        <!-- Resolves Skole and Skoleafstand together: the distance is measured
             to the derived school, so there is nothing to recalculate
             separately. -->
        <button
          slot="genberegn"
          type="button"
          class="text-sky-600 hover:text-sky-800 disabled:opacity-40 disabled:cursor-not-allowed"
          disabled={!canEdit || genberegnerSkole}
          on:click={genberegnSkole}
          title="Genberegn skole og skoleafstand nu"
          aria-label="Genberegn skole og skoleafstand"
        >
          <svg
            class="w-3.5 h-3.5 {genberegnerSkole ? 'animate-spin' : ''}"
            fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"
          >
            <path stroke-linecap="round" stroke-linejoin="round" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
          </svg>
        </button>

        <svelte:fragment slot="genberegn-besked">
          {#if genberegnFejl}
            <p class="mt-1 text-[11px] text-red-700">{genberegnFejl}</p>
          {:else if genberegnBesked}
            <p class="mt-1 text-[11px] text-amber-700">{genberegnBesked}</p>
          {/if}
        </svelte:fragment>
      </Elevoplysninger>
    </div>


  {/if}


  <!-- PARTER TAB -->
  {#if activeTab === "parter"}

    <!-- Oplysninger om forældremyndige -->
    <div class="bg-white border border-gray-300 rounded-lg shadow px-4 md:px-6 py-5 mb-4">
      <div class="flex items-center gap-2 mb-4">
        <div class="w-2.5 h-2.5 rounded-full bg-green-500 flex-shrink-0"></div>
        <h2 class="font-semibold text-gray-800">Oplysninger om forældremyndige</h2>
      </div>
      <DataTable
          data={parents}
          columns={parentColumns}
          filterable={false}
          paginated={false}
        />
    </div>

    <!-- Øvrige parter (ikke-forældremyndige, som må orienteres) -->
    <div class="bg-white border border-gray-300 rounded-lg shadow px-4 md:px-6 py-5 mb-4">
      <div class="flex items-center gap-2 mb-4">
        <div class="w-2.5 h-2.5 rounded-full bg-slate-400 flex-shrink-0"></div>
        <h2 class="font-semibold text-gray-800">Øvrige parter</h2>
      </div>
      <ParterTable cpr={stamdata.cpr} parter={parter} />
    </div>

  {/if}


  <!-- BEVILLINGER (shown in Elev tab) -->
  {#if activeTab === "elev"}

    <!-- Bevillinger section header -->
    <div class="flex items-center justify-between mb-4 mt-2">
      <div class="flex items-center gap-3">
        <h2 class="text-lg font-semibold text-gray-900">Bevillinger</h2>
        <span
          class="inline-flex items-center justify-center min-w-[1.5rem] h-5 px-1.5 rounded-full text-xs font-bold"
          style="background-color: #dbeafe; color: #1d4ed8;"
        >
          {bevillinger?.length ?? 0}
        </span>
      </div>

      <div class="flex gap-2">
      <button
        type="button"
        class="px-4 py-2 text-sm font-medium text-white rounded transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
        style="background-color: #032A42;"
        disabled={!canEdit}
        on:click={() => opretBevilling('kopi')}
      >
        + Ny bevilling fra kopi
      </button>

      <button
        type="button"
        class="px-4 py-2 text-sm font-medium text-white rounded transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
        style="background-color: #032A42;"
        disabled={!canEdit}
        on:click={() => opretBevilling('tom')}
      >
        + Ny bevilling fra tom
      </button>

      <button
        type="button"
        class="px-4 py-2 text-sm font-medium bg-purple-600 hover:bg-purple-700 text-white rounded transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
        disabled={!canEdit}
        on:click={opretBrev}
      >
        + Opret brev
      </button>
      </div>
    </div>


    <!-- Create bevilling modal -->
    {#if showCreateBevillingModal}
      <CreateBevillingModal
        cpr={stamdata.cpr}
        mode={createBevillingMode}
        existingBevillinger={bevillinger ?? []}
        elevklassetrin={stamdata?.elevklassetrin ?? null}
        parter={recipients}
        {lookupOptions}
        on:created={async () => { showCreateBevillingModal = false; await invalidateAll(); }}
        on:cancel={() => { showCreateBevillingModal = false; }}
      />
    {/if}


    <!-- Create letter modal (shared with the revurdering page) -->
    <CreateLetterModal
      bind:open={showCreateLetterModal}
      cpr={stamdata.cpr}
      bevillinger={bevillinger}
      on:created={() => invalidateAll()}
    />


    <BevillingTable
      bevillinger={bevillinger}
      lookupOptions={lookupOptions}
      onSaveBevilling={handleSaveBevilling}
      onSaveKoerselsraekke={handleSaveKoerselsraekke}
      onCreateKoerselsraekke={handleCreateKoerselsraekke}
      onFinalizeKoerselsraekke={handleFinalizeKoerselsraekke}
      parter={recipients}
      onSetBevillingLock={handleSetBevillingLock}
      onDeleteBevilling={handleDeleteBevilling}
      onGenberegnGaaafstand={handleGenberegnGaaafstand}
      onDeleteKoerselsraekke={handleDeleteKoerselsraekke}
    />

    <div class="mt-4">
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

  {/if}


  <!-- SAGSFORLØB TAB -->
  {#if activeTab === "sagsforloeb"}

    <!-- PPR / BR revurderet status banner -->
    {#if anyPprRevurderet || anyBrRevurderet}
      <div class="bg-green-50 border border-green-300 rounded-lg px-4 py-3 mb-4 flex items-center gap-3 flex-wrap">
        <svg class="w-4 h-4 text-green-600 shrink-0" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
        </svg>
        <p class="text-sm font-medium text-green-800">Revurderet:</p>
        {#if anyPprRevurderet}
          <span class="px-2 py-0.5 rounded-full text-xs font-semibold bg-green-100 text-green-800 border border-green-300">✓ PPR revurderet</span>
        {/if}
        {#if anyBrRevurderet}
          <span class="px-2 py-0.5 rounded-full text-xs font-semibold bg-green-100 text-green-800 border border-green-300">✓ BR revurderet</span>
        {/if}
      </div>
    {/if}

    <!-- Ny kommentar -->
    <div class="bg-white border border-gray-300 rounded-lg shadow px-4 md:px-6 py-5 mb-4">
      <h2 class="font-semibold text-gray-800 mb-3">Tilføj kommentar</h2>

      {#if kommentarError}
        <div class="mb-3 px-3 py-2 text-sm text-red-700 bg-red-50 border border-red-200 rounded" role="alert">
          {kommentarError}
        </div>
      {/if}

      <textarea
        bind:value={nyKommentar}
        rows="3"
        class="w-full border border-gray-300 rounded px-3 py-2 text-sm focus:border-blue-400 focus:ring-0 resize-none"
        placeholder="Skriv kommentar..."
      ></textarea>

      <div class="mt-2 flex flex-wrap items-center gap-3">
        <button
          type="button"
          class="px-4 py-2 text-sm font-medium text-white rounded transition-colors disabled:opacity-50 bg-blue-500"
          on:click={saveKommentar}
          disabled={savingKommentar || !nyKommentar.trim()}
        >
          {savingKommentar ? "Gemmer..." : "Gem kommentar"}
        </button>

        <!-- Optional, and deliberately defaulted to none: a general note about
             the case should not be forced onto one bevilling. Every bevilling
             is offered, not only the active one — a comment about an expired
             bevilling is perfectly ordinary. -->
        <label class="flex items-center gap-2 text-sm text-gray-600">
          Knyt til
          <select
            bind:value={kommentarBevillingId}
            class="border border-gray-300 rounded pl-2 pr-8 py-1.5 text-sm bg-white focus:border-blue-400 focus:ring-0"
          >
            <option value="">Ingen bevilling</option>
            {#each bevillinger ?? [] as bev}
              <option value={String(bev.bevilling_id)}>{bevillingLabelWithStatus(bev)}</option>
            {/each}
          </select>
        </label>
      </div>
    </div>

    <!-- Timeline feed -->
    <div class="bg-white border border-gray-300 rounded-lg shadow px-4 md:px-6 py-5 mb-4">

      <!-- Header -->
      <div class="flex items-center gap-3 mb-4">
        <h2 class="font-semibold text-gray-800">Sagsforløb</h2>
        <span class="inline-flex items-center justify-center min-w-[1.5rem] h-5 px-1.5 rounded-full text-xs font-bold bg-blue-100 text-blue-800">
          {filteredAktiviteter.length}{feedHasActiveFilters && (aktiviteter?.length ?? 0) > 0 ? `/${aktiviteter.length}` : ""}
        </span>
        <!-- Sort toggle -->
        <button
          type="button"
          class="ml-auto flex items-center gap-1 text-xs text-gray-500 hover:text-gray-700"
          on:click={() => sortAsc = !sortAsc}
        >
          {#if sortAsc}
            <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" d="M3 4h13M3 8h9m-9 4h6m4 0
l4-4m0 0l4 4m-4-4v12"/></svg>
            Ældste først
          {:else}
            <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" d="M3 4h13M3 8h9m-9 4h9m5-4
v12m0 0l-4-4m4 4l4-4"/></svg>
            Nyeste først
          {/if}
        </button>
      </div>

      <!-- Filters -->
      <div class="flex flex-wrap gap-2 mb-3">

        <!-- Aktivitetstype dropdown -->
        <div class="relative feed-filter-dropdown">
          <button
            type="button"
            class="relative min-w-[160px] border border-gray-300 rounded pl-2 pr-6 py-1 text-xs text-gray-700 bg-white hover:border-gray-400 text-left"
            on:click|stopPropagation={() => openDropdown = openDropdown === "type" ? null : "type"}
          >
            {filterTypes.length > 0 ? filterTypes.join(", ") : "Alle typer"}
            <svg class="absolute right-1.5 top-1/2 -translate-y-1/2 w-3 h-3 text-gray-400 pointer-events-none" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path
stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7"/></svg>
          </button>
          {#if openDropdown === "type"}
            <div class="absolute top-full left-0 mt-1 z-50 bg-white border border-gray-200 rounded shadow-lg min-w-[170px] py-1">
              {#each uniqueCategories as cat}
                <label class="flex items-center gap-2 px-3 py-1.5 hover:bg-gray-50 cursor-pointer text-xs text-gray-700">
                  <input
                    type="checkbox"
                    checked={filterTypes.includes(cat)}
                    on:change={() => {
                      filterTypes = filterTypes.includes(cat)
                        ? filterTypes.filter(t => t !== cat)
                        : [...filterTypes, cat];
                    }}
                    class="rounded border-gray-300 text-blue-500"
                  />
                  {cat}
                </label>
              {/each}
            </div>
          {/if}
        </div>


        <!-- Bevilling dropdown -->
        {#if bevillingFilterOptions.length > 0}
          <div class="relative feed-filter-dropdown">
            <button
              type="button"
              class="relative min-w-[160px] border border-gray-300 rounded pl-2 pr-6 py-1 text-xs text-gray-700 bg-white hover:border-gray-400 text-left"
              on:click|stopPropagation={() => openDropdown = openDropdown === "bevilling" ? null : "bevilling"}
            >
              {filterBevillingIds.length > 0
                ? bevillingFilterOptions.filter((o) => filterBevillingIds.includes(o.id)).map((o) => o.label).join(", ")
                : "Alle bevillinger"}
              <svg class="absolute right-1.5 top-1/2 -translate-y-1/2 w-3 h-3 text-gray-400 pointer-events-none" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7"/></svg>
            </button>
            {#if openDropdown === "bevilling"}
              <div class="absolute top-full left-0 mt-1 z-50 bg-white border border-gray-200 rounded shadow-lg min-w-[190px] py-1">
                {#each bevillingFilterOptions as option}
                  <label class="flex items-center gap-2 px-3 py-1.5 hover:bg-gray-50 cursor-pointer text-xs text-gray-700">
                    <input
                      type="checkbox"
                      checked={filterBevillingIds.includes(option.id)}
                      on:change={() => {
                        filterBevillingIds = filterBevillingIds.includes(option.id)
                          ? filterBevillingIds.filter((id) => id !== option.id)
                          : [...filterBevillingIds, option.id];
                      }}
                      class="rounded border-gray-300 text-blue-500"
                    />
                    {option.label}
                    <span class="ml-auto font-mono text-[10px] text-gray-400">#{option.id}</span>
                  </label>
                {/each}
              </div>
            {/if}
          </div>
        {/if}


        <!-- Udført af dropdown -->
        <div class="relative feed-filter-dropdown">
          <button
            type="button"
            class="relative min-w-[160px] border border-gray-300 rounded pl-2 pr-6 py-1 text-xs text-gray-700 bg-white hover:border-gray-400 text-left"
            on:click|stopPropagation={() => openDropdown = openDropdown === "sender" ? null : "sender"}
          >
            {filterUdfoertAf.length > 0 ? filterUdfoertAf.join(", ") : "Alle afsendere"}
            <svg class="absolute right-1.5 top-1/2 -translate-y-1/2 w-3 h-3 text-gray-400 pointer-events-none" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path
stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7"/></svg>
          </button>
          {#if openDropdown === "sender"}
            <div class="absolute top-full left-0 mt-1 z-50 bg-white border border-gray-200 rounded shadow-lg min-w-[170px] py-1">
              {#each uniqueSenders as sender}
                <label class="flex items-center gap-2 px-3 py-1.5 hover:bg-gray-50 cursor-pointer text-xs text-gray-700">
                  <input
                    type="checkbox"
                    checked={filterUdfoertAf.includes(sender)}
                    on:change={() => {
                      filterUdfoertAf = filterUdfoertAf.includes(sender)
                        ? filterUdfoertAf.filter(s => s !== sender)
                        : [...filterUdfoertAf, sender];
                    }}
                    class="rounded border-gray-300 text-blue-500"
                  />
                  {sender}
                </label>
              {/each}
            </div>
          {/if}
        </div>

        <!-- Periode -->
        <div class="flex items-center gap-1.5">
          <span class="text-xs text-gray-500">Dato fra</span>
          <input
            type="date"
            bind:value={filterFra}
            min={feedMinDate}
            max={feedMaxDate}
            class="border border-gray-300 rounded px-2 py-1 text-xs text-gray-700 focus:border-blue-400 focus:ring-0 bg-white"
          />
          <span class="text-xs text-gray-500">Til</span>
          <input
            type="date"
            bind:value={filterTil}
            min={feedMinDate}
            max={feedMaxDate}
            class="border border-gray-300 rounded px-2 py-1 text-xs text-gray-700 focus:border-blue-400 focus:ring-0 bg-white"
          />
        </div>

      </div>

      <!-- Active filter bar -->
      {#if feedHasActiveFilters}
        <div class="flex items-center justify-between px-3 py-1.5 mb-3 rounded-md bg-sky-50 border border-sky-100 text-xs text-sky-700">
          <span>Aktive filtre · viser {filteredAktiviteter.length} af {aktiviteter?.length ?? 0}</span>
          <button type="button" on:click={clearFeedFilters} class="font-medium hover:underline">Ryd filtre</button>
        </div>
      {/if}

      {#if filteredAktiviteter.length === 0}
        <p class="text-sm text-gray-400 italic">
          {feedHasActiveFilters ? "Ingen aktiviteter matcher de valgte filtre." : "Ingen aktiviteter registreret endnu."}
        </p>
      {:else}
        <div class="space-y-3">
          {#each filteredAktiviteter as aktivitet}
            {@const style = feedStyle(aktivitet)}
            <div class="border-l-4 {style.border} {style.cardBg} border border-gray-100 rounded-r-lg px-4 py-3">
              <div class="flex items-start justify-between gap-2">

                <!-- All information sits left, in two rows: what happened, then
                     when and by whom. The right side carries only the action, so
                     a destructive button is never mixed in among metadata. -->
                <div class="min-w-0">

                <!-- Row 1: icon + type badge + bevilling pill -->
                <div class="flex items-center gap-2 flex-wrap">
                  {#if style.icon === "check"}
                    <svg class="w-3.5 h-3.5 text-green-600 shrink-0" fill="none" stroke="currentColor" stroke-width="2.5" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" d="M5 13l4 4L19 7" />
                    </svg>
                  {:else if style.icon === "xmark"}
                    <svg class="w-3.5 h-3.5 text-gray-500 shrink-0" fill="none" stroke="currentColor" stroke-width="2.5" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
                    </svg>
                  {:else if style.icon === "xmark-red"}
                    <svg class="w-3.5 h-3.5 text-red-600 shrink-0" fill="none" stroke="currentColor" stroke-width="2.5" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
                    </svg>
                  {:else if style.icon === "chat"}
                    <svg class="w-3.5 h-3.5 text-blue-600 shrink-0" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z" />
                    </svg>
                  {:else if style.icon === "envelope"}
                    <svg class="w-3.5 h-3.5 text-gray-500 shrink-0" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" d="M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
                    </svg>
                  {:else if style.icon === "status"}
                    <svg class="w-3.5 h-3.5 text-slate-500 shrink-0" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" d="M7 16V4m0 0L3 8m4-4l4 4M17 8v12m0 0l4-4m-4 4l-4-4" />
                    </svg>
                  {:else}
                    <svg class="w-3.5 h-3.5 text-gray-500 shrink-0" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
                      <path stroke-linecap="round" stroke-linejoin="round" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
                    </svg>
                  {/if}
                  <span class="px-2 py-0.5 rounded text-xs font-medium {style.badgeBg} {style.badgeText}">
                    {getDisplayLabel(aktivitet)}
                  </span>
                  {#if aktivitet.relateret_bevilling_id}
                    <!-- The map holds only the bevillinger on this page, so a soft-deleted one
                         falls through. Saying "(slettet)" rather than just the id makes that
                         read as a fact about the bevilling instead of a failed lookup. -->
                    <span class="text-xs text-gray-500 bg-gray-100 px-1.5 py-0.5 rounded">{bevillingLabelById.get(aktivitet.relateret_bevilling_id) ?? `Bevilling #${aktivitet.relateret_bevilling_id} (slettet)`}</span>
                  {/if}
                </div>

                <!-- Row 2: when + by whom. Muted and smaller so the badge above
                     stays the anchor the eye lands on when scanning the feed. -->
                <div class="mt-1 flex items-center gap-1.5 flex-wrap text-[11px] text-gray-500">
                  <span class="whitespace-nowrap">{formatAktivitetTidspunkt(aktivitet.oprettet_tidspunkt)}</span>
                  {#if aktivitet.udfoert_af}
                    <span class="text-gray-300" aria-hidden="true">·</span>
                    {#if aktivitet.udfoert_af === "System"}
                      <span class="italic">System</span>
                    {:else}
                      <span class="font-medium text-gray-600">{aktivitet.udfoert_af}</span>
                    {/if}
                  {/if}
                </div>

                </div>

                <!-- Right: action only. Only comments can be deleted — system
                     entries are the case history, and the backend refuses them. -->
                <div class="shrink-0">
                  {#if (aktivitet.type_kode === "kommentar" || aktivitet.aktivitetstype === "Kommentar") && erEgenKommentar(aktivitet.udfoert_af, brugerNavn)}
                    <button
                      type="button"
                      title="Slet din kommentar"
                      class="p-1 text-gray-400 hover:text-red-600 transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
                      on:click={() => { confirmingDeleteAktivitetId = aktivitet.aktivitet_id; deleteAktivitetError = null; }}
                    >
                      <svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                      </svg>
                    </button>
                  {/if}
                </div>

              </div>
              {#if aktivitet.kommentar}
                <p
                  class="mt-2 text-sm whitespace-pre-wrap"
                  class:text-blue-900={aktivitet.type_kode === 'kommentar' || aktivitet.aktivitetstype === 'Kommentar'}
                  class:text-gray-800={aktivitet.type_kode !== 'kommentar' && aktivitet.aktivitetstype !== 'Kommentar'}
                >{aktivitet.kommentar}</p>
              {/if}
            </div>
          {/each}
        </div>
      {/if}
    </div>

  {/if}

</section>


<!-- Delete kommentar confirmation modal -->
{#if confirmingDeleteAktivitetId !== null}
  <div
    class="fixed inset-0 z-50 flex items-center justify-center bg-black/40"
    role="presentation"
  >
    <div
      class="w-[420px] bg-white rounded-lg shadow-2xl"
      role="dialog"
      aria-modal="true"
      tabindex="-1"
    >
      <div class="px-6 py-5 border-b border-gray-200">
        <div class="flex items-center gap-3">
          <div class="w-9 h-9 rounded-full bg-red-100 flex items-center justify-center shrink-0">
            <svg class="w-5 h-5 text-red-600" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
            </svg>
          </div>
          <div>
            <h3 class="text-sm font-semibold text-gray-900">Slet kommentar</h3>
            <p class="text-xs text-gray-500 mt-0.5">Kommentar #{confirmingDeleteAktivitetId}</p>
          </div>
        </div>
      </div>
      <div class="px-6 py-4">
        <!-- Unlike bevilling og kørselsrække, this is a real delete: the row is
             removed from the database and cannot be restored. Say so plainly —
             the other dialogs promise the opposite. -->
        <p class="text-sm text-gray-700">
          Er du sikker på, at du vil slette denne kommentar?
          Den slettes permanent fra databasen og kan ikke gendannes.
        </p>
        {#if deleteAktivitetError}
          <p class="mt-3 text-sm text-red-600 bg-red-50 border border-red-200 rounded px-3 py-2">{deleteAktivitetError}</p>
        {/if}
      </div>
      <div class="flex justify-end gap-3 px-6 py-4 border-t border-gray-200 bg-gray-50 rounded-b-lg">
        <button
          type="button"
          class="px-4 py-2 text-sm font-medium border border-gray-300 rounded hover:bg-gray-100 transition-colors"
          on:click={() => confirmingDeleteAktivitetId = null}
        >
          Annullér
        </button>
        <button
          type="button"
          disabled={deletingAktivitet}
          class="px-4 py-2 text-sm font-medium bg-red-600 hover:bg-red-700 text-white rounded transition-colors disabled:opacity-50"
          on:click={doDeleteKommentar}
        >
          {deletingAktivitet ? "Sletter…" : "Slet kommentar"}
        </button>
      </div>
    </div>
  </div>
{/if}
