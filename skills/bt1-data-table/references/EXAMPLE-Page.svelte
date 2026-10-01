<!--
  EXAMPLE-Page.svelte — the bt1-data-table page component (no-cache baseline).

  Copy this into <feature>/ui/<Feature>Page.svelte. It owns: resolving filters,
  calling the remote query, loading/error/truncated states, handing rows to the
  table, and the mutations the views need (kanban `onMove`). To add the
  stale-while-revalidate cache instead, follow references/caching.md.

  Data flow: `get_orders(filters)` returns a RemoteQuery. Reading `.current`
  in a `$derived` is reactive — when `filters` changes SvelteKit issues the new
  request and `.current` follows; a slow old response can never overwrite a new
  one because each set of args is its own query. `.loading`/`.error` give the
  UI states, and `.refresh()` / `command().updates(...)` re-fetch after a write.
  No `$effect`, no cancellation flags.
-->
<script lang="ts">
import {get_orders, set_channel} from '../data.remote'
import type {OrdersResult, OrderRow} from '../types'
import OrdersTable from './components/OrdersTable.svelte'
import {Badge} from '$lib/components/ui/badge'

// ── GENERATE: props the page accepts (optional) ────────────────────────────
// Keep props if the table is embedded elsewhere; drop them for a standalone page.
interface Props {
  from?: string
  to?: string
}
let {from: pFrom, to: pTo}: Props = $props()

const EMPTY: OrdersResult = {rows: [], total: 0, returned: 0, truncated: false, cap: 50_000}

// ── GENERATE: filter resolution ────────────────────────────────────────────
// Resolve each filter from props, then URL search params, then a default.
// Drop the URL layer if the table is always embedded.
const filters = $derived.by(() => {
  const today = new Date()
  const iso = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
  const thirtyAgo = new Date(today.getTime() - 29 * 86_400_000)
  return {
    from: pFrom ?? iso(thirtyAgo),
    to: pTo ?? iso(today),
  }
})

// The query object for the current filters. `.current` is undefined until the
// first response arrives (and during the first fetch of a new filter set).
const q = $derived(get_orders(filters))
const datos = $derived(q.current ?? EMPTY)

// ── GENERATE: mutations the views need ─────────────────────────────────────
// Kanban: dropping a card on another lane. The override shows the move at once;
// the command runs on the server and, because it calls
// `requested(get_orders, N).refreshAll()`, ships the refreshed rows back in the
// same response (single-flight mutation). Without that server-side call the
// override is simply released and the card snaps back.
async function moveOrder(row: OrderRow, lane: string) {
  const channel = lane as 'web' | 'phone' | 'store'
  await set_channel({id: row.id, channel}).updates(q.withOverride(d => ({...d, rows: d.rows.map(r => (r.id === row.id ? {...r, channel} : r))})))
}

// Filter chips — a compact summary of what's currently applied.
const summary = $derived.by(() => {
  const chips: {label: string; value: string}[] = [{label: 'Period', value: `${filters.from} → ${filters.to}`}]
  return chips
})
</script>

<div class="space-y-4 p-6">
  <div class="flex flex-wrap items-start justify-between gap-3">
    <div>
      <h1 class="text-2xl font-semibold tracking-tight">Orders</h1>
      <p class="text-muted-foreground text-sm">Individual rows with all filters applied.</p>
    </div>
    <div class="flex items-center gap-2 text-sm">
      {#if q.error}
        <Badge variant="destructive">Could not load: {q.error?.body?.message ?? q.error?.message ?? 'error'}</Badge>
      {:else if q.loading}
        <Badge variant="outline" class="animate-pulse">Loading…</Badge>
      {/if}
      {#if datos.truncated}
        <Badge variant="destructive">
          Truncated: {datos.returned.toLocaleString()} of {datos.total.toLocaleString()} (cap {datos.cap.toLocaleString()}). Narrow the filters.
        </Badge>
      {:else if datos.returned > 0}
        <Badge variant="secondary">{datos.returned.toLocaleString()} rows</Badge>
      {/if}
    </div>
  </div>

  <div class="flex flex-wrap gap-2">
    {#each summary as chip (chip.label)}
      <Badge variant="outline">
        <span class="text-muted-foreground mr-1">{chip.label}:</span>
        <span>{chip.value}</span>
      </Badge>
    {/each}
  </div>

  <OrdersTable rows={datos.rows} onMove={moveOrder} />
</div>
