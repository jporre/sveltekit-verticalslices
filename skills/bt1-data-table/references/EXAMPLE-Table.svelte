<!--
  EXAMPLE-Table.svelte — the bt1-data-table table component (TanStack Table v9).

  Copy this into <feature>/ui/components/<Feature>Table.svelte and adapt the
  five places marked `── GENERATE`. Everything else is fixed boilerplate that
  works the same for every table.

  SPEC (contrato del cuestionario bt1 — Step 0)  ← ajusta con la spec real
  fuente:     <vista/tabla> · guard: <ver:xxx>
  columnas:   ...
  filtros:    ...
  export:     sí · búsqueda global: sí
  orden:      ... · paginación: 50 [50,100,200,500] · cap: 5000
  agrupar:    channel, customer, delivered · vistas: tabla, cards, kanban(channel → set_channel)
  batch:      no · detalle: no · cache: no · fila destacada: no
  =====
  resolvido:  <fecha> con el usuario

  v9 shape: `tableFeatures()` declares exactly the features + row models used
  (tree-shaking); component-owned state slices use `createTableState`
  ($state + per-slice on*Change); the prefs slices are external atoms.

  Three views share ONE table instance, so filters, search and sort apply to
  all of them: `table` (rows, optional grouping), `cards` (paginated grid) and
  `kanban` (lanes = the values of one column; drag a card to call `onMove`).

  The example row below covers every cell + filter recipe once:
    createdAt  Date|null   sortable('datetime') · dateRange filter · mono date cell · aggregated: max
    code       string|null sortable · text filter · mono cell
    channel    string|null sortable · faceted filter (fixed enum) · mapped label · groupable · kanban lanes
    customer   string|null sortable · faceted filter ('auto') · plain text · groupable
    amount     number|null sortable · numeric cell · aggregated: sum
    delivered  boolean|null sortable · faceted filter (boolean) · badge cell · groupable
    notes      string|null  NOT sortable · text filter · truncated cell

  See references/column-recipes.md for the full catalogue and
  references/views.md for the grouping / cards / kanban details.
-->
<script lang="ts">
import type {ColumnDef, ColumnFiltersState, ExpandedState, GroupingState, PaginationState, SortingState} from '@tanstack/svelte-table'
import {
  aggregationFn_max,
  aggregationFn_sum,
  columnFacetingFeature,
  columnFilteringFeature,
  columnGroupingFeature,
  columnOrderingFeature,
  columnVisibilityFeature,
  createExpandedRowModel,
  createFacetedRowModel,
  createFacetedUniqueValues,
  createFilteredRowModel,
  createGroupedRowModel,
  createPaginatedRowModel,
  createSortedRowModel,
  createTable,
  createTableState,
  filterFn_includesString,
  FlexRender,
  globalFilteringFeature,
  renderComponent,
  renderSnippet,
  rowAggregationFeature,
  rowExpandingFeature,
  rowPaginationFeature,
  rowSortingFeature,
  sortFn_datetime,
  tableFeatures,
} from '@tanstack/svelte-table'
import {createTablePrefs} from '$lib/components/ui/data-table/table-prefs.svelte'
import {exportTableXlsx} from '$lib/components/ui/data-table/table-export'
import DataTableColumnHeader from '$lib/components/ui/data-table/data-table-column-header.svelte'
import * as Table from '$lib/components/ui/table'
import * as Popover from '$lib/components/ui/popover'
import * as Card from '$lib/components/ui/card'
import {Badge} from '$lib/components/ui/badge'
import {Button} from '$lib/components/ui/button'
import {Input} from '$lib/components/ui/input'
import ChevronLeftIcon from '@lucide/svelte/icons/chevron-left'
import ChevronRightIcon from '@lucide/svelte/icons/chevron-right'
import ChevronsLeftIcon from '@lucide/svelte/icons/chevrons-left'
import ChevronsRightIcon from '@lucide/svelte/icons/chevrons-right'
import Columns3Icon from '@lucide/svelte/icons/columns-3'
import DownloadIcon from '@lucide/svelte/icons/download'
import GripVerticalIcon from '@lucide/svelte/icons/grip-vertical'
import KanbanIcon from '@lucide/svelte/icons/kanban'
import LayersIcon from '@lucide/svelte/icons/layers'
import LayoutGridIcon from '@lucide/svelte/icons/layout-grid'
import Table2Icon from '@lucide/svelte/icons/table-2'
import XIcon from '@lucide/svelte/icons/x'
import {createRawSnippet} from 'svelte'
import {formatDate} from '$lib/utils/format-date'

// ── GENERATE 1: the row type ───────────────────────────────────────────────
// Import this from the feature's types.ts — it must match the remote function.
// `id` is required: it keys rows (getRowId) and identifies a dragged kanban card.
interface OrderRow {
  id: string
  createdAt: Date | null
  code: string | null
  channel: string | null
  customer: string | null
  amount: number | null
  delivered: boolean | null
  notes: string | null
}

interface Props {
  rows: OrderRow[]
  /** Kanban: called when a card is dropped on another lane. Omit to make cards read-only. */
  onMove?: (row: OrderRow, lane: string) => void | Promise<void>
}
let {rows, onMove}: Props = $props()

// ── Cell HTML helpers ──────────────────────────────────────────────────────
// `createRawSnippet` renders a raw HTML string. ANY value interpolated from row
// data MUST go through `escape()` first — these strings are injected as innerHTML,
// so an unescaped value is a stored-XSS hole. `txt`/`bool` already escape; if you
// write a bespoke cell, escape every dynamic piece yourself.
// (Svelte templates and `{#snippet}`s escape by themselves — the card snippet
// below needs none of this.)
function escape(s: string): string {
  return s.replace(/[&<>"']/g, c => ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'})[c]!)
}
function txt(v: unknown): string {
  return v == null || v === '' ? '<span class="text-muted-foreground">—</span>' : `<span>${escape(String(v))}</span>`
}
function bool(v: unknown): string {
  if (v === true) return '<span class="inline-flex items-center rounded-full border px-2 py-0.5 text-xs font-medium bg-green-500/10 text-green-700 dark:text-green-400">yes</span>'
  if (v === false) return '<span class="inline-flex items-center rounded-full border px-2 py-0.5 text-xs font-medium bg-gray-500/10 text-muted-foreground">no</span>'
  return '<span class="text-muted-foreground">—</span>'
}
const raw = (html: string) => renderSnippet(createRawSnippet(() => ({render: () => html})))
const dateHtml = (v: unknown) => `<span class="font-mono text-xs">${escape(v instanceof Date ? formatDate(v, 'dd-MM-yyyy') : '—')}</span>`
const amountHtml = (v: unknown, extra = '') => `<span class="font-mono text-xs tabular-nums ${extra}">${escape(typeof v === 'number' ? v.toLocaleString() : '—')}</span>`

// Mapped label for an enum-ish column (see `channel` below).
const CHANNEL_LABEL: Record<string, string> = {web: 'Web', phone: 'Phone', store: 'In store'}
const CHANNEL_OPTS = Object.entries(CHANNEL_LABEL).map(([value, label]) => ({label, value}))

// ── Features: declare exactly what this table uses ─────────────────────────
// v9 is feature-gated: every feature, row-model factory, filter/sort/aggregation
// fn is registered here — nothing else ships to the client. String references
// ('includesString', 'datetime', 'sum') resolve only because they are registered.
// Row-model order is fixed by tanstack: filtered → grouped → sorted → expanded → paginated.
const features = tableFeatures({
  rowSortingFeature,
  sortedRowModel: createSortedRowModel(),
  sortFns: {datetime: sortFn_datetime},
  columnFilteringFeature,
  filteredRowModel: createFilteredRowModel(),
  filterFns: {includesString: filterFn_includesString},
  columnFacetingFeature,
  facetedRowModel: createFacetedRowModel(),
  facetedUniqueValues: createFacetedUniqueValues(),
  globalFilteringFeature,
  columnGroupingFeature,
  groupedRowModel: createGroupedRowModel(),
  rowExpandingFeature,
  expandedRowModel: createExpandedRowModel(),
  rowAggregationFeature,
  aggregationFns: {sum: aggregationFn_sum, max: aggregationFn_max},
  rowPaginationFeature,
  paginatedRowModel: createPaginatedRowModel(),
  columnVisibilityFeature,
  columnOrderingFeature,
})

// ── GENERATE 2: column definitions ─────────────────────────────────────────
// One entry per column. The `header` is always a DataTableColumnHeader; the
// `cell` is a raw snippet; `meta.export` keeps the XLSX in sync. The
// `column as any` cast is unavoidable tanstack/Svelte generics friction.
// Grouping: `enableGrouping: false` on columns it makes no sense to group by.
// Group rows show `aggregatedCell` for columns with an `aggregationFn`
// ('sum' / 'max' registered above) and nothing for the rest.
const columns: ColumnDef<typeof features, OrderRow, unknown>[] = [
  {
    accessorKey: 'createdAt',
    header: ({column}) => renderComponent(DataTableColumnHeader, {column: column as any, title: 'Date', enableFilter: true, filterType: 'dateRange'}),
    // dateRange filter: value is {from, to} as yyyy-MM-dd strings.
    filterFn: (row, id, value) => {
      if (!value) return true
      const v = row.getValue(id) as Date | null
      if (!v) return false
      const {from, to} = value as {from?: string; to?: string}
      const s = formatDate(v, 'yyyy-MM-dd')
      if (from && s < from) return false
      if (to && s > to) return false
      return true
    },
    // Dates don't compare with the default sortFn — use the built-in 'datetime'.
    sortFn: 'datetime',
    cell: ({row}) => raw(dateHtml(row.getValue('createdAt'))),
    enableSorting: true,
    enableGrouping: false,
    aggregationFn: 'max', // group row shows the latest date of the group
    aggregatedCell: ({getValue}) => raw(dateHtml(getValue())),
    meta: {export: {label: 'Date', value: r => (r.createdAt ? formatDate(r.createdAt, 'dd-MM-yyyy') : '')}},
  },
  {
    accessorKey: 'code',
    header: ({column}) => renderComponent(DataTableColumnHeader, {column: column as any, title: 'Code', enableFilter: true, filterPlaceholder: 'Search code…'}),
    filterFn: 'includesString',
    cell: ({row}) => raw(`<span class="font-mono text-xs">${txt(row.getValue('code'))}</span>`),
    enableSorting: true,
    enableGrouping: false,
    meta: {export: {label: 'Code', value: r => r.code ?? ''}},
  },
  {
    accessorKey: 'channel',
    header: ({column}) => renderComponent(DataTableColumnHeader, {column: column as any, title: 'Channel', enableFilter: true, filterOptions: CHANNEL_OPTS}),
    // Faceted filter: value is an array of selected values.
    filterFn: (row, id, value) => !value || !Array.isArray(value) || value.length === 0 || value.includes(row.getValue(id)),
    cell: ({row}) => {
      const v = row.getValue('channel') as string | null
      return raw(`<span class="text-xs">${escape(v ? (CHANNEL_LABEL[v] ?? v) : '—')}</span>`)
    },
    enableSorting: true,
    meta: {export: {label: 'Channel', value: r => (r.channel ? (CHANNEL_LABEL[r.channel] ?? r.channel) : '')}},
  },
  {
    accessorKey: 'customer',
    // filterOptions: 'auto' discovers the values from the data (faceted).
    header: ({column}) => renderComponent(DataTableColumnHeader, {column: column as any, title: 'Customer', enableFilter: true, filterOptions: 'auto'}),
    filterFn: (row, id, value) => !value || !Array.isArray(value) || value.length === 0 || value.includes(row.getValue(id)),
    cell: ({row}) => raw(txt(row.getValue('customer'))),
    enableSorting: true,
    meta: {export: {label: 'Customer', value: r => r.customer ?? ''}},
  },
  {
    accessorKey: 'amount',
    header: ({column}) => renderComponent(DataTableColumnHeader, {column: column as any, title: 'Amount', enableFilter: true, filterPlaceholder: 'Search amount…'}),
    filterFn: 'includesString',
    cell: ({row}) => raw(amountHtml(row.getValue('amount'))),
    enableSorting: true,
    enableGrouping: false,
    aggregationFn: 'sum', // group row shows the total of the group
    aggregatedCell: ({getValue}) => raw(amountHtml(getValue(), 'font-medium')),
    meta: {export: {label: 'Amount', value: r => r.amount ?? ''}},
  },
  {
    accessorKey: 'delivered',
    header: ({column}) =>
      renderComponent(DataTableColumnHeader, {
        column: column as any,
        title: 'Delivered',
        enableFilter: true,
        filterOptions: [
          {label: 'Yes', value: true},
          {label: 'No', value: false},
        ],
      }),
    filterFn: (row, id, value) => !value || !Array.isArray(value) || value.length === 0 || value.includes(row.getValue(id)),
    cell: ({row}) => raw(bool(row.getValue('delivered'))),
    enableSorting: true,
    meta: {export: {label: 'Delivered', value: r => (r.delivered === true ? 'Yes' : r.delivered === false ? 'No' : '')}},
  },
  {
    accessorKey: 'notes',
    header: ({column}) => renderComponent(DataTableColumnHeader, {column: column as any, title: 'Notes', enableFilter: true, filterPlaceholder: 'Search notes…'}),
    filterFn: 'includesString',
    // Long free text: truncate with a native tooltip; not worth sorting or grouping.
    cell: ({row}) => {
      const v = (row.getValue('notes') as string | null) ?? ''
      return raw(v ? `<span class="text-xs max-w-xs truncate inline-block align-middle" title="${escape(v)}">${escape(v)}</span>` : '<span class="text-muted-foreground">—</span>')
    },
    enableSorting: false,
    enableGrouping: false,
    meta: {export: {label: 'Notes', value: r => r.notes ?? ''}},
  },
]

// ── GENERATE 3: column ids, labels, defaults ───────────────────────────────
// `ALL_COLUMN_IDS` order = natural display order. `DEFAULT_VISIBLE` = columns
// shown on first load. `COLUMN_LABELS` = names in the "Columns"/"Group" popovers.
const ALL_COLUMN_IDS = ['createdAt', 'code', 'channel', 'customer', 'amount', 'delivered', 'notes']
const DEFAULT_VISIBLE = ['createdAt', 'code', 'channel', 'customer', 'amount', 'delivered']
const COLUMN_LABELS: Record<string, string> = {
  createdAt: 'Date',
  code: 'Code',
  channel: 'Channel',
  customer: 'Customer',
  amount: 'Amount',
  delivered: 'Delivered',
  notes: 'Notes',
}

// ── GENERATE 4: views ──────────────────────────────────────────────────────
// Delete the entries (and their template blocks below) the spec doesn't ask for.
// Kanban lanes are the values of ONE column, in this order; lanes with no rows
// still render so cards can be dropped on them. Values are compared as strings.
type View = 'table' | 'cards' | 'kanban'
const VIEWS: {id: View; label: string; icon: typeof Table2Icon}[] = [
  {id: 'table', label: 'Table', icon: Table2Icon},
  {id: 'cards', label: 'Cards', icon: LayoutGridIcon},
  {id: 'kanban', label: 'Kanban', icon: KanbanIcon},
]
const KANBAN = {column: 'channel', lanes: CHANNEL_OPTS} satisfies {column: keyof OrderRow; lanes: {label: string; value: string}[]}
// Hoisted so the grouping getter below returns stable references (a fresh array
// per read would recompute the grouped row model on every option sync).
const KANBAN_GROUPING: GroupingState = [KANBAN.column]
const NO_GROUPING: GroupingState = []

// ── Fixed boilerplate below — no changes needed ─────────────────────────────
// Visibility + ordering + localStorage are external atoms (createTablePrefs).
// Component-owned slices (sorting, filters, pagination, grouping, expanded) use
// createTableState, which accepts both value and functional updaters from on*Change.
const prefs = createTablePrefs({storageKey: 'orders_table_cols', columnIds: ALL_COLUMN_IDS, defaultVisible: DEFAULT_VISIBLE})

let view = $state<View>('table')
const [pagination, setPagination] = createTableState<PaginationState>({pageIndex: 0, pageSize: 50})
const [sorting, setSorting] = createTableState<SortingState>([{id: 'createdAt', desc: true}])
const [columnFilters, setColumnFilters] = createTableState<ColumnFiltersState>([])
const [globalFilter, setGlobalFilter] = createTableState<string>('')
const [grouping, setGrouping] = createTableState<GroupingState>([])
const [expanded, setExpanded] = createTableState<ExpandedState>({})

const table = createTable({
  features,
  get data() {
    return rows
  },
  get columns() {
    return columns
  },
  getRowId: r => r.id,
  globalFilterFn: 'includesString',
  paginateExpandedRows: false, // page over groups; expanded children don't count towards the page size
  // REQUIRED with grouping in svelte-table 9.2.x: the adapter re-syncs options on
  // every state change, which re-runs the core row model and would auto-reset
  // `expanded` right after you expand a group. Group ids are stable, so keeping
  // the expanded state across data changes is harmless.
  autoResetExpanded: false,
  atoms: prefs.atoms, // columnVisibility + columnOrder — app-owned (localStorage)
  state: {
    get pagination() {
      return pagination()
    },
    get sorting() {
      return sorting()
    },
    get columnFilters() {
      return columnFilters()
    },
    get globalFilter() {
      return globalFilter()
    },
    // The active view decides the grouping: kanban lanes ARE a grouping by the
    // lane column; cards never group; the table view uses what the user picked.
    get grouping() {
      return view === 'kanban' ? KANBAN_GROUPING : view === 'cards' ? NO_GROUPING : grouping()
    },
    get expanded() {
      return expanded()
    },
  },
  onPaginationChange: setPagination,
  onSortingChange: setSorting,
  onColumnFiltersChange: setColumnFilters,
  onGlobalFilterChange: setGlobalFilter,
  onGroupingChange: setGrouping,
  onExpandedChange: setExpanded,
})

const isFiltered = $derived(columnFilters().length > 0 || globalFilter().length > 0)
const filteredCount = $derived(table.getFilteredRowModel().rows.length)
const groupableColumns = $derived(table.getAllLeafColumns().filter(c => c.getCanGroup()))

// Header drag-and-drop → column order (persisted by prefs). Native HTML5 DnD, no deps.
let dragCol = $state<string | null>(null)
function dropColumn(targetId: string) {
  if (dragCol) prefs.moveTo(dragCol, targetId)
  dragCol = null
}

// Kanban drag-and-drop → `onMove(row, lane)`; the page owns the mutation.
let dragRow = $state<OrderRow | null>(null)
function dropCard(lane: string) {
  const row = dragRow
  dragRow = null
  if (row && onMove && String(row[KANBAN.column]) !== lane) void onMove(row, lane)
}
</script>

<!-- ── GENERATE 5: the card (cards + kanban views) ─────────────────────────
     Plain Svelte — values are escaped automatically, no `escape()` needed. -->
{#snippet card(r: OrderRow)}
  <div class="flex items-start justify-between gap-2">
    <span class="font-mono text-xs">{r.code ?? '—'}</span>
    <span class="text-muted-foreground text-xs">{r.createdAt ? formatDate(r.createdAt, 'dd-MM-yyyy') : '—'}</span>
  </div>
  <p class="mt-1 truncate text-sm font-medium">{r.customer ?? '—'}</p>
  <div class="mt-2 flex items-center justify-between text-xs">
    <span class="text-muted-foreground">{r.channel ? (CHANNEL_LABEL[r.channel] ?? r.channel) : '—'}</span>
    <span class="font-mono tabular-nums">{r.amount?.toLocaleString() ?? '—'}</span>
  </div>
{/snippet}

<div class="w-full space-y-3">
  <div class="flex flex-wrap items-center justify-between gap-2">
    <div class="flex items-center gap-2">
      <Input placeholder="Search the whole table…" value={globalFilter()} oninput={e => setGlobalFilter(e.currentTarget.value)} class="h-8 w-72" />
      {#if isFiltered}
        <Button
          variant="ghost"
          size="sm"
          class="h-8"
          onclick={() => {
            table.resetColumnFilters()
            setGlobalFilter('')
          }}
        >
          Clear filters
          <XIcon class="ml-1 h-3 w-3" />
        </Button>
      {/if}
      <span class="text-muted-foreground text-xs">
        {filteredCount.toLocaleString()} of {rows.length.toLocaleString()} rows
      </span>
    </div>
    <div class="flex items-center gap-2">
      {#if VIEWS.length > 1}
        <div class="flex items-center rounded-md border p-0.5" role="group" aria-label="View">
          {#each VIEWS as v (v.id)}
            <Button variant={view === v.id ? 'secondary' : 'ghost'} size="sm" class="h-7 px-2" title={v.label} aria-pressed={view === v.id} onclick={() => (view = v.id)}>
              <v.icon class="size-3.5" />
            </Button>
          {/each}
        </div>
      {/if}
      {#if view === 'table'}
        <Popover.Root>
          <Popover.Trigger>
            {#snippet child({props})}
              <Button {...props} variant="outline" size="sm" class="h-8 gap-1">
                <LayersIcon class="h-3 w-3" />
                Group
                {#if grouping().length > 0}
                  <Badge variant="secondary" class="ml-1 rounded-sm px-1 text-xs font-normal">{grouping().length}</Badge>
                {/if}
              </Button>
            {/snippet}
          </Popover.Trigger>
          <Popover.Content class="w-56 p-3" align="end">
            <div class="mb-2 flex items-center justify-between">
              <span class="text-sm font-medium">Group by</span>
              <Button variant="ghost" size="sm" class="h-6 px-2 text-xs" onclick={() => table.resetGrouping(true)}>Clear</Button>
            </div>
            <div class="space-y-0.5">
              {#each groupableColumns as column (column.id)}
                <label class="hover:bg-muted/50 flex cursor-pointer items-center gap-2 rounded px-1 py-0.5 text-xs">
                  <input type="checkbox" class="size-3" checked={column.getIsGrouped()} onchange={() => column.toggleGrouping()} />
                  {COLUMN_LABELS[column.id] ?? column.id}
                  {#if column.getIsGrouped()}
                    <span class="text-muted-foreground ml-auto font-mono">#{column.getGroupedIndex() + 1}</span>
                  {/if}
                </label>
              {/each}
            </div>
          </Popover.Content>
        </Popover.Root>
        {#if grouping().length > 0}
          <Button variant="ghost" size="sm" class="h-8" onclick={() => table.toggleAllRowsExpanded()}>
            {table.getIsAllRowsExpanded() ? 'Collapse all' : 'Expand all'}
          </Button>
        {/if}
        <Popover.Root>
          <Popover.Trigger>
            {#snippet child({props})}
              <Button {...props} variant="outline" size="sm" class="h-8 gap-1">
                <Columns3Icon class="h-3 w-3" />
                Columns
              </Button>
            {/snippet}
          </Popover.Trigger>
          <Popover.Content class="w-64 p-3" align="end">
            <div class="mb-2 flex items-center justify-between">
              <span class="text-sm font-medium">Visible columns</span>
              <Button variant="ghost" size="sm" class="h-6 px-2 text-xs" onclick={() => prefs.reset()}>Reset</Button>
            </div>
            <div class="max-h-80 space-y-0.5 overflow-y-auto">
              {#each prefs.orderedIds as id, i (id)}
                <div class="hover:bg-muted/50 flex items-center gap-1 rounded px-1 py-0.5">
                  <input
                    type="checkbox"
                    id="col-{id}"
                    checked={prefs.visibility[id] !== false}
                    onchange={e => {
                      prefs.setVisibility({...prefs.visibility, [id]: e.currentTarget.checked})
                    }}
                    class="size-3 cursor-pointer"
                  />
                  <label for="col-{id}" class="flex-1 cursor-pointer truncate text-xs">{COLUMN_LABELS[id] ?? id}</label>
                  <div class="flex shrink-0 gap-0.5">
                    <button type="button" class="text-muted-foreground hover:bg-muted hover:text-foreground flex h-5 w-5 items-center justify-center rounded text-xs disabled:opacity-30" onclick={() => prefs.moveUp(id)} disabled={i === 0} aria-label="Move up">↑</button>
                    <button type="button" class="text-muted-foreground hover:bg-muted hover:text-foreground flex h-5 w-5 items-center justify-center rounded text-xs disabled:opacity-30" onclick={() => prefs.moveDown(id)} disabled={i === prefs.orderedIds.length - 1} aria-label="Move down">↓</button>
                  </div>
                </div>
              {/each}
            </div>
          </Popover.Content>
        </Popover.Root>
      {/if}
      <Button variant="outline" size="sm" class="h-8" onclick={() => exportTableXlsx(table, {filename: 'orders', sheetName: 'Orders'})} disabled={filteredCount === 0}>
        <DownloadIcon class="mr-1 h-3 w-3" />
        Export Excel
      </Button>
    </div>
  </div>

  {#if view === 'table'}
    <div class="overflow-x-auto rounded-md border">
      <Table.Root>
        <Table.Header>
          {#each table.getHeaderGroups() as headerGroup (headerGroup.id)}
            <Table.Row class="bg-muted/50">
              {#each headerGroup.headers as header (header.id)}
                <!-- Drop target for header drag-and-drop; the grip is the draggable, so
                     the filter inputs inside the header keep normal text selection. -->
                <Table.Head ondragover={e => e.preventDefault()} ondrop={() => dropColumn(header.column.id)} class={dragCol && dragCol !== header.column.id ? 'border-l-primary/40 border-l-2' : ''}>
                  {#if !header.isPlaceholder}
                    <div class="flex items-center gap-1">
                      <span draggable="true" ondragstart={() => (dragCol = header.column.id)} ondragend={() => (dragCol = null)} class="text-muted-foreground/40 hover:text-muted-foreground cursor-grab active:cursor-grabbing" title="Drag to reorder" aria-hidden="true">
                        <GripVerticalIcon class="size-3" />
                      </span>
                      <FlexRender {header} />
                    </div>
                  {/if}
                </Table.Head>
              {/each}
            </Table.Row>
          {/each}
        </Table.Header>
        <Table.Body>
          {#each table.getRowModel().rows as row (row.id)}
            <Table.Row class={row.getIsGrouped() ? 'bg-muted/40' : 'hover:bg-muted/50'}>
              {#each row.getVisibleCells() as cell (cell.id)}
                <Table.Cell>
                  {#if cell.getIsGrouped()}
                    <!-- Group row: chevron + the grouped value + leaf count. Other cells of a
                         group row render `aggregatedCell` (or nothing) via FlexRender. -->
                    <button type="button" class="flex items-center gap-1 font-medium" style:padding-left="{row.depth * 1.25}rem" onclick={row.getToggleExpandedHandler()}>
                      <ChevronRightIcon class="size-3.5 transition-transform {row.getIsExpanded() ? 'rotate-90' : ''}" />
                      <FlexRender {cell} />
                      <span class="text-muted-foreground text-xs">({row.getLeafRows().length})</span>
                    </button>
                  {:else}
                    <FlexRender {cell} />
                  {/if}
                </Table.Cell>
              {/each}
            </Table.Row>
          {:else}
            <Table.Row>
              <Table.Cell colspan={columns.length} class="h-24 text-center">No results.</Table.Cell>
            </Table.Row>
          {/each}
        </Table.Body>
      </Table.Root>
    </div>
  {:else if view === 'cards'}
    <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
      {#each table.getRowModel().rows as row (row.id)}
        <Card.Root class="gap-0 py-4">
          <Card.Content class="px-4">{@render card(row.original)}</Card.Content>
        </Card.Root>
      {:else}
        <p class="text-muted-foreground col-span-full py-10 text-center text-sm">No results.</p>
      {/each}
    </div>
  {:else if view === 'kanban'}
    <!-- Lanes come from the grouped+sorted model (grouping is forced to KANBAN.column
         in this view), so search, filters and sort apply inside each lane. No pagination. -->
    {@const groups = table.getSortedRowModel().rows}
    <div class="flex gap-3 overflow-x-auto pb-2">
      {#each KANBAN.lanes as lane (lane.value)}
        {@const cards = groups.find(g => String(g.groupingValue) === lane.value)?.subRows ?? []}
        <section role="list" aria-label={lane.label} class="bg-muted/40 flex w-72 shrink-0 flex-col rounded-lg border {dragRow ? 'border-dashed' : ''}" ondragover={e => e.preventDefault()} ondrop={() => dropCard(lane.value)}>
          <header class="flex items-center justify-between px-3 py-2 text-xs font-semibold tracking-wide uppercase">
            {lane.label}
            <Badge variant="secondary" class="font-mono">{cards.length}</Badge>
          </header>
          <div class="flex max-h-[70vh] flex-col gap-2 overflow-y-auto p-2">
            {#each cards as row (row.id)}
              <div role="listitem" draggable={!!onMove} ondragstart={() => (dragRow = row.original)} ondragend={() => (dragRow = null)} class="bg-card rounded-md border p-3 shadow-xs {onMove ? 'cursor-grab active:cursor-grabbing' : ''}">
                {@render card(row.original)}
              </div>
            {:else}
              <p class="text-muted-foreground py-6 text-center text-xs">Empty</p>
            {/each}
          </div>
        </section>
      {/each}
    </div>
  {/if}

  {#if view !== 'kanban'}
    <div class="flex items-center justify-between">
      <div class="text-muted-foreground text-sm">
        Page {pagination().pageIndex + 1} of {Math.max(1, table.getPageCount())}
      </div>
      <div class="flex items-center gap-3">
        <div class="flex items-center gap-2">
          <span class="text-sm">Rows/page</span>
          <select value={pagination().pageSize} onchange={e => table.setPageSize(Number(e.currentTarget.value))} class="border-input bg-background h-8 rounded-md border px-2 text-sm">
            {#each [50, 100, 200, 500] as ps (ps)}
              <option value={ps}>{ps}</option>
            {/each}
          </select>
        </div>
        <Button variant="outline" size="sm" class="h-8 w-8 p-0" onclick={() => table.setPageIndex(0)} disabled={!table.getCanPreviousPage()}>
          <ChevronsLeftIcon class="size-4" />
        </Button>
        <Button variant="outline" size="sm" class="h-8 w-8 p-0" onclick={() => table.previousPage()} disabled={!table.getCanPreviousPage()}>
          <ChevronLeftIcon class="size-4" />
        </Button>
        <Button variant="outline" size="sm" class="h-8 w-8 p-0" onclick={() => table.nextPage()} disabled={!table.getCanNextPage()}>
          <ChevronRightIcon class="size-4" />
        </Button>
        <Button variant="outline" size="sm" class="h-8 w-8 p-0" onclick={() => table.setPageIndex(table.getPageCount() - 1)} disabled={!table.getCanNextPage()}>
          <ChevronsRightIcon class="size-4" />
        </Button>
      </div>
    </div>
  {/if}
</div>
