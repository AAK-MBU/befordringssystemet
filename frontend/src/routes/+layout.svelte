<script lang="ts">
  import favicon from '$lib/assets/speedometer.png';
  import "../app.css";
  import { page } from '$app/stores';
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { backendFetch } from '$lib/client/backendFetch';
  import { formatCpr } from '$lib/tableColumnConfig';
  import { sidetitel } from '$lib/sidetitel';

  let { children, data } = $props();

  // Derived from layout data rather than fetched on mount, so invalidateAll()
  // after a save updates the badges without a refresh. See +layout.server.ts.
  const nyeCount = $derived(data.counts?.nye ?? 0);
  const revCount = $derived(data.counts?.revurderinger ?? 0);
  const genbehandlingCount = $derived(data.counts?.genbehandlinger ?? 0);
  const forsendelseCount = $derived(data.counts?.forsendelser ?? 0);
  const minSideCount = $derived(data.counts?.min_side ?? 0);

  const tabs = [
    { href: '/', label: 'Overblik' },
    { href: '/nye-ansoegninger', label: 'Nye ansøgninger' },
    { href: '/revurdering', label: 'Revurdering' },
    { href: '/genbehandling', label: 'Genbehandling' },
    { href: '/forsendelse', label: 'Forsendelse' },
    { href: '/min-side', label: 'Min side' },
    { href: '/links', label: 'Links' },
  ];

  const currentPath = $derived($page.url.pathname);

  // The create forms can be opened as their own browser window, parked on a
  // second screen beside the case. Navigation chrome there would take room
  // from the form and invite someone to navigate the popup off the form they
  // are filling in.
  const erLoesrevetVindue = $derived(/^\/sag\/[^/]+\/opret-/.test(currentPath));

  const pageBg = $derived(
    currentPath.startsWith('/nye-ansoegninger') ? 'bg-blue-50' :
    currentPath.startsWith('/revurdering') ? 'bg-orange-50' :
    currentPath.startsWith('/genbehandling') ? 'bg-rose-50' :
    ''
  );

  function isActive(tab: { href: string }) {
    if (tab.href === '/') return currentPath === '/';
    return currentPath.startsWith(tab.href);
  }

  // --- Dark mode toggle ---
  let isDark = $state(false);

  onMount(() => {
    isDark = localStorage.getItem('darkMode') === 'true';
    document.documentElement.classList.toggle('dark', isDark);
  });

  function toggleDark() {
    isDark = !isDark;
    document.documentElement.classList.toggle('dark', isDark);
    localStorage.setItem('darkMode', String(isDark));
  }

  // --- Signed-in user ---
  let userMenuOpen = $state(false);

  const user = $derived(data.user);
  const displayName = $derived(user?.name || user?.email || user?.sub || 'Ukendt bruger');
  const initials = $derived(
    displayName
      .split(/\s+/)
      .filter(Boolean)
      .slice(0, 2)
      .map((part: string) => part[0]?.toUpperCase() ?? '')
      .join('')
  );

  // --- Global search ---
  let searchQuery = $state('');
  let searchResults = $state<any[]>([]);
  let searchOpen = $state(false);
  let searchLoading = $state(false);
  let searchFocused = $state(false);
  let debounceTimer: ReturnType<typeof setTimeout> | null = null;
  let highlightedIndex = $state(-1);

  function onSearchInput() {
    if (debounceTimer) clearTimeout(debounceTimer);
    highlightedIndex = -1;

    if (searchQuery.trim().length < 2) {
      searchResults = [];
      searchOpen = false;
      searchLoading = false;
      return;
    }

    searchLoading = true;
    debounceTimer = setTimeout(async () => {
      try {
        const res = await backendFetch(`/overview/search?q=${encodeURIComponent(searchQuery.trim())}`);
        if (res.ok) {
          searchResults = await res.json();
          searchOpen = searchResults.length > 0;
        }
      } catch {
        searchResults = [];
        searchOpen = false;
      } finally {
        searchLoading = false;
      }
    }, 280);
  }

  function selectResult(cpr: string) {
    searchQuery = '';
    searchResults = [];
    searchOpen = false;
    searchFocused = false;
    highlightedIndex = -1;
    goto(`/sag/${cpr}`);
  }

  function closeSearch() {
    // Small delay so a click on a result registers before closing
    setTimeout(() => {
      searchOpen = false;
      highlightedIndex = -1;
    }, 150);
  }

  function onSearchKeydown(e: KeyboardEvent) {
    if (e.key === 'Escape') {
      searchOpen = false;
      highlightedIndex = -1;
      (e.currentTarget as HTMLInputElement).blur();
    } else if (e.key === 'ArrowDown') {
      e.preventDefault();
      highlightedIndex = Math.min(highlightedIndex + 1, searchResults.length - 1);
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      highlightedIndex = Math.max(highlightedIndex - 1, -1);
    } else if (e.key === 'Enter' && highlightedIndex >= 0) {
      e.preventDefault();
      selectResult(searchResults[highlightedIndex].cpr_elev);
    } else if (e.key === 'Enter' && searchResults.length === 1) {
      e.preventDefault();
      selectResult(searchResults[0].cpr_elev);
    }
  }
</script>

{#if !erLoesrevetVindue}
<nav style="background-color: #032A42; box-shadow: 0 2px 8px rgba(0,0,0,0.3);" class="px-4 md:px-8">
  <div class="flex items-center flex-wrap" style="min-height: 60px;">

    <div class="flex items-center gap-3 mr-6 md:mr-10 shrink-0 py-3">
      <div class="w-8 h-8 rounded flex items-center justify-center overflow-hidden" style="background-color: #2ab4a0;">
        <svg
          class="w-5 h-5"
          viewBox="0 0 24 24"
          fill="none"
          stroke="#ffffff"
          stroke-width="2"
          stroke-linecap="round"
          stroke-linejoin="round"
          aria-hidden="true"
        >
          <!-- body -->
          <path d="M5 17V6a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2v11" />
          <!-- window band + centre divider -->
          <path d="M5 11h14" />
          <path d="M12 4v7" />
          <!-- chassis + wheels -->
          <path d="M4 17h16" />
          <circle cx="8.5" cy="19" r="1.5" />
          <circle cx="15.5" cy="19" r="1.5" />
        </svg>
      </div>
      <div class="leading-none">
        <p class="font-bold text-sm tracking-widest" style="color: #ffffff;">BEFORDRING</p>
        <p class="text-[10px] tracking-wider mt-0.5" style="color: #7ec8e3;">BØRN OG UNGE</p>
      </div>
    </div>

    <ul class="flex flex-wrap">
      {#each tabs as tab}
        {@const active = isActive(tab)}
        {@const count = tab.href === '/nye-ansoegninger' ? nyeCount : tab.href === '/revurdering' ? revCount : tab.href === '/genbehandling' ? genbehandlingCount : tab.href === '/forsendelse' ? forsendelseCount : tab.href === '/min-side' ? minSideCount : 0}
        <li>
          <a
            href={tab.href}
            class="flex items-center gap-2 px-3 md:px-5 py-4 text-sm font-medium border-b-2 transition-colors"
            style={active
              ? 'color: #ffffff; border-color: #ffffff;'
              : 'color: rgba(255,255,255,0.6); border-color: transparent;'}
          >
            {tab.label}
            {#if count > 0}
              <span
                class="px-1.5 py-0.5 text-[10px] font-bold rounded-full leading-none"
                style="background: #2ab4a0; color: #ffffff;"
              >
                {count}
              </span>
            {/if}
          </a>
        </li>
      {/each}
    </ul>

    <!-- Global search -->
    <div class="ml-auto pl-4 relative">
      <div class="relative">
        <!-- Search icon -->
        <svg
          class="absolute left-2.5 top-1/2 -translate-y-1/2 w-3.5 h-3.5 pointer-events-none"
          style="color: rgba(255,255,255,0.5);"
          fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"
        >
          <circle cx="11" cy="11" r="8"/><path stroke-linecap="round" d="M21 21l-4.35-4.35"/>
        </svg>

        <!-- Spinner (while loading) -->
        {#if searchLoading}
          <svg
            class="absolute right-2.5 top-1/2 -translate-y-1/2 w-3.5 h-3.5 animate-spin"
            style="color: rgba(255,255,255,0.5);"
            fill="none" viewBox="0 0 24 24"
          >
            <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"/>
            <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8H4z"/>
          </svg>
        {/if}

        <input
          type="search"
          placeholder="Søg navn eller CPR…"
          autocomplete="off"
          bind:value={searchQuery}
          oninput={onSearchInput}
          onfocus={() => { searchFocused = true; if (searchResults.length > 0) searchOpen = true; }}
          onblur={closeSearch}
          onkeydown={onSearchKeydown}
          class="w-52 pl-8 pr-3 py-1.5 rounded text-xs transition-all outline-none focus:w-64"
          style="
            background: rgba(255,255,255,0.1);
            border: 1px solid rgba(255,255,255,0.2);
            color: #ffffff;
          "
        />
      </div>

      <!-- Results dropdown -->
      {#if searchOpen && searchResults.length > 0}
        <div
          class="absolute right-0 top-full mt-1.5 w-80 bg-white rounded-lg shadow-2xl border border-gray-200 overflow-hidden z-50"
        >
          {#each searchResults as result, i}
            <!-- svelte-ignore a11y_click_events_have_key_events -->
            <div
              role="option"
              aria-selected={highlightedIndex === i}
              tabindex="-1"
              class="flex items-center justify-between px-4 py-3 cursor-pointer transition-colors border-b border-gray-100 last:border-0
                {highlightedIndex === i ? 'bg-blue-50' : 'hover:bg-gray-50'}"
              onmousedown={(e) => { e.preventDefault(); selectResult(result.cpr_elev); }}
              onmouseenter={() => highlightedIndex = i}
            >
              <div class="min-w-0">
                <p class="text-sm font-semibold text-gray-900 truncate">{result.adresseringsnavn ?? '—'}</p>
                <p class="text-xs text-gray-400 mt-0.5">{formatCpr(result.cpr_elev)}</p>
              </div>
            </div>
          {/each}
        </div>
      {/if}
    </div>

    <!-- Signed-in user -->
    <div class="pl-2 relative">
      <button
        type="button"
        title="Vis loginoplysninger"
        onclick={() => (userMenuOpen = !userMenuOpen)}
        class="flex items-center gap-2 pl-1 pr-2 py-1 rounded-full transition-colors hover:bg-white/10"
      >
        <span
          class="w-7 h-7 shrink-0 rounded-full flex items-center justify-center text-[11px] font-bold"
          style="background-color: #2ab4a0; color: #ffffff;"
        >
          {initials || '?'}
        </span>
        <span class="hidden md:inline text-xs font-medium max-w-32 truncate" style="color: rgba(255,255,255,0.85);">
          {displayName}
        </span>
      </button>

      {#if userMenuOpen}
        <!-- Click-away backdrop -->
        <!-- svelte-ignore a11y_click_events_have_key_events -->
        <!-- svelte-ignore a11y_no_static_element_interactions -->
        <div class="fixed inset-0 z-40" onclick={() => (userMenuOpen = false)}></div>

        <div
          class="absolute right-0 top-full mt-1.5 w-80 bg-white rounded-lg shadow-2xl border border-gray-200 overflow-hidden z-50"
        >
          <div class="px-4 py-3 border-b border-gray-100">
            <p class="text-sm font-semibold text-gray-900 truncate">{displayName}</p>
            <p class="text-xs text-gray-500 truncate">{user?.email ?? 'Ingen e-mail i token'}</p>
          </div>

          <dl class="px-4 py-3 space-y-2 text-xs">
            <div>
              <dt class="text-gray-400">Bruger-id (sub)</dt>
              <dd class="text-gray-800 font-mono break-all">{user?.sub ?? '—'}</dd>
            </div>
            <div>
              <dt class="text-gray-400">Organisation</dt>
              <dd class="text-gray-800">{user?.organisation ?? '—'}</dd>
            </div>
            <div>
              <dt class="text-gray-400">Roller</dt>
              <dd class="text-gray-800">{user?.roles?.length ? user.roles.join(', ') : 'Ingen'}</dd>
            </div>
            <div>
              <dt class="text-gray-400">Grupper</dt>
              <dd class="text-gray-800">{user?.groups?.length ? user.groups.join(', ') : 'Ingen'}</dd>
            </div>
          </dl>

          <a
            href={data.logoutUrl}
            data-sveltekit-reload
            class="block px-4 py-3 text-sm font-medium text-red-600 border-t border-gray-100 hover:bg-gray-50"
          >
            Log ud
          </a>
        </div>
      {/if}
    </div>

    <!-- Dark mode toggle -->
    <div class="pl-2">
      <button
        type="button"
        title={isDark ? 'Skift til lyst tema' : 'Skift til mørkt tema'}
        onclick={toggleDark}
        class="w-8 h-8 flex items-center justify-center rounded-full transition-colors hover:bg-white/10"
        style="color: rgba(255,255,255,0.7);"
      >
        {#if isDark}
          <!-- Sun icon -->
          <svg class="w-4.5 h-4.5" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
            <circle cx="12" cy="12" r="5"/>
            <path stroke-linecap="round" d="M12 2v2M12 20v2M4.22 4.22l1.42 1.42M18.36 18.36l1.42 1.42M2 12h2M20 12h2M4.22 19.78l1.42-1.42M18.36 5.64l1.42-1.42"/>
          </svg>
        {:else}
          <!-- Moon icon -->
          <svg class="w-4.5 h-4.5" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" d="M21 12.79A9 9 0 1111.21 3a7 7 0 009.79 9.79z"/>
          </svg>
        {/if}
      </button>
    </div>

  </div>
</nav>
{/if}

<div
  class={erLoesrevetVindue
    ? 'min-h-screen'
    : `px-4 md:px-8 py-4 md:py-6 min-h-[calc(100vh-60px)] ${pageBg}`}
>
  {@render children()}
</div>

<svelte:head>
  <title>{sidetitel($page.route.id, {
    navn: $page.data.stamdata?.adresseringsnavn,
    cpr: $page.params.cpr,
  })}</title>
  <link rel="icon" href={favicon} />
</svelte:head>
