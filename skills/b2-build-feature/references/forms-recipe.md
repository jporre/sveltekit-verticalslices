# Forms Recipe — Remote Functions `form()` + shadcn-svelte

Canonical patterns for building a create/edit screen with the Remote Functions `form()`
API and shadcn-svelte fields. Read this when the screen has a create/edit form.

**The gap this closes:** native inputs (`Input`, `Textarea`) accept `{...fields.x.as('text')}`
and just work. The non-native shadcn components (`Select`, `Checkbox`, `RadioGroup`,
`Calendar`/date) render `div`/`button`, not `<input>` — the form never sees their value
and validation errors are invisible. Each needs a bridge. And the `disabled={!isFormValid}`
anti-pattern hides the very error borders it should show.

---

## 1. Base pattern — `<form {...create_x}>`

Server: schema lives IN the remote function. Never validate on the client for the server op.

```ts
// src/routes/<feature>/<feature>.remote.ts
import { z } from 'zod/v4'
import { form, query, getRequestEvent } from '$app/server'
import { error } from '@sveltejs/kit'
import { db } from '$lib/server/db'
import { taItem } from '$lib/server/db/schema'
import { eq } from 'drizzle-orm'

function requireUser() {
  const { locals } = getRequestEvent()
  if (!locals.user) error(401, { message: 'No autenticado', code: 'AUTH_REQUIRED' })
  return locals.user
}

export const get_items = query(async () => {
  requireUser()
  return db.query.taItem.findMany({ orderBy: (t, { desc }) => [desc(t.createdAt)] })
})

const upsertSchema = z.object({
  id: z.string().optional(),
  nombre: z.string().min(1, 'Nombre requerido'),
  activo: z.boolean().default(false),        // Checkbox
  categoria: z.string().min(1, 'Elegi una categoria'), // Select
  plan: z.enum(['free', 'pro'], { message: 'Elegi un plan' }),  // RadioGroup
  vence: z.string().min(1, 'Fecha requerida'), // Calendar/date -> YYYY-MM-DD
})

export const upsert_item = form(upsertSchema, async (data) => {
  requireUser()
  if (data.id) {
    const [row] = await db.update(taItem).set(data).where(eq(taItem.id, data.id)).returning()
    return { ok: true as const, row }
  }
  const [row] = await db.insert(taItem).values(data).returning()
  return { ok: true as const, row }
})
```

Client: spread the form on `<form>`, native fields via `.as()`, toast on success.

```svelte
<script lang="ts">
  import { get_items, upsert_item } from './<feature>.remote'
  import * as Card from '$lib/components/ui/card'
  import { Button } from '$lib/components/ui/button'
  import { Input } from '$lib/components/ui/input'
  import { Label } from '$lib/components/ui/label'
  import { toast } from 'svelte-sonner'

  const submitting = $derived(!!upsert_item.pending)
</script>

<Card.Root>
  <Card.Header><Card.Title>Nuevo item</Card.Title></Card.Header>
  <Card.Content>
    <form
      class="flex flex-col gap-4"
      {...upsert_item.enhance(async ({ form, submit }) => {
        try {
          await submit().updates(get_items)
          form.reset()
          toast.success('Guardado')
        } catch {
          toast.error('Error al guardar')
        }
      })}
    >
      <!-- Native field: Input forwards the spread to a real <input> -->
      <div class="grid gap-2">
        <Label for="nombre">Nombre</Label>
        <Input
          {...upsert_item.fields.nombre.as('text')}
          id="nombre"
          aria-invalid={upsert_item.fields.nombre.issues().length > 0}
        />
        {#each upsert_item.fields.nombre.issues() as issue}
          <p class="text-destructive text-sm">{issue.message}</p>
        {/each}
      </div>

      <!-- ...non-native fields: see sections 2-5... -->

      <!-- HARD RULE: disabled={submitting}, NEVER disabled={!isFormValid} -->
      <Button type="submit" disabled={submitting}>
        {submitting ? 'Guardando...' : 'Guardar'}
      </Button>
    </form>
  </Card.Content>
</Card.Root>
```

**Native fields** (`Input`, `Textarea`) forward the spread — always prefer them. Use `.as()`:
`text | email | password | url | tel | number | date | datetime-local | time`. Full list: `../../using-remote-functions/FORM.md`.

---

## 2. Select (shadcn) — bind + hidden input

`Select.Root` is not a native `<select>`. Bridge: bind a `$state`, mirror it into a hidden
input the form actually submits. Errors come from `fields.categoria.issues()`.

```svelte
<script lang="ts">
  import * as Select from '$lib/components/ui/select'
  let categoria = $state('')
  const categorias = [
    { value: 'a', label: 'Categoria A' },
    { value: 'b', label: 'Categoria B' },
  ]
  const invalid = $derived(upsert_item.fields.categoria.issues().length > 0)
</script>

<div class="grid gap-2">
  <Label>Categoria</Label>
  <!-- hidden input carries the value into the form submission -->
  <input {...upsert_item.fields.categoria.as('hidden', categoria)} />
  <Select.Root type="single" bind:value={categoria}>
    <Select.Trigger aria-invalid={invalid}>
      {categorias.find((c) => c.value === categoria)?.label ?? 'Elegi una categoria'}
    </Select.Trigger>
    <Select.Content>
      {#each categorias as c}
        <Select.Item value={c.value}>{c.label}</Select.Item>
      {/each}
    </Select.Content>
  </Select.Root>
  {#each upsert_item.fields.categoria.issues() as issue}
    <p class="text-destructive text-sm">{issue.message}</p>
  {/each}
</div>
```

> Simpler alternative when you don't need the shadcn look: a native `<select {...fields.categoria.as('select')}>`
> styled with the shadcn input classes. Prefer this if the trigger/popover UX is not required.

---

## 3. Checkbox (shadcn) — bind + hidden input

`Checkbox` renders a `button[role=checkbox]`. Bind the boolean, mirror into a hidden input.
Schema field is `z.boolean()`.

```svelte
<script lang="ts">
  import { Checkbox } from '$lib/components/ui/checkbox'
  let activo = $state(false)
</script>

<div class="flex items-center gap-2">
  <input {...upsert_item.fields.activo.as('hidden', activo ? 'true' : '')} />
  <Checkbox id="activo" bind:checked={activo} />
  <Label for="activo">Activo</Label>
</div>
{#each upsert_item.fields.activo.issues() as issue}
  <p class="text-destructive text-sm">{issue.message}</p>
{/each}
```

> Boolean coercion: an empty string is falsy for `z.boolean()` via SvelteKit's checkbox
> coercion — send `'true'` when checked, `''` otherwise. For a single boolean without the
> shadcn styling, a native `<input {...fields.activo.as('checkbox')}>` needs no bridge.

---

## 4. RadioGroup (shadcn) — bind + hidden input

`RadioGroup.Root` is not native radios. Bind the selected value, mirror into a hidden input.

```svelte
<script lang="ts">
  import * as RadioGroup from '$lib/components/ui/radio-group'
  let plan = $state<'free' | 'pro'>('free')
  const invalid = $derived(upsert_item.fields.plan.issues().length > 0)
</script>

<div class="grid gap-2" aria-invalid={invalid}>
  <Label>Plan</Label>
  <input {...upsert_item.fields.plan.as('hidden', plan)} />
  <RadioGroup.Root bind:value={plan}>
    <div class="flex items-center gap-2">
      <RadioGroup.Item value="free" id="plan-free" />
      <Label for="plan-free">Free</Label>
    </div>
    <div class="flex items-center gap-2">
      <RadioGroup.Item value="pro" id="plan-pro" />
      <Label for="plan-pro">Pro</Label>
    </div>
  </RadioGroup.Root>
  {#each upsert_item.fields.plan.issues() as issue}
    <p class="text-destructive text-sm">{issue.message}</p>
  {/each}
</div>
```

> Native alternative: `{#each opts as o}<input {...fields.plan.as('radio', o)} />{/each}`.

---

## 5. Calendar / date (shadcn) — bind + hidden input

`Calendar` (bits-ui) uses a `DateValue` object, not a string. Bridge: bind the `DateValue`,
format to `YYYY-MM-DD` for the hidden input the schema expects.

```svelte
<script lang="ts">
  import { Calendar } from '$lib/components/ui/calendar'
  import * as Popover from '$lib/components/ui/popover'
  import { type DateValue, getLocalTimeZone, today } from '@internationalized/date'

  let vence = $state<DateValue | undefined>(undefined)
  const venceStr = $derived(vence ? vence.toString() : '') // YYYY-MM-DD
  const invalid = $derived(upsert_item.fields.vence.issues().length > 0)
</script>

<div class="grid gap-2">
  <Label>Vence</Label>
  <input {...upsert_item.fields.vence.as('hidden', venceStr)} />
  <Popover.Root>
    <Popover.Trigger aria-invalid={invalid}>
      {venceStr || 'Elegi una fecha'}
    </Popover.Trigger>
    <Popover.Content class="w-auto p-0">
      <Calendar type="single" bind:value={vence} minValue={today(getLocalTimeZone())} />
    </Popover.Content>
  </Popover.Root>
  {#each upsert_item.fields.vence.issues() as issue}
    <p class="text-destructive text-sm">{issue.message}</p>
  {/each}
</div>
```

> Simplest option if you don't need a calendar popover: `<Input {...fields.vence.as('date')} />`
> renders the browser's native date picker with zero bridging.

---

## 6. Anti-pattern: `disabled={!isFormValid}` (do NOT do this)

Real bug already paid for (memoria `feedback_disabled_submit_hides_errors`, PR #488):
gating the submit button on a client-computed `isFormValid`, with `aria-invalid` only set
inside `handleSubmit`, makes the red error borders **unreachable** — the user can never
submit to trigger them, so they never appear.

```svelte
<!-- WRONG: user cannot submit -> aria-invalid never fires -> errors invisible -->
<Button type="submit" disabled={!isFormValid}>Guardar</Button>
```

```svelte
<!-- RIGHT: always allow submit; server validates; issues() render on invalid submit -->
<Button type="submit" disabled={submitting}>Guardar</Button>
```

**Rule:** the submit button is disabled ONLY while a request is in flight
(`disabled={submitting}` where `const submitting = $derived(!!upsert_item.pending)`).
Validation is server-side (schema in the `form()`); on an invalid submit the form
re-renders with `fields.x.issues()` populated and `aria-invalid` visible on every field.
Never block submit on client-side validity — that is what hides the errors.

Show all errors at the top with `{#each upsert_item.fields.allIssues() as issue}` if you
prefer a summary, in addition to (not instead of) per-field `issues()`.

---

## Checklist

- [ ] Schema in the `form()`, not client-side. `requireUser()` / permission guard first.
- [ ] Native fields (`Input`/`Textarea`) via `{...fields.x.as('...')}`.
- [ ] Each non-native shadcn field (Select, Checkbox, RadioGroup, Calendar) has a bound
      `$state` + a hidden input `{...fields.x.as('hidden', value)}` bridging its value.
- [ ] Every field renders `fields.x.issues()` and sets `aria-invalid` — visible after an
      invalid submit, no gate hiding them.
- [ ] Submit button `disabled={submitting}` only. NEVER `disabled={!isFormValid}`.
- [ ] `toast.success(...)` on success via `.enhance`; `.updates(get_x)` refreshes the list.
