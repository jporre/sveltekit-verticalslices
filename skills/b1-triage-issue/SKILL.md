---
name: b1-triage-issue
description: 'Triage de un GitHub issue: evalúa, etiqueta y postea el comentario de evaluación antes de desarrollar. Usar cuando pidan triage/evaluar/revisar el issue #N o "tarea N" (tarea = issue en este codebase), o cuando otro skill (b10-ship, b7-issue-to-pr, b8-swarm) necesite un issue triageado. NO es la entrada de "resuelve el issue N" (eso es b10-ship) ni de features descritas sin issue (eso es b2-build-feature).'
context: fork
agent: Explore
model: sonnet
---

# Triage Issue

## Argumentos recibidos

```text
$ARGUMENTS
```

> Skill `context: fork`: el subagente solo ve este `SKILL.md`. El placeholder `$ARGUMENTS` es la ÚNICA vía por la que el número de issue tipeado llega al fork — el harness lo sustituye. El primer token es el número/URL del issue. Si aparece vacío o sin sustituir, abortar pidiendo el número de issue.

**Flag `--auto`** (para orquestadores como b10-ship): modo desatendido, cero preguntas interactivas; los deltas van marcados "(Con `--auto`)" en cada step. Todo lo demás idéntico al modo normal.

Development that starts from a GitHub issue must understand, research, and enrich it before any code gets written. The objective is three outputs:

1. Proper labels on the issue
2. A structured evaluation comment **in the issue's language**
3. A terminal summary telling the user whether the issue is ready to build

## Step 1: Fetch issue (two-phase, lazy comments)

Start narrow — pull only what triage actually consumes:

```bash
gh issue view <N> --json number,title,body,state,labels,comments \
  -q '{number,title,state,body,labels:[.labels[].name],firstComments:(.comments[:3]|map({author:.author.login,bot:(.author.login|test("\\[bot\\]$")),body})),commentCount:(.comments|length)}'
```

> OJO: `gh issue view --json comments` NO expone `author.type` (solo `login`) — detectar bots por el sufijo `[bot]` del login.

Title, body, labels, state, the first 3 comments, and a count. Most triages resolve here without ever reading the full thread.

**Re-fetch all comments only if** any of:
- Comment count > 3 AND any of the first 3 contradicts or refines the body
- Body is short/ambiguous and acceptance criteria likely live in the discussion
- Reporter explicitly asked to "read the discussion"

When you do re-fetch, filter noise:

```bash
gh issue view <N> --json comments \
  -q '.comments[] | select(.author.login | test("\\[bot\\]$|^github-actions$|^renovate";"i") | not) | select((.body|length) > 20)'
```

This drops Renovate/dependabot/github-actions comments and reaction-only ones ("+1", "👍", emoji-only).

Closed issues: warn the user, proceed only if they insist. (Con `--auto`: abortar emitiendo `TRIAGE_RESULT {"issue":<N>,"verdict":"closed"}`.)

## Step 2: Early-exit checks

Before any research, decide if the work can short-circuit. Triage that races to "needs-info" or "duplicate" doesn't need codebase grep.

**Already triaged?** If labels include any of `ready`, `needs-info`, `blocked`, `duplicate`, OR a previous comment starts with `## Evaluacion de Issue` / `## Issue Evaluation`, surface the prior verdict and ask the user whether to re-triage. Don't redo research silently — it wastes tokens and risks contradicting prior alignment. (Con `--auto`: no preguntar — re-evaluar solo si hay comentarios humanos nuevos, si no reusar el veredicto.)

**Issue de b0 (label `ready` sin comentario de evaluación).** Un sub-issue creado por `b0-conversation-to-issues/create-epic.sh` nace con label `ready` pero **sin** comentario `## Evaluacion de Issue` — su grounding y gate humano ya se pagaron en b0. Con `--auto`, si no hay comentarios humanos posteriores a la creación del issue: **reusar sin research**. Derivar el veredicto de los labels en vez de re-explorar:

- `verdict` = `ready` (por el label)
- `complexity` = `simple` | `medium` | `complex` (el label de complejidad presente)
- `type` = `feature` | `bug` | `enhancement`
- `scope` = valor de `scope:*`
- `blocked_by` = números `#N` de la sección `## Blocked by` del body (o `[]` si no hay)

Emitir el `TRIAGE_RESULT` con esos campos y terminar. Si apareció un comentario humano posterior a la creación → correr triage completo normal (el humano cambió algo).

**Trivially incomplete?** If `body` is empty or <100 chars and no acceptance criteria appear in the first comments, skip Steps 3-4 entirely and go straight to Step 6/7 as `needs-info`. There is nothing to ground.

**Obvious duplicate?** Run the single search from 4d first; if a hard match exists, classify as `duplicate` without further research.

## Step 3: Detect language

Identify the primary language from body + comments. **All GitHub responses (Step 7 comment) must be in that language.** Terminal output stays in your default.

Spanish issue → Spanish comment. English → English. Mixed → use the body's language; if mixed in equal parts, write in both.

## Step 4: Research the codebase (bounded)

Only reach this step when Step 2 didn't short-circuit. The goal is grounding, not exhaustive exploration.

**4-probe. Probe codegraph antes de grepear (fallback rg siempre disponible).** No confiar en "existe `.codegraph/`": la db puede estar rota o stale. Correr el probe compartido; el `CODEGRAPH_STATUS` elige la vía de grounding y se anota en `grounding_source` del triage.

```bash
bash "$CLAUDE_PLUGIN_ROOT/skills/b1-add-worktree/scripts/codegraph-probe.sh" .   # -> CODEGRAPH_STATUS=ok|stale|missing|broken
```

- `ok` → usar `codegraph_search "<entidad>"` en el main loop para aterrizar paths reales; `grounding_source: "codegraph"`.
- `stale`/`missing`/`broken` → NO invocar tools `codegraph_*` (datos stale o fallan); usar el `rg` de 4a como fallback; `grounding_source: "rg"`. El probe SIEMPRE sale 0; codegraph es recomendación, nunca gate.

**Gate anti-fabricación en `files_likely`.** Todo path que exista en el repo DEBE venir del output de una herramienta (codegraph/rg/fd), no de memoria. Un archivo que aún no existe y hay que crear va como glob marcado (ej. `src/routes/<feature>/+page.svelte (nuevo)`). No listar un path existente sin haberlo visto en un output. Si no se pudo verificar ningún path, dejar `files_likely: []` y decirlo en el triage.

**4a-doc. Read the feature doc FIRST (antes del grep).** Si el issue es un bug o cambio sobre un feature EXISTENTE, leer su doc colocado `src/routes/<feature>/<feature>.md` (o el `docs/` legacy si el feature vive bajo `src/lib/features/`) ANTES de grepear entidades. El `.md` es la primera parada de debug: da propósito, pantallas/rutas, remote functions, datos y problemas conocidos sin escanear código. Si existe, citarlo en el triage (sección Archivos / Files) y usarlo para acotar el grep de 4a. Si no existe, seguir con 4a normal.

```bash
# El nombre del feature suele salir de las entidades del issue.
fd -g '<feature>.md' src/routes 2>/dev/null || find src/routes -name '<feature>.md'
```

**4a. Extract entities.** Pull 1-3 nouns the issue is about (e.g., "productos", "ventas", "auth", "campaigns"). For each, one targeted grep:

```bash
rg -l "<entidad>" src/routes src/lib/server/db/schema
```

Open a file only when the match count justifies it (>1 hit, or the path is the obvious owner — e.g., `src/routes/<entidad>/`). Do not open the full directory tree. Do not read README unless the issue references concepts you don't recognize.

**4b. Already implemented?** If 4a lands on a feature route folder matching the request, read its `+page.svelte` and `<entidad>.remote.ts` only. If the function/screen exists → mark `duplicate` and stop researching.

**4c. Affected files.** List specific paths that would change. This grounds the complexity estimate and the risk checklist below.

**4d. Related issues + PRs (one combined call).**

```bash
gh search issues "<2-3 keywords> repo:$(gh repo view --json nameWithOwner -q .nameWithOwner)" --limit 10
```

**4e. Evidence-first (solo bugs / `type: fix`).** Un bug no es `ready` por afirmar un síntoma: hace falta al menos **un artefacto observado** que confirme síntoma y causa. Antes de marcar ready un `fix`, obtener evidencia observable y guardarla en `evidence` del triage:

- `evidence.observed` — cita textual del artefacto: mensaje de error exacto, salida de comando, línea de log, o snippet de código (path:línea) que reproduce/explica el bug. Pegar lo observado, no parafrasear.
- `evidence.source` — de dónde salió: comando corrido, `path:línea`, URL de CI, o comentario `#N`.

Si NO se logra observar el síntoma ni ubicar la causa en código, degradar a **needs-info**: la verificación pendiente pasa a ser una pregunta concreta (ej. "No pude reproducir el error; pega la salida exacta de `<comando>` o el stack trace"). Un `fix` sin `evidence.observed` no avanza: b7 tiene un gate determinístico (jq) que lo trata como needs-info y baila.

## Step 5: Evaluate quality and risk

Assess against these criteria:

| Criterion           | Check                                                      |
| ------------------- | ---------------------------------------------------------- |
| Entity clarity      | Is it clear what data/entity is involved?                  |
| Operation clarity   | What needs to happen? (CRUD, behavior change, UI addition) |
| Scope               | Boundary defined or open-ended?                            |
| **Vertical slice**  | Does it deliver a usable **screen** end-to-end, or is it a horizontal technical layer? (see below) |
| Acceptance criteria | How will anyone know it's done?                            |
| Dependencies        | Does this need other work to land first?                   |

Classification: **ready** | **needs-info** | **duplicate** | **blocked**.

### Vertical-slice check (gate antes de marcar ready)

Este proyecto es **screen-first / Vertical Slice Architecture**: cada issue que entra a build debe ser una **rebanada vertical** — algo que un usuario puede USAR al mergearse, cruzando todo el stack (Drizzle → Remote Function → pantalla en `src/routes`). Un issue que entrega solo una **capa técnica** rompe el modelo: b2/b7 construyen y revisan por pantalla, no por capa, y un slice horizontal no se puede verificar en browser ni cierra nada útil.

Señales de **capa horizontal** (mal slice) en el título/cuerpo:

- "crear el schema/migración de todo el módulo", "escribir todas las remote functions", "maquetar los componentes", "conectar el front al back".
- El issue no nombra ninguna **ruta/pantalla** (`/<feature>`) ni un journey de usuario.
- Lo entregable no se puede ver/usar en el browser por sí solo.

Acción cuando el issue es horizontal:

- **needs-info** con una pregunta concreta que proponga re-slicear en vertical: "Este issue es una capa horizontal (solo `<X>`). En este proyecto cada tarea debe entregar una pantalla usable end-to-end. ¿Lo reescribimos como slice vertical (ej. 'listar `<entidad>` en `/<feature>`') o lo partimos en slices con `/b-pipeline:b0-conversation-to-issues`?"
- Si es parte de un feature más grande mal cortado, recomendar pasar el contexto por **b0** (que slicea en vertical + arma el epic) en vez de buildearlo tal cual.

**Excepción — concerns transversales:** auth, db, storage, notificaciones y audit son infra genuinamente transversal, no features. Un issue legítimamente backend (ej. "agregar índice a `taVentas`", "rotar el secreto de storage") NO es un mal slice — no exige pantalla. Marcar estos como `ready` normal; el `## Pantalla(s)` del body se reemplaza por `## Remote functions / endpoints` (mismo criterio que b0). La regla horizontal aplica a **features de producto** partidas por capa, no a infra transversal.

**Flag `data_table` por pantalla:** al poblar cada pantalla del contrato de triage, marcar `data_table: true` cuando la pantalla lista datos tabulares — su `acceptance_criteria_visual` menciona columnas, orden, filtros o paginación. Rutea el build al skill `bt1-data-table` (ver `$CLAUDE_PLUGIN_ROOT/skills/b7-issue-to-pr/templates/triage-output.schema.json`). Omitir o `false` si la pantalla no muestra una tabla de datos.

### Risk checklist (conditional — only flag what the affected files trigger)

Walk this once using the file list from 4c. Each row produces at most one bullet in the evaluation comment IF its trigger fires. Most issues fire zero or one — that's expected.

| Trigger (path / change kind)                       | Flag in comment                                                                                       |
| -------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| Touches auth, permissions, sessions, OAuth         | **security**: validate `requireUser` / `requirePermission` + structured error (`AUTH_REQUIRED`, `FORBIDDEN`) |
| Touches `*.remote.ts` or `src/lib/server/db/schema` | **data**: needs Zod schema; if schema changes, include migration plan and `app.route_permissions` impact |
| Adds a new route under `src/routes`                | **perms**: must register in `app.route_permissions` + assignment, or the layout guard redirects to fallback |
| Affects public API or a core feature               | **docs**: update `docs/` (or a markdown colocated in the feature route folder) and `CHANGELOG`        |

## Step 6: Apply labels (combined with Step 7)

Discover existing labels once per session (cache if you've already pulled them):

```bash
gh label list --limit 100 --json name -q '.[].name'
```

Use existing labels first. Only create when none match. Categories to cover:

- **Type**: `feature`, `bug`, `enhancement`, `docs`
- **Readiness**: `ready`, `needs-info`, `blocked`, `duplicate`
- **Complexity**: `simple`, `medium`, `complex` (maps to b2's 3-5 / 5-8 / 8-15 file scale)
- **Scope**: `scope:<area>` based on affected module

Label application and comment posting (Step 7) share the same verdict — emit them in the same turn with two parallel `gh` calls. Do not reason twice over the same evaluation.

```bash
gh issue edit <N> --add-label "ready" --add-label "feature" --add-label "scope:productos"
```

Creating a missing label (follow repo color/naming conventions):

```bash
gh label create "needs-info" --description "Issue needs clarification before work can start" --color "FBCA04"
```

Never remove existing labels — only add the missing ones.

## Step 7: Post evaluation comment (compact template)

Write the comment in the language detected in Step 3. Use the compact structure below. **Full per-classification examples live in `$CLAUDE_PLUGIN_ROOT/skills/b1-triage-issue/references/comment-templates.md` — read that file only when actually drafting.**

Compact structure:

```
## Evaluacion de Issue   (or Issue Evaluation)

**Estado / Status**: <ready | needs-info | duplicate | blocked>

**Entendimiento / Understanding**: 2-3 lines. Cite relevant comments as #N when they refined the body.

**Archivos / Files**: bullets with exact paths from Step 4c.

**Complejidad / Complexity**: simple | medium | complex — one-line justification (simple = 3-5 files, medium = 5-8, complex = 8-15).

**Riesgos / Risks**: only the bullets the Step 5 checklist triggered. Omit the section entirely if none.

**Evidencia / Evidence** (solo bugs / `type: fix`): cita el artefacto observado de Step 4e — error exacto, salida de comando, o `path:línea` de la causa — con su fuente. Omitir la sección si el issue no es un bug. Un `fix` marcado ready SIN esta sección es incoherente: o hay evidencia, o el veredicto es needs-info.

**Plan**: numbered steps (ready)
   — OR —
**Preguntas / Questions**: numbered, concrete, codebase-grounded (needs-info).
```

Post via heredoc:

```bash
gh issue comment <N> --body "$(cat <<'EOF'
<contenido>
EOF
)"
```

For `needs-info`, anchor every question in the codebase. Bad: "¿puedes aclarar?". Good: "El issue menciona 'ventas' pero existen `taVentas` (cabecera) y `taVentasDetalle` (líneas). ¿Cuál entidad gestiona la pantalla?".

**Marker obligatorio en needs-info:** el comentario de preguntas termina SIEMPRE con un marker HTML invisible con timestamp UTC, para que la reanudación automática detecte respuestas posteriores comparando fechas de comentarios:

```
<!-- b10:questions 2026-06-10T15:30:00Z -->
```

## Step 8: Report to user (terminal)

Short summary, no markdown headings:

- Classification (ready / needs-info / duplicate / blocked)
- Key codebase finding (1-2 lines)
- Recommended next step:
  - **ready**: "Issue #N listo. Procede con b2-build-feature referenciando #N."
  - **needs-info**: "Posté preguntas en #N. Espera respuesta antes de implementar."
  - **duplicate**: "Duplica #X. Recomiendo cerrar referenciando."
  - **blocked**: "Bloqueado por #Y. Esa tarea debe mergear primero."

**Última línea OBLIGATORIA machine-readable** (la parsean orquestadores como b10-ship; fallback de ellos: leer labels del issue):

```
TRIAGE_RESULT {"issue":261,"verdict":"ready","complexity":"complex","type":"feature","scope":"campaigns","blocked_by":[]}
```

- `verdict`: `ready` | `needs-info` | `duplicate` | `blocked` | `closed`
- `complexity`: `simple` | `medium` | `complex`
- `blocked_by`: números de issues que bloquean (de la sección "Blocked by" del body o del análisis), `[]` si ninguno
- Emitirla SIEMPRE, en todo modo y para todo veredicto, como línea final del output de terminal.

## Edge cases

- **Very old issues** → grep first; modules get renamed, referenced files may not exist.
- **Multiple issues for one feature** → identify the primary, reference the others.
