# Modo base — la base canónica de un proyecto SvelteKit

> Se aplica con `--init`, cuando `audit.sh` reporta `mode=base`, y como paso 1-2 de E1 en un rescate. Es idempotente: lo que ya existe no se pisa. El layout del slice es el de `../../b2-build-feature/references/slice-spec.md` — ante contradicción, gana ese archivo.

Que NO hace este modo: nada especulativo. Cero capas, cero carpetas vacías, cero scaffolding "para después" (YAGNI). Un slice de ejemplo solo si el usuario nombra un feature concreto.

## 1. `svelte.config.js`

```js
const config = {
  kit: {
    experimental: {
      remoteFunctions: true
    }
  },
  compilerOptions: {
    experimental: {
      async: true
    }
  }
};
```

Merge sobre la config existente (adapter, preprocess, etc. se respetan). Requiere SvelteKit >= 2.27; si la versión no alcanza, proponer el upgrade al usuario — no forzarlo.

## 2. `src/lib/server/auth.ts` — guards transversales

Solo si no existen (buscar `requireUser` en `src/lib/server/` primero). Adaptar `locals.user` al mecanismo de sesión real del repo; si el repo NO tiene auth cableada (sin hooks de sesión, sin tabla users), crear los guards excede el scope — decidirlo con el usuario antes de inventar infraestructura.

```ts
import { error } from '@sveltejs/kit';
import { getRequestEvent } from '$app/server';

export async function requireUser() {
  const { locals } = getRequestEvent();
  if (!locals.user) error(401, { message: 'No autenticado', code: 'AUTH_REQUIRED' });
  return locals.user;
}

// permisos formato verbo:sustantivo — leer:informe, crear:post, eliminar:item
export async function requirePermission(permission: string) {
  const user = await requireUser();
  if (!user.permissions?.includes(permission))
    error(403, { message: `Falta permiso ${permission}`, code: 'FORBIDDEN' });
  return user;
}
```

Mapeo operación → permiso y variante `requireAnyPermission`: `../../b6-pr-review/references/security-checklist.md`.

## 3. `CLAUDE.md` del repo — la doctrina en 10 líneas

```markdown
# Reglas del proyecto

- Cada feature es un vertical slice en `src/routes/<feature>/`: página + `<feature>.remote.ts` + componentes hermanos + `<feature>.md`. La carpeta de ruta ES la carpeta del feature.
- Datos SOLO via remote functions (`query`/`form`/`command` de `$app/server`): sin `load()`, sin `+server.ts` internos, sin `fetch` manual. Camino más corto: Drizzle -> remote function -> componente; cero capas intermedias.
- Toda remote function: guard (`requireUser`/`requirePermission`) primera línea + schema zod si recibe argumentos. Nombres `snake_case`.
- Svelte 5 runes siempre: `$state`/`$derived`/`$props`/snippets; `onclick` no `on:click`; `$effect` solo para efectos reales (DOM, timers).
- Mutación => refresh explícito (`.refresh()` / `.updates()`), nunca datos stale.
- `$lib` solo para transversales genuinos (ui shadcn, db, auth, helpers de 3+ features).
- Sin comentarios salvo `// ponytail:` (atajo deliberado, nombra el techo). La documentación vive en `<feature>.md` y `docs/ARCHITECTURE.md`, no en el código.
- El código más simple que funciona, gana: nada especulativo, abstraer recién con 2+ implementaciones reales.
```

Si ya existe `CLAUDE.md`, agregar solo las líneas que falten — no duplicar ni pisar reglas del proyecto.

## 4. `docs/ARCHITECTURE.md` semilla (~30 líneas)

```markdown
# Arquitectura

## Stack
SvelteKit (remote functions + async experimental) · Svelte 5 runes · Drizzle + <db> · zod · shadcn-svelte · @lucide/svelte

## Mapa de slices
| Feature | Ruta | Doc |
|---|---|---|
| <feature> | `src/routes/<feature>/` | [`<feature>.md`](../src/routes/<feature>/<feature>.md) |

## Transversales ($lib)
- `$lib/server/db` — cliente Drizzle
- `$lib/server/auth` — requireUser / requirePermission
- `$lib/components/ui` — shadcn-svelte

## Decisiones
- <fecha> — <decision y por qué> (las decisiones de features viven en su <feature>.md)
```

Se actualiza la tabla al agregar slices. Rechazos load-bearing del usuario durante un rescate se anotan en Decisiones para no re-sugerirlos.

## 5. Política documental y de comentarios (E6)

- **Por feature**: `<feature>.md` colocado, 6 secciones (fuente única: `slice-spec.md`): Propósito, Pantallas y rutas, Remote functions, Datos, Decisiones, Problemas conocidos. Primera parada de debug; se actualiza en el mismo PR que cambia contratos o pantallas.
- **Nivel repo**: `docs/ARCHITECTURE.md` (mapa) + `CLAUDE.md` (reglas para agentes). Nada más — la doc que nadie mantiene es peor que ninguna.
- **Comentarios**: default cero. Borrar el QUÉ ("incrementa el contador"), referencias a tasks/PRs, y prosa defensiva. Preservar `// ponytail:` (con techo y upgrade path) y TODO/FIXME accionables. Contexto útil migra al `<feature>.md` antes de borrar. Regla: si la explicación es más larga que el código, se borra la explicación.

## 6. Checklist de base instalada

- [ ] flags `remoteFunctions` + `async` en `svelte.config.js`
- [ ] scripts `check` y `build` presentes en `package.json`
- [ ] guards en `$lib/server/auth.ts` (o decisión explícita de no tenerlos)
- [ ] `CLAUDE.md` con la doctrina
- [ ] `docs/ARCHITECTURE.md` semilla
- [ ] `rung-verify.sh E1` → `RUNG_VERIFY ok`
- [ ] commit via b3: `chore(genie): base sveltekit`
