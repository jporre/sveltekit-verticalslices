# Feature Templates

Copy-paste templates for common feature types. Replace `<feature>`, `<Feature>`, `<entity>`, `<Entity>` with your actual names.

## Template 1: Simple CRUD (List + Create + Edit + Delete)

The most common feature. One entity, one screen.

### `src/lib/features/<feature>/types.ts`

```typescript
import type { InferSelectModel } from 'drizzle-orm'
import { ta<Entity> } from '$lib/server/db/schema'

export type <Entity> = InferSelectModel<typeof ta<Entity>>
```

### `src/lib/features/<feature>/data.remote.ts`

```typescript
import { query, form, command } from '$app/server'
import * as v from 'valibot'
import { getRequestEvent } from '$app/server'
import { error } from '@sveltejs/kit'
import { db } from '$lib/server/db'
import { ta<Entity> } from '$lib/server/db/schema'
import { eq } from 'drizzle-orm'

function requireUser() {
  const { locals } = getRequestEvent()
  if (!locals.user) error(401, { message: 'No autenticado', code: 'AUTH_REQUIRED' })
  return locals.user
}

// List
export const get_<entities> = query(async () => {
  requireUser()
  return db.query.ta<Entity>.findMany({
    orderBy: (t, { desc }) => [desc(t.createdAt)],
  })
})

// Upsert (create + edit in ONE form)
const upsertSchema = v.object({
  id: v.optional(v.string()),
  // TODO: add your fields here
  name: v.pipe(v.string(), v.nonEmpty('Requerido')),
})

export const upsert_<entity> = form(upsertSchema, async (data) => {
  requireUser()
  if (data.id) {
    const [updated] = await db
      .update(ta<Entity>)
      .set(data)
      .where(eq(ta<Entity>.id, data.id))
      .returning()
    return updated
  }
  const [created] = await db.insert(ta<Entity>).values(data).returning()
  return created
})

// Delete
export const delete_<entity> = command(
  v.object({ id: v.string() }),
  async ({ id }) => {
    requireUser()
    await db.delete(ta<Entity>).where(eq(ta<Entity>.id, id))
  },
)
```

### `src/lib/features/<feature>/ui/<Feature>Page.svelte`

```svelte
<script lang="ts">
  import { get_<entities>, upsert_<entity>, delete_<entity> } from '../data.remote'
  import * as Card from '$lib/components/ui/card'
  import * as Table from '$lib/components/ui/table'
  import { Button } from '$lib/components/ui/button'
  import { Input } from '$lib/components/ui/input'
  import { Label } from '$lib/components/ui/label'
  import { toast } from 'svelte-sonner'
  import Plus from '@lucide/svelte/icons/plus'
  import Pencil from '@lucide/svelte/icons/pencil'
  import Trash from '@lucide/svelte/icons/trash-2'

  const items = $derived(await get_<entities>())
  let editingId = $state<string | null>(null)

  function startEdit(item: typeof items[0]) {
    editingId = item.id
    upsert_<entity>.fields.set({
      id: item.id,
      name: item.name,
      // TODO: set all fields
    })
  }

  function cancelEdit() {
    editingId = null
  }

  async function handleDelete(id: string) {
    if (!confirm('Delete?')) return
    await delete_<entity>({ id })
    get_<entities>.refresh()
    toast.success('Deleted')
  }
</script>

<div class="space-y-6">
  <!-- Table -->
  <Card.Root>
    <Card.Header class="flex flex-row items-center justify-between">
      <Card.Title><Feature></Card.Title>
    </Card.Header>
    <Card.Content>
      {#if items.length === 0}
        <p class="text-muted-foreground py-8 text-center">No items yet</p>
      {:else}
        <Table.Root>
          <Table.Header>
            <Table.Row>
              <Table.Head>Name</Table.Head>
              <!-- TODO: add columns -->
              <Table.Head class="w-24"></Table.Head>
            </Table.Row>
          </Table.Header>
          <Table.Body>
            {#each items as item (item.id)}
              <Table.Row>
                <Table.Cell>{item.name}</Table.Cell>
                <!-- TODO: add cells -->
                <Table.Cell class="text-right">
                  <Button size="icon" variant="ghost" onclick={() => startEdit(item)}>
                    <Pencil class="h-4 w-4" />
                  </Button>
                  <Button size="icon" variant="ghost" onclick={() => handleDelete(item.id)}>
                    <Trash class="h-4 w-4" />
                  </Button>
                </Table.Cell>
              </Table.Row>
            {/each}
          </Table.Body>
        </Table.Root>
      {/if}
    </Card.Content>
  </Card.Root>

  <!-- Upsert Form -->
  <Card.Root>
    <Card.Header>
      <Card.Title>{editingId ? 'Edit' : 'Create'}</Card.Title>
    </Card.Header>
    <Card.Content>
      <form
        class="flex flex-col gap-4"
        {...upsert_<entity>.enhance(async ({ form, submit }) => {
          try {
            await submit().updates(get_<entities>)
            form.reset()
            editingId = null
            toast.success(editingId ? 'Updated' : 'Created')
          } catch {
            toast.error('Error saving')
          }
        })}
      >
        <div class="grid gap-2">
          <Label for="name">Name</Label>
          <Input {...upsert_<entity>.fields.name.as('text')} id="name" placeholder="Name" />
        </div>
        <!-- TODO: add more fields -->

        <div class="flex gap-2">
          <Button type="submit">{editingId ? 'Update' : 'Create'}</Button>
          {#if editingId}
            <Button type="button" variant="outline" onclick={cancelEdit}>Cancel</Button>
          {/if}
        </div>
      </form>
    </Card.Content>
  </Card.Root>
</div>
```

### `src/routes/[country]/<feature>/+page.svelte`

```svelte
<script>
  import <Feature>Page from '$lib/features/<feature>/ui/<Feature>Page.svelte'
</script>

<<Feature>Page />
```

---

## Template 2: List with Filters + Detail Modal

For viewing items with search/filter and opening a detail view.

### Additional in `data.remote.ts`

```typescript
// Query with filters
const filterSchema = v.object({
  search: v.optional(v.string()),
  status: v.optional(v.picklist(['active', 'inactive', 'all'])),
  page: v.optional(v.pipe(v.number(), v.integer(), v.minValue(1))),
  limit: v.optional(v.pipe(v.number(), v.integer(), v.minValue(1), v.maxValue(100))),
})

export const get_<entities> = query(filterSchema, async (filters) => {
  requireUser()
  const page = filters.page ?? 1
  const limit = filters.limit ?? 50
  const offset = (page - 1) * limit

  let where = undefined
  const conditions = []

  if (filters.search) {
    conditions.push(ilike(ta<Entity>.name, `%${filters.search}%`))
  }
  if (filters.status && filters.status !== 'all') {
    conditions.push(eq(ta<Entity>.status, filters.status))
  }
  if (conditions.length > 0) {
    where = and(...conditions)
  }

  const [items, totalResult] = await Promise.all([
    db.select().from(ta<Entity>).where(where)
      .orderBy(desc(ta<Entity>.createdAt))
      .limit(limit).offset(offset),
    db.select({ count: count() }).from(ta<Entity>).where(where),
  ])

  return {
    items,
    total: totalResult[0]?.count ?? 0,
    page,
    limit,
  }
})

// Single item detail
export const get_<entity> = query(
  v.object({ id: v.string() }),
  async ({ id }) => {
    requireUser()
    const item = await db.query.ta<Entity>.findFirst({
      where: (t, { eq }) => eq(t.id, id),
    })
    if (!item) error(404, { message: 'No encontrado', code: 'NOT_FOUND' })
    return item
  },
)
```

### Component pattern for filtered list

```svelte
<script lang="ts">
  import { get_<entities> } from '../data.remote'

  let search = $state('')
  let status = $state<'all' | 'active' | 'inactive'>('all')
  let page = $state(1)

  // Reactive query — re-fetches when search/status/page changes
  const result = $derived(await get_<entities>({
    search: search || undefined,
    status: status !== 'all' ? status : undefined,
    page,
    limit: 50,
  }))

  let selectedId = $state<string | null>(null)
</script>

<div class="mb-4 flex gap-4">
  <Input bind:value={search} placeholder="Search..." class="max-w-sm" />
  <select bind:value={status} class="rounded border px-3">
    <option value="all">All</option>
    <option value="active">Active</option>
    <option value="inactive">Inactive</option>
  </select>
</div>

<!-- Table with pagination -->
{#each result.items as item (item.id)}
  <Table.Row onclick={() => (selectedId = item.id)} class="cursor-pointer">
    <!-- ... -->
  </Table.Row>
{/each}

<div class="mt-4 flex justify-between">
  <span>{result.total} total</span>
  <div class="flex gap-2">
    <Button disabled={page <= 1} onclick={() => page--}>Previous</Button>
    <Button disabled={page * 50 >= result.total} onclick={() => page++}>Next</Button>
  </div>
</div>

<!-- Detail Dialog -->
{#if selectedId}
  <Dialog.Root open onOpenChange={() => (selectedId = null)}>
    <Dialog.Content>
      {#await get_<entity>({id: selectedId})}
        <p>Loading...</p>
      {:then detail}
        <Dialog.Header>
          <Dialog.Title>{detail.name}</Dialog.Title>
        </Dialog.Header>
        <!-- detail content -->
      {/await}
    </Dialog.Content>
  </Dialog.Root>
{/if}
```

---

## Template 3: Dashboard with Metrics

Multiple queries, display as cards and charts.

### `data.remote.ts`

```typescript
export const get_dashboard_stats = query(async () => {
  requireUser()

  const [totalResult, activeResult, recentResult] = await Promise.all([
    db.select({ count: count() }).from(ta<Entity>),
    db.select({ count: count() }).from(ta<Entity>).where(eq(ta<Entity>.status, 'active')),
    db.select().from(ta<Entity>).orderBy(desc(ta<Entity>.createdAt)).limit(5),
  ])

  return {
    total: totalResult[0]?.count ?? 0,
    active: activeResult[0]?.count ?? 0,
    recent: recentResult,
  }
})
```

### Dashboard component

```svelte
<script lang="ts">
import {get_dashboard_stats} from '../data.remote'
import * as Card from '$lib/components/ui/card'

const stats = $derived(await get_dashboard_stats())
</script>

<div class="grid gap-4 md:grid-cols-3">
  <Card.Root>
    <Card.Header class="pb-2">
      <Card.Description>Total</Card.Description>
    </Card.Header>
    <Card.Content>
      <p class="text-2xl font-bold">{stats.total}</p>
    </Card.Content>
  </Card.Root>

  <Card.Root>
    <Card.Header class="pb-2">
      <Card.Description>Active</Card.Description>
    </Card.Header>
    <Card.Content>
      <p class="text-2xl font-bold">{stats.active}</p>
    </Card.Content>
  </Card.Root>

  <Card.Root>
    <Card.Header class="pb-2">
      <Card.Description>Rate</Card.Description>
    </Card.Header>
    <Card.Content>
      <p class="text-2xl font-bold">
        {stats.total > 0 ? Math.round((stats.active / stats.total) * 100) : 0}%
      </p>
    </Card.Content>
  </Card.Root>
</div>

<!-- Recent items -->
<Card.Root class="mt-6">
  <Card.Header>
    <Card.Title>Recent</Card.Title>
  </Card.Header>
  <Card.Content>
    {#each stats.recent as item (item.id)}
      <div class="flex items-center justify-between py-2">
        <span>{item.name}</span>
        <span class="text-muted-foreground text-sm">
          {new Date(item.createdAt).toLocaleDateString()}
        </span>
      </div>
    {/each}
  </Card.Content>
</Card.Root>
```

---

## Template 4: Tab-Based Multi-View

Multiple views of the same data (e.g., overview + settings + history).

```svelte
<script lang="ts">
import * as Tabs from '$lib/components/ui/tabs'
import OverviewTab from './components/OverviewTab.svelte'
import SettingsTab from './components/SettingsTab.svelte'
import HistoryTab from './components/HistoryTab.svelte'
</script>

<Tabs.Root value="overview">
  <Tabs.List>
    <Tabs.Trigger value="overview">Overview</Tabs.Trigger>
    <Tabs.Trigger value="settings">Settings</Tabs.Trigger>
    <Tabs.Trigger value="history">History</Tabs.Trigger>
  </Tabs.List>

  <Tabs.Content value="overview">
    <OverviewTab />
  </Tabs.Content>
  <Tabs.Content value="settings">
    <SettingsTab />
  </Tabs.Content>
  <Tabs.Content value="history">
    <HistoryTab />
  </Tabs.Content>
</Tabs.Root>
```

Each tab is a separate component that imports its own remote functions. Keep tabs independent — each manages its own data.
