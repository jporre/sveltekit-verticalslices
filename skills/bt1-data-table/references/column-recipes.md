# Column recipes

Every column is a `ColumnDef<typeof features, RowType, unknown>` with four
parts: a `header` (always `DataTableColumnHeader`), a `filterFn`, a `cell`
renderer, and `meta.export`. Pick the recipe that matches the data type.
`EXAMPLE-Table.svelte` has one working column of each kind.

## The non-negotiable: escape cell HTML

Cells render with `createRawSnippet`, which injects a **raw HTML string**. Any
value taken from row data MUST pass through `escape()` before it lands in that
string — otherwise a value like `<img onerror=...>` stored in the database
becomes executable script in every user's browser (stored XSS).

`txt()` and `bool()` escape for you. If you hand-write a cell, escape every
dynamic piece yourself. Static class names and markup you wrote are safe; values
from `row.getValue(...)` are not.

`raw(html)` is the shorthand for `renderSnippet(createRawSnippet(() => ({render: () => html})))`;
`dateHtml(v)` / `amountHtml(v, extraClass)` are the shared date/number
renderers (used by both `cell` and `aggregatedCell`). All three live in the
template.

The **card snippet** (`{#snippet card(r)}`, used by the cards and kanban views)
is plain Svelte — the compiler escapes interpolations, so it needs none of this.

```ts
function escape(s: string): string {
  return s.replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!)
}
function txt(v: unknown): string {
  return v == null || v === '' ? '<span class="text-muted-foreground">—</span>' : `<span>${escape(String(v))}</span>`
}
function bool(v: unknown): string {
  if (v === true) return '<span class="inline-flex items-center rounded-full border px-2 py-0.5 text-xs font-medium bg-green-500/10 text-green-700 dark:text-green-400">yes</span>'
  if (v === false) return '<span class="inline-flex items-center rounded-full border px-2 py-0.5 text-xs font-medium bg-gray-500/10 text-muted-foreground">no</span>'
  return '<span class="text-muted-foreground">—</span>'
}
```

## Filter types

`DataTableColumnHeader` offers four filter UIs, chosen by props:

| Want | Header props | Pair with `filterFn` |
|---|---|---|
| Substring search | `enableFilter: true, filterPlaceholder: '…'` | `'includesString'` |
| Date range | `enableFilter: true, filterType: 'dateRange'` | custom (see below) |
| Single date | `enableFilter: true, filterType: 'date'` | custom |
| Multi-select, fixed values | `enableFilter: true, filterOptions: [{label,value}]` | array-includes (see below) |
| Multi-select, values from data | `enableFilter: true, filterOptions: 'auto'` | array-includes |

The two custom `filterFn`s:

```ts
// dateRange — filter value arrives as { from?: string, to?: string } (yyyy-MM-dd)
filterFn: (row, id, value) => {
  if (!value) return true
  const v = row.getValue(id) as Date | null
  if (!v) return false
  const { from, to } = value as { from?: string; to?: string }
  const s = formatDate(v, 'yyyy-MM-dd')
  if (from && s < from) return false
  if (to && s > to) return false
  return true
}

// faceted (filterOptions list OR 'auto') — value arrives as an array of picks
filterFn: (row, id, value) => !value || !Array.isArray(value) || value.length === 0 || value.includes(row.getValue(id))
```

`filterOptions: 'auto'` needs the `columnFacetingFeature` feature plus the
`facetedRowModel: createFacetedRowModel()` and
`facetedUniqueValues: createFacetedUniqueValues()` slots on `tableFeatures()`
(already wired in the template) — that's how the header discovers the distinct
values and their counts. In v9 these are feature-gated: without the slots, the
API simply doesn't exist.

## Cell recipes

```ts
// Plain text with an em-dash for null/empty
cell: ({ row }) => raw(txt(row.getValue('customer')))

// Monospace (codes, ids, ruts)
cell: ({ row }) => raw(`<span class="font-mono text-xs">${txt(row.getValue('code'))}</span>`)

// Date — format for display (same renderer serves the group-row aggregate)
cell: ({ row }) => raw(dateHtml(row.getValue('createdAt')))

// Number — mono + tabular, null-safe
cell: ({ row }) => raw(amountHtml(row.getValue('amount')))

// Boolean — coloured yes/no pill
cell: ({ row }) => raw(bool(row.getValue('delivered')))

// Mapped label — db code -> human label
cell: ({ row }) => {
  const v = row.getValue('channel') as string | null
  return raw(`<span class="text-xs">${escape(v ? (CHANNEL_LABEL[v] ?? v) : '—')}</span>`)
}

// Long text — truncate with a native tooltip
cell: ({ row }) => {
  const v = (row.getValue('notes') as string | null) ?? ''
  return raw(v ? `<span class="text-xs max-w-xs truncate inline-block align-middle" title="${escape(v)}">${escape(v)}</span>` : '<span class="text-muted-foreground">—</span>')
}
```

For an interactive cell (a button, a link with an `onclick`, a nested
component), a raw HTML string can't carry behaviour — use `renderComponent(MyCell, { ... })`
with a real Svelte component instead of `renderSnippet`.

## Sorting

- `enableSorting: true` on most columns; `false` for long free-text where order
  is meaningless.
- **Date columns need `sortFn: 'datetime'`** — `Date` objects don't compare
  with the default comparator. The built-in is registered in the template
  (`sortFns: {datetime: sortFn_datetime}`); `null` dates sort first ascending.
  It also works on group rows (they carry the `max` aggregate, a `Date`).
- Set the initial sort via the table's `sorting` state, e.g.
  `createTableState<SortingState>([{ id: 'createdAt', desc: true }])`.
- v9 renames v8's `sortingFn` → `sortFn` (and `getSortingFn()` →
  `getSortFn()`). There are no deprecated aliases. String `sortFn`s resolve
  only if registered in `sortFns` — same feature-gating as `filterFns`.

## Grouping & aggregation

Grouping is on by default for every accessor column. Per column:

```ts
enableGrouping: false,            // dates, ids, amounts, free text: not in the "Group" popover
aggregationFn: 'sum',             // group row shows the total   (register aggregationFn_sum)
aggregatedCell: ({ getValue }) => raw(amountHtml(getValue(), 'font-medium')),
aggregationFn: 'max',             // group row shows the latest date (register aggregationFn_max)
aggregatedCell: ({ getValue }) => raw(dateHtml(getValue())),
getGroupingValue: r => r.createdAt?.getFullYear() ?? '—',   // group by a derived key
```

Columns without `aggregationFn` show nothing on group rows (numbers would
auto-sum). `aggregatedCell` receives the aggregate through `getValue()`; treat
it as `unknown` and format defensively — `dateHtml`/`amountHtml` already do.
The full behaviour (expand/collapse, pagination over groups, the
`autoResetExpanded: false` requirement) is in `views.md`.

## Export

Each column carries `meta.export` so `exportTableXlsx` builds the spreadsheet
straight from the column defs — no separate mapping to maintain:

```ts
meta: { export: { label: 'Date', value: r => (r.createdAt ? formatDate(r.createdAt, 'dd-MM-yyyy') : '') } }
```

`label` is the spreadsheet header; `value` returns the **plain** value (no HTML).
Omit `meta.export` to leave a column out of the file (e.g. an actions column).
This needs the `ColumnMeta` augmentation from `table-meta.d.ts` to be present
(v9 shape: `ColumnMeta<TFeatures, TData, TValue>`).

## Row-level interactions (opt-in)

The fixed boilerplate doesn't include these; add them per table when the
product needs them. Both follow the same rule: an interactive cell can't be raw
HTML — it is a real Svelte component rendered with `renderComponent`.

### Row selection → batch changes

1. Register `rowSelectionFeature` in `tableFeatures({...})` (no row-model slot;
   no other change to the features object).
2. Own the slice (component-owned state, same as sorting/filters):

   ```ts
   const [rowSelection, setRowSelection] = createTableState<RowSelectionState>({})
   // in createTable: state: { get rowSelection() { return rowSelection() }, }, onRowSelectionChange: setRowSelection,
   ```

3. Add a selection column FIRST:

   ```ts
   {
     id: 'select',
     header: ({ table }) => renderComponent(SelectCheckbox, { checked: table.getIsAllPageRowsSelected(), indeterminate: table.getIsSomePageRowsSelected() && !table.getIsAllRowsSelected(), onchange: () => table.toggleAllPageRowsSelected() }),
     cell: ({ row }) => renderComponent(SelectCheckbox, { checked: row.getIsSelected(), onchange: () => row.toggleSelected() }),
     enableSorting: false,
   }
   ```

   `SelectCheckbox` is a ~10-line Svelte component (an `<input type="checkbox">`
   with `aria-label`), one per project, in `$lib/components/ui/data-table/`.
   v9 note: `row.getToggleSelectedHandler()` does Shift range selection by
   default; direct `row.toggleSelected()` calls don't.

4. Batch bar above the table when `Object.keys(rowSelection()).length > 0`:
   count + the action buttons, each handler receiving the selected originals
   via `table.getSelectedRowModel().rows.map(r => r.original)`.
5. Row highlighting for selected rows: add
   `data-[state=selected]:bg-muted/60` to the body `Table.Row` (the shadcn
   `table-row` already sets `data-[state=selected]:bg-muted`).

### Detail side-sheet per row

1. Add a display column LAST — no `meta.export`, so it stays out of the XLSX:

   ```ts
   {
     id: 'acciones',
     header: () => '',
     cell: ({ row }) => renderComponent(AccionFila, { row: row.original, onVer: r => (detalle = r) }),
     enableSorting: false,
   }
   ```

2. `AccionFila` is a real component file (a ghost icon button that calls
   `onVer(row)`). Interactive cells MUST go through `renderComponent` — a raw
   HTML string can't carry the `onclick`.
3. The parent owns `let detalle = $state<Row | null>(null)` and renders a
   shadcn `Sheet.Root` next to the table: `open={detalle !== null}`,
   `onOpenChange` resets it to `null`. Content: the row's own data (labels +
   values) plus anything already mapped by the remote function.
4. If the detail needs fields the flat row doesn't carry, map them into the row
   in the remote function — fetch-once means zero extra round-trips to open it.
