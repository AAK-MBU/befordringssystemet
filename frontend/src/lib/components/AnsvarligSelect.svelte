<script lang="ts">
  import { invalidateAll } from "$app/navigation";
  import { page } from "$app/stores";

  import { backendFetch } from "$lib/client/backendFetch";

  /**
   * Who is handling a bevilling's pending revurdering / genbehandling.
   *
   * Not the same question as PprSagsbehandlerSelect, which sets the
   * bevilling's own PPR-sagsbehandler. This one answers "has anybody picked
   * this up", and an empty control is the answer the worklists exist to show —
   * the bevilling's own two name fields are filled on nearly every row from
   * creation, so they could never say it.
   *
   * Writes ONLY this field. The bevilling's own sagsbehandler / PPR-
   * sagsbehandler are left untouched, because the afgørelsesbrev prints its
   * {sagsbehandler} from them — see BevillingService.set_ansvarlig.
   */

  export let bevillingId: number;
  export let valgt: number | null = null;
  export let muligheder: { id: number; label: string }[] = [];
  export let label: string | null = null;

  /** Which side of the assignment this control writes. */
  export let felt: "sagsbehandler" | "ppr_sagsbehandler" = "sagsbehandler";

  /**
   * Run after a successful write.
   *
   * invalidateAll() only re-runs SvelteKit load functions, and the expanded
   * bevillingskort is not one — the worklists fetch it on demand and keep it
   * in a component-local map. Assigning also writes the bevilling's own
   * sagsbehandler_id, so without this the card below goes on showing the
   * previous name until the browser is reloaded.
   */
  export let efterGem: (() => void | Promise<void>) | null = null;

  $: sti =
    felt === "ppr_sagsbehandler"
      ? `/bevilling/${bevillingId}/ansvarlig_ppr_sagsbehandler`
      : `/bevilling/${bevillingId}/ansvarlig_sagsbehandler`;

  // The two sides are governed by different permissions, matching the two
  // endpoints: PPR Medarbejder holds "user-read" and may write nothing else on
  // a bevilling, but shares PPR's own cases out. Disabling here is a courtesy;
  // the endpoint decides.
  $: maaTildele =
    felt === "ppr_sagsbehandler"
      ? ($page.data.user?.can_act_as_ppr ?? false)
      : ($page.data.user?.can_edit ?? false);

  let fejl: string | null = null;
  let gemmer = false;

  async function gem(event: Event) {
    const target = event.currentTarget as HTMLSelectElement;
    const forrige = valgt;
    const ny = target.value === "" ? null : Number(target.value);

    if (ny === forrige) return;

    fejl = null;
    gemmer = true;

    // Shown immediately so the control does not sit on the old name while the
    // request is in flight; put back below if the write is refused, otherwise
    // the page claims an assignment that does not exist.
    valgt = ny;

    const res = await backendFetch(sti, {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ tildelt_id: ny }),
    });

    gemmer = false;

    if (!res.ok) {
      valgt = forrige;

      let besked = "Tildelingen kunne ikke gemmes";

      try {
        const body = await res.json();
        const detail = body?.detail?.message ?? body?.detail;

        if (typeof detail === "string") besked = detail;
      } catch {
        // Keep the fallback; a non-JSON body has nothing better to offer.
      }

      fejl = besked;
      console.error(`Failed to assign ${felt} on bevilling ${bevillingId}:`, res.status, besked);

      return;
    }

    await invalidateAll();
    await efterGem?.();
  }
</script>

<div class="flex flex-col min-w-0">
  {#if label}
    <span class="text-[10px] font-bold uppercase tracking-wider text-gray-400 leading-none mb-0.5">
      {label}
    </span>
  {/if}

  <select
    value={valgt ?? ""}
    on:change={gem}
    on:click|stopPropagation
    disabled={!maaTildele || gemmer}
    title={maaTildele ? "" : "Du har ikke rettigheder til at tildele denne sag"}
    class="w-full border rounded px-1.5 py-0.5 text-sm bg-white
           focus:border-blue-400 focus:outline-none
           disabled:bg-gray-100 disabled:text-gray-400 disabled:cursor-not-allowed
           {valgt == null ? 'border-amber-300 text-gray-400' : 'border-gray-300 text-gray-700'}"
  >
    <option value="">— Ikke tildelt —</option>
    {#each muligheder as mulighed}
      <option value={mulighed.id}>{mulighed.label}</option>
    {/each}
  </select>

  {#if fejl}
    <span class="text-[10px] text-red-600 mt-0.5">{fejl}</span>
  {/if}
</div>
