# Changelog

## [Unreleased]

<!--
  Entrada CHANGELOG generada por b7-issue-to-pr.
  Tono: técnico-analítico para devs futuros leyendo historia.
  Se inserta bajo la sección [Unreleased] del CHANGELOG.md raíz.
-->

### feat(b2): Phase 1.5 impact check condicional + impact_files en el state de b7 (#22)

Antes se modificaban simbolos existentes (helpers de `$lib`, `*.remote.ts` con consumidores, `schema.ts`) sin mirar quien los consume — drift silencioso hasta el review. b2 gana Phase 1.5 condicional: impact set por simbolo via `codegraph_impact` (probe `ok`) con fallback `rg -l`, skip explicito para greenfield y gate de scope-growth (archivos fuera del plan se agregan o se declara scope-growth antes de codear). b7 persiste el set en `.b7/state.json` campo `impact_files` via state-set (bullet en el prompt del agente del paso 4) y en 8c contrasta `git diff --name-only` contra impact_files+files_likely emitiendo la señal `IMPACT_DRIFT` (visible, NO gate).

**Archivos clave**:
- `skills/b2-build-feature/SKILL.md` — Phase 1.5 entre Clarify y Build (trigger, skip greenfield, fallback rg, gate de scope-growth)
- `skills/b7-issue-to-pr/SKILL.md` — paso 4 bullet de persistencia de `impact_files`; 8c bloque de contraste con señal `IMPACT_DRIFT`
- `skills/b7-issue-to-pr/scripts/guardrails.sh` — clave `impact_files` en el scaffold de init-state (whitelist de state-set la acepta)

**Riesgos / consideraciones**:
Bajo. La señal de 8c es informativa (el gate duro sigue siendo el budget); codegraph nunca es gate (fallback rg); la clave nueva en el scaffold no la consume ningun template (envsubst la ignora).

**Links**: [issue #22](https://github.com/jporre/sveltekit-verticalslices/issues/22)


### feat(b6): CHANGED_SYMBOLS en pr-context.sh + callers de simbolos modificados (#21)

b6 excluia del analisis los simbolos que el PR modifica y nadie trazaba sus callers fuera del diff (asi se escapo la regresion D5). `pr-context.sh` gana la seccion `=== CHANGED_SYMBOLS ===` reutilizando el diff ya capturado: `NEW:`/`MODIFIED:` best-effort (exports en lineas +/- y contexto de hunk headers para modificaciones body-only) mas linea `CODEGRAPH: ok|absent` via el probe informativo de b1. SKILL.md cablea el uso: Area 2 punto 6 traza callers de cada MODIFIED (codegraph si ok, fallback `rg`; call site externo roto por firma nueva = BLOCKER) y Area 5 paso 2 usa codegraph como primario con las recetas Grep degradadas a fallback.

**Archivos clave**:
- `skills/b6-pr-review/scripts/pr-context.sh` — seccion CHANGED_SYMBOLS al final (reusa `$DIFF`, sin llamadas gh extra)
- `skills/b6-pr-review/SKILL.md` — Paso 1 documenta la seccion; Area 2 punto 6 (callers de MODIFIED); Area 5 paso 2 (codegraph primario, Grep fallback)

**Riesgos / consideraciones**:
Bajo. Deteccion best-effort solo para exports JS/TS; con codegraph ausente todo funciona via rg (codegraph nunca es gate). Hallazgos se reportan dentro de '## 2. Calidad del Codigo' — cero impacto en los parsers de verdict.sh/b7/b9/b10.

**Links**: [issue #21](https://github.com/jporre/sveltekit-verticalslices/issues/21)


### feat(b7): carril rapido S — classify-run + lane S|M|L (#16)

classify-run asigna lane S/M/L; carril S usa render mecanico de screens, agente sonnet, 3 iteraciones y b6 --light. M/L byte-identicos.
<!--
  SUMMARY_TECHNICAL: 1-3 frases técnicas. Qué se cambió y por qué.
  Ej: "Agrega remote function get_tareas_by_estado y nueva pantalla BandejaTareasPage para reemplazar el filtrado client-side que escalaba mal a >2k tareas."
-->

**Pantallas afectadas**: —
<!-- "BandejaTareasPage (/tareas), DetalleTareaPage (/tareas/[id])" o "—" si no hay -->

**Archivos clave**:
—
<!--
  - `src/routes/—/—.remote.ts` — nueva query + permission check
  - `src/routes/—/+page.svelte` — UI principal
-->

**Riesgos / consideraciones**:
—
<!--
  - Migración requerida: —
  - Permiso nuevo registrado: —
  - Posible impacto en cache: —
  - "Sin riesgos identificados" si nada aplica.
-->

**Métricas del run**: 0 iter · 0 archivos · 0 líneas netas · —

**Links**: [issue #16](https://github.com/jporre/sveltekit-verticalslices/issues/16) · [PR #—](—) · [run report](—)

### feat — flag data_table por pantalla cablea bt1-data-table en el build (#20)

Cierra el gap de ruteo: el skill `bt1-data-table` solo se mencionaba en la tabla de skills auxiliares de b2, sin que triage ni los prompts de build de b7/b8 lo referenciaran. Se agrega la propiedad opcional `data_table: boolean` por pantalla en el contrato de triage y se propaga hasta los prompts de implementacion. b1 marca `data_table: true` cuando la pantalla lista datos tabulares (columnas, orden, filtros o paginacion en el acceptance criteria); b7 (paso 4) y b8 (prompt de build) inyectan una clausula condicional: para esas pantallas el sub-agente invoca `bt1-data-table` via Skill tool si esta disponible, con fallback documentado a shadcn Table + paginacion server-side segun tamano. Solo schema y texto de prompts, sin logica nueva.

**Archivos clave**:
- `skills/b7-issue-to-pr/templates/triage-output.schema.json` — propiedad `data_table: boolean` (default false) por pantalla con description del criterio
- `skills/b1-triage-issue/SKILL.md` — criterio para marcar `data_table` al poblar pantallas tabulares
- `skills/b7-issue-to-pr/SKILL.md` — paso 4: clausula condicional `data_table=true` en el prompt del sub-agente
- `skills/b8-swarm/SKILL.md` — misma clausula en el prompt de build secuencial

**Riesgos / consideraciones**:
Bajo. `data_table` es opcional con default `false`: triage que no lo emite conserva el comportamiento actual y validate-triage pasa con y sin el flag (schema parsea con `json.load`). No hay ruteo forzado — el sub-agente cae al fallback shadcn Table si el skill no esta disponible.

**Links**: [issue #20](https://github.com/jporre/sveltekit-verticalslices/issues/20)

### feat — vocabulario de states alineado + estado invalid-submit en screen-review (#19)

Screen-review ya no se limita al golden path. Se alinea el vocabulario de `states_required` entre el triage schema y screen-review, y se agrega el estado `invalid-submit`: submit con requeridos vacios debe mostrar errores visibles; si el boton submit esta `disabled` y por eso no aparece ningun error, es el anti-patron de la receta de forms (`disabled={submitting}`, nunca `disabled={!isFormValid}`) y se marca `passed: false`. El enum de `states_required` pasa a `[golden, empty, loading, error, success, permission-denied, invalid-submit]` con default `[golden]`, y b7 deja de hardcodear `states=golden`: pasa los `states_required` reales de cada pantalla con fallback golden.

**Archivos clave**:
- `skills/b7-issue-to-pr/templates/triage-output.schema.json` — enum + default `[golden]` + description exigiendo `invalid-submit` en forms de crear/editar
- `skills/b7-screen-review/SKILL.md` — Step 3: estado `invalid-submit` (submit vacio → errores visibles; disabled sin errores = passed:false) + mapeo legacy (`success` ≡ `golden`, `permission-denied` → not-evaluated)
- `skills/b7-issue-to-pr/SKILL.md` — prompt del sub-agente pasa `states_required` con fallback golden; ejemplo de triage con `states_required: [golden, invalid-submit]`

**Riesgos / consideraciones**:
Bajo. Solo schema y documentacion de skills, sin codigo ejecutable. Triage sin `states_required` conserva el comportamiento actual (golden) via el default del schema y el fallback del prompt. Schema parsea con `json.load`.

**Links**: [issue #19](https://github.com/jporre/sveltekit-verticalslices/issues/19)

### feat — gate de test de regresion para runs type:fix (#18)

Todo run `type: fix` debe incluir un test de regresion (el que falla sin el fix y pasa con el). b7 inyecta un item `regression-test` al `plan[]` cuando el triage es `fix`, gateado por `plan-check` (DoD #6) sin logica nueva; DoD gana un check #8 que degrada el run a `needs-human-review` (sin abortar) si el diff `master..HEAD` no toca ningun archivo `.(test|spec).`. Un waiver explicito (`plan-done regression-test` con `note: waived: <razon>`) cierra el item pero mantiene el status en `needs-human-review` para que un humano confirme. b6 detecta el mismo caso en el PR: `pr-context.sh` emite `FIX_REGRESSION_GATE` con `FIX_WITHOUT_TEST=true` cuando el headRef es `fix/*` y el diff no toca tests, y el Area 2 emite un WARNING pidiendo el test o justificacion.

**Archivos clave**:
- `skills/b7-issue-to-pr/SKILL.md` — paso 1 inyecta `regression-test` al plan[] + documenta waiver; DoD check #8 (`FIX_SIN_TEST` → needs-human-review)
- `skills/b6-pr-review/scripts/pr-context.sh` — seccion `FIX_REGRESSION_GATE` con `FIX_WITHOUT_TEST` al final de CLASSIFY_FILES
- `skills/b6-pr-review/SKILL.md` — Paso 1 lista `FIX_REGRESSION_GATE`; Area 2 emite WARNING si `FIX_WITHOUT_TEST=true`

**Riesgos / consideraciones**:
Bajo. El gate b7 es la fuente deterministica (inyeccion al plan + DoD #8); b6 es una segunda red en el PR, no bloquea (WARNING). La deteccion de test es por patron `.(test|spec).` — un proyecto con otra convencion de nombres de test escaparia el gate. `bash -n` OK sobre `pr-context.sh`.

**Links**: [issue #18](https://github.com/jporre/sveltekit-verticalslices/issues/18)

### feat — triage de bugs con evidencia observable + gate anti-fabricacion (#17)

Endurece el triage de `type: fix`: un bug ya no es `ready` por afirmar un sintoma, necesita al menos un artefacto observado. b1-triage gana Step 4e evidence-first (error exacto / salida / `path:linea` en `evidence.observed`, o degrada a needs-info con la verificacion pendiente como pregunta), un probe de codegraph inline en Step 4 con fallback rg y `grounding_source`, y un gate anti-fabricacion en `files_likely` (paths existentes deben venir de output de herramienta; archivos nuevos van como glob marcado). El schema compartido gana `evidence {observed, source}`, `grounding_source` y un `if type==fix then required evidence`. b7 agrega un gate deterministico via jq en el paso 1: `fix` sin `evidence.observed` se trata como needs-info y baila antes de abrir worktree/PR.

**Archivos clave**:
- `skills/b7-issue-to-pr/templates/triage-output.schema.json` — `evidence`, `grounding_source`, `if/then` fix→evidence, nueva description de `files_likely`
- `skills/b1-triage-issue/SKILL.md` — Step 4 probe codegraph + gate anti-fabricacion, Step 4e evidence-first, Step 7 seccion Evidencia
- `skills/b1-triage-issue/references/comment-templates.md` — ejemplo Ready bug con `### Evidencia` citando output observado
- `skills/b7-issue-to-pr/SKILL.md` — paso 1 gate jq (fix sin evidence.observed → needs-info)

**Riesgos / consideraciones**:
El subset de `validate-triage` (guardrails.sh) no evalua `if/then`; la obligatoriedad de `evidence` para bugs la aplica el gate jq de b7. Verificado: schema parsea, `validate-triage` sigue OK sobre triages existentes y rechaza claves desconocidas, el gate jq baila un `fix` sin `evidence.observed` y deja pasar uno con evidencia.

**Links**: [issue #17](https://github.com/jporre/sveltekit-verticalslices/issues/17)

### perf — batch de llamadas gh en topologia de epics (#15)

Reutiliza los objetos completos del endpoint REST `sub_issues` (antes se descartaba todo salvo `.number` y se re-pegaba un `gh issue view` por sub-issue) y colapsa loops N+1 en una sola llamada. Sobre el epic #27 (25 sub-issues): `epic-graph.sh` 28->3 procesos gh, `epic-diff.sh` 103->3. Las deps de `run.sh` pasan a una query `gh api graphql` aliaseada; `b9-close` PASO 4 fusiona los dos `--paginate` identicos sobre el endpoint de events en uno que emite `actor<TAB>created_at`.

**Archivos clave**:
- `skills/b10-ship/scripts/epic-graph.sh` — NDJSON directo con `state|ascii_upcase` (preserva el contrato OPEN de `epic-state.sh`); fallback por body intacto
- `skills/b10-ship/scripts/epic-diff.sh` — captura `sub_issues` una vez, lookups jq en memoria
- `skills/b10-ship/scripts/run.sh` — deps del reconcile via una query graphql aliaseada
- `skills/b9-close/SKILL.md` — PASO 4 fusiona dos `--paginate` en uno

**Riesgos / consideraciones**:
Bajo. Outputs verificados byte-identicos vs version previa sobre epic #27. Un dep inexistente en `run.sh` degrada a "sin deps abiertas" (misma tolerancia previa).

**Links**: [issue #15](https://github.com/jporre/sveltekit-verticalslices/issues/15) · [PR #42](https://github.com/jporre/sveltekit-verticalslices/pull/42)


<!--
  Entrada CHANGELOG generada por b7-issue-to-pr.
  Tono: técnico-analítico para devs futuros leyendo historia.
  Se inserta bajo la sección [Unreleased] del CHANGELOG.md raíz.
-->

### feat(screen-review): mint-dev-session.sh — sesión dev scriptada (#14)

Nuevo `mint-dev-session.sh` (mint/verify/cleanup) que inserta una sesión válida en la DB del worktree para que screen-review pase el muro OAuth sin login manual. `mint` genera token base64url, deriva sessionId = sha256(token) hex (patrón Lucia v3), inserta en `app.user_session` (24h) vía node del worktree, y emite SOLO la línea `B7_SESSION_COOKIE=auth-session=<token>`. `verify` clasifica 200/permiso/inválida; `cleanup` borra por hash. b7-screen-review des-deprecа `auth_cookie` e inyecta la cookie via `document.cookie` en el mismo origen; b7-issue-to-pr 5.1 intenta mint+verify con fallback limpio al Chrome real y 5.9 hace cleanup siempre.

**Pantallas afectadas**: — (cambio de infra/skills)

**Archivos clave**:
- `skills/b7-screen-review/scripts/mint-dev-session.sh` — nuevo script mint/verify/cleanup
- `skills/b7-screen-review/SKILL.md` — flujo 2a (con cookie) vs 2b (Chrome real); anti-patrón ajustado
- `skills/b7-issue-to-pr/SKILL.md` — 5.1 mint+verify+fallback, 5.2 pasa auth_cookie, 5.9 cleanup siempre

**Riesgos / consideraciones**:
- El token en claro aparece solo en la línea `B7_SESSION_COOKIE`; en DB y `.b7/dev-session.json` vive solo el hash.
- Nombres de tabla/columnas de usuario (`app.ta_usuario`) son defaults overridables por env — la app real puede diferir; `B7_SESSION_USER_ID` es el path confiable sin conocer schema.
- Cookie host-scoped (`localhost`): b7 + b8-swarm en paralelo se pisan (documentado; wiring en b8 es follow-up).
- Sin `B7_SESSION_USER_ID`/`EMAIL` o `DATABASE_URL` → exit 3 (fallback limpio, no error).

**Métricas del run**: 1 iter · 3 archivos · +324 líneas netas · screens: []

**Links**: [issue #14](https://github.com/jporre/sveltekit-verticalslices/issues/14)



<!--
  Entrada CHANGELOG generada por b7-issue-to-pr.
  Tono: técnico-analítico para devs futuros leyendo historia.
  Se inserta bajo la sección [Unreleased] del CHANGELOG.md raíz.
-->

### feat —  (#13)

2 hooks nuevos (env-probe.sh, block-env-dump.sh) + wiring en hooks.json (Bash y Read) + nota de convencion en guardrails.sh.
### — — b7-pipeline (#12)

publish-docs.sh state-set/milestone (whitelist python3), render-report.sh exit 4 en vars indefinidas, init-state siembra claves faltantes y borra started_utc duplicado.
<!--
  SUMMARY_TECHNICAL: 1-3 frases técnicas. Qué se cambió y por qué.
  Ej: "Agrega remote function get_tareas_by_estado y nueva pantalla BandejaTareasPage para reemplazar el filtrado client-side que escalaba mal a >2k tareas."
-->

**Pantallas afectadas**: —
<!-- "BandejaTareasPage (/tareas), DetalleTareaPage (/tareas/[id])" o "—" si no hay -->

**Archivos clave**:
hooks/env-probe.sh, hooks/block-env-dump.sh, hooks/hooks.json, skills/b7-issue-to-pr/scripts/guardrails.sh
<!--
  - `src/routes//.remote.ts` — nueva query + permission check
  - `src/routes//+page.svelte` — UI principal
-->

**Riesgos / consideraciones**:
Over-block deliberado (verbo de dump que mencione .env). Falso positivo se esquiva usando env-probe.sh o .env.example.
<!--
  - Migración requerida: 
  - Permiso nuevo registrado: 
  - Posible impacto en cache: 
  - "Sin riesgos identificados" si nada aplica.
-->

**Métricas del run**: 0 iter · 0 archivos · 0 líneas netas · —

**Links**: [issue #13](https://github.com/jporre/sveltekit-verticalslices/issues/13) · [PR #—](—) · [run report](—)
—
<!--
  - `src/routes/b7-pipeline/b7-pipeline.remote.ts` — nueva query + permission check
  - `src/routes/b7-pipeline/+page.svelte` — UI principal
-->

**Riesgos / consideraciones**:
Bajo: cambios acotados a scripts del pipeline b7.
<!--
  - Migración requerida: ninguna
  - Permiso nuevo registrado: ninguno
  - Posible impacto en cache: ninguna
  - "Sin riesgos identificados" si nada aplica.
-->

**Métricas del run**: 1 iter · 0 archivos · 0 líneas netas · —

**Links**: [issue #12](https://github.com/jporre/sveltekit-verticalslices/issues/12) · [PR #—](—) · [run report](—)



