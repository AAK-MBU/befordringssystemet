<script lang="ts">
  import { invalidateAll } from "$app/navigation";
  import { page } from "$app/stores";

  import { backendFetch } from "$lib/client/backendFetch";

  export let bevillingId: number;
  export let valgt: number | null = null;
  export let muligheder: { id: number; label: string }[] = [];
  /** Rendered above the control, matching the read-only labels it replaces. */
  export let label: string | null = null;

  // Not can_edit. PPR Medarbejder holds "user-read" and may write nothing else
  // on the bevilling, but may set this field — see PPR_ASSIGN_ROLES and
  // require_ppr_assign. Disabling here is a courtesy; the endpoint decides.
  $: canAssign = $page.data.user?.can_act_as_ppr ?? false;

  let fejl: string | null = null;
  let gemmer = false;

  async function gem(event: Event) {
    const target = event.currentTarget as HTMLSelectElement;
    const forrige = valgt;
    const ny = target.value === "" ? null : Number(target.value);

    if (ny === forrige) return;

    fejl = null;
    gemmer = true;

    // Shown immediately so the dropdown does not sit on the old name while the
    // request is in flight; put back below if the write is refused, otherwise
    // the page claims an assignment that does not exist.
    valgt = ny;

    const res = await backendFetch(`/bevilling/${bevillingId}/ppr_sagsbehandler`, {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ ppr_sagsbehandler_id: ny }),
    });

    gemmer = false;

    if (!res.ok) {
      valgt = forrige;

      let besked = "PPR sagsbehandler kunne ikke gemmes";

      try {
        const body = await res.json();
        const detail = body?.detail?.message ?? body?.detail;

        if (typeof detail === "string") besked = detail;
      } catch {
        // Keep the fallback; a non-JSON body has nothing better to offer.
      }

      fejl = besked;
      console.error(`Failed to assign PPR on bevilling ${bevillingId}:`, res.status, besked);

      return;
    }

    await invalidateAll();
  }
</script>

<div class="flex flex-col min-w-0">
  {#if label}
    <span class="text-[9px] font-bold uppercase tracking-wider text-gray-400 leading-none mb-0.5">
      {label}
    </span>
  {/if}

  <select
    value={valgt ?? ""}
    on:change={gem}
    on:click|stopPropagation
    disabled={!canAssign || gemmer}
    title={canAssign ? "" : "Du har ikke rettigheder til at tildele PPR sagsbehandler"}
    class="w-full border border-gray-300 rounded px-1.5 py-0.5 text-xs text-gray-700 bg-white
           focus:border-blue-400 focus:outline-none
           disabled:bg-gray-100 disabled:text-gray-400 disabled:cursor-not-allowed"
  >
    <option value="">— Ingen —</option>
    {#each muligheder as mulighed}
      <option value={mulighed.id}>{mulighed.label}</option>
    {/each}
  </select>

  {#if fejl}
    <span class="text-[10px] text-red-600 mt-0.5">{fejl}</span>
  {/if}
</div>
