# Svelte 5 is Not React — Complete Translation Guide

This document maps every React pattern to its Svelte 5 equivalent. Read this when you catch yourself thinking in React terms. The Svelte way is almost always simpler — fewer lines, fewer files, fewer abstractions.

## 1. State Management

### Declaring State

```tsx
// React
const [count, setCount] = useState(0)
const [user, setUser] = useState({name: '', email: ''})

// Update
setCount(prev => prev + 1)
setUser(prev => ({...prev, name: 'Alice'}))
```

```svelte
<!-- Svelte 5 -->
<script>
let count = $state(0)
let user = $state({name: '', email: ''})

// Update: direct mutation (Svelte tracks it)
count++
user.name = 'Alice'
</script>
```

Key difference: Svelte 5 uses **fine-grained reactivity** with proxies. You mutate directly — no spread operators, no setter functions, no immutability patterns.

### Computed Values

```tsx
// React: useMemo
const doubled = useMemo(() => count * 2, [count])
const fullName = useMemo(() => `${first} ${last}`, [first, last])
const filtered = useMemo(() => items.filter(i => i.active), [items])
```

```svelte
<!-- Svelte 5: $derived (auto-tracks dependencies, no dep arrays) -->
<script>
let doubled = $derived(count * 2)
let fullName = $derived(`${first} ${last}`)
let filtered = $derived(items.filter(i => i.active))
</script>
```

`$derived` auto-tracks dependencies. No dependency arrays, no stale closure bugs.

**Never assign to `$derived`** — it is read-only. If you need a mutable computed value, use `$state` and update it manually.

### Complex Derived (multi-step)

```tsx
// React
const stats = useMemo(() => {
  const total = items.length
  const active = items.filter(i => i.active).length
  return {total, active, ratio: active / total}
}, [items])
```

```svelte
<script>
let stats = $derived.by(() => {
  const total = items.length
  const active = items.filter(i => i.active).length
  return {total, active, ratio: active / total}
})
</script>
```

## 2. Side Effects

```tsx
// React
useEffect(() => {
  document.title = `Count: ${count}`
}, [count])

useEffect(() => {
  const interval = setInterval(tick, 1000)
  return () => clearInterval(interval)
}, [])
```

```svelte
<script>
// Auto-tracks count, no dep array
$effect(() => {
  document.title = `Count: ${count}`
})

// Cleanup via return
$effect(() => {
  const interval = setInterval(tick, 1000)
  return () => clearInterval(interval)
})
</script>
```

**When NOT to use $effect:**

- Computing values → use `$derived` instead
- Fetching data → use remote functions with `$derived(await ...)` instead
- Syncing two state values → use `$derived` instead
- Initializing Chart.js/D3 → use `bind:this` + `$effect` carefully (but never re-run on data change without explicit guards)

## 3. Event Handling

```tsx
// React
<button onClick={handler}>Click</button>
<button onClick={() => doThing(id)}>Click</button>
<input onChange={(e) => setName(e.target.value)} />
<form onSubmit={(e) => { e.preventDefault(); submit() }}>
```

```svelte
<!-- Svelte 5: lowercase, no on: prefix -->
<button onclick={handler}>Click</button>
<button onclick={() => doThing(id)}>Click</button>
<input bind:value={name} />
<!-- bind:value, NOT onChange -->
<!-- Forms: use remote function enhance, NOT onsubmit -->
```

Key changes:

- `onClick` -> `onclick` (lowercase)
- `on:click` (Svelte 4) -> `onclick` (Svelte 5)
- `onChange` -> `{...form.fields.x.as('text')}` in remote function forms; `bind:value` only for non-form UI state (search, filters, toggles)
- `onSubmit` -> remote function `form.enhance()` or `onsubmit` if truly needed

## 4. Props

```tsx
// React
function Card({title, children, variant = 'default'}) {
  return (
    <div className={variant}>
      {title}
      {children}
    </div>
  )
}
```

```svelte
<!-- Svelte 5 -->
<script>
let {title, children, variant = 'default'} = $props()
</script>

<div class={variant}>{title}{@render children()}</div>
```

### Typed props

```svelte
<script lang="ts">
interface Props {
  title: string
  variant?: 'default' | 'outline'
  children: import('svelte').Snippet
}
let {title, variant = 'default', children}: Props = $props()
</script>
```

### Bindable props (two-way binding)

```svelte
<script lang="ts">
let {value = $bindable()}: {value: string} = $props()
</script>

<!-- Parent can do: <MyInput bind:value={name} /> -->
```

## 5. Children & Composition

```tsx
// React: children prop
function Layout({children}) {
  return <main>{children}</main>
}

// React: render props
function List({items, renderItem}) {
  return items.map(item => renderItem(item))
}
```

```svelte
<!-- Svelte 5: snippets replace slots AND render props -->
<script>
  let { children } = $props()
</script>
<main>{@render children()}</main>

<!-- Named snippets (like named slots) -->
<script>
  let { header, children, footer } = $props()
</script>
<header>{@render header?.()}</header>
<main>{@render children()}</main>
<footer>{@render footer?.()}</footer>

<!-- Snippet with parameters (like render props) -->
<script>
  let { items, renderItem } = $props()
</script>
{#each items as item}
  {@render renderItem(item)}
{/each}
```

**Never use `<slot />`** — it is Svelte 4 syntax.

## 6. Data Fetching

```tsx
// React: useEffect + fetch + loading state
const [data, setData] = useState(null)
const [loading, setLoading] = useState(true)
const [error, setError] = useState(null)

useEffect(() => {
  fetch('/api/items')
    .then(r => r.json())
    .then(setData)
    .catch(setError)
    .finally(() => setLoading(false))
}, [])
```

```svelte
<!-- SvelteKit: one line with remote functions -->
<script>
import {get_items} from './data.remote'

// experimental async: one line, reactive, cached
const items = $derived(await get_items())
</script>

<!-- items is ready to use. Loading/error handled by svelte:boundary or {#await} -->
{#each items as item}
  <p>{item.name}</p>
{/each}
```

No loading state management. No error state management. No useEffect. No cleanup. The remote function handles caching, deduplication, and type safety.

### Dependent queries (params change = refetch)

```svelte
<script>
let categoryId = $state('all')

// Re-fetches automatically when categoryId changes
const products = $derived(categoryId !== 'all' ? await get_products_by_category({categoryId}) : await get_all_products())
</script>
```

## 7. Error Handling

```tsx
// React: return error objects
export async function loader() {
  if (!user) return {status: 401, error: 'Unauthorized'} // BAD: does nothing
}

// React: try/catch around navigation
try {
  navigate('/dashboard')
} catch {} // Unnecessary
```

```typescript
// SvelteKit: error() and redirect() THROW — that's the design
import {error, redirect} from '@sveltejs/kit'

// These throw. Never wrap in try/catch.
if (!user) error(401, {message: 'No autenticado', code: 'AUTH_REQUIRED'})
redirect(303, '/login')

// Always use structured errors with message + code
error(403, {message: 'Sin permiso', code: 'FORBIDDEN'})
error(404, {message: 'No encontrado', code: 'NOT_FOUND'})
```

## 8. Navigation

```tsx
// React
import { useNavigate } from 'react-router'
const navigate = useNavigate()
<button onClick={() => navigate('/page')}>Go</button>
```

```svelte
<!-- Only use goto() for programmatic navigation after an action -->
<script>
import {goto} from '$app/navigation'

async function handleAction() {
  await doSomething()
  goto('/result') // OK: navigation after action, not as click handler
}
</script>

<!-- Svelte: use HTML links, not JS navigation -->
<a href="/page">Go</a>
<Button href="/page">Go</Button>
```

## 9. Forms — The Complete Guide

This is where React habits cause the most bugs. Read carefully.

### Simple form (no validation needed)

```svelte
<script>
import {create_item, get_items} from './data.remote'
</script>

<form
  {...create_item.enhance(async ({form, submit}) => {
    await submit().updates(get_items)
    form.reset()
  })}
>
  <input {...create_item.fields.name.as('text')} />
  <button type="submit">Create</button>
</form>
```

### Upsert form (create AND edit in one)

```svelte
<script>
import {upsert_item, get_items} from './data.remote'
import {toast} from 'svelte-sonner'

let editingId = $state<string | null>(null)

function startEdit(item) {
  editingId = item.id
  upsert_item.fields.set({id: item.id, name: item.name, price: item.price})
}

function cancelEdit() {
  editingId = null
  // The form resets automatically on next submission
}
</script>

<form
  {...upsert_item.enhance(async ({form, submit}) => {
    try {
      await submit().updates(get_items)
      form.reset()
      editingId = null
      toast.success(editingId ? 'Updated' : 'Created')
    } catch {
      toast.error('Error')
    }
  })}
>
  <input {...upsert_item.fields.name.as('text')} placeholder="Name" />
  <input {...upsert_item.fields.price.as('number')} placeholder="Price" />
  <button type="submit">{editingId ? 'Update' : 'Create'}</button>
  {#if editingId}
    <button type="button" onclick={cancelEdit}>Cancel</button>
  {/if}
</form>
```

### Complex interactive form (when enhance pattern is too restrictive)

For forms with conditional fields, dynamic sections, or multi-step flows:

```svelte
<script>
import {upsert_item, get_items} from './data.remote'

let name = $state('')
let type = $state('simple')
let config = $state({})

async function handleSubmit() {
  await upsert_item({name, type, config})
  get_items.refresh()
  toast.success('Saved')
}
</script>

<form onsubmit|preventDefault={handleSubmit}>
  <input bind:value={name} />
  <select bind:value={type}>
    <option value="simple">Simple</option>
    <option value="complex">Complex</option>
  </select>
  {#if type === 'complex'}
    <!-- conditional fields -->
  {/if}
  <button type="submit">Save</button>
</form>
```

Use this pattern ONLY when the `enhance` + `fields.as()` approach cannot express the UI. Default to `enhance`.

## 10. shadcn-svelte Specifics

### ALWAYS namespace imports

```svelte
<!-- CORRECT -->
<script>
  import * as Card from '$lib/components/ui/card'
  import * as Table from '$lib/components/ui/table'
  import * as Select from '$lib/components/ui/select'
  import * as Dialog from '$lib/components/ui/dialog'
  import * as Alert from '$lib/components/ui/alert'
</script>

<Card.Root>
  <Card.Header><Card.Title>Title</Card.Title></Card.Header>
  <Card.Content>Content</Card.Content>
</Card.Root>

<!-- WRONG: named imports -->
<script>
  import { Card, CardHeader, CardTitle } from '$lib/components/ui/card'  // NO
</script>
```

### Components that DON'T have subcomponents

These import directly (no namespace):

```svelte
<script>
import {Button} from '$lib/components/ui/button'
import {Input} from '$lib/components/ui/input'
import {Label} from '$lib/components/ui/label'
import {Textarea} from '$lib/components/ui/textarea'
import {Badge} from '$lib/components/ui/badge'
import {Separator} from '$lib/components/ui/separator'
</script>
```

### Select component gotcha

`Select.Value` does NOT exist. Use placeholder on Trigger:

```svelte
<!-- WRONG -->
<Select.Trigger>
  <Select.Value>Choose...</Select.Value>
</Select.Trigger>

<!-- CORRECT -->
<Select.Trigger placeholder="Choose..." />
```

### Lucide icons

```svelte
<script>
import Plus from '@lucide/svelte/icons/plus'
import Trash from '@lucide/svelte/icons/trash-2'
import Pencil from '@lucide/svelte/icons/pencil'
</script>

<Button><Plus class="mr-2 h-4 w-4" /> Add</Button>
```

## 11. Client-Side Filtering

For lists under 1000 items, filter on the client. No server round-trips.

```svelte
<script>
import {get_products} from './data.remote'

const products = $derived(await get_products())
let search = $state('')
let category = $state('all')

// Client-side filtering with $derived (reactive, instant)
let filtered = $derived(products.filter(p => (category === 'all' || p.category === category) && p.name.toLowerCase().includes(search.toLowerCase())))
</script>

<input bind:value={search} placeholder="Search..." />
<select bind:value={category}>
  <option value="all">All</option>
  <option value="electronics">Electronics</option>
</select>

{#each filtered as product (product.id)}
  <p>{product.name}</p>
{/each}
```

For 1000+ items or when you need pagination, use server-side queries with parameters:

```svelte
<script>
let page = $state(1)
let search = $state('')
const result = $derived(await get_products({page, search, limit: 50}))
</script>
```

## Quick Decision Matrix

| I need to...                     | Use                                       |
| -------------------------------- | ----------------------------------------- |
| Hold mutable UI state            | `$state()`                                |
| Compute from other values        | `$derived()`                              |
| Multi-step computation           | `$derived.by(() => { ... })`              |
| React to changes (DOM, timers)   | `$effect()`                               |
| Fetch server data                | `$derived(await query())`                 |
| Submit form data                 | `form.enhance()`                          |
| Delete / toggle / one-off action | `command()` + `.refresh()`                |
| Navigate to a page               | `<a href="...">` or `<Button href="...">` |
| Navigate after action            | `goto('/path')`                           |
| Pass content to child            | `{@render children()}`                    |
| Two-way bind to parent           | `$bindable()` prop                        |
