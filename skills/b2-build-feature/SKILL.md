---
name: b2-build-feature
# prettier-ignore
description: End-to-end SvelteKit feature development. Use ALWAYS when building new features, CRUD screens, forms, dashboards, data pages, or any UI that reads/writes data. Covers planning, implementation (remote functions + Svelte 5 + Drizzle + shadcn-svelte), and browser verification. Prevents React anti-patterns. Triggers on "build feature", "create page", "new screen", "CRUD", "implement", "agregar modulo", "crear pantalla", "necesito una pagina", "add feature for", "build me a". Use even when the user just describes a screen or data operation without saying "feature".
---

# Build Feature

SvelteKit features are SMALL. Typical feature = 3-5 files, 15-35 KB total.
No unnecessary layers. The shortest path: **Drizzle query -> remote function -> Svelte component**.

## Two Entry Points

This skill has two starting paths:

1. **Direct user input** — the user describes a feature in the terminal. Proceed to Phase 0.
2. **GitHub issue** — the user references an issue number (e.g., "build issue #42"). Before building, the issue should have been triaged with `b1-triage-issue`. If it hasn't, run triage first. When an issue number is present, read the full issue context (body + ALL comments) at the start of Phase 1 — decisions and clarifications live in the comments, not just the description.

## STOP: You Are Not Writing React

These mistakes happen every single time. Read this table before writing ANY code:

| About to write (WRONG)                            | Write this instead (CORRECT)                                                      |
| ------------------------------------------------- | --------------------------------------------------------------------------------- |
| `const [val, setVal] = useState()`                | `let val = $state(initial)`                                                       |
| `onChange={(e) => setVal(e.target.value)}`        | `{...form.fields.name.as('text')}` in forms; `bind:value` only for non-form state |
| `onSubmit={e => { e.preventDefault(); fetch() }}` | `form.enhance()` — see Form Trap below                                            |
| `useEffect(() => { fetch('/api/') }, [])`         | `$derived(await get_items())`                                                     |
| `<button onClick={handler}>`                      | `<button onclick={handler}>`                                                      |
| `on:click={handler}` (Svelte 4)                   | `onclick={handler}`                                                               |
| `export let data` (Svelte 4)                      | `let { data } = $props()`                                                         |
| `$: computed = x * 2` (Svelte 4)                  | `let computed = $derived(x * 2)`                                                  |
| `<slot />`                                        | `{@render children()}`                                                            |
| `try { error(401) } catch {}`                     | Just `error(401, {...})` — it throws by design                                    |
| `return { status: 401 }`                          | `error(401, { message: '...', code: '...' })`                                     |
| `import { Card } from 'ui/card'`                  | `import * as Card from '$lib/components/ui/card'`                                 |
| `<Select.Value>text</Select.Value>`               | `<Select.Trigger placeholder="text" />` (Value missing)                           |
| `<Button onClick={() => goto('/x')}>`             | `<Button href="/x">`                                                              |
| `const doubled = useMemo(() => x*2, [x])`         | `let doubled = $derived(x * 2)`                                                   |
| Separate create + edit forms                      | ONE upsert form with optional `id`                                                |

For the comprehensive React-to-Svelte guide, read `references/svelte5-not-react.md`.

### The Form Trap (Your #1 Error Source)

React trains you to handle forms with onSubmit + preventDefault + state + fetch. **SvelteKit remote functions handle all of that for you:**

```svelte
<!-- WRONG: React form handling -->
<script>
  let name = $state('')
  async function handleSubmit(e) {
    e.preventDefault()
    await fetch('/api/users', { method: 'POST', body: JSON.stringify({ name }) })
  }
</script>
<form onsubmit={handleSubmit}>
  <input bind:value={name} />
  <button>Save</button>
</form>

<!-- CORRECT: SvelteKit remote function form -->
<script>
  import { upsert_user, get_users } from './data.remote'
  import { toast } from 'svelte-sonner'
</script>
<form {...upsert_user.enhance(async ({ form, submit }) => {
  try {
    await submit().updates(get_users)
    form.reset()
    toast.success('Saved')
  } catch { toast.error('Error') }
})}>
  <input {...upsert_user.fields.name.as('text')} placeholder="Name" />
  <button type="submit">Save</button>
</form>
```

To edit existing records, pre-populate:

```typescript
function editItem(item) {
  upsert_user.fields.set({id: item.id, name: item.name})
}
```

## Workflow: 4 Phases

### Phase 0: Branch

**ALWAYS create a branch before writing any code.** Never work on master.

When working from a GitHub issue, include the issue number in the branch name:

```bash
git checkout -b feat/<issue-number>-<feature-name>    # e.g., feat/42-product-crud
git checkout -b fix/<issue-number>-<description>      # e.g., fix/87-login-redirect
```

When working from direct user input (no issue):

```bash
git checkout -b feat/<feature-name>    # new feature
git checkout -b fix/<description>      # bug fix
```

For complex features that need isolation, use a worktree:

```bash
git worktree add ../worktrees/<feature> -b feat/<feature-name>
```

### Phase 1: Clarify

**If working from a GitHub issue**, read the full context first:

```bash
gh issue view <NUMBER> --json number,title,body,comments,labels
```

Read ALL comments — not just the body. Clarifications, scope changes, and decisions often happen in the comment thread. If the issue was triaged by `b1-triage-issue`, there will be an evaluation comment with affected files, complexity estimate, and a proposed plan. Use that as your starting point.

**If the user described the feature directly**, and the request is already clear (entity, operations, screens), skip to Phase 2.

Otherwise, confirm in 1-2 questions:

1. **What entity?** Fields, types, relationships
2. **What operations?** List + Create/Edit + Delete? Filters? Pagination?

Then propose the file structure:

```
src/lib/features/<feature>/
  types.ts                   # Types from Drizzle schema
  data.remote.ts             # query + form + command
  ui/<Feature>Page.svelte    # Main component

src/routes/[country]/<feature>/
  +page.svelte               # Thin wrapper
```

Only add more files when justified:

- `schemas.ts` — only if validation is complex (beyond basic required/type checks)
- `server/service.server.ts` — only if there is real business logic (rules, orchestration), NOT for simple CRUD
- `server/repo.server.ts` — only if queries are reused by multiple remote functions

### Phase 2: Build

Write files in this exact order. Use absolute paths, avoid cd.

**Step 1: Types** (`types.ts`)

```typescript
import type {InferSelectModel} from 'drizzle-orm'
import {taProducts} from '$lib/server/db/schema'
export type Product = InferSelectModel<typeof taProducts>
```

If the DB table does not exist, create the Drizzle schema first. Read `drizzle-best-practices` skill for patterns.

**Step 2: Remote Functions** (`data.remote.ts`)
The CORE file. Every data operation the UI needs goes here:

```typescript
import {query, form, command} from '$app/server'
import {z} from 'zod'
import {requireAuthUser} from '$lib/server/auth-helpers'
import {db} from '$lib/server/db'
import {taProducts} from '$lib/server/db/schema'
import {eq} from 'drizzle-orm'

export const get_products = query(async () => {
  requireAuthUser()
  return db.query.taProducts.findMany({
    orderBy: (t, {desc}) => [desc(t.createdAt)],
  })
})

const upsertSchema = z.object({
  id: z.string().optional(),
  name: z.string().min(1, 'Requerido'),
  price: z.number().min(0),
})

export const upsert_product = form(upsertSchema, async data => {
  requireAuthUser()
  if (data.id) {
    const [updated] = await db.update(taProducts).set(data).where(eq(taProducts.id, data.id)).returning()
    return updated
  }
  const [created] = await db.insert(taProducts).values(data).returning()
  return created
})

export const delete_product = command(z.object({id: z.string()}), async ({id}) => {
  requireAuthUser()
  await db.delete(taProducts).where(eq(taProducts.id, id))
})
```

**Step 3: Page Component** (`ui/<Feature>Page.svelte`)

```svelte
<script lang="ts">
import {get_products, upsert_product, delete_product} from '../data.remote'
import * as Card from '$lib/components/ui/card'
import * as Table from '$lib/components/ui/table'
import {Button} from '$lib/components/ui/button'
import {Input} from '$lib/components/ui/input'
import {toast} from 'svelte-sonner'

const products = $derived(await get_products())

async function handleDelete(id: string) {
  await delete_product({id})
  get_products.refresh()
  toast.success('Deleted')
}

function editProduct(item: (typeof products)[0]) {
  upsert_product.fields.set({id: item.id, name: item.name, price: item.price})
}
</script>

<div class="space-y-6">
  <Card.Root>
    <Card.Header>
      <Card.Title>Products</Card.Title>
    </Card.Header>
    <Card.Content>
      <Table.Root>
        <Table.Header>
          <Table.Row>
            <Table.Head>Name</Table.Head>
            <Table.Head>Price</Table.Head>
            <Table.Head class="w-24"></Table.Head>
          </Table.Row>
        </Table.Header>
        <Table.Body>
          {#each products as product (product.id)}
            <Table.Row>
              <Table.Cell>{product.name}</Table.Cell>
              <Table.Cell>{product.price}</Table.Cell>
              <Table.Cell>
                <Button size="sm" variant="ghost" onclick={() => editProduct(product)}>Edit</Button>
                <Button size="sm" variant="ghost" onclick={() => handleDelete(product.id)}>Delete</Button>
              </Table.Cell>
            </Table.Row>
          {/each}
        </Table.Body>
      </Table.Root>
    </Card.Content>
  </Card.Root>

  <Card.Root>
    <Card.Header><Card.Title>Add / Edit</Card.Title></Card.Header>
    <Card.Content>
      <form
        class="flex gap-2"
        {...upsert_product.enhance(async ({form, submit}) => {
          try {
            await submit().updates(get_products)
            form.reset()
            toast.success('Saved')
          } catch {
            toast.error('Error')
          }
        })}
      >
        <Input {...upsert_product.fields.name.as('text')} placeholder="Name" />
        <Input {...upsert_product.fields.price.as('number')} placeholder="Price" />
        <Button type="submit">Save</Button>
      </form>
    </Card.Content>
  </Card.Root>
</div>
```

**Step 4: Route** (`+page.svelte`)

```svelte
<script>
import ProductsPage from '$lib/features/products/ui/ProductsPage.svelte'
</script>

<ProductsPage />
```

### Phase 3: Verify (MANDATORY — no exceptions)

Code that compiles but hasn't been tested in a browser is NOT done.

1. `pnpm check:machine` — zero errors in YOUR files before proceeding
2. `pnpm format`
3. Run MCP `svelte-autofixer` on each `.svelte` file you created/modified
4. **Browser test with `agent-browser`** — this is NOT optional:
   - Open the page, take a screenshot — does it render?
   - Check server terminal for errors (`grep -i error` on dev server output)
   - Test each operation: list loads, create works, edit pre-populates, delete removes
   - If the page has a form: test BOTH create and edit mode
5. Fix any issues found, repeat from step 1

If you can't browser-test (no credentials, server down), tell the user explicitly:
"I verified types and autofixer but could NOT browser-test because [reason]."
Never claim a feature is done without stating what was and wasn't tested.

Read `references/verification-checklist.md` for the detailed process.

### Phase 4: Finalize

After verification passes:

1. **Update CHANGELOG.md** — add entry under new date section
2. **Commit on the branch** — use conventional commit format. If working from a GitHub issue, reference it:

   ```bash
   git add <specific files>
   git commit -m "feat(<scope>): description

   Refs #<issue-number>"
   ```

   Without an issue:

   ```bash
   git add <specific files>
   git commit -m "feat(<scope>): description"
   ```

3. **Report to user** — summarize what was built, what was tested, what's ready for merge. If working from an issue, remind to use `Closes #<N>` in the PR body (the `b4-pull-request` skill will handle this if given the issue number)

## Golden Rules
0. Commit tour changes
1. **One upsert form** — optional `id` field, never separate create/update
2. **$derived for queries** — `$derived(await get_items())`, never $effect+fetch
3. **form.fields.x.as('text') for form inputs** — no bind:value, no state; use `bind:value` only for non-form UI state (search, filters, toggles)
4. **Namespace imports for shadcn** — `import * as Card from '...'`
5. **Auth in remote functions** — `requireUser()`, never in services
6. **error() throws** — don't catch it, SvelteKit handles it
7. **href for navigation** — `<Button href="/x">`, never goto() for links
8. **3-5 files per feature** — more = over-engineering
9. **$derived for filtering** — client-side for <1000 items
10. **snake_case functions** — `get_items`, `upsert_item`, `delete_item`

## When to Read References

| Situation                                     | Read                                   |
| --------------------------------------------- | -------------------------------------- |
| React->Svelte doubts                          | `references/svelte5-not-react.md`      |
| Need copy-paste templates                     | `references/feature-templates.md`      |
| Running verification                          | `references/verification-checklist.md` |
| Feature has 4+ screens                        | `references/complex-features.md`       |
| URL-synced page state (filter/tab/month)      | `references/url-synced-state.md`       |
| Remote function details                       | `sveltekit-remote-functions` skill     |
| Drizzle query patterns                        | `drizzle-best-practices` skill         |
| shadcn component usage                        | `ui-stack` skill                       |
| Svelte 5 runes                                | `svelte-runes` skill                   |
| Auth & permissions                            | `security` skill                       |

## Complexity Guide

| Size                               | Files | Approach                                                           |
| ---------------------------------- | ----- | ------------------------------------------------------------------ |
| Simple (1 entity, 1 screen)        | 3-4   | Implement directly                                                 |
| Medium (2-3 entities, 2-3 screens) | 5-8   | Brief plan, implement screen by screen with verification           |
| Complex (3+ entities, 4+ screens)  | 8-15  | Read `references/complex-features.md` FIRST, then screen by screen |

**Critical for medium/complex:** build by SCREEN not by LAYER. Each screen must type-check
and work in the browser before starting the next. This prevents the "50 tasks complete,
feature broken" failure mode. Read the complex features reference for the full strategy.

## Minimizing Friction

- **Branch always** — `feat/` for features, `fix/` for bugs. Never work on master
- **No worktrees for simple features** — a regular branch is enough
- **Absolute paths always** — never cd between directories
- **Batch file writes** — write all files, then verify once
- **Leverage existing skills** — don't reinvent patterns already documented
- **Be honest about testing** — state what was tested and what wasn't
- **Commit when finished** - use b3-git-commit skill
