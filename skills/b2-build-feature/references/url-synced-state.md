# URL-Synced Reactive State (Context API + Svelte 5 Runes)

Pattern for **page-level state that lives in the URL** (filters, current selection, current tab, current month, etc.) and needs to be readable from descendant components **without prop-drilling**.

This is the canonical Svelte 5 use case for `setContext` / `getContext` — combined with `$derived` and a class with private getters, you get URL-bookmarkable state that auto-updates everywhere it's read, with no `goto()` and no full page reload.

## When to use this pattern

- A page has a "current X" (month, tab, filter) that:
  - Should be in the URL (bookmarkable, shareable, browser back/forward works).
  - Is read by 3+ descendant components.
  - Changes shouldn't trigger a full server load.

If only ONE component reads the state, just use `$state` locally. If 2 components need it, prop-drill once. Context is for 3+ levels or 3+ consumers.

## When NOT to use this pattern

- **State that doesn't belong in the URL** — drawer open/closed, hover state, form draft. Use `$state` locally.
- **State that DOES need a server reload** — auth-affecting filters, country switch, or anything that depends on `+page.server.ts` re-running. Use `goto(url)` (the rare legitimate case for `goto`).
- **Single consumer** — just bind props.

## Anti-patterns this replaces

```svelte
<!-- WRONG: full page reload on every change -->
<Button href="?month={prevMonth}">Anterior</Button>

<!-- WRONG: invalidate dance + `goto` chain -->
<Button onclick={() => { goto(`?month=${prev}`); invalidate('list:month') }}>...</Button>

<!-- WRONG: prop-drilling currentMonth through 4 levels -->
<Page {currentMonth}>
  <Filters {currentMonth}>
    <DateChip {currentMonth} />
  </Filters>
</Page>
```

## The pattern (3 pieces)

### 1. The context class (`<feature>-context.svelte.ts`)

```ts
import { createContext } from 'svelte'

export class MonthCtx {
  // Private getters — closures captured at construction.
  // The class doesn't own the state, it READS it via these closures
  // so the source of truth stays in the page component.
  #getMonth: () => string = () => ''
  #setMonth: (m: string) => void = () => {}

  // Public reactive properties — re-derive when their sources change.
  month = $derived(this.#getMonth())
  prev = $derived(offsetMonth(this.month, -1))
  next = $derived(offsetMonth(this.month, 1))
  label = $derived(formatMonthLabel(this.month))

  constructor(getMonth: () => string, setMonth: (m: string) => void) {
    this.#getMonth = getMonth
    this.#setMonth = setMonth
  }

  // Public actions — descendant components call these to mutate.
  goPrev() { this.#setMonth(this.prev) }
  goNext() { this.#setMonth(this.next) }
  set(m: string) { this.#setMonth(m) }
}

// Svelte 5.37+ idiom — typed get/set tuple in one call.
export const [getMonthContext, setMonthContext] = createContext<MonthCtx>()
```

### 2. The page root — owns state, instantiates context

```svelte
<script lang="ts">
import { untrack } from 'svelte'
import { page } from '$app/state'
import { pushState } from '$app/navigation'
import { MonthCtx, setMonthContext } from './month-context.svelte'
import { get_items } from './<feature>.remote'

// `data.initialMonth` resolved server-side from URL or default.
// `untrack` so we only initialize once — subsequent prop updates don't reset.
let { data }: { data: { initialMonth: string } } = $props()
let currentMonth = $state(untrack(() => data.initialMonth))

function setMonth(m: string) {
  if (m === currentMonth) return
  currentMonth = m
  // pushState updates the URL (bookmarkable, browser back works)
  // WITHOUT re-running +page.server.ts. The remote query reacts.
  const url = new URL(page.url)
  url.searchParams.set('month', m)
  pushState(url, {})
}

// Closures over $state — context reads via these, so it stays in sync.
setMonthContext(new MonthCtx(() => currentMonth, setMonth))

// Remote query keyed by argument — re-runs when currentMonth changes,
// cached per argument so revisiting a month is instant.
const itemsPage = $derived(await get_items({ month: currentMonth }))
</script>

<svelte:boundary>
  {#snippet pending()}<Spinner />{/snippet}
  <ItemList items={itemsPage.items} />
</svelte:boundary>
```

### 3. Descendants — read context, no props

```svelte
<!-- month-bar.svelte -->
<script lang="ts">
import { getMonthContext } from './month-context.svelte'
const ctx = getMonthContext()
</script>

<button onclick={() => ctx.goPrev()}>{ctx.prevLabel}</button>
<span>{ctx.label}</span>
<button onclick={() => ctx.goNext()}>{ctx.nextLabel}</button>
```

```svelte
<!-- copy-dialog.svelte — even deeper, still no prop-drilling -->
<script lang="ts">
import { getMonthContext } from './month-context.svelte'
const month = getMonthContext()
const targetMonth = $derived(month.next)
</script>

<p>Copiar de <strong>{month.label}</strong> a <strong>{month.nextLabel}</strong></p>
```

## Why this works

1. **Single source of truth.** State lives in `$state` on the page. The context class is a *projection* of that state — it doesn't store, it derives.
2. **No staleness.** `$derived(this.#getMonth())` re-runs whenever `currentMonth` changes. Every consumer sees the new value automatically.
3. **No prop drilling.** Components 4 levels deep call `getMonthContext()` and read `ctx.label` directly.
4. **URL stays in sync.** `pushState` writes to the URL; browser back/forward and bookmarking work.
5. **No server reload.** `pushState` ≠ `goto` — `+page.server.ts` does NOT re-run. The remote query (`get_items`) re-runs on its own because it's `$derived` over the changing argument.
6. **Cached navigation.** Remote queries cache by argument, so revisiting a month/tab is instant — no spinner, no refetch.

## Why a class with getters (vs. a plain object)

Classes let you have **private state via closures** (`#getMonth`) and **public reactive properties** (`$derived`). A plain object with `$derived` works for read-only context, but you can't easily expose actions (`goPrev`, `set`) that mutate the page's `$state` without leaking the setter everywhere.

The closure pattern is the trick: the class is constructed inside the page, with closures over the page's `$state` and `setMonth`. Descendants get a typed handle to the same state without ever seeing the underlying `$state` variable.

## Common variants

- **Tab state** — `ActiveTabCtx` with `tab`, `setTab(t)`, optional URL hash sync
- **Filter state** — `FilterCtx` with `q`, `setQ(s)`, multi-select arrays
- **Selected entity** — `SelectedDealCtx` with `deal`, `select(id)`, `clear()`

## Checklist when implementing

- [ ] Context class file ends in `.svelte.ts` (so runes work outside .svelte)
- [ ] Page owns the `$state`, context is constructed with closures
- [ ] `setContext` called on page root, BEFORE rendering descendants
- [ ] `pushState` (not `goto`) for URL sync — no server reload
- [ ] Initial state read from `data.*` (server-resolved) wrapped in `untrack`
- [ ] Remote query is `$derived(await fn({ ...currentState }))` — re-runs on change
- [ ] Page wraps async content in `<svelte:boundary>` with `pending` / `failed` snippets
- [ ] Descendants import only `getXContext` — never the class or setter

## Reference implementation

See `seguimiento-comercial` feature, specifically:

- `month-context.svelte.ts` — the context class
- `seguimiento-page.svelte` — page root that owns state + instantiates ctx
- `month-bar.svelte` — descendant that reads context
- `copy-deals-dialog.svelte` — deeply-nested descendant that reads context
