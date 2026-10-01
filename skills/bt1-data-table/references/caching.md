# Optional: stale-while-revalidate cache

This is an **opt-in upgrade** to the page component. Skip it for a plain table —
the no-cache `EXAMPLE-Page.svelte` is the right default.

## When it earns its place

Add it only when both are true:

- The remote query is **slow** (heavy aggregation, large scans), AND
- Users **revisit the same filters** — reopening the page, navigating back,
  toggling between a few saved filter sets.

For those, SWR makes the table feel instant: cached rows from a previous visit
paint immediately while a fresh fetch runs in the background. For a fast query,
or filters that are different every time, the cache is pure overhead — don't add
it.

## Install

Copy `assets/idb-cache.ts` into the project (e.g. `src/lib/utils/idb-cache.ts`)
and rename `DB_NAME` to something app-specific. Then replace the two lines
`const q = $derived(get_orders(filters))` / `const datos = $derived(q.current ?? EMPTY)`
in the page with the `$effect` block below (the `$effect` owns `datos` here,
so `q.current` is no longer the source of truth).

**Cost of the cache:** `command().updates(q.withOverride(...))` no longer
reaches the table, because the table reads `datos`, not `q.current`. If the
page has mutations (kanban `onMove`, batch actions), add
`let version = $state(0)`, read `version` at the top of the `$effect`, and
bump it after each `await command(...)` so the effect re-fetches. Simpler:
don't combine the cache with kanban.

## The page `$effect`, with caching

```svelte
<script lang="ts">
import { idbGet, idbSet } from '$lib/utils/idb-cache'
// ...other imports

const CACHE_TTL = 60 * 60 * 1000 // 1 hour — tune to how stale is acceptable

let datos = $state<OrdersResult>(EMPTY)
let isStale = $state(false)  // showing cached data while revalidating
let isLoading = $state(true)

// SWR: serve cached rows instantly, then let the network override.
// $effect (not $derived) because this coordinates two async sources with
// cancellation. Note: `datos` is NOT reset at the top — resetting caused a
// flash to an empty table on every filter change even when a valid cache
// existed. Keep the previous rows on screen; IDB (near-instant) or the network
// replaces them. Only clear when IDB misses AND the network hasn't answered.
$effect(() => {
  const params = { ...filters }
  const key = `orders:${JSON.stringify(params)}`

  let cancelled = false
  let networkDone = false

  isLoading = true
  isStale = false

  // (a) Serve stale from IndexedDB if present.
  idbGet<OrdersResult>(key).then(cached => {
    if (cancelled || networkDone) return
    if (cached !== null) {
      datos = cached
      isStale = true
      isLoading = false
    } else {
      // No cache for these filters — clear stale rows from the previous filter
      // so the "Loading…" badge isn't shown over the wrong data.
      datos = EMPTY
    }
  })

  // (b) Revalidate against the server. The network always wins.
  get_orders(params)
    .then(fresh => {
      if (cancelled) return
      networkDone = true
      datos = fresh
      isStale = false
      isLoading = false
      idbSet(key, fresh, CACHE_TTL)
    })
    .catch(() => {
      if (!cancelled && !networkDone) isLoading = false
    })

  return () => {
    cancelled = true
  }
})
</script>
```

## Show the stale state

Give the user an honest signal that they're looking at cached data:

```svelte
{#if isLoading && datos.rows.length === 0}
  <Badge variant="outline" class="animate-pulse">Loading…</Badge>
{:else if isStale}
  <Badge variant="outline" class="text-muted-foreground">From cache · refreshing…</Badge>
{/if}
```

## Why the ordering details matter

- **`networkDone` guard** — if the network beats IndexedDB, the late cache read
  must not overwrite fresher rows. The flag makes the network authoritative.
- **`cancelled` flag** — when filters change mid-flight, the old request's
  resolution is dropped, so a slow stale response can't clobber the new filter.
- **Don't reset `datos` at the top** — resetting flashes an empty table on every
  filter change. Hold the old rows; let IDB or the network swap them in.
- **TTL** — `idbGet` returns `null` past the TTL, so expired entries fall
  straight through to a normal fetch.
