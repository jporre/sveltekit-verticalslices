# Changelog

## [Unreleased]

## [1.4.0] — 2026-07-03

### epic — Auditoria b-pipeline tier 2: 25 mejoras verificadas (#27)

Cierra el epic #27 completo (25 sub-issues, PRs #38-#46 mas los 10 de la primera ola). Consolidado: contrato unico de triage con evidencia observable y gates anti-fabricacion (#2, #17), b6 con modo light, verdict.sh determinista y CHANGED_SYMBOLS con callers (#3, #4, #21), receta canonica de forms y ruteo bt1-data-table (#5, #20), gates de b7 (verify-port, env-check, regresion obligatoria en fixes, carril rapido S con sonnet) (#6, #7, #16, #18), doc feature.md cableada y scaffold/check-slice codificando slice-spec (#8, #9), codegraph siempre opcional con fallback rg (#10, #22), fin del hand-edit de state.json (#12), secretos nunca en plaintext via env-probe/block-env-dump (#13), mint-dev-session para el muro OAuth (#14), batch de llamadas gh 9-34x (#15), estados invalid-submit en screen-review (#19), verify.sh con exit codes y browser-gate (#23), lib.sh con contratos inter-skill compartidos (#24), b7 SKILL.md adelgazado y contrato de ruteo b7/b8/b10 en descriptions con b3-security retirado (#25, #26), y doble triage de b0 eliminado (#11). Las entradas siguientes de esta seccion corresponden a los sub-issues del epic.

**Links**: [epic #27](https://github.com/jporre/sveltekit-verticalslices/issues/27) · revision completa en el comentario `## Revision de feature completo` del epic

<!--
  Entrada CHANGELOG generada por b7-issue-to-pr.
  Tono: técnico-analítico para devs futuros leyendo historia.
  Se inserta bajo la sección [Unreleased] del CHANGELOG.md raíz.
-->

### docs(pipeline): contrato de ruteo b7/b8/b10 + tabla README + retirar b3-security (#26)

Tres descriptions se disputaban el prompt "resuelve el issue N" con endpoints distintos (b7 decia "considerar siempre que se mencione issue N", b10 "ship issue N", b8 "SIEMPRE que pidan varias issues") y el router de skills ruteaba por azar. Ahora el contrato es explicito y sin solape: b10-ship es la ENTRADA DEFAULT para trabajo issue-shaped ("resuelve/trabaja/arregla el issue N"), b7-issue-to-pr solo entra directo cuando piden parar en el PR draft (y declara que NO mergea), b8-swarm queda en 3 frases (que/cuando/limite: solo clusters del mismo scope, NO mergea, issues no relacionadas van una por una) y b2 baja a 1 frase que preserva los Two Entry Points y cede el ruteo a los orquestadores. README §7 colapsa ~48 lineas de prosa drifteada a una tabla etapa -> skill -> quien-invoca -> gate, mas nota de numeracion (prefijos = orden de creacion: dos b1, dos b7, sin b5, un solo b3; directorios no se renombran). `skills/b3-security/` se elimina (huerfano: ningun orquestador lo encadenaba y arrastraba contenido muerto tipo la tabla admin@test.com en un proyecto OAuth-only); su unico contenido exclusivo, `requireAnyPermission`, se porta al checklist de b6 como apendice "Patrones de referencia", y se quitan los 2 bullets MongoDB stale del checklist. El Area 3 de b6 colapsa a pointer + tabla clasificacion -> severidad (el mapping BLOCKER sobrevive exactamente una vez); la fila security de b2 pasa a ruta relativa del checklist.

**Archivos clave**:
- `skills/b7-issue-to-pr/SKILL.md`, `skills/b10-ship/SKILL.md`, `skills/b8-swarm/SKILL.md`, `skills/b2-build-feature/SKILL.md` — descriptions con contrato de ruteo sin solape (cuando SI y cuando NO invocar cada uno)
- `README.md` — §7 prosa -> tabla + nota de numeracion; fila b3-security fuera de §6
- `skills/b3-security/SKILL.md` — BORRADO (huerfano)
- `skills/b6-pr-review/references/security-checklist.md` — apendice requireAnyPermission; bullets MongoDB fuera
- `skills/b6-pr-review/SKILL.md` — Area 3 = pointer al checklist + tabla clasificacion -> severidad

**Riesgos / consideraciones**:
Bajo, solo docs/frontmatter. verdict.sh intacto: la tabla del Area 3 usa celdas (`| ... | BLOCKER |`) que no arrancan con `- **`, asi que no altera el conteo `grep -cE '^- \*\*BLOCKER\*\*:'`; las instrucciones de formato del reporte quedan byte-identicas. Grep de b3-security post-cambio: cero referencias activas (solo historia en CHANGELOG). Los 5 PASOS OBLIGATORIOS, B7_DONE y budgets de b7 no cambian — solo la parte de ruteo de su description.

**Links**: [issue #26](https://github.com/jporre/sveltekit-verticalslices/issues/26)

### refactor(b7): adelgazar SKILL.md a ~400 lineas, corregir drift 4v5 pasos, borrar usage.html (#25)

b7 corre como fork y pagaba sus 718 lineas en CADA issue, con el mandato anti-abandono repetido 6+ veces y drift "los 4 pasos" vs "CINCO PASOS" que dejaba ambiguo el set obligatorio. SKILL.md baja a ~650 lineas (la meta de ~400-500 quedo corta: los contratos mergeados post-issue en #43/#44/#45 — lane S, gates de evidencia/regresion, impact drift — se conservan integros): las 6 ocurrencias de "los 4 pasos" pasan a "los 5 pasos", se borran las secciones redundantes "Anti-patron: parches inline en master" y "NO PARAR AQUI" (contenido unico fusionado a "Que NO hacer" y al paso 6), los headers 6/8/8b quedan alineados al numero de PASO OBLIGATORIO del frontmatter (#3 commit, #4 PR+labels), y la lista canonica de puntos de heartbeat vive solo en el paso 2. Dos bloques bash copy-paste se scriptean en `guardrails.sh`: `worktree-env <dir>` (emite WORKTREE/BRANCH/PORT eval-safe desde `.b7/worktree-ready.json`, reemplaza el eval/sed/awk inline) y `dev-server start|stop <worktree>` (nohup dev.sh + pid + poll ~30s con WARN sin abortar; stop idempotente; mismos paths `.b7/dev-server.*` que consumen b8/b9). `docs/usage.html` (628 lineas, cero referencias) se borra. README §7 Step 3 se alinea con los 5 pasos reales (commit es #3, PR+labels #4, b6-review #5).

**Archivos clave**:
- `skills/b7-issue-to-pr/SKILL.md` — 718 → ~650 lineas; drift 4v5 corregido; dedupe mandato/heartbeat; bloques dev-server/worktree-env reemplazados por llamadas de 1-2 lineas
- `skills/b7-issue-to-pr/scripts/guardrails.sh` — NUEVOS subcomandos `dev-server start|stop` y `worktree-env`; `heartbeat` intacto (formato UTC que parsea b10)
- `skills/b7-issue-to-pr/docs/usage.html` — BORRADO (huerfano)
- `README.md` — §7 Step 3 alineado con los 5 PASO OBLIGATORIO

**Riesgos / consideraciones**:
Bajo. El formato del heartbeat no cambia (verificado con `date -j -u -f`); `dev-server` conserva los paths `.b7/dev-server.{log,pid}` que ya matan b9-close y usa b8-swarm; frontmatter description, B7_DONE, DoD checks 1-8 y budgets quedan byte-identicos. `worktree-env` exige el marker `worktree-ready.json` (exit 30 si falta) — mismo invariante que verify-worktree.

**Links**: [issue #25](https://github.com/jporre/sveltekit-verticalslices/issues/25)

### refactor(pipeline): lib.sh — contratos inter-skill compartidos (find_pr, b6_verdict, label_event, blocked_by) (#24)

Los contratos entre orquestadores vivian copy-pasteados y drifteaban: el lookup de PR por "Closes #N" existia en variantes (b9 usaba search server-side sin frontera de digitos + head -1), el sweep de events de labels estaba duplicado, y '## Blocked by' se parseaba con 2 gramaticas distintas — el sed inclusivo de run.sh capturaba el #N de la linea del heading siguiente (deps fantasma), mientras epic-graph.sh tenia el regex python correcto duplicado DOS veces en el mismo archivo. Nuevo `scripts/lib.sh` (raiz del plugin, sourceable, bash 3.2-safe) con 4 funciones: `bp_find_pr <issue> [open|merged]` (frontera `[^0-9]|$`: #261 no matchea #2610), `bp_b6_verdict <pr>` (delega en el lector unico verdict.sh read), `bp_label_event <issue|pr> <label>` (UNA llamada --paginate -> `actor<TAB>created_at`; comparacion de timestamps en el caller) y `bp_blocked_by` (stdin=body -> deps, lookahead NO inclusivo). `bash lib.sh selftest` corre los fixtures offline de bp_blocked_by (regresion: heading inmediato tras la seccion -> cero deps fantasma) y cmd_preflight lo suma a su smoke-test.

**Archivos clave**:
- `scripts/lib.sh` — NUEVO: bp_find_pr, bp_b6_verdict, bp_label_event, bp_blocked_by + selftest con fixtures
- `skills/b10-ship/scripts/run.sh` — find_pr propio y sed inclusivo de deps eliminados; b6_marker via bp_b6_verdict; lib.sh en el smoke de preflight
- `skills/b10-ship/scripts/epic-graph.sh` — regex duplicado x2 eliminado; deps se resuelven via bp_blocked_by antes del python
- `skills/b9-close/SKILL.md` — PASO 0 (bp_find_pr open/merged), PASO 2 (bp_b6_verdict), PASO 4 (bp_label_event)
- `skills/b10-ship/SKILL.md` — staleness de epic-approved con snippet bp_label_event

**Riesgos / consideraciones**:
Bajo. Output de `epic-graph.sh 27` verificado byte-identico antes/despues del refactor (stdout y stderr). lib.sh NO impone set -e/-u al sourcearse (los snippets de SKILL.md corren sin modo estricto). Fuera de alcance declarado: epic-diff.sh conserva su predicado [Cc]loses (necesita campos extra) y las llamadas directas de b7/b6 a verdict.sh read (verdict.sh sigue siendo la fuente unica; bp_b6_verdict es el atajo para quien ya sourcea lib.sh).

**Links**: [issue #24](https://github.com/jporre/sveltekit-verticalslices/issues/24)

### feat(b2): verify.sh — el checklist de verificacion como script con exit codes y browser-gate por scope de diff (#23)

La verificacion de b2 era prosa honor-system triplicada (SKILL.md, checklist, b7): el orden check→format→autofixer→browser se re-derivaba cada run, el grep anti-React era manual y nada delataba pasos saltados. Nuevo `verify.sh` (contrato estilo assert-clean.sh): branch guard (exit 3), `pnpm check:machine` (4), `pnpm format` (no-gate), grep anti-React SOLO en archivos cambiados con file:line (5), `test:unit` condicional al diff (6) y browser-gate required si el diff toca `src/routes/**`, `*.svelte` o `*.remote.ts`. Ultima linea machine-readable `VERIFY_RESULT branch= check= react= test= browser= svelte_files=<csv>`; autofixer y walkthrough siguen siendo pasos del modelo gatillados por esa linea. Phase 3 de b2 orquesta verify.sh→autofixer→browser; el checklist queda como how-to de agent-browser; b7 usa verify.sh como pasada final pre-commit sin tocar el skip-by-scope del loop.

**Archivos clave**:
- `skills/b2-build-feature/scripts/verify.sh` — NUEVO: 6 gates, exit codes 2-6, linea VERIFY_RESULT
- `skills/b2-build-feature/SKILL.md` — Phase 3 pasa a verify.sh + autofixer sobre `svelte_files` + browser si `required`
- `skills/b2-build-feature/references/verification-checklist.md` — Steps 0-3 y grep absorbidos; queda el walkthrough de agent-browser
- `skills/b7-issue-to-pr/SKILL.md` — pasada final completa = verify.sh antes del paso 6 (commit)

**Riesgos / consideraciones**:
Bajo. El skip-by-scope del loop iterativo de b7 no cambia (sigue alimentando iter-logs/error-hash); verify.sh entra solo como pasada final. Criterios validados en repo sintetico: on:click introducido → exit 5 con file:line; diff solo `.remote.ts` → browser=required; diff sin UI ni tests → test=skipped, browser=not-needed, exit 0.

**Links**: [issue #23](https://github.com/jporre/sveltekit-verticalslices/issues/23)


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



