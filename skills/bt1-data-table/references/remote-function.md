# The remote functions

The table is fed by **one** remote `query` that returns the full result set (up
to a cap) in a single shape. All sorting, filtering, grouping, paging and export
then happen client-side over that array — see
[when-to-use](#when-this-pattern-fits). Writes that the views need (kanban
moves, batch actions) are remote `command`s that refresh that same query.

## The return shape

Always return this object — the page and table depend on every field:

```ts
interface OrdersResult {
  rows: OrderRow[]   // the data, already mapped to the UI row type
  total: number      // total rows matching the filters, BEFORE the cap
  returned: number   // rows.length — rows actually sent
  truncated: boolean // total > cap — the page shows a "narrow your filters" badge
  cap: number        // the row limit, surfaced so the badge can name it
}
```

`total` vs `returned` is what powers the truncation warning. Without it the user
silently gets a partial dataset and trusts it. Count first, then fetch.

**Every row needs a stable `id`** (the primary key, as a string). The table
uses it as `getRowId` — keys for rows, cards and expanded groups — and the
commands use it to address the row. Never rely on the array index.

## The query

```ts
import { query, command, requested } from '$app/server'
import { z } from 'zod'
import { db } from '$lib/server/db'
import { orders } from '$lib/server/db/schema'
import { and, count, desc, eq, gte, lte, type SQL } from 'drizzle-orm'
import type { OrdersResult, OrderRow } from './types'
// import your project's auth + security helpers

const CAP = 50_000

// Validate every input. dateStr keeps malformed dates out of the query.
const dateStr = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Invalid date (YYYY-MM-DD)')
const filtersSchema = z.object({
  from: dateStr,
  to: dateStr,
  // ...other optional filters
})

export const get_orders = query(filtersSchema, async (params): Promise<OrdersResult> => {
  // 1. AUTH — follow the project's pattern (requireUser / requirePermission / etc.)
  //    Apply row-level security here too, before any data leaves the server.

  // 2. WHERE — build conditions from the validated filters.
  const conds: SQL[] = [gte(orders.fechaProceso, params.from), lte(orders.fechaProceso, params.to)]
  const where = and(...conds)

  // 3. COUNT first — cheap, and it tells us whether to warn about truncation.
  const [countRow] = await db.select({ n: count() }).from(orders).where(where)
  const total = Number(countRow?.n ?? 0)
  if (total === 0) return { rows: [], total: 0, returned: 0, truncated: false, cap: CAP }

  // 4. FETCH — capped. orderBy gives a stable default order for the table.
  const truncated = total > CAP
  const dbRows = await db.select({ /* exact columns the row type needs */ }).from(orders).where(where).orderBy(desc(orders.createdAt)).limit(CAP)

  // 5. MAP — db row -> UI row type. Coerce anything the client shouldn't see raw
  //    (e.g. JSON columns) to a plain string here. `id` must be a string.
  const rows: OrderRow[] = dbRows.map(r => ({ id: String(r.id), /* ... */ }))

  return { rows, total, returned: rows.length, truncated, cap: CAP }
})
```

## The command (kanban move, batch actions)

One `command` per write. Same auth as the query, same Zod trust boundary, and
**it must opt in to refreshing the query** — that is what makes the kanban
card stay where it was dropped:

```ts
export const set_channel = command(
  z.object({ id: z.string(), channel: z.enum(['web', 'phone', 'store']) }),
  async ({ id, channel }) => {
    // 1. AUTH — same guard as the query (or a stricter one: editar:pedidos).
    // 2. WRITE
    await db.update(orders).set({ channel }).where(eq(orders.id, Number(id)))
    // 3. REFRESH — re-run the get_orders instances the client asked for in
    //    `.updates(...)` and ship their fresh rows back in THIS response
    //    (single-flight mutation: no second round-trip, no invalidateAll).
    await requested(get_orders, 10).refreshAll()
    return { ok: true }
  }
)
```

How the pieces fit (SvelteKit 2.70, verified):

- Client: `set_channel(args).updates(q.withOverride(fn))` — applies `fn` to
  the query's current value immediately (optimistic) and tells the server which
  query instances to refresh.
- Server: `requested(get_orders, limit)` yields those instances;
  `.refreshAll()` re-runs them and attaches the results to the response.
  Instances beyond `limit` are rejected with a 400 *and put in a failed state*,
  so pick a limit ≥ the number of `get_orders(...)` instances mounted on the
  page (one per distinct filter set; `10` is a safe ceiling).
- **Without the server call, nothing refreshes**: the override is released when
  the command resolves and the UI snaps back to the stale rows.

Alternative when the command knows the exact args: `await get_orders(params).refresh()`
on the server has the same effect for that one instance.

## When this pattern fits

This is a **fetch-once, explore-offline** table. Client-side filtering means
every keystroke is instant — no round-trip — and export covers the whole set.

- **Good fit:** up to ~tens of thousands of rows. tanstack handles 10k–50k
  comfortably; the cap is the safety valve. Tune `CAP` to the data — start at
  `50_000`, lower it if a row is wide or the page feels heavy. The kanban view
  shows every filtered row (no pagination), so boards with thousands of cards
  per lane want a lower cap or tighter page filters.
- **Not a fit:** millions of rows, or data that must be paged on the server.
  Then build true server-side pagination instead — a different pattern, not
  this skill. (The project's CLAUDE.md notes the general rule: client filtering
  for small sets, server for "miles de registros o paginación real". This table
  is the deliberate middle ground — a bounded export/exploration tool.)

## Notes

- **Validate everything** with the Zod schema. The remote functions are public
  endpoints; the schema is the trust boundary.
- **Map db → UI type** explicitly. Don't leak raw db column shapes to the
  client; the `OrderRow` type is the contract the table is built against.
- Follow the project's existing remote-function conventions for auth and
  errors. If the project has a `using-remote-functions` skill or
  `.remote.ts` files already, match them.
