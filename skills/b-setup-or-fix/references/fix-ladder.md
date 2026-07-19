# La escalera E1-E6 en profundidad

> La tabla canonica de la escalera vive inline en `../SKILL.md`; este archivo usa la misma numeracion y solo agrega las transformaciones exactas. La doctrina citada no se duplica aca — se resuelve con esta tabla de notacion:
>
> | Sigla | Fuente real |
> |---|---|
> | `AP1`-`AP14` | secciones 1-14 de `../../b6-pr-review/references/sveltekit-antipatterns.md` (mismo numero) |
> | `SEC-A` / `SEC-B` / `SEC-C` | secciones 1 (+page.server.ts sin auth) / 2 (remote functions sin guard) / 3 (API endpoints) de `../../b6-pr-review/references/security-checklist.md` |
> | `SEC-D` / `SEC-E` | secciones 5 (datos sensibles/secrets) / 6 (estado compartido en servidor) del mismo archivo |
> | `CAL` (calidad), `DUP` (duplicados), `REG` (callers rotos) | notacion interna de b-setup-or-fix; la doctrina vive en el SKILL.md de b6 (Areas 2 y 5) y en `../../b2-build-feature/references/simplicity-ladder.md` |

Regla transversal: cada peldaño **entra** con el repo verde (vs baseline) y **sale** con `RUNG_VERIFY ok` + commit via b3. La salida de todo peldaño es MENOS codigo — si una transformacion agrega archivos o capas, esta mal hecha.

---

## E1 — Base y seguridad

Entrada: siempre (es el primer peldaño y es idempotente).

1. **Flags experimentales** en `svelte.config.js` — config exacta en `base-setup.md`. Sin esto E3 no puede existir.
1b. **Scripts npm minimos**: `check` (svelte-check) y `build` presentes en `package.json` — sin ellos `rung-verify.sh` no tiene que verificar (reporta el sentinel 999 y el gate queda ciego; agregado el script, el gate exige limpio desde ese momento).
2. **Guards faltantes** (SEC-B): toda `query`/`form`/`command` existente llama `requireUser()` o `requirePermission('verbo:sustantivo')` como PRIMERA operacion. Si `$lib/server/auth.ts` no existe, crearlo primero (template en `base-setup.md`) — sino este fix genera BLOCKERs en cascada.
3. **Loads y endpoints que se quedan** (SEC-A/C): los que E3 migrara no se tocan aca; los que sobreviven (paginas publicas declaradas, webhooks) reciben su check de `locals.user` o API key si corresponde.
4. **Estado mutable a nivel de modulo** (SEC-E):

```ts
// MAL — compartido entre TODOS los requests (data leak)
let cache: Item[] = [];

// BIEN — no existe; si el cache es real, mecanismo explicito (KV, tabla) decidido con el usuario
```

5. **Secrets hardcodeados** (SEC-D) → `$env/static/private` o `$env/dynamic/private`.

Salida: check/build verdes, cero SEC pendientes fuera del plan.

## E2 — Estructura

Entrada: E1 verde. Riesgo: mover archivos rompe imports — **trazar callers antes de cada move** (`codegraph_callers` o `rg -n "from ['\"].*<archivo>"`), actualizar imports en el mismo cambio (REG-1).

1. Feature bajo `src/lib/features/<x>/` → `src/routes/<x>/` (layout canonico: `../../b2-build-feature/references/slice-spec.md`). Con muchos features, migrar solo los del plan aprobado — tolerancia legacy para el resto.
2. `data.remote.ts` → `<feature>.remote.ts` (nombre generico prohibido).
3. `*.remote.ts` bajo `src/lib/server/` → carpeta de la ruta (AP10: el cliente lo importa, SvelteKit lo rechaza bajo `lib/server`).
4. Subcarpeta `ui/` dentro del slice → componentes hermanos planos PascalCase.
5. Wrapper `<Feature>Page.svelte` → la UI va directo en `+page.svelte`.

Salida: `check-slice.sh` de b2 (`../../b2-build-feature/scripts/check-slice.sh <dir>`) sin violaciones sobre cada feature tocado.

## E3 — Remote functions

Entrada: E1 verde (flags presentes) + SvelteKit >= 2.27 (sino el peldaño queda **bloqueado** y se reporta). Recetas completas con codigo: `migrate-to-remote.md` (R1-R7).

**Feature por feature, nunca barrido global**: migrar `load()` cambia semantica SSR (datos heredados de layouts, waterfalls, auth heredada). Por cada feature: migrar → check → browser si hay dev server → siguiente.

| Legacy | Destino | Receta |
|---|---|---|
| `load()` en `+page(.server).ts` | `query()` en `<feature>.remote.ts` + `$derived(await get_x())` | R1 |
| `export const actions` + `use:enhance` | `form()` + `{...upsert_x}` + `fields.x.as()` | R2 |
| `onMount` + `fetch` | `query()` + `await` en el componente | R3 |
| `+server.ts` interno (GET) | `query()` | R4 |
| `+server.ts` interno (POST/mutacion) | `command()` o `form()` (preferir form) | R4 |
| Mutacion sin refresh (AP11) | single-flight: `.refresh()` server-side o `.updates()` | R5 |
| Data estatica de build | `prerender()` | R6 |
| N+1 en listas | `query.batch()` | R7 |

Excepciones que NO se migran: webhooks/endpoints consumidos por terceros, rutas de auth de librerias (better-auth, etc.), `+server.ts` que sirve archivos binarios.

Salida: cero `load()`/`actions` en los features del plan; toda mutacion con estrategia de refresh explicita; `requireUser()` primera linea de cada funcion nueva.

## E4 — Runas y stack

Entrada: E3 verde. Transformaciones mecanicas, verificables con `svelte-autofixer` sobre cada archivo tocado. Codigo de cada par en `../../b6-pr-review/references/sveltekit-antipatterns.md`; la tabla STOP (React → Svelte 5) vive en `../../b2-build-feature/SKILL.md` con version extendida en `references/svelte5-not-react.md`.

- `on:click={...}` → `onclick={...}` (AP6); `export let x` → `let { x } = $props()`; `<slot />` → `{@render children()}` (AP5); `$: y = f(x)` → `let y = $derived(f(x))`.
- `$effect` que computa o sincroniza estado → `$derived` (AP3). `$effect` legitimo (DOM, timers, subscripciones externas) se queda.
- `user = { ...user, name }` sobre `$state` → mutacion directa `user.name = ...` (AP4).
- `import { Card } from '$lib/components/ui/card'` → `import * as Card` (AP7; `Button/Input/Label/Textarea/Badge/Separator` directos son validos). `from 'lucide-svelte'` → `@lucide/svelte/icons/<icono>` (AP9). `Select.Value` → `<Select.Trigger placeholder>` (AP8).
- `onclick={() => goto('/x')}` → `<a href>` / `<Button href>` (AP1; `goto` post-accion se queda).

Salida: cero sintaxis Svelte 4 en los archivos del plan; autofixer limpio.

## E5 — Desingenieria y duplicados

Entrada: E4 verde. El peldaño con mas juicio y menos grep — el script solo da el catalogo.

1. **Deletion test** sobre cada capa sospechosa (service/repository/factory/wrapper): imaginar borrarla — si la complejidad desaparece, era pass-through (CAL-1..3): inline hacia la remote function y borrar. Si reaparece en N callers, se queda.

```ts
// MAL — 4 saltos para un SELECT
export const get_items = query(async () => itemService.list());
// itemService.list() -> repo.findAll() -> db.select()...

// BIEN — la remote function consulta Drizzle directo
export const get_items = query(async () => {
  await requireUser();
  return db.select().from(items);
});
```

2. **Duplicados** (DUP-1): zonas calientes `src/lib/utils`, `helpers`, formateo fecha/moneda, validacion. Si el skill `finding-duplicate-functions` esta disponible, usarlo; sino comparar semantica manual. Consolidar SOLO con confianza alta Y tests que cubran al survivor; ante duda, reportar como INVESTIGATE y no tocar. Al consolidar: actualizar callers (REG-1), borrar duplicados, re-verificar.
3. **Codigo muerto**: exports sin consumidor (trazar con codegraph o `rg`) se borran. Falsos duplicados a respetar: `identity`/`noop` genericos, funciones que difieren en manejo de nulls/timezones.

Salida: cada consolidacion con su lista de callers actualizados; diff neto negativo.

## E6 — Comentarios y docs

Entrada: E5 verde (se documenta el estado FINAL). Politica completa en `base-setup.md`.

1. **Podar comentarios**: borrar los que explican el QUE, los que referencian tasks/PRs, y docstrings de parrafo. Contexto UTIL (por que existe un workaround, techo de un atajo) migra al `<feature>.md` ANTES de borrar. Se preservan `// ponytail:` y TODO/FIXME accionables.
2. **`<feature>.md` colocado** por cada feature tocado, con las 6 secciones de `slice-spec.md`: Proposito, Pantallas y rutas, Remote functions, Datos, Decisiones, Problemas conocidos.
3. **Doc nivel repo**: `docs/ARCHITECTURE.md` (mapa de slices + stack + decisiones) y `CLAUDE.md` con la doctrina (~10 lineas, template en `base-setup.md`).

Salida: `audit.sh` E6 en cero para los features del plan; regla de oro: si la explicacion es mas larga que el codigo, se borra la explicacion.
