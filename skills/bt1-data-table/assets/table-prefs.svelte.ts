import { createAtom, useSelector } from '@tanstack/svelte-store'
import type { ColumnVisibilityState } from '@tanstack/svelte-table'

interface TablePrefsOptions {
  /** localStorage key — must be unique per table. */
  storageKey: string
  /** Every column id, in their natural declaration order. */
  columnIds: string[]
  /** Column ids visible by default. Everything else starts hidden. */
  defaultVisible: string[]
}

/**
 * Column visibility + ordering, owned outside the table and persisted to
 * localStorage via TanStack Table v9 external atoms.
 *
 * The atoms are passed to `createTable` through the `atoms` option, so the
 * table writes these two state slices directly into them — no
 * onColumnVisibilityChange / onColumnOrderChange handlers. This module
 * subscribes for persistence and exposes rune-reactive reads for the
 * "Columns" popover.
 *
 * Wire it into the table like this:
 *
 *   const prefs = createTablePrefs({ storageKey: 'mytable_cols', columnIds, defaultVisible })
 *
 *   const table = createTable({
 *     features,
 *     ...,
 *     atoms: prefs.atoms, // columnVisibility + columnOrder
 *   })
 *
 * `orderedIds` drives the "Columns" popover (checkbox list + reorder arrows).
 *
 * Must be called during component init — it registers `$effect`s for saving.
 */
export function createTablePrefs(opts: TablePrefsOptions) {
  const { storageKey, columnIds, defaultVisible } = opts

  const buildDefaultVisibility = (): ColumnVisibilityState => Object.fromEntries(columnIds.map(id => [id, defaultVisible.includes(id)]))

  // Hydrate from localStorage, falling back to defaults. Unknown column ids
  // (renamed/removed since the prefs were saved) are dropped from `order`.
  let initialVisibility = buildDefaultVisibility()
  let initialOrder: string[] = []
  if (typeof localStorage !== 'undefined') {
    try {
      const raw = localStorage.getItem(storageKey)
      if (raw) {
        const parsed = JSON.parse(raw)
        if (parsed.visibility) initialVisibility = parsed.visibility
        if (Array.isArray(parsed.order)) initialOrder = parsed.order.filter((id: string) => columnIds.includes(id))
      }
    } catch {
      // corrupt entry — ignore, use defaults
    }
  }

  const visibilityAtom = createAtom<ColumnVisibilityState>(initialVisibility)
  const orderAtom = createAtom<string[]>(initialOrder)

  // Rune-reactive holders — a raw atom's `.get()` is not Svelte-tracked.
  const visibility = useSelector(visibilityAtom)
  const order = useSelector(orderAtom)

  // `columnIds` rearranged by the saved `order`; new/unordered ids append in
  // declaration order so a column added later never disappears.
  const orderedIds = $derived(
    order.current.length > 0
      ? [...order.current.filter(id => columnIds.includes(id)), ...columnIds.filter(id => !order.current.includes(id))]
      : [...columnIds]
  )

  $effect(() => {
    localStorage.setItem(storageKey, JSON.stringify({ visibility: visibility.current, order: order.current }))
  })

  function move(id: string, dir: -1 | 1) {
    const ids = orderedIds
    const idx = ids.indexOf(id)
    const next = idx + dir
    if (idx < 0 || next < 0 || next >= ids.length) return
    const arr = [...ids]
    ;[arr[idx], arr[next]] = [arr[next], arr[idx]]
    orderAtom.set(arr)
  }

  // Drop `id` onto `targetId`: lands after the target when dragged rightwards,
  // before it when dragged leftwards (what a header drag-and-drop expects).
  function moveTo(id: string, targetId: string) {
    if (id === targetId) return
    const arr = orderedIds.filter(x => x !== id)
    const to = orderedIds.indexOf(targetId)
    if (to < 0 || !orderedIds.includes(id)) return
    arr.splice(to, 0, id)
    orderAtom.set(arr)
  }

  return {
    /** Spread into `createTable`'s `atoms` option — the table owns the writes. */
    atoms: { columnVisibility: visibilityAtom, columnOrder: orderAtom },
    /** Reactive visibility read — drives the popover checkboxes. */
    get visibility() {
      return visibility.current
    },
    setVisibility(v: ColumnVisibilityState) {
      visibilityAtom.set(v)
    },
    /** Column ids in display order — drives the "Columns" popover. */
    get orderedIds() {
      return orderedIds
    },
    moveUp: (id: string) => move(id, -1),
    moveDown: (id: string) => move(id, 1),
    /** Drag-and-drop reorder: place `id` at `targetId`'s slot. */
    moveTo,
    /** Restore default visibility and clear custom ordering. */
    reset() {
      visibilityAtom.set(buildDefaultVisibility())
      orderAtom.set([])
    },
  }
}
