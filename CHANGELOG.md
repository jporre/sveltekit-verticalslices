# Changelog

## [Unreleased]

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

### — — b7-pipeline (#12)

publish-docs.sh state-set/milestone (whitelist python3), render-report.sh exit 4 en vars indefinidas, init-state siembra claves faltantes y borra started_utc duplicado.
<!--
  SUMMARY_TECHNICAL: 1-3 frases técnicas. Qué se cambió y por qué.
  Ej: "Agrega remote function get_tareas_by_estado y nueva pantalla BandejaTareasPage para reemplazar el filtrado client-side que escalaba mal a >2k tareas."
-->

**Pantallas afectadas**: —
<!-- "BandejaTareasPage (/tareas), DetalleTareaPage (/tareas/[id])" o "—" si no hay -->

**Archivos clave**:
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



