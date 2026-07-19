# Recetas de migracion a remote functions (E3)

> Templates canonicos completos (CRUD entero): `../../b2-build-feature/references/feature-templates.md`. Forms con shadcn y campos no-nativos: `../../b2-build-feature/references/forms-recipe.md`. Este archivo solo trae el mapeo legacy → remote, receta por receta. Si el skill `using-remote-functions` esta disponible, sus docs (QUERY/FORM/COMMAND/SINGLE-FLIGHT) profundizan cada tipo.

Prerequisitos (E1 ya los dejo): `svelte.config.js` con `kit.experimental.remoteFunctions: true` y `compilerOptions.experimental.async: true`; SvelteKit >= 2.27.

Reglas fijas de toda funcion migrada:

- Vive en `src/routes/<feature>/<feature>.remote.ts` — nunca `data.remote.ts`, nunca bajo `src/lib/server/`.
- `requireUser()` / `requirePermission('verbo:sustantivo')` como **primera operacion**.
- Todo argumento validado con schema zod como primer parametro (`query(z.string(), async (id) => ...)`). Sin schema solo cuando no recibe argumentos.
- Nombres `snake_case`: `get_items`, `upsert_item`, `delete_item`.
- La transformacion de datos (sort, map, merge) vive en la remote function; la pagina solo renderiza.
- Preferir `form` sobre `command`: form degrada sin JavaScript. `command` solo para mutaciones no ligadas a un formulario (like, toggle, delete inline).

---

## R1 — `load()` → `query()`

```ts
// MAL — +page.server.ts
export const load = async ({ locals }) => {
  if (!locals.user) error(401);
  return { items: await db.select().from(items) };
};
```

```ts
// BIEN — <feature>.remote.ts
import { query } from '$app/server';
import { requireUser } from '$lib/server/auth';

export const get_items = query(async () => {
  await requireUser();
  return db.select().from(items);
});
```

```svelte
<!-- BIEN — +page.svelte: sin prop data, sin loading manual -->
<script lang="ts">
  import { get_items } from './<feature>.remote';
  const items = $derived(await get_items());
</script>

{#each items as item (item.id)}...{/each}
```

- Loading/error UI: envolver en `<svelte:boundary>` con snippet `pending` — no estados `loading` manuales.
- Al borrar el `load`, revisar si `+page.server.ts` queda vacio → borrar el archivo (o dejar solo el guard de ruta si la pagina lo necesita).
- `load` de `+layout.server.ts` consumido por varias paginas → una `query` compartida del feature dueño; queries se deduplican por request, llamarla en cada pagina que la necesita es gratis.

## R2 — form actions → `form()`

```ts
// MAL — +page.server.ts
export const actions = { default: async ({ request }) => { /* FormData a mano */ } };
```

```ts
// BIEN — <feature>.remote.ts: UN upsert con id opcional (nunca create/edit separados)
import { form } from '$app/server';
import { z } from 'zod';

export const upsert_item = form(
  z.object({ id: z.string().optional(), name: z.string().min(1) }),
  async ({ id, name }) => {
    await requireUser();
    if (id) await db.update(items).set({ name }).where(eq(items.id, id));
    else await db.insert(items).values({ name });
    await get_items().refresh();   // single-flight: ver R5
  }
);
```

```svelte
<!-- BIEN — el spread reemplaza a use:enhance; inputs con fields.as() -->
<form {...upsert_item}>
  {#each upsert_item.fields.name.issues() ?? [] as issue}<p class="issue">{issue.message}</p>{/each}
  <input {...upsert_item.fields.name.as('text')} />
  <button disabled={!!upsert_item.pending}>Guardar</button>
</form>
```

- HARD RULE heredada de b2: el submit se deshabilita SOLO en vuelo (`disabled={!!f.pending}`), NUNCA `disabled={!isFormValid}`.
- Edit pre-popula con `fields.set({...})` o `fields.x.as('text', valor)`; forms repetidos en lista usan `upsert_item.for(item.id)`.
- Campos sensibles con prefijo underscore (`fields._password`) para no repoblarse tras error.
- Post-submit con logica custom: `{...upsert_item.enhance(async (f) => { if (await f.submit()) { f.element.reset(); toast(...); } })}` — con `enhance` el reset es manual.

## R3 — `onMount` + `fetch` → `query()`

```svelte
<!-- MAL — React-ism (AP2) -->
<script>
  let items = [];
  onMount(async () => { items = await (await fetch('/api/items')).json(); });
</script>
```

```svelte
<!-- BIEN -->
<script lang="ts">
  import { get_items } from './<feature>.remote';
  const items = $derived(await get_items());
</script>
```

Borrar el `+server.ts` que servia ese fetch (ver R4). Cero estados `loading`/`error` manuales: boundary.

## R4 — `+server.ts` interno → `query` / `command`

- GET que devuelve JSON al propio app → `query()`.
- POST/PUT/DELETE del propio app → `form()` (preferido) o `command()`.
- **NO migrar**: webhooks de terceros, callbacks OAuth, endpoints que sirven binarios, rutas consumidas por apps externas — se quedan como `+server.ts` con su auth (SEC-C).

```ts
// MAL — command con redirect (no soportado)
export const delete_item = command(z.string(), async (id) => { redirect(303, '/items'); });

// BIEN — command retorna, el cliente navega; o usar form (si soporta redirect)
export const delete_item = command(z.string(), async (id) => {
  await requirePermission('eliminar:item');
  await db.delete(items).where(eq(items.id, id));
  await get_items().refresh();
});
```

## R5 — Single-flight: refresh explicito tras cada mutacion (AP11)

`form` sin instruccion refresca TODO (desperdicio); `command` no refresca NADA (datos stale). Toda mutacion migrada declara su estrategia:

| Situacion | Estrategia |
|---|---|
| El server sabe que cambio | dentro del handler: `await get_items().refresh()` |
| El server ya tiene el dato nuevo | `get_item(id).set(result)` |
| Solo el cliente conoce la instancia exacta (args con filtros) | `await submit().updates(get_items({ filter }))` o `await mi_command(x).updates(...)` |
| Feedback instantaneo | `.updates(get_likes(id).withOverride((n) => n + 1))` — se revierte si falla |

Nota de version: en SvelteKit reciente los refreshes pedidos por el cliente via `.updates()` deben ser **aceptados** en el handler con `requested(get_items, limite).refreshAll()` (el limite es defensa DoS); en versiones previas el server los aplicaba implicito. Revisar la version del repo antes de elegir la variante.

## R6 — Data estatica → `prerender()`

Datos que cambian a lo sumo por deploy (catalogos, paginas de contenido): `prerender()` en vez de `query()` — se resuelve en build y viaja por CDN. Con argumentos, declarar `inputs` para que el crawler los genere. Ojo con la asimetria: las `query` NO funcionan en paginas totalmente prerendereadas (`export const prerender = true`, tipico de adapter-static) — `prerender()` si, y es justamente el reemplazo correcto ahi.

## R7 — N+1 en listas → `query.batch()`

```ts
// BIEN — una sola query para todos los ids del mismo tick
export const get_weather = query.batch(z.string(), async (ids) => {
  await requireUser();
  const rows = await db.select().from(weather).where(inArray(weather.cityId, ids));
  const lookup = new Map(rows.map((r) => [r.cityId, r]));
  return (id) => lookup.get(id);
});
```

Usar cuando el componente de cada item de una lista pide sus propios datos.

---

## Checklist por feature migrado

- [ ] `<feature>.remote.ts` nombrado por feature, en la carpeta de la ruta
- [ ] guard primera linea de CADA funcion; schema zod en toda funcion con argumentos
- [ ] cero `load()`/`actions`/`fetch` interno restantes en el feature (los `+server.ts` que quedan tienen razon declarada)
- [ ] toda mutacion con estrategia de refresh explicita (R5)
- [ ] pagina sin logica: solo `$derived(await ...)` + render; boundary para pending
- [ ] check + browser test del feature ANTES de migrar el siguiente
