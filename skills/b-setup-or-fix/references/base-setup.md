# Modo base — la base canónica de un proyecto SvelteKit

> Se aplica con `--init`, cuando `audit.sh` reporta `mode=base`, y como paso 1-2 de E1 en un rescate. Es idempotente: lo que ya existe no se pisa. El layout del slice es el de `../../b2-build-feature/references/slice-spec.md` — ante contradicción, gana ese archivo.

Que NO hace este modo: nada especulativo. Cero capas, cero carpetas vacías, cero scaffolding "para después" (YAGNI). Un slice de ejemplo solo si el usuario nombra un feature concreto.

## 1. Flags experimentales

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

Van donde la config YA vive — verificar antes de crear nada:
- `vite.config.{js,ts}` pasa opciones a `sveltekit({...})` → mergear los flags ahí. Desde @sveltejs/kit 2.62.0 la config puede ir inline en el plugin y en ese caso `svelte.config.js` se IGNORA (crearlo sería un no-op silencioso). `sv create` >= 0.16.0 (jun 2026) scaffoldea así, sin `svelte.config.js`.
- Existe `svelte.config.js` y `sveltekit()` va sin opciones → mergear ahí (adapter, preprocess, etc. se respetan).
- SK3 (`SK_MAJOR=3`): `svelte.config.js` ya no se soporta, solo `sveltekit({...})` en `vite.config`; remote functions siguen experimentales (mismos flags). Delta completo: `../../b2-build-feature/references/sveltekit-3.md`; prácticas con remote functions: `../../b2-build-feature/references/sveltekit-3-remote-functions.md`.
- Ninguno tiene config → flags dentro de `sveltekit({...})` en `vite.config`.

Requiere SvelteKit >= 2.27; si la versión no alcanza, proponer el upgrade al usuario — no forzarlo.

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

## 3. Auth de pruebas del browser — decidir y declarar

El pipeline verifica pantallas en browser (b7-screen-review por PR, walkthrough del epic-review). CÓMO obtiene sesión depende del proyecto — su auth, su base de datos y sus criterios de seguridad — así que se decide UNA vez acá, con el usuario (gate, no adivinar), y queda DECLARADO en el CLAUDE.md del repo. Los skills leen esa sección; sin ella, cada run improvisa el método y las pantallas protegidas quedan sin evaluar.

Analizar el repo y proponer (en este orden de preferencia):

1. **¿Usuario de prueba en seeds?** (grep seeds/fixtures por emails `@test`/`@dev`, tabla users) → `dev-user`: el browser llena el form de login con credenciales de env vars.
2. **¿Endpoint de login solo-dev?** (ruta guardada por `import.meta.env.DEV` / `NODE_ENV`) → `dev-endpoint`. Si no existe y el equipo lo acepta, crearlo es un slice de infra chico — la mejor opción para apps OAuth-only.
3. **¿DB dev accesible y tabla de sesiones conocida?** → `session-mint`: `mint-dev-session.sh` inserta la fila de sesión directo (overrides `B7_SESSION_*` si el schema difiere).
4. **¿Nada de lo anterior / política estricta?** → `manual-cookies`: pedir al usuario UN login manual y reusar las cookies de esa sesión.

Sección a escribir en el CLAUDE.md del repo (los skills la parsean — mantener el formato `clave: valor`):

```markdown
## Auth de pruebas (browser)

- estrategia: dev-user | dev-endpoint | session-mint | manual-cookies
- login_url: /login                      # dev-user
- credenciales: env TEST_USER_EMAIL / TEST_USER_PASSWORD   # dev-user — SOLO nombres de env vars
- endpoint: /dev/login?as=<email>        # dev-endpoint (404 fuera de dev)
- email_seed: <email>                    # session-mint (B7_SESSION_EMAIL) + overrides B7_SESSION_* si aplican
- nota: <lo que un run nuevo necesita saber>
```

Solo las claves de la estrategia elegida. Reglas de seguridad: NADA de esto puede funcionar en producción (dev-user solo en seeds locales, dev-endpoint guardado por flag de build); secrets SIEMPRE por env var referenciada por NOMBRE — jamás un password en CLAUDE.md.

## 3b. `CLAUDE.md` del repo — la doctrina en 10 líneas

```markdown
# Reglas del proyecto

- Cada feature vive completo y plano en `src/routes/<feature>/`: `+page.svelte` (pantalla) + `data.remote.ts` (TODO el manejo de datos). Se agregan en la misma carpeta, solo cuando hacen falta: `<Componente>.svelte`, `schemas.ts`, `<nombre>.server.ts`, tests `*.spec.ts` junto al archivo y `README.md`. Sin subcarpetas `server/`, `ui/`, `docs/` ni `tests/`.
- Datos SOLO via remote functions (`query`/`form`/`command` de `$app/server`) en `data.remote.ts`: sin `+server.ts` internos, sin `fetch` manual, sin `load()` (no crear `+page.server.ts`, `+layout.server.ts` ni `+page.ts`; el guard de página vive en `hooks.server.ts`). Camino más corto: Drizzle -> remote function -> componente; cero capas intermedias.
- Código de servidor que no es remote lleva sufijo `.server.ts`: dentro de `src/routes` una carpeta `server/` no protege nada. Siempre `.ts`, nunca `.js`.
- SQL-first: filtros, group by, agregaciones y aritmética en la query (Drizzle); JavaScript solo lo mínimo justificable. Debug de datos = `data.remote.ts`, un solo archivo.
- Toda remote function: guard (`requireUser`/`requirePermission`) primera línea + schema zod si recibe argumentos. Nombres `snake_case`.
- Svelte 5 runes siempre: `$state`/`$derived`/`$props`/snippets; `onclick` no `on:click`; `$effect` solo para efectos reales (DOM, timers).
- Mutación => refresh explícito (`.refresh()` / `.updates()`), nunca datos stale.
- `src/lib/` solo para lo que usan 3 o más features (ui shadcn, db, auth). Con dos consumidores, el segundo importa desde la carpeta del primero.
- Sin comentarios salvo `// ponytail:` (atajo deliberado, nombra el techo). Los porqués viven en el `README.md` del feature (solo si hace falta) y `docs/ARCHITECTURE.md`, no en el código.
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
| <feature> | `src/routes/<feature>/` | [`README.md`](../src/routes/<feature>/README.md) |

## Transversales ($lib)
- `$lib/server/db` — cliente Drizzle
- `$lib/server/auth` — requireUser / requirePermission
- `$lib/components/ui` — shadcn-svelte

## Decisiones
- <fecha> — <decision y por qué> (las decisiones de features viven en su README.md)
```

Se actualiza la tabla al agregar slices. Rechazos load-bearing del usuario durante un rescate se anotan en Decisiones para no re-sugerirlos.

## 5. Política documental y de comentarios (E6)

- **Por feature**: `README.md` dentro del slice, 6 secciones (fuente única: `slice-spec.md`): Propósito, Pantallas y rutas, Remote functions, Datos, Decisiones, Problemas conocidos. Primera parada de debug; se actualiza en el mismo PR que cambia contratos o pantallas.
- **Nivel repo**: `docs/ARCHITECTURE.md` (mapa) + `CLAUDE.md` (reglas para agentes). Nada más — la doc que nadie mantiene es peor que ninguna.
- **Comentarios**: default cero. Borrar el QUÉ ("incrementa el contador"), referencias a tasks/PRs, y prosa defensiva. Preservar `// ponytail:` (con techo y upgrade path) y TODO/FIXME accionables. Contexto útil migra al `README.md` antes de borrar. Regla: si la explicación es más larga que el código, se borra la explicación.

## 6. Checklist de base instalada

- [ ] flags `remoteFunctions` + `async` donde viva la config (`vite.config` o `svelte.config.js`)
- [ ] scripts `check` y `build` presentes en `package.json`
- [ ] guards en `$lib/server/auth.ts` (o decisión explícita de no tenerlos)
- [ ] `## Auth de pruebas (browser)` declarada en `CLAUDE.md` (estrategia decidida con el usuario)
- [ ] `CLAUDE.md` con la doctrina
- [ ] `docs/ARCHITECTURE.md` semilla
- [ ] `rung-verify.sh E1` → `RUNG_VERIFY ok`
- [ ] commit via b3: `chore(genie): base sveltekit`
