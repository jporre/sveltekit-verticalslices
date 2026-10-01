# Grouping, column reorder, cards and kanban

`EXAMPLE-Table.svelte` ships four things beyond the plain table. All of them
run on the **same tanstack instance**, so the global search, the column filters
and the sort apply everywhere — there is no second data pipeline.

```
rows ─ filtered ─ grouped ─ sorted ─ expanded ─ paginated
                    │                    │
   kanban lanes ────┘   table/cards ─────┘
```

Row-model order is fixed by tanstack (filtered → grouped → sorted → expanded →
paginated). Everything below is a consequence of that.

## Group by (table view)

**What the user sees:** a "Group" popover listing the groupable columns
(checkbox each, `#n` shows the nesting order), an "Expand all / Collapse all"
button while grouping is active, and group rows with a chevron, the grouped
value and the leaf count `(12)`. Cells of a group row show the column's
`aggregatedCell` (sum, latest date…) or nothing.

**Wiring (fixed boilerplate, already in the template):**

- Features: `columnGroupingFeature` + `groupedRowModel: createGroupedRowModel()`,
  `rowExpandingFeature` + `expandedRowModel: createExpandedRowModel()`,
  `rowAggregationFeature` + `aggregationFns: {sum, max}`.
- State: `grouping` and `expanded` are component-owned slices
  (`createTableState`) with `onGroupingChange` / `onExpandedChange`.
- Options: `paginateExpandedRows: false` (pagination counts groups, not their
  children) and **`autoResetExpanded: false` — required**. In svelte-table
  9.2.x the adapter re-syncs options on every state change, which re-runs the
  core row model and auto-resets `expanded` right after you expand a group
  (verified: the group closes itself). Group ids are stable
  (`channel:web`), so keeping the state across data changes is harmless.
- Body: `{#if cell.getIsGrouped()}` renders the chevron button around
  `<FlexRender {cell} />`; every other cell is a plain `<FlexRender {cell} />` —
  the adapter picks `aggregatedCell` for aggregated cells and renders nothing
  for placeholders.

**Per column (GENERATE 2):**

| Want | Set |
|---|---|
| Column can be grouped by | nothing (default) — the popover lists it |
| Column can NOT be grouped by (dates, ids, amounts, free text) | `enableGrouping: false` |
| Group row shows a total | `aggregationFn: 'sum'` + `aggregatedCell: ({getValue}) => raw(amountHtml(getValue(), 'font-medium'))` |
| Group row shows the latest date | `aggregationFn: 'max'` + `aggregatedCell: ({getValue}) => raw(dateHtml(getValue()))` |
| Group by something derived (month of a date, first letter…) | `getGroupingValue: row => …` on the column, keep `enableGrouping` on |

Only register the aggregation fns you use (`aggregationFn_sum`,
`aggregationFn_max`, `aggregationFn_count`, `aggregationFn_mean`… all exported
by `@tanstack/svelte-table`). A string `aggregationFn` that is not registered
logs a warning and yields `undefined`. Columns without `aggregationFn` use
`'auto'`: numbers sum, everything else is blank — text columns need nothing.

**Interactions with the rest:**

- Sorting a column while grouped sorts the groups by their aggregated value
  and the rows inside each group.
- Export (`exportTableXlsx`) reads the *filtered* row model — leaf rows only,
  never group rows. Grouping doesn't change the spreadsheet.
- Faceted filters and the count badge use leaf rows too.

## Column reorder

Two ways, both persisted through `createTablePrefs` (localStorage):

1. **Drag the grip** (`⋮` at the left of every header) and drop it on another
   header. Native HTML5 DnD, no dependency. The grip — not the `<th>` — is the
   `draggable`, so the filter inputs inside headers keep normal text selection.
   The drop target is the whole `<th>`; the highlighted left border shows where
   it will land. `prefs.moveTo(fromId, toId)` lands *after* the target when
   dragging rightwards, *before* it when dragging leftwards.
2. **↑ / ↓ arrows** in the "Columns" popover (keyboard-friendly fallback;
   `prefs.moveUp` / `prefs.moveDown`).

"Reset" in the popover clears both the custom order and the visibility.

## Cards view

A responsive grid (`sm:2 · lg:3 · xl:4` columns) of shadcn `Card`s over
`table.getRowModel().rows` — i.e. the **paginated** rows, so the page footer
stays. Grouping is forced off in this view (`NO_GROUPING` in the grouping
getter). Each card renders the `card` snippet (GENERATE 5).

The snippet is plain Svelte: interpolations are escaped by the compiler, so
**no `escape()`/`txt()` here** — those are only for `createRawSnippet` cells.

## Kanban view

**Contract (GENERATE 4):**

```ts
const KANBAN = {column: 'channel', lanes: CHANNEL_OPTS}
//                      ▲ one column id        ▲ [{label, value}] in display order
```

- Lanes are the values of **one** column, in the order given. Lanes with no
  rows still render (empty state) so a card can be dropped on them.
- Rows whose value is not in `lanes` (e.g. `null`) don't appear in the kanban.
  Add a lane for them if they matter (`{label: 'Sin canal', value: 'null'}` —
  values are compared with `String()`).
- The view **forces `grouping = [KANBAN.column]`** and reads
  `table.getSortedRowModel().rows`: one group row per lane whose `subRows` are
  the cards, already filtered by the toolbar search/filters and sorted by the
  current sort. Switching back to the table restores the user's own grouping.
- **No pagination** in kanban: every filtered row is on the board. That is
  fine within the fetch cap (thousands); if a board could exceed a few hundred
  cards per lane, add a lane-level `slice()` or narrow the page filters.

**Moving a card** — `onMove?: (row, lane) => void | Promise<void>` prop:

- Omit it and the board is read-only (cards aren't draggable).
- Pass it and cards become draggable (native DnD). The table calls
  `onMove(row.original, lane.value)` only when the lane actually changes; it
  never mutates the rows itself — **the page owns the write**:

```ts
// <Feature>Page.svelte
async function moveOrder(row: OrderRow, lane: string) {
  const channel = lane as 'web' | 'phone' | 'store'
  await set_channel({id: row.id, channel}).updates(
    q.withOverride(d => ({...d, rows: d.rows.map(r => (r.id === row.id ? {...r, channel} : r))}))
  )
}
```

  The override moves the card immediately; when the command resolves, the
  refreshed query replaces it. **The command must opt in on the server** with
  `await requested(get_orders, 10).refreshAll()` — see
  `remote-function.md`. Without it SvelteKit just releases the override and
  the card snaps back (verified on SvelteKit 2.70).

- The row type needs an `id` (used by `getRowId` and by the command). Don't
  key cards by array index.

**Accessibility:** lanes are `<section role="list" aria-label={lane.label}>`,
cards `role="listitem"` — the roles Svelte's a11y checker requires on elements
with drag handlers.

## Dropping a view you don't need

The spec (Step 0, item 16) decides which views exist. To remove one:

| Remove | Delete |
|---|---|
| kanban | its `VIEWS` entry, the `KANBAN`/`KANBAN_GROUPING` consts, the `{:else if view === 'kanban'}` block, `dragRow`/`dropCard`, the `onMove` prop, and the lane branch in the grouping getter |
| cards | its `VIEWS` entry and the `{:else if view === 'cards'}` block (keep the `card` snippet only if kanban stays) |
| both | all of the above plus the `card` snippet, the `View` type/`view` state and the view switcher; the grouping getter becomes `return grouping()` and the footer's `{#if view !== 'kanban'}` goes away |

With a single entry the view switcher hides itself (`VIEWS.length > 1`).

To remove **grouping** instead: drop the three grouping/expanding/aggregation
feature lines, the `grouping`/`expanded` state and handlers, the "Group"
popover + expand-all button, the `{#if cell.getIsGrouped()}` branch, and the
`aggregationFn`/`aggregatedCell`/`enableGrouping` keys on the columns.

## Verify in the browser (Step 5 additions)

- Group by a faceted column → group rows show the count and the totals; expand
  one group, then "Expand all" / "Collapse all"; the page index must not jump.
- Drag a header grip onto another header → order changes and survives a reload.
- Cards: pagination still works; every card value is displayed as text
  (paste `<b>x</b>` in a row to be sure it is not rendered as HTML).
- Kanban: type in the search box → cards shrink per lane; drag a card to
  another lane → it moves at once and is still there after a reload.
