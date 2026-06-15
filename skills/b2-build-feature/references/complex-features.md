# Complex Features (8+ files, multiple screens)

When a feature needs more than 5 files, the risk of "completed but broken" increases
exponentially. The envío de resultados feature had 50 tasks marked complete, 6 planning
documents, and 20+ files — but shipped with 5 type errors, broken edit mode, and
commented-out security. This happens when you build by LAYER instead of by SCREEN.

## The #1 Rule: Build by Screen, Not by Layer

### WRONG: Layer-by-layer (how multi-agent systems build)

```
Phase 1: ALL types for ALL entities
Phase 2: ALL schemas for ALL entities
Phase 3: ALL repos for ALL entities
Phase 4: ALL services for ALL entities
Phase 5: ALL remote functions for ALL screens
Phase 6: ALL UI components for ALL screens
```

This produces code where each layer compiles in isolation but breaks at boundaries.
The UI agent doesn't know the query returns `{sql, params}` instead of `string`.
The form agent doesn't test edit mode with real data. Nobody runs `pnpm check:machine`
until the end, when there are 5 errors across 15 files.

### CORRECT: Screen-by-screen with verification

```
Screen 1: List page
  → <feature>.remote.ts (get_items query)
  → +page.svelte (list UI)
  → VERIFY: type check + browser test
  ✓ Screen 1 works

Screen 2: Create/Edit form
  → add upsert_item form to <feature>.remote.ts
  → <Feature>Form.svelte (colocated sibling)
  → sub-routes new/+page.svelte, [id]/+page.svelte
  → VERIFY: type check + browser test (create AND edit)
  ✓ Screen 2 works

Screen 3: Detail/execution view
  → add queries to <feature>.remote.ts
  → <Feature>Detail.svelte (colocated sibling)
  → VERIFY: type check + browser test
  ✓ Screen 3 works
```

Each screen is a self-contained increment that WORKS before you move on. Every file — remote,
components, sub-route pages — stays in the one feature route folder under `src/routes/`.

## Decomposition Strategy

### Step 1: Identify the screens

List every screen the user will see. For envío de resultados:

1. Destinations list
2. Destination create/edit form
3. Envíos list
4. Envío wizard (create/edit)
5. Envío detail + execution
6. Execution history list
7. Execution detail

### Step 2: Order by dependency

Start with the screen that has the fewest dependencies:

1. Destinations list + CRUD (standalone entity)
2. Envíos list (needs destinations to exist)
3. Envío wizard (needs destinations + field introspection)
4. Envío detail + manual execution (needs envío to exist)
5. Execution history (needs executions to exist)
6. Execution detail + retry (needs history)

### Step 3: Build each screen as a mini-feature

For each screen, write these files in order:

1. Add types/schemas IF this screen introduces new entities
2. Add remote functions for THIS screen only
3. Write the UI component
4. Wire the route
5. **VERIFY**: `pnpm check:machine` + browser test

Only then move to the next screen.

### Step 4: Keep ONE `<feature>.remote.ts`

Do NOT split remote functions across files. One `<feature>.remote.ts` per feature, growing
as you add screens. This prevents import confusion and makes the API surface visible.

For a complex feature the file might reach 200-300 lines — that's fine. A single file
with 15 well-organized remote functions is better than 3 files with unclear boundaries.

Exception: a sub-route with heavy, self-contained data needs may get its own scoped remote file
colocated in that sub-route folder (e.g. `[id]/detail.remote.ts`, `new/create.remote.ts`).

## When to Split Files

All split targets stay INSIDE the feature route folder — never `src/lib/features/`.

| Situation                                    | Split? | How (all in the route folder)                       |
| -------------------------------------------- | ------ | --------------------------------------------------- |
| Multiple screens sharing types               | Yes    | One `<feature>-types.ts`                             |
| Complex validation schemas                   | Yes    | One `schemas.ts`                                     |
| Business logic beyond CRUD                   | Yes    | `<feature>.server.ts`                               |
| Multiple destination types (adapter pattern) | Yes    | `adapters/` subfolder (`*.server.ts` files)         |
| UI components reused across screens          | Yes    | Sibling `.svelte` files, flat and PascalCase        |
| Simple CRUD screens                          | No     | Query in `<feature>.remote.ts`, UI in `+page.svelte`|

## When NOT to Abstract

The envío de resultados feature has 4 adapters (tabla-local, tabla-externa, api-rest,
email-excel). Of these, tabla-externa only works for PostgreSQL (MySQL/SQL Server throw
"not implemented"). Building the adapter factory + 4 adapter files + the interface before
ANY of them work is over-engineering.

Better approach:

1. Build the simplest adapter first (tabla-local) and get it working end-to-end
2. Add adapters one at a time, each verified before moving on
3. Extract the adapter interface AFTER you have 2+ working adapters (not before)

## Complex Form Patterns

Multi-tab wizards (like the 5-tab envío form) are the hardest UI pattern. Rules:

### Use $state for form data, NOT hidden fields

The envío form uses hidden inputs + `.fields.set()` to sync custom components
back to the form. This is fragile and breaks when components don't update.

Better: use `$state` for the form data and submit manually:

```svelte
<script>
import {create_envio, get_envios} from './envios.remote'

let formData = $state({
  nombre: '',
  canalCampaniaId: '',
  destinoDatosId: '',
  campos: [],
  filtros: {},
  mapeo: [],
  recurrencia: null,
})

let activeTab = $state('general')

async function handleSubmit() {
  await create_envio(formData)
  get_envios.refresh()
  toast.success('Created')
}
</script>

<Tabs.Root bind:value={activeTab}>
  <Tabs.Content value="general">
    <input bind:value={formData.nombre} />
    <!-- direct binding to state, no hidden fields -->
  </Tabs.Content>
  <Tabs.Content value="campos">
    <CampoSelector bind:selected={formData.campos} />
  </Tabs.Content>
  <!-- etc -->
</Tabs.Root>

<Button onclick={handleSubmit}>Save</Button>
```

### For edit mode: populate $state from loaded data

```svelte
<script>
let {envio} = $props() // from +page.server.ts load

// Initialize state from loaded data
let formData = $state({
  nombre: envio.nombre,
  campos: envio.camposSeleccionados,
  // ... all fields from envio
})
</script>
```

This avoids the reactivity bug where `$derived` captures the initial prop value
and never updates. With `$state` initialized from props, it works correctly.

## Verification Cadence for Complex Features

After EACH screen (not at the end):

1. `pnpm check:machine` — zero new errors from your files
2. Browser test — open the page, try the operation, check console
3. If the screen has a form: test BOTH create and edit mode
4. If the screen loads data: test with real data AND empty state

After ALL screens:

5. Test the full flow end-to-end (create → list → edit → execute → view result)
6. Check server terminal for unhandled errors
7. Run `svelte-autofixer` on all .svelte files
8. Run `pnpm format`

## The Real Lesson

A feature with 50 completed tasks and 6 planning documents can still be broken.
Planning doesn't prevent bugs — verification does. Every screen must work before
you build the next one. The most dangerous state is "all tasks complete, nothing tested."
