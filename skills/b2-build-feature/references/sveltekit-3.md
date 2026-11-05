# SvelteKit 2 → 3 (delta)

Si el context snapshot dice `SK_MAJOR=3` aplica esta tabla; los ejemplos del plugin usan `$lib` (SK2) — en SK3 escribe `#lib/...` con extensión de archivo. Si dice `SK_MAJOR=2`, ignora este archivo. Sigue el alias que reporte el snapshot, no lo hardcodees.

Mínimos SK3: Node 22.17, TypeScript 6, Svelte 5.57.1, Vite 8.0.12, vite-plugin-svelte 7. Migración: subir a la última 2.x y correr `npx sv migrate sveltekit-3`.

| Tema | SK2 | SK3 |
|---|---|---|
| Alias | `$lib/server/db` | `#lib/server/db.ts` (declarado en `imports` de `package.json`, lo agrega `sv migrate`; imports con extensión) |
| Config | `svelte.config.js` o `sveltekit({...})` | solo `sveltekit({...})` en `vite.config`; `svelte.config.js` ya no se soporta |
| Opciones removidas | `files.lib`, `vitePlugin`, `preloadStrategy`, `prerender.origin`, `csrf.checkOrigin`, `experimental.handleRenderingErrors`, `experimental.instrumentation` | borrarlas. `experimental.tracing` → `tracing` (top-level). Nuevas: `csrf.trustedOrigins`, `paths.origin` |
| Env | `$app/environment`, `$env/static/private`, `$env/dynamic/*` | `$app/env`; `$app/env/private` y `$app/env/public` (`$env/*` deprecado) |
| Estado de página | `$app/stores` | removido: `$app/state` |
| Navegación | `pushState`/`replaceState`, `invalidateAll`, `keepFocus`/`noScroll` | `goto(url, { shallow: true, state })`, `refreshAll`; opciones de `goto`: `replace`, `state`, `reset: false` |
| Paths | `base`, `assets`, `resolveRoute` de `$app/paths` | `resolve(...)` y `asset(...)` |
| `error()` | `error(401, { message, code })` | `error(401, 'mensaje', { code })` — 2º arg siempre string, props extra en 3º. `App.Error` siempre trae `status` |
| Respuestas | `json(x)`, `text(s)` de `@sveltejs/kit` | `Response.json(x)`, `new Response(s)` (deprecados). 204/2xx vacío de `+server` sin body |
| Forms | `use:enhance` | navega si la action está en otra página; controles con `field.as(...)` |
| Remote | tipos desde kit | tipos desde `$app/server`; archivos con segmento `remote` son módulos remote; `event.url/params/route` lanzan dentro de queries. SIGUE experimental: `experimental.remoteFunctions` + `compilerOptions.experimental.async` dentro de `sveltekit({...})` |
| CSRF | `csrf.checkOrigin` | siempre activo; orígenes externos en `csrf.trustedOrigins` (origen completo con protocolo) |
| Redirect externo | `redirect(307, 'https://x')` | `redirect(307, url, { external: true })` (o lista de orígenes) |
| Cookies | nombres libres | v2: nombres ASCII; `path` por defecto `'/'` |
| Hooks | `handleValidationError` | `handleError` con `kind: 'validation'` |
| Param matchers | `src/params/<name>.ts` | un solo `src/params.ts` con `defineParams` |
| Server-only | `$lib/server`, `*.server.ts` | además cualquier archivo con segmento `server` o dir `server` fuera de `src/routes` |

Regla de slice: el contrato de errores del plugin (`code` estable) se conserva; solo cambia la forma de la llamada.
