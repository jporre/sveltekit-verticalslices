# Changelog

## [Unreleased]

<!--
  Entrada CHANGELOG generada por b7-issue-to-pr.
  Tono: técnico-analítico para devs futuros leyendo historia.
  Se inserta bajo la sección [Unreleased] del CHANGELOG.md raíz.
-->

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



