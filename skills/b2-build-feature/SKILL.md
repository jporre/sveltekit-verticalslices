---
name: b2-build-feature
# model/allowed-tools omitidos a propósito: hereda los de la sesión
description: 'Construye cualquier pantalla SvelteKit — CRUD, form, dashboard o página de datos — desde una descripción directa del usuario ("crear pantalla", "build feature", o una pantalla descrita sin la palabra feature) o desde un issue triageado. Ruteo de issues, PR y merge pertenecen a b7/b8/b10, que invocan este skill como fase de build.'
---

# Build Feature

SvelteKit features are SMALL. Typical feature = 3-5 files, 15-35 KB total.
No unnecessary layers. The shortest path: **Drizzle query -> remote function -> Svelte component**.

**Build lazy: stop at the first rung that holds.** Need it at all? (YAGNI, skip and say so) → stdlib/SvelteKit does it? → native platform feature (`<input type="date">`, CSS, DB constraint)? → already-installed dep? → one line? → only then the minimum code. No abstraction nobody asked for, no service layer for CRUD, no `query → fn → drizzle-wrapper → fn → query` indirection — the remote function queries Drizzle directly. Fewest files, shortest working diff. Mark deliberate shortcuts with a `// ponytail:` comment (the sanctioned exception to the no-comments default). Full discipline: `references/simplicity-ladder.md`.

## Colocation

**The route folder IS the feature folder.** Everything for a feature lives in one
folder under `src/routes/` — page, remote functions, components, types. Only `+`-prefixed files
are special to the router, so `server/data.remote.ts`, `ui/<Componente>.svelte` components, and
`<feature>-types.ts` live inside the route folder next to `+page.svelte`. No `src/lib/features/`
split, no thin wrappers. One folder you can review, debug, and copy to another project as a unit. Shared-only
code (shadcn `$lib/components/ui`, `$lib/server/db`, cross-feature helpers) stays in `$lib`.

**Canonical spec: `references/slice-spec.md`** — the 99% rule, the exact `$lib` exception
table, the legacy tolerance (editing an existing `src/lib/features/` feature follows ITS
pattern; NEW features never go there), and the colocated `docs/readme.md` doc every new
feature ships with. When in doubt about where a file goes, that spec wins.

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
el `<form>` se conecta con spread `{...upsert_x.enhance(...)}`, cada input con `{...upsert_x.fields.name.as('text')}`, y el modo edit se pre-popula con `upsert_x.fields.set({...})`. Nada de onsubmit + fetch manual. Patrón completo con código: `references/forms-recipe.md`.
- Decisión de diseño UI (qué componente shadcn para qué patrón, tokens semánticos, dark mode, confirmación destructiva): `references/shadcn-ui.md`.

## Workflow: 4 Phases

### Phase 0: Branch

**ALWAYS create a branch before writing any code.** Nunca trabajar sobre la rama default.

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

Patrón de nombre configurable vía `git config b-pipeline.branchPattern` (o env
`B_PIPELINE_BRANCH_PATTERN`), placeholders `{type}` `{issue}` `{slug}`; default
`{type}/{issue}-{slug}`. Con lib.sh sourceado (`. "$PLUGIN_ROOT/scripts/lib.sh"`):
`git checkout -b "$(bp_branch_name feat <issue> <slug>)"`.

**No worktrees para features simples** — una rama normal basta.
For complex features that need isolation, create the worktree via `b1-add-worktree` —
a raw `git worktree add` is BLOCKED by the plugin's PreToolUse hook (it skips the env
symlinks, port allocation, and budget hook that `setup-worktree.sh` provisions):

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cat "$HOME/.claude/b-pipeline.root" 2>/dev/null || ls -d "$HOME"/.claude/plugins/marketplaces/b-pipeline* 2>/dev/null | head -1)}"
. "$PLUGIN_ROOT/scripts/lib.sh"
bash "$PLUGIN_ROOT/skills/b1-add-worktree/scripts/setup-worktree.sh" "feat/<feature-name>" "$(bp_default_branch)" --headless
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

Then propose the file structure — everything colocated in the route folder:

```
src/routes/<feature>/
  +page.svelte               # The page itself (UI here; imports from ./ui/ and ./server/data.remote)
  +page.server.ts            # route guard (auth/permission); load() solo según la regla de datos
  server/data.remote.ts      # query + form + command — all data ops (SQL-first)
  <feature>-types.ts         # types (or export them straight from server/data.remote.ts)
  docs/readme.md          # doc del feature
```

Placement: the route folder IS the feature folder (ver Colocation arriba y `references/slice-spec.md`).

Only add more files — all colocated in the same folder — when justified:

- `ui/<Feature>Form.svelte`, `ui/<Feature>Table.svelte` — componentes del feature en `ui/`, PascalCase
- `schemas.ts` — only if validation is complex (beyond basic required/type checks)
- archivos extra en `server/` — solo cuando el tamaño de `data.remote.ts` lo exija de verdad (ver `references/slice-spec.md`), NOT for simple CRUD
- sub-routes (`new/`, `[id]/`) get their own colocated `+page.svelte`; their data also comes from `../server/data.remote.ts`

### Phase 1.5: Análisis de impacto (condicional)

**Trigger:** el plan modifica símbolos EXISTENTES — un helper compartido de `$lib`, un `*.remote.ts` que ya tiene consumidores, o `schema.ts`. **Skip greenfield:** si el plan solo crea archivos nuevos en `src/routes/<feature>/`, saltar esta fase (impact set vacío) y seguir a Phase 2.

Antes de escribir código, construir el **impact set** (archivos afectados) por cada símbolo a modificar:

- Con codegraph disponible (`CODEGRAPH_STATUS=ok` del probe): tool `codegraph_impact` sobre el símbolo.
- Fallback sin codegraph (status != ok): `rg -l '<simbolo>' src`

**Gate de scope-growth:** si el impact set trae archivos fuera del feature que NO están en el plan, resolver ANTES de codear — o se agregan al plan explícitamente, o se declara scope-growth (el issue es más grande de lo previsto; corriendo bajo b7, reportarlo al sticky del issue). Nunca tocar archivos no planificados en silencio.

Corriendo bajo b7, el impact set se persiste en `.b7/state.json` campo `impact_files` (paso 4 de b7).

### Phase 2: Build

**Feature NUEVO: arranca del esqueleto por script — no improvises la estructura.**
`scaffold-slice.sh` crea el slice colocado mínimo compilable (`+page.svelte`,
`server/data.remote.ts`, `docs/readme.md`) siguiendo `references/slice-spec.md` (regla 99%,
remote SOLO bajo `server/`, sin capa service; `ui/` y `tests/` se crean cuando hay contenido):

```bash
bash "$CLAUDE_PLUGIN_ROOT/skills/b2-build-feature/scripts/scaffold-slice.sh" <feature> [--route-group <g>]
# → SCAFFOLD_OK dir=src/routes/<feature> files=<csv>
```

Después rellenas esos archivos (pasos siguientes). Para editar un feature legacy
existente NO scaffoldees: sigue su patrón interno.

Write files in this exact order. Use absolute paths, avoid cd. **Batch file writes** — escribe
todos los archivos y verifica una sola vez. El código copy-paste completo de cada step vive en
`references/feature-templates.md` (Template 1); acá solo el orden, nombres y gotchas:

**Step 1: Types** (`<feature>-types.ts`) — `InferSelectModel` sobre la tabla Drizzle; en features
simples exporta los types directo desde `server/data.remote.ts`. Si la tabla no existe, crea el
schema Drizzle primero (skill `postgresql-table-design` si está disponible).

**Step 2: Remote functions** (`server/data.remote.ts`) — el archivo CORE, SQL-first:
`query` (list) + `form` (UN upsert con `id` opcional) + `command` (delete). Siempre
`server/data.remote.ts`, nunca `*.remote.ts` suelto en la raíz de la ruta (patrón anterior
`<feature>.remote.ts`) ni bajo `src/lib/server/` (el cliente lo importa). Toda remote
function llama `requireUser()` (importado de `$lib/server`, ver `references/slice-spec.md`) como
primera operación — b6 marca BLOCKER si falta.

**Step 3: Page** (`+page.svelte`) — la UI va directo en `+page.svelte`: importa `./server/data.remote`
y componentes de `./ui/`; sin wrapper `<Feature>Page.svelte`. Query con `$derived(await get_x())`,
form con `{...upsert_x.enhance(...)}` + `fields.as(...)`, refresh con `.updates(get_x)` /
`get_x.refresh()`.

**Step 4: Route guard** (`+page.server.ts`, opcional pero recomendado) — las remote functions ya
chequean auth, pero un `load` que tira `error(401, {...})` si `!locals.user` evita renderizar una
página que el usuario no puede usar.

When a feature needs more screens, split into `ui/` components and sub-route folders
(`new/+page.svelte`, `[id]/+page.svelte`) — the route folder IS the feature folder (ver Colocation).

### Phase 3: Verify (MANDATORY — no exceptions)

Code that compiles but hasn't been tested in a browser is NOT done.

0. **Conformidad del slice (mecánico)** — antes de type-check, corre:
   ```bash
   bash "$CLAUDE_PLUGIN_ROOT/skills/b2-build-feature/scripts/check-slice.sh"
   # → SLICE_CHECK ok | SLICE_CHECK violations=<n>
   ```
   Cualquier `VIOLATION` (feature nuevo bajo `src/lib/features/`, `*.remote.ts` fuera de
   `server/`, `*.remote.ts` bajo `src/lib/server/`, slice nuevo sin `docs/readme.md`) se corrige
   ANTES de seguir. Es la misma verificación que corre b6 en el review.
1. **Correr `verify.sh`** — los gates mecánicos como script (branch guard, `check:machine`,
   `format`, grep anti-React scoped al diff, `test:unit` condicional, browser-gate):
   ```bash
   bash "$CLAUDE_PLUGIN_ROOT/skills/b2-build-feature/scripts/verify.sh"
   # ultima linea: VERIFY_RESULT branch=ok check=ok react=ok test=ok|skipped browser=required|not-needed svelte_files=<csv>
   # exit 3 rama default (o main/master) | 4 check:machine | 5 patron React (file:line) | 6 test:unit
   ```
   Si sale non-zero: corregir lo que reporta y re-correr hasta exit 0. No avanzar
   con un gate en `fail`.
2. **Autofixer** — correr MCP `svelte-autofixer` sobre cada archivo del csv
   `svelte_files=` de la línea `VERIFY_RESULT`. Si reporta issues: corregir y volver
   al paso 1 (verify.sh de nuevo — el fix puede romper types o formato).
3. **Browser test con `agent-browser`** — SOLO si `VERIFY_RESULT` dice `browser=required`
   (el diff toca `src/routes/**`, `*.svelte` o `*.remote.ts`). Con `browser=not-needed`
   se omite dejando nota en el reporte. El walkthrough NO es opcional cuando es required.
   **`agent-browser` CLI, nunca las tools MCP de Chrome:** el CLI deja los PNG en disco;
   un screenshot vía MCP entra al contexto y se re-lee en cada request de la sesión.
   - Open the page, take a screenshot — does it render?
   - Check server terminal for errors (`grep -i error` on dev server output)
   - Test each operation: list loads, create works, edit pre-populates, delete removes
   - If the page has a form: test BOTH create and edit mode
4. Fix any issues found, repeat from step 1

If you can't browser-test (no credentials, server down), tell the user explicitly:
"I verified types and autofixer but could NOT browser-test because [reason]."
Never claim a feature is done without stating what was and wasn't tested.

Read `references/verification-checklist.md` for the browser walkthrough how-to.

### Phase 4: Finalize

After verification passes:

1. **Write/update the feature doc `docs/readme.md`** — colocado en `src/routes/<feature>/docs/readme.md`.
   Es la primera parada de debug (ver `references/slice-spec.md`). No es opcional:
   - **Feature NUEVO** → crear `docs/readme.md` con las 6 secciones del slice-spec:
     **Propósito** (2-3 líneas, lenguaje de usuario), **Pantallas y rutas** (qué se ve, dónde),
     **Remote functions** (nombre + una línea de contrato c/u), **Datos** (tablas/vistas que toca),
     **Decisiones** (por qué así, atajos `ponytail:` relevantes), **Problemas conocidos**.
   - **Feature EXISTENTE con `.md`** → actualizarlo en ESTE PR si el cambio altera contratos
     (remote functions, datos) o pantallas.
   - **Feature legacy tocado SIN `.md`** → generarlo esta primera vez que un issue lo toca.

2. **Update CHANGELOG.md** — add entry under new date section
3. **Gate final de conformidad** — re-correr `check-slice.sh` (paso 0 de Phase 3);
   debe salir `SLICE_CHECK ok`. Con violaciones NO se commitea.
4. **Commit on the branch** — invoke `Skill b-pipeline:b3-git-commit` (in pi: load
   `skills/b3-git-commit/SKILL.md` with `read` and follow it; pass the issue
   number if any: it adds the `Refs #N`, stages only your files with intelligent
   grouping, and runs the mandatory clean-tree gate). Do NOT hand-write `git add` +
   `git commit` — two competing commit procedures is how messages drift and files
   get staged by accident.

5. **Report to user** — summarize what was built, what was tested, what's ready for merge. If working from an issue, remind to use `Closes #<N>` in the PR body (the `b4-pull-request` skill will handle this if given the issue number)

## Golden Rules
1. **Auth in remote functions** — `requireUser()` importado de `$lib/server`, never in services
2. **Colocate in the route folder** — the route folder IS the feature folder (ver Colocation y `references/slice-spec.md`)
3. **$derived for filtering** — client-side for <1000 items
4. **snake_case functions** — `get_items`, `upsert_item`, `delete_item`
5. **Lazy ladder** — stop at the first rung that holds; no unrequested abstraction; mark deliberate shortcuts with `// ponytail:` (see `references/simplicity-ladder.md`)

Todo lo demás (upsert único, `$derived` para queries, `fields.as`, namespace imports, `error()` throws, `href`) ya vive en la tabla STOP de arriba.

## When to Read References

| Situation                                     | Read                                   |
| --------------------------------------------- | -------------------------------------- |
| Where does this file go? / layout doubts      | `references/slice-spec.md`             |
| React->Svelte doubts                          | `references/svelte5-not-react.md`      |
| Tempted to add a layer/abstraction/dependency | `references/simplicity-ladder.md`      |
| Need copy-paste templates                     | `references/feature-templates.md`      |
| Browser walkthrough (`browser=required`)      | `references/verification-checklist.md` |
| Feature has 4+ screens                        | `references/complex-features.md`       |
| URL-synced page state (filter/tab/month)      | `references/url-synced-state.md`       |
| Screen has a create/edit form (`form()` + shadcn) | `references/forms-recipe.md`        |
| Screen lists/filters/exports DB records       | `bt1-data-table` skill — invoke it, do NOT hand-roll the table |
| Remote function details / forms               | `using-remote-functions` skill         |
| Drizzle / Postgres table patterns             | `postgresql-table-design` skill        |
| Svelte 5 runes                                | `svelte-runes` skill                   |
| Auth & permissions                            | `../b6-pr-review/references/security-checklist.md` |

> Los skills externos (`bt1-data-table`, `using-remote-functions`, `postgresql-table-design`,
> `svelte-runes`) son del entorno del usuario: si no aparecen en la lista de skills
> disponibles, seguir con las references del plugin y decirlo en el reporte.

## Complexity Guide

| Size                               | Files | Approach                                                           |
| ---------------------------------- | ----- | ------------------------------------------------------------------ |
| Simple (1 entity, 1 screen)        | 3-4   | Implement directly                                                 |
| Medium (2-3 entities, 2-3 screens) | 5-8   | Brief plan, implement screen by screen with verification           |
| Complex (3+ entities, 4+ screens)  | 8-15  | Read `references/complex-features.md` FIRST, then screen by screen |

**Critical for medium/complex:** build by SCREEN not by LAYER. Each screen must type-check
and work in the browser before starting the next. This prevents the "50 tasks complete,
feature broken" failure mode. Read the complex features reference for the full strategy.