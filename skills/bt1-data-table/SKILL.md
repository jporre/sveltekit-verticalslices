---
name: bt1-data-table
description: >-
  Generate a feature-rich client-side data table for SvelteKit 5 + Svelte 5,
  powered by @tanstack/svelte-table (v9) and fed by remote functions: sorting,
  substring/date-range/faceted filters, global search, group-by with expandable
  rows and aggregates, column show-hide + reorder persisted to localStorage,
  pagination, XLSX export, plus cards-grid and kanban views with drag-and-drop.
  Trigger WHENEVER the user asks for a data table, "tabla de datos", a
  sortable/filterable/searchable/exportable table, a tanstack table, a grouped
  table, a kanban or "tablero", a cards/grid view of records, a list or admin
  view of database records, or a screen "to browse/list" rows — including
  casual phrasings like "build me a screen that lists X" or "necesito una
  pantalla para listar Y". Prefer this over hand-rolling a <table>: it ships
  the tanstack wiring, view templates and reusable helpers, and prevents the
  stored-XSS hole from raw createRawSnippet cells. NOT for a static table of a
  few fixed rows or chart/dashboard visuals.
---

# bt1-data-table

Generates the "estadísticas datos" table — a polished, client-side data table
for SvelteKit 5 — into any feature of any SvelteKit project. Sorting, filtering,
search, grouping, column management, pagination, Excel export and the
cards/kanban views all work out of the box.

## What it builds

A **fetch-once, explore-offline** table:

- One **remote `query`** fetches the full result set (up to a cap) in a single
  call. Everything below happens client-side — instant, no round-trips.
  Writes (kanban moves, batch actions) are remote **`command`s** that refresh
  that query in the same response.
- A **page component** resolves filters, reads the query (`.current`,
  `.loading`, `.error`), shows truncated states, hands rows to the table and
  owns the mutations.
- A **table component** built on `@tanstack/svelte-table` v9 (`tableFeatures` +
  `createTable`): per-column sort, three filter kinds, a whole-table search
  box, a "Group" popover (group rows with counts + aggregates, expand/collapse),
  a "Columns" popover (show/hide + reorder, remembered in localStorage) plus
  drag-and-drop header reorder, pagination, XLSX export, and a view switcher:
  **table / cards / kanban** over the one tanstack instance.
- Shared **infrastructure** copied into `$lib/components/ui/data-table/`.

## How the pieces fit

```
route +page.svelte ─ thin wrapper, <svelte:boundary>
  └─ <Feature>Page.svelte ──── filters + $derived(query) + mutations (onMove)
       └─ <Feature>Table.svelte ── tanstack table, columns, toolbar, 3 views
            ├─ data-table-column-header.svelte ─ sort + filter UI per column
            ├─ createTablePrefs() ───── visibility/order + localStorage (+ moveTo for DnD)
            └─ exportTableXlsx() ────── XLSX from column meta

data.remote.ts ─ query(): validate → auth → count → capped fetch → map
                 command(): validate → auth → write → requested(query).refreshAll()
```

## Before you start

Confirm the target is a **SvelteKit 2 + Svelte 5** project using runes and
shadcn-svelte. If it is not, stop and tell the user — this skill targets that
stack specifically.

Then check, in order:

1. **Read the project's `CLAUDE.md`** (if any) for its feature-folder layout,
   remote-function conventions, auth helpers, and code style. Match them — the
   examples here use one common layout but the project's wins.
2. **npm deps** — ensure `@tanstack/svelte-table` (v9, ≥ 9.2), `@tanstack/svelte-store`
   and `xlsx` are installed. Install whatever is missing with the project's
   package manager. TanStack Table **v8 is not compatible** — a bare
   `@tanstack/table-core` dependency or a v8 adapter is a signal to install v9
   and migrate the imports, not to keep the old adapter. SvelteKit must be
   ≥ 2.5x with `kit.experimental.remoteFunctions: true` (the page reads
   `query.current`; the command uses `requested()`).
3. **shadcn-svelte components** — the table needs `table`, `button`, `input`,
   `badge`, `card`, `command`, `popover`, `separator` (and `dialog`, which
   `command` imports). Add any that are missing
   (`npx shadcn-svelte@latest add <name>`).
4. **Date formatting** — the templates import a `formatDate(date, 'dd-MM-yyyy' | 'yyyy-MM-dd')`
   from `$lib/utils/format-date`. If the project has its own date util, use
   that instead; if it has none, inline a small formatter. Don't invent a
   dependency.

## Build steps

Work through these in order. Read each reference file when the step points to
it — they hold the detail this overview leaves out.

### Step 0 — Intake questionnaire

Before writing anything, collect the table's spec. Fill in from context what
the request already answers, propose your defaults for the rest, and ask ONLY
the unanswered items — in **one** message, numbered, each with your proposed
default so the user can reply "todo ok" and move on. If the request already
spells an item out, do not re-ask it.

**Presets:** if the request references an existing table built with this skill
("como la de estadísticas", "igual que la de importaciones"), read that
component's spec block first and pre-fill the questionnaire from it — then ask
only what genuinely differs. A preset user should answer one question, not
seventeen.

**Required (no defaults — the table can't be built without these):**

1. **Fuente de datos** — vista/tabla (nombre exacto, p. ej. `vi_carga_operacion`)
   o remote function existente que la envuelve. Debe tener una clave primaria
   (la fila necesita `id`).
2. **Permiso del guard** — qué `requirePermission('verbo:sustantivo')` protege
   el query (p. ej. `ver:cargas`).
3. **Columnas** — lista en orden de aparición, con etiqueta visible de cada una
   (p. ej. `fila_origen → "Fila"`). Si el usuario dice "los primeros N campos de
   la vista", listalos y confirmalos.
4. **Ubicación** — feature carpeta + nombre del componente (default:
   `<feature>/ui/<tabla>.svelte`).

**Optional (each has a default — only ask when the user's request hints
otherwise):**

5. **Export a Excel** — default: sí. Columnas sin `meta.export` quedan fuera
   del archivo; confirmar si alguna debe excluirse (p. ej. acciones).
6. **Filtros por columna** — default: texto (`includesString`) en columnas de
   búsqueda natural; faceta en enums/booleanos; sin filtro en el resto.
   Rango de fechas si hay columnas de fecha.
7. **Búsqueda global** — default: sí.
8. **Orden inicial** — default: primera columna, asc.
9. **Paginación** — default: 50 por página, opciones 50/100/200/500.
10. **Cap del fetch-once** — default: 5000 filas con badge de truncado. Preguntar
    solo si el total esperado puede rozar el cap.
11. **Selección batch** — default: no. Si sí: cuáles acciones batch (ver receta
    "Row selection" en `column-recipes.md`).
12. **Detalle por fila** — default: no. Si sí: ¿Sheet lateral con qué contenido?
    (ver receta "Detail side-sheet" en `column-recipes.md`).
13. **Cache stale-while-revalidate** — default: no (solo queries lentas con
    filtros que se repiten; ver `references/caching.md`). Incompatible con
    kanban sin trabajo extra.
14. **Fila destacada condicional** — default: no. Si sí: qué condición resalta
    la fila (p. ej. filas con errores → fondo suave).
15. **Agrupar por** — default: sí, en las columnas de faceta (enums, booleanos,
    categorías); nunca en fechas, ids, montos ni texto libre. Agregados por
    defecto: suma en montos, fecha máxima en fechas. Preguntar solo si hay una
    columna categórica que NO deba agruparse o un agregado distinto.
16. **Vistas** — default: solo tabla. Ofrecer **cards** (grilla paginada) y
    **kanban** (tablero por una columna). Si el usuario pide kanban o tablero:
    ¿qué columna define los carriles y en qué orden?
17. **Mover tarjetas en kanban** — default: no (tablero de solo lectura). Si
    sí: ¿qué `command` actualiza la columna del carril (nombre, permiso)?
    Entonces la fila necesita `id` y el command llama
    `requested(<query>, N).refreshAll()`.

Record the resolved spec — **always, no exceptions** — as a comment block at
the top of the table component using this template. It is the contract the
GENERATE blocks implement and the preset source for future tables:

```
<!--
  SPEC (contrato del cuestionario bt1 — Step 0)
  fuente:     vi_ejemplo · guard: ver:ejemplos
  columnas:   id→"ID", nombre→"Nombre", estado→"Estado", fecha→"Fecha"
  filtros:    nombre texto · estado faceta · fecha rango
  export:     sí (todas) · búsqueda global: sí
  orden:      fecha desc · paginación: 50 [50,100,200,500] · cap: 5000
  agrupar:    estado, nombre · vistas: tabla, kanban(estado → set_estado)
  batch:      no · detalle: sheet lateral · cache: no · fila destacada: no
  =====
  resolvido:  2026-XX-XX con el usuario ("todo ok" sobre defaults, salvo N)
-->
```

### Step 1 — Set up the data-table module

TanStack Table v9 ships a native Svelte 5 adapter: there is **no local adapter
to copy anymore**. `createTable`, `tableFeatures`, `FlexRender`,
`renderComponent`, `renderSnippet`, `createTableState`, the `*Feature` imports,
the `create*RowModel` factories and the built-in `filterFn_*` / `sortFn_*` /
`aggregationFn_*` all come straight from `@tanstack/svelte-table`.

v9 typing gotchas the assets already handle (don't regress them):

- The state slice is `ColumnVisibilityState` (v8's `VisibilityState` no longer
  exists).
- Generic reusable components (the column header) must type the column as
  `Column<TableFeatures, TData, TValue>` — with an unconstrained `TFeatures`
  the feature-gated APIs resolve to an unqueryable union. Callers with concrete
  features cast `column as any` at the `renderComponent` boundary.
- `table-export.ts` reads `meta.export` through a structural cast: per-table
  meta unions include plain `object`, so `c.columnDef.meta?.export` alone
  doesn't type-check.

Copy into `src/lib/components/ui/data-table/` (create it if absent):

| From `assets/` | Purpose |
|---|---|
| `data-table-column-header.svelte` | Per-column sort + filter UI |
| `table-prefs.svelte.ts` | Column visibility/order as external atoms + localStorage; `moveTo` for header drag-and-drop |
| `table-export.ts` | XLSX export driven by column meta |
| `table-meta.d.ts` | Augments tanstack `ColumnMeta` with `export` config |

If the project **already has** a v8-era `$lib/components/ui/data-table/`
(`createSvelteTable`, `flex-render.svelte`, `render-helpers.ts`,
`data-table.svelte.ts`), it is incompatible with v9: delete those adapter files
and import from `@tanstack/svelte-table` instead. Keep (or re-add) the four
files from the table above.

`assets/idb-cache.ts` is **only** for the optional cache (Step 4) — skip it now.

After copying, open `data-table-column-header.svelte` and translate the four
strings in the `STRINGS` block to the project's language (the source is English;
this project's UI is Spanish — `Filtrar…`, `Sin resultados.`, `Limpiar filtros`,
`a`). It is the only baked-in copy there; the table template's toolbar labels
("Group", "Columns", "Export Excel", "Expand all"…) are translated in place.

### Step 2 — The row type and remote functions

Decide the feature folder (e.g. `src/lib/features/<feature>/`). Then:

1. In `types.ts`, define the **row type** (`id: string` first, then one field
   per column, all nullable as the DB allows) and the **result type** —
   `{ rows, total, returned, truncated, cap }`.
2. In `data.remote.ts`, write the `query`. **Read `references/remote-function.md`**
   — it has the count-then-capped-fetch template and explains the `truncated`
   flag. Wire the project's auth and any row-level security.
3. If the spec has kanban moves (item 17) or batch actions, add the
   `command`(s) from the same file — including the
   `await requested(get_x, 10).refreshAll()` line. Without it the UI snaps
   back after every write.

### Step 3 — The table component

Copy `references/EXAMPLE-Table.svelte` to
`<feature>/ui/components/<Feature>Table.svelte` and adapt the five
`── GENERATE` blocks: the row type, the column definitions, the
ids/labels/defaults arrays, the views (`VIEWS` + `KANBAN`), and the `card`
snippet. Everything else is fixed boilerplate — including the `features`
object (v9: declare exactly the features, row models and fns the table uses;
the registered set covers every recipe in the catalogue, so leave it as-is),
the state wiring (`createTableState` getters + per-slice `on*Change`;
`prefs.atoms` external atoms for visibility/order), the grouping getter that
the views drive, and `autoResetExpanded: false` (required — see `views.md`).

**Read `references/column-recipes.md`** before writing columns — it is the
catalogue of cell renderers, the four filter types, sorting and
grouping/aggregation notes, and the **HTML-escaping rule that prevents stored
XSS** in cells. That rule is not optional; cells inject raw HTML.

**Read `references/views.md`** for grouping, header drag-and-drop, cards and
kanban: what each view reads from the table, the `KANBAN` contract, the
`onMove` prop, and — when the spec says "solo tabla" — exactly which blocks to
delete. Don't leave an unused kanban in a table that has no lane column.

### Step 4 — The page and route

1. Copy `references/EXAMPLE-Page.svelte` to `<feature>/ui/<Feature>Page.svelte`
   and adapt the filter resolution, the props and the mutations. The data
   flow is `const q = $derived(get_x(filters))` + `q.current` — no `$effect`,
   no cancellation flags: each filter set is its own query instance, so a slow
   old response can't overwrite a new one. Kanban moves call the command with
   `.updates(q.withOverride(...))` (optimistic, then refreshed).
2. Create the route: a thin `+page.svelte` that wraps the page component in
   `<svelte:boundary>` with a `pending` snippet. If the route needs auth or a
   `load`, follow the project's routing conventions.
3. **If — and only if — the query is slow and users revisit the same filters**,
   add the stale-while-revalidate cache: **read `references/caching.md`**. It is
   opt-in; the plain page is the right default. (The user chose "optional,
   documented" for this skill — so default to no cache unless asked or unless
   the query is clearly heavy.)

### Step 5 — Verify

- Run the project's type-checker (e.g. `pnpm check:machine` / `svelte-check`)
  and fix every error. The `column as any` casts in column defs are expected
  tanstack/Svelte generics friction — leave those.
- If a Svelte MCP server is available, run `svelte-autofixer` on the new
  components and apply its fixes.
- Sanity-check in the browser: sort a column, open each filter type, type in
  the global search, toggle a column off in the "Columns" popover and reload
  (it should stay off), drag a header grip onto another header, export to
  Excel. Then the views checklist at the end of `views.md` (group + expand,
  cards, kanban search + drag). Type-check alone does not catch UI bugs — the
  `autoResetExpanded` and `requested()` requirements were both found only in
  the browser.

## Design notes — keep these intact

The reference files explain the reasoning; the short version:

- **One fetch, client-side everything.** Filtering/sorting/grouping/paging
  never hit the server, so they are instant. The `cap` + `truncated` badge is
  the safety valve for oversized result sets. Good to ~tens of thousands of
  rows — see `remote-function.md` for when to reach for real server pagination
  instead.
- **One tanstack instance, three views.** Cards and kanban are renderers over
  the same row models — the search box, filters and sort apply to all of them
  and there is no second pipeline to keep in sync. Kanban lanes are literally
  `grouping = [laneColumn]`; cards are the paginated leaf rows.
- **Escape every dynamic value in a raw cell.** Cells render raw HTML strings;
  an unescaped DB value is a stored-XSS hole. `txt()`/`bool()`/`dateHtml()`/
  `amountHtml()` escape for you. Svelte snippets (the card) escape themselves.
- **Reads are queries, writes are commands, and the command refreshes.**
  `.updates(q.withOverride(...))` on the client only *asks*; the server must
  answer with `requested(get_x, N).refreshAll()`. Skip it and the optimistic
  move reverts.
- **`createTablePrefs` over hand-rolled state.** It replaces ~80 lines of
  visibility/order/localStorage boilerplate that used to be copied per table.
  In v9 the two slices are external atoms: the table writes them directly
  (no `on*Change` wiring), the module subscribes for persistence. Header
  drag-and-drop is native HTML5 on the grip — no DnD library.
- **`meta.export` over a second mapping.** The XLSX is built from the column
  defs, so it can't drift out of sync with the table. Grouping doesn't affect
  it (leaf rows only).
- **Feature-gated on purpose.** v9's `tableFeatures()` lists only what the
  table uses (sorting, filtering, faceting, global search, grouping,
  expanding, aggregation, pagination, visibility, ordering) and only the
  string fns it references (`includesString`, `datetime`, `sum`, `max`) —
  unused feature code never ships to the client.
- **`autoResetExpanded: false` is load-bearing** with grouping on
  svelte-table 9.2.x; the adapter's option sync would otherwise collapse a
  group the moment it is expanded.
- **Never hand-write interactive row cells as HTML.** Buttons, links and
  checkboxes are `renderComponent` with a real Svelte component — see the
  "Row-level interactions" recipes in `column-recipes.md` (selection → batch
  actions, detail side-sheet).
- **Theming belongs to the project, not the table.** Two rules the templates
  rely on:
  - Column-header titles are rendered small-caps by the column-header
    component (`uppercase tracking-wide`), so callers can pass titles in any
    case and the table stays uniform.
  - Tailwind v4 defaults `border-color` to `currentColor`: without the shadcn
    `@layer base { * { @apply border-border outline-ring/50; } }` reset in the
    project CSS, bare `border-b` row dividers inherit the text color and glow
    near-white in dark mode. If dividers look too bright, fix the reset in the
    project CSS — never per-component overrides.
- **`$derived` for the query, `$derived` for the rest.** `get_x(filters)` is
  synchronous (it returns the query object); its `.current` is reactive. The
  only `$effect` left in the stack is the optional SWR cache.

## Reference files

| File | Read it when |
|---|---|
| `references/remote-function.md` | Writing `data.remote.ts` — query and commands (Step 2) |
| `references/column-recipes.md` | Writing column definitions (Step 3) |
| `references/views.md` | Grouping, header DnD, cards, kanban — and what to delete (Step 3) |
| `references/caching.md` | Adding the optional SWR cache (Step 4) |
| `references/EXAMPLE-Table.svelte` | The table component to copy + adapt |
| `references/EXAMPLE-Page.svelte` | The page component to copy + adapt |

## Evals

See `evals/` for trigger and quality evals. Run them after changing the
description or the build steps — a skill that triggers on the wrong prompts or
generates tables that miss the intake spec is worse than no skill.
