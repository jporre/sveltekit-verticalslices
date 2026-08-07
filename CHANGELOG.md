# Changelog

## [1.9.0] — 2026-08-07

### feat — doctrina slice v2: docs/readme.md, data/, frontera entre features, sufijo .server.ts, sin load()

Absorbe las definiciones acordadas en el starter de Bnex (CONTEXT.md + ADR 0001 del starter):

- Doc del feature pasa de `docs/<feature>.md` a **`docs/readme.md`** — path fijo en todo feature (mismo argumento que `data.remote.ts`) y GitHub lo renderiza al navegar la carpeta. `docs/comments.md` opcional: el porqué de código no obvio anclado por símbolo. Sin changelog local: git es el changelog.
- Subcarpeta **`data/`** nueva en el layout: constantes estructurales `as const` y `schemas.ts` isomórficos (zod único validador; schemas inline en `data.remote.ts` por default, se extraen cuando el cliente los necesita).
- **Frontera entre features**: `server/data.remote.ts` es la API pública — lo único importable desde otro feature; `ui/`/`data/`/`server/*.server.ts`/`tests/` son privados. Tests solo importan del propio feature o `$lib`. Checklist de conformidad item 8 nuevo.
- **Sufijo `.server.ts` obligatorio** para todo archivo no-remote en `server/` (la carpeta no protege; el sufijo activa el enforcement del compilador). Check mecánico nuevo en `audit.sh` (E1).
- **`load()` deja de ser excepción**: la deduplicación de queries por request cubre el dato compartido; `+page.server.ts` queda solo para guard/redirect. `+server.ts` solo consumidores externos.
- **Tests**: tríada `*.test.ts` / `*.svelte.test.ts` / `*.e2e.ts` plana en `tests/` (el sufijo decide el runner).

**Archivos clave**: `skills/b2-build-feature/references/slice-spec.md` (fuente única), `scaffold-slice.sh` (genera `docs/readme.md`), `audit.sh` (check E1 nuevo + CAL-6 renombrado), `base-setup.md` (doctrina CLAUDE.md), `fix-ladder.md`, renombres de la doc en b0/b1/b6/b7.

### fix — b9: el canal auto-merge ahora ve el screen-review y las condiciones humanas de b6 (#50)

El canal auto-merge gateaba solo con `b6 blockers=0` + CI + `mergeable`; un `Veredicto: fail` del screen-review o un "esto debe recorrerse a mano" en prosa del b6 no lo frenaban (casos reales Snuuper#218/#219).

- b7/b8: el marker `b7:screen-review=done` lleva `result=ok|fail` (la clasificación que ya calculaba para `B7_DONE screens=`); b8 hereda el guard `utiles` de b7 (100% `infra_fail` → `skipped reason=infra-fail`, nunca `done result=ok`).
- b9 condición 4b nueva: `result=fail` → DESCALIFICADO + `needs-human-review` persistente; marker ausente o formato viejo con UI en el diff → default-deny al canal humano; `skipped-<r>` no bloquea pero queda visible en el audit.
- b6: línea contable `- **HUMAN**: <razón>` → `verdict.sh stamp` anexa ` human=required` al marker (retrocompatible; no altera el verdict); b9 lo trata como veto del auto-merge en la condición 4.
- Audit trail del auto-merge refleja lo evaluado real: `CI n/a (sin checks)` cuando la condición 5 pasó por lista vacía, y `screens=<estado>` de 4b.

**Archivos clave**: `skills/b9-close/SKILL.md` (PASO 4), `skills/b6-pr-review/scripts/verdict.sh` (lector/estampador único), `skills/b7-issue-to-pr/SKILL.md` + `skills/b8-swarm/SKILL.md` (marker), `skills/b6-pr-review/SKILL.md`.

## [1.8.0] — 2026-08-06

### feat — slice: layout canónico `server/ui/docs/tests`

Todo el manejo de datos del feature en `server/data.remote.ts` (debug de una query = UN archivo, mismo path en todo feature); componentes en `ui/`, doc en `docs/<feature>.md`, tests en `tests/`. Invierte dos reglas: `data.remote.ts` pasa de prohibido a canon, `ui/` de vetada a canónica. SQL-first (filtros/group by/agregaciones en la query; JS mínimo); `load()` solo para dato compartido entre varios componentes. `scaffold-slice`/`check-slice`/`audit.sh` generan y validan el árbol nuevo; tolerancia legacy al layout colocado anterior.

**Archivos clave**: `skills/b2-build-feature/references/slice-spec.md` (fuente única), scripts de b2, referencias de b0/b1/b6/b7.

### feat — b10: modo rápido completo (épicas a wall-clock mínimo)

Con `epic-auto-merge` vigente: builds con `--no-screens --light-review --no-changelog` — la revisión funcional en browser se paga UNA vez en el walkthrough del epic-review (1 sesión, 1 PNG golden por pantalla), b6 light por PR (el pase profundo lo hace el epic-review) y CHANGELOG solo rollup al cierre (mata el conflicto aditivo que frenaba el drain N-1 veces por ola). `B10_WAVE_MAX` 2→4. Triage sin re-spawn para issues de b0 (`B10_TRIAGE` desde labels en el reconcile, anulado por comentario humano nuevo).

**Archivos clave**: `skills/b10-ship/references/epic-mode.md`, `skills/b10-ship/scripts/run.sh`, `skills/b7-issue-to-pr/SKILL.md` (flags nuevos).

### feat — b0: `--from=<issue>`, consolidación anti-roce y gate por criterios

Un issue existente puede ser la fuente Y el epic padre (`epic.number` — solo linkeo nativo, no se edita el origen). Consolidación pre-gate: matriz archivo × slice (overlap misma ola → cluster/merge; tests+docs de 3+ slices → UN slice de cierre, escritos una vez contra el estado final). Excepciones de corte: prefactor y refactor ancho expand–contract. El gate muestra el plan completo y aprueba CRITERIOS de éxito por slice — no un "¿de acuerdo?" genérico.

### feat — b-setup-or-fix: vite.config, orden de archivos y auth de pruebas declarada

Flags experimentales donde la config ya vive (kit ≥ 2.62 ignora `svelte.config.js` si `sveltekit()` recibe opciones; `sv` ≥ 0.16 scaffoldea sin él). E2 ordena archivos al layout canónico y actualiza la sección Estructura del README/CLAUDE.md del repo. Paso nuevo del modo base: estrategia de auth de pruebas del browser (dev-user / dev-endpoint / session-mint / manual-cookies) decidida con el usuario y declarada en `## Auth de pruebas (browser)` del CLAUDE.md — b7 5.1 y el walkthrough la leen.

### fix — fricciones de pipeline

- `lib.sh` zsh-safe: `_BP_ROOT` prioriza `PLUGIN_ROOT`/`CLAUDE_PLUGIN_ROOT` con fallback `${BASH_SOURCE[0]:-$0}` (bug real de `bp_b6_verdict` al sourcear desde zsh).
- Commit fantasma: b3 termina con `B3_DONE commits=<n> head=<sha>` probado con `git log`; b9 verifica post-b3 (`rev-list @{u}..HEAD` == 0) antes del merge.
- `cleanup-worktree.sh` (b9): camino sancionado de limpieza — rescue primero, huérfanos solo si demuestran ser worktrees, nunca `rm -rf` a mano.
- Menos ceremonia: rollup del epic como lista plana, sin comentario de progreso duplicado en b9, b6 Área 1 mecánica en PRs bot, epic-link sin label/summary redundantes.

## [1.7.2] — 2026-07-30

### fix — b2: verify.sh formatea solo archivos cambiados, nunca repo-wide

El paso 3 de `verify.sh` corría `pnpm format` sin argumentos — en SvelteKit eso es `prettier --write .` sobre el repo completo. Resultado real: un reformateo de 68 archivos ajenos al feature que hubo que revertir. Todos los demás gates ya estaban scoped al diff vs merge-base; format era el único sin scope.

- Format ahora recibe solo la lista `$CHANGED` (diff vs merge-base + untracked, la misma de los otros gates) vía `pnpm exec prettier --write --ignore-unknown`.
- Lista vacía → no corre nada. Sigue siendo auto-fix sin gate (WARN si falla, no bloquea).
- Compatible con bash 3.2 de macOS bajo `set -euo pipefail` (guard de largo antes de expandir el array).

**Archivos clave**: `skills/b2-build-feature/scripts/verify.sh`.

Además: `marketplace.json` quedó en 1.7.0 desde la release anterior (el bump de 1.7.1 solo tocó `plugin.json`); sincronizado a 1.7.2.

## [1.7.1] — 2026-07-20

### fix — ortografía correcta en todo el repo (tildes, ñ)

CLAUDE.md exige español chileno neutro con tildes y ñ correctas; el repo tenía docs y mensajes escritos sin diacríticos. Pasada de corrección en 65 archivos (skills, agents, hooks, scripts) — sin cambios de comportamiento, solo texto.

## [1.7.0] — 2026-07-19

### refactor — BREAKING: `b11-genie` ahora se llama `b-setup-or-fix`

El nombre viejo no decía nada sobre lo que el skill hace; el nuevo sí. Se renombró el directorio, las referencias internas (`SKILL.md`, `audit.sh`, `rung-verify.sh`, `fix-ladder.md`) y el `README.md`.

- **Cambio de invocación**: `/b-pipeline:b11-genie` deja de existir. Usar `/b-pipeline:b-setup-or-fix`. No hay alias de compatibilidad — quien tenga el nombre viejo en scripts o notas debe actualizarlo.
- **Sin alias por diseño**: mantener dos nombres para el mismo skill invita a que la mitad de la documentación quede apuntando al obsoleto.
- El token `B11_RESULT` de la línea final machine-readable se conserva tal cual: nada dentro del repo lo parsea, pero un consumidor externo podría hacerlo, así que renombrarlo sería un breaking change sin beneficio.
- Las notas históricas de v1.6.0 conservan el nombre `b11-genie` a propósito: describen lo que se publicó bajo ese nombre.

### docs — b-setup-or-fix: reference de PWA (manifest, service worker, cache, updates)

El skill sabía dejar un repo SvelteKit sano pero no tenía nada que decir cuando el pedido era "hazla PWA" / "que ande offline" / "instalable en el celular". Nuevo `references/pwa-setup.md`, opt-in puro: no entra en la escalera E1-E6 ni en el modo base, y el skill tiene prohibido instalar service worker por iniciativa propia.

- **Gate antes de código**: manifest solo ya cubre el pedido típico (icono, standalone, instalable) — el service worker se agrega recién con requisito offline concreto. Chrome 108 móvil / 112 desktop dejaron de exigir SW para instalabilidad.
- **El ejemplo oficial de los docs de SvelteKit es inseguro con auth**: hace `cache.put` sobre toda respuesta 200 de su rama network-first, o sea escribe HTML SSR y respuestas de query de UN usuario en un cache compartido por origen. La versión del reference nunca escribe cache en runtime (solo sirve lo precacheado en `install`) — menos código y elimina la clase de bug.
- **Trampa verificada en el source de `@sveltejs/kit@2.70.1`, no documentada**: `query` sale GET a `${base}/_app/remote/<id>?payload=...` mientras `command`/`form`/`query.batch` salen POST. El filtro `method !== 'GET'` del ejemplo oficial salta commands y forms pero NO las queries — camino directo a filtrar datos autenticados entre usuarios del mismo dispositivo.
- **Datos offline sin cache propio**: el flavor `prerender` de remote functions ya guarda su resultado en la Cache API (`sveltekit:${version}`), sobrevive reloads y se limpia solo en cada deploy. Encaja con la doctrina del plugin (datos solo por remote functions). Datos por usuario offline = sincronización, se declara como feature, no como flag.
- **Flujo de update completo**: SW nuevo queda en `waiting` hasta cerrar todas las pestañas, las navegaciones client-side no disparan `registration.update()`, y una navegación a página ya cacheada "tiene éxito" con contenido viejo (kit#3666, abierto desde 2022). Componente `UpdatePrompt.svelte` con `afterNavigate` + prompt → `SKIP_WAITING` → reload en `controllerchange` con guard anti-primera-instalación; validado con svelte-autofixer (cero issues).
- **Tooling**: default SW a mano (los docs lo llaman "probably a good solution for most users"). `@vite-pwa/sveltekit` no aporta la lista de archivos — `$service-worker` ya la da; lo único real es revisión por archivo vs invalidar todo el `cache-${version}`. Agregar recién con granularidad como problema medido.
- **Checklist de verificación de browser**, no de types: Cache Storage sin HTML autenticado ni nada bajo `/_app/remote/`, offline throttling, deploy con pestaña abierta, logout → reabrir sin contenido del usuario anterior.

**Archivos clave**: `skills/b-setup-or-fix/{SKILL.md,references/pwa-setup.md}`.

**Riesgos / consideraciones**: investigado con dos rondas de workflow adversarial (210 agentes). La segunda ronda encontró que kit#3498 y kit#3642 — las issues que se citan habitualmente para el pitfall de cachear HTML autenticado — son misatribución (una es feature request de SSR dentro del SW, la otra sobre cachear APIs externas); por eso el dato del método HTTP salió del source y no de docs. Marcado explícito como NO verificado dentro del archivo: Web Push en iOS 2026, Badging API en Safari, política de evicción de storage de iOS, reemplazo formal de la categoría PWA de Lighthouse, y edge cache de adapter-vercel. El reference no se probó aún contra un repo real.

## [1.6.0] — 2026-07-15

### feat — b0 modo diseño + modo rápido de epic con switch único

Dos mejoras sobre b0/b10: (1) b0 servía solo al FINAL de una conversación madura — ahora acompaña desde la idea cruda; (2) la maquinaria de velocidad de v1.5.0 era toda opt-in manual (label a mano, `--cluster`, `B7_PARALLEL=1`) y nadie la activaba — el diseño ahora la conecta.

- **b0 modo diseño**: Paso 0 evalúa madurez de la conversación (`--design` fuerza entrevista, `--yes` fuerza clásico). Idea cruda → entrevista 1x1 vía AskUserQuestion (respuesta recomendada por pregunta, hechos verificados en el codebase antes de preguntar, resumen inteligente si hubo conversación previa), checklist de convergencia con propuesta de cierre, y design doc `docs/plans/<tema>.md` actualizado a medida que cierran decisiones (sobrevive sesiones; `--from` lo retoma). b0 lo commitea docs-only a la rama default al crear el epic — tree limpio para b10 y contrato con epic-review (que ya leía `docs/plans/*.md`). Nuevo `references/design-interview.md`.
- **Template de issue reforzado**: bodies ganan `## Seguridad / permisos` y `## Archivos previstos` (paths exactos del grounding — fija la estructura de carpetas y alimenta la elegibilidad de wave-build); las reglas globales (sin comentarios, simplicidad, browser-first) viven UNA vez en `## Reglas de ejecución` del design doc, linkeado desde cada body.
- **Olas anchas por diseño**: `blocked_by` SOLO con dependencia técnica real; prohibido encadenar por orden estético. Ejemplo de la guía corregido (s4-filter dependía de s2/s3 sin necesidad — ahora ola 1 ancha de 3 slices).
- **Gate de b0 pregunta modo de ejecución**: "rápido" estampa `epic-auto-merge` en el epic post-creación vía `gh issue edit` (evento labeled con token del usuario = actor humano válido para `bp_label_event`). `--fast` junto a `--yes` para headless. Preview del gate muestra el plan de ejecución (que corre junto por ola, donde caen los gates).
- **Switch único en b10**: `epic-auto-merge` vigente activa el modo rápido COMPLETO — drenaje auto-merge + wave-build (`B7_PARALLEL=1` implícito) + cluster automático por scope + cap dinámico — sin flags ni env vars; quitar el label vuelve todo a secuencial. Los 4 gates humanos sobreviven intactos (batch complex, batch waivers, epic-review/`epic-approved`, CI FAILURE corta el drenaje).

**Archivos clave**: `skills/b0-conversation-to-issues/{SKILL.md,references/{design-interview.md,slicing-guide.md}}`, `skills/b10-ship/{SKILL.md,references/epic-mode.md}`.

**Riesgos / consideraciones**: cero cambios de scripts — el switch conecta mecanismos ya existentes de v1.5.0. Wave-build con locks sharded sigue sin probarse en un epic real (validar con un epic chico). El commit docs-only a la rama default es comportamiento nuevo de b0 (solo `docs/plans/`, post-gate).

### feat — b11-genie: base sana o rescate de repo SvelteKit degradado

El pipeline construía y revisaba CAMBIOS (un issue, un PR) pero no tenía como rescatar un repo que ya llegó degradado: load functions y fetch manual ignorando remote functions, sintaxis Svelte 4, capas pass-through, duplicados, comentarios por todos lados, features desparramados fuera de `src/routes/`. b11-genie ("el genio de la botella") audita el codebase entero y lo migra hacia la misma doctrina que b2 usa para construir y b6 para revisar — o instala esa base en un proyecto nuevo.

- **Solo invocación directa del usuario**: ningún skill del pipeline lo encadena; la description lo declara explícito. Review de PR sigue siendo b6; feature nuevo sigue siendo b2.
- **Escalera E1-E6 con orden fijo**: E1 base y seguridad (flags `remoteFunctions`/`async`, guards SEC-B/D/E) → E2 estructura (colocación en `src/routes/<feature>/`) → E3 remote functions (load/actions/+server/fetch → query/form/command + single-flight, feature por feature) → E4 runas Svelte 5 y stack → E5 desingeniería y duplicados (deletion test, INVESTIGATE ante duda) → E6 comentarios y docs (`<feature>.md`, ARCHITECTURE.md, CLAUDE.md). Cada peldaño: transformar → `rung-verify.sh` contra baseline → commit vía b3; peldaño roto se revierte y detiene la escalera.
- **Gates**: nada se edita antes del gate humano de FASE 2 (plan aprobado vía AskUserQuestion); `--audit` termina en el diagnóstico; `--init` solo instala la base; `--feature`/`--hasta` acotan alcance.
- **Scripts con contrato parseable**: `audit.sh` (secciones `=== E<n> ===` + `AUDIT_RESULT mode=base|rescate rungs=E1:n,...`; exit 3 = no es SvelteKit) y `rung-verify.sh` (`baseline` captura errores preexistentes; `E<n>` compara — el genio nunca se atribuye errores que ya estaban). Línea final `B11_RESULT`.
- **Single-source**: catálogos AP1-14/SEC-A..F/CAL-1..7 se citan de b6, layout de slice-spec de b2 — cero duplicación doctrinal. Lo propio: la escalera (`fix-ladder.md`), recetas R1-R7 de migración a remote functions (`migrate-to-remote.md`, basadas en la doc oficial: query/form/command/prerender, query.batch, single-flight con `.refresh()`/`.updates()`/`.withOverride()`) y el modo base (`base-setup.md`).

**Archivos clave**: `skills/b11-genie/{SKILL.md,scripts/{audit.sh,rung-verify.sh},references/{fix-ladder.md,migrate-to-remote.md,base-setup.md}}`, `README.md`.

**Riesgos / consideraciones**: remote functions son API experimental (requiere SvelteKit >= 2.27; E3 se reporta bloqueado si la versión no alcanza, no se intenta). `rung-verify` solo cubre types+build — en repos sin tests, E3/E5 pueden romper runtime sin detectarse; el reporte lo declara (frase de honestidad) y recomienda browser test pre-merge. Smoke-testeado contra fixture sintético degradado (paths con espacios incluidos) y revisado con workflow adversarial de 31 agentes (26 hallazgos crudos → 22 confirmados y aplicados, entre ellos 2 BLOCKER del gate de verificación: sentinel 999 que dejaba pasar builds rotos y check no-parseable contado como limpio); sin correr aún contra un repo real.

## [1.5.0] — 2026-07-04

### feat — pipeline sin fricción: auto-merge por epic, screen-review observable, batch de aprobaciones, builds paralelos opt-in

Review de fricción de b10-ship (workflow 31 agentes: 6 lectores, 4 analistas, 21 verificadores adversariales; 20 hallazgos aplicados). Causa raíz de la lentitud: gate humano por CADA PR + backpressure cap 3 que se llenaba porque nadie mergea + b7.lock global. Chrome se saltaba porque cada falla de infra degradaba a "nota" sin costo observable.

- **Auto-merge por epic (b9 canal 3)**: `--auto-merge --epic=<N>` mergea sub-issue PRs sin gate humano por PR cuando TODO cumple: label `epic-auto-merge` en el epic (actor humano, removible en cualquier momento), pertenencia de TODOS los issues del PR verificada por b9 vía endpoint parent (ISSUES vacío descalifica), nunca el closing_slice, b6 `blockers=0` fresco vs último commit (stale re-reviewa `--light`), CI sin FAILURE (PENDING/no-mergeable saltan el PR; FAILURE corta el drenaje), merge siempre serial. El único gate humano del epic pasa a ser `epic-approved` (final).
- **Drain automático de backpressure**: con `epic-auto-merge` vigente, exit 17 drena los closeable del epic vía b9 auto-merge y sigue, en vez de parar a esperar labels. Cap dinámico por ola (`B7_MAX_OPEN_PRS` inline, max 8) tras drain exitoso.
- **Screen-review observable (fin del skip gratis)**: `guardrails.sh screens-check` (exit 8 si falta el JSON de una pantalla sin skip válido; enum cerrado en `SKIPPED.json`) como check del DoD y precondición del commit; token `screens=` en `B7_DONE`; marker `<!-- b7:screen-review=done|skipped -->` en el PR (b7 y b8); gate `SCREEN_EVIDENCE` en b6 (PR de bot que toca UI sin evidencia ni skip = BLOCKER); dev-server espera `B7_DEV_SERVER_WAIT_SECS=120` (antes ~30s — vite frío nunca llegaba) + 1 reintento ante verify-port 40; env-check avisa (warn) si faltan `B7_SESSION_USER_ID/EMAIL`; fallas de infra en b7-screen-review pasan de `fail` a `warn`+`infra_fail` (no queman iteraciones); lenguaje débil eliminado ("puede saltar", "Chrome real").
- **Batch de aprobaciones por ola**: UNA AskUserQuestion multiSelect post-triage (complex → label `force-complex-ok`) y UNA al fin de ola (waivers → `regression-waiver-ok`, remueve `needs-human-review`), en vez de N preguntas seriales.
- **Paralelismo**: reconcile de b10 emite `B10_APPROVED`/`B10_DIRTY` (drain-first rutea desde el snapshot sin pagar N evaluaciones b9); wave-verify (b6 de la ola en paralelo vía Workflow); sharding opt-in del lock de b7 (`B7_PARALLEL=1`, shard `b7-issue-<N>.lock` atómico, cap 2, janitor shard-aware) + sección wave-build en epic-mode; setup-worktree excluye puertos ya asignados a worktrees hermanos (evitaba verify-port 41 → skip del screen-review); b8 lanza sus screen-reviews en el mismo turno (antes seriales).

**Archivos clave**: `skills/b9-close/SKILL.md`, `skills/b10-ship/{SKILL.md,references/epic-mode.md,scripts/run.sh}`, `skills/b7-issue-to-pr/{SKILL.md,scripts/{run,guardrails}.sh}`, `skills/b6-pr-review/{SKILL.md,scripts/pr-context.sh}`, `agents/b7-screen-review.md`, `skills/b8-swarm/SKILL.md`, `skills/b1-add-worktree/scripts/setup-worktree.sh`.

**Riesgos / consideraciones**: el auto-merge degrada deliberadamente el invariante "ningún PR del bot sin ojo humano" a nivel PR — lo compensan el gate SCREEN_EVIDENCE de b6 (sin evidencia visual no hay blockers=0 en PRs de UI), la tabla consolidada de sub-PRs en el reporte de epic-review (obligatoria con auto-merge) y el label removible. `B7_PARALLEL` es opt-in y default off (comportamiento idéntico sin flag); wave-build exige puertos únicos + shard cableado (ya incluidos). El gate final `epic-approved` y el merge serial quedan intactos.

### fix — rama base detectada, no hardcodeada (bp_default_branch + bp_branch_name)

El pipeline asumía `master` como rama base en ~18 sitios; en repos con default `main` fallaban `diff-summary.sh` y `check-budget` de b7 (merge-base), `epic-diff.sh` de b10 (rangos `..master`) y el link a CHANGELOG (`blob/master`). Ahora:

- `scripts/lib.sh` gana `bp_default_branch` (origin/HEAD -> gh -> main|master local) y `bp_branch_name` (patrón de feature branch configurable: `git config b-pipeline.branchPattern 'feature/{issue}-{slug}'` o env `B_PIPELINE_BRANCH_PATTERN`; default `{type}/{issue}-{slug}` = comportamiento histórico, cero cambio sin config).
- `setup-worktree.sh <name> [base-branch]` — base-branch opcional, default `bp_default_branch`; todos los callers dejan de pasar `master` literal.
- Scripts y prosa de b1/b2/b7/b8/b9/b10 usan la rama default resuelta; b7 construye la rama del worktree vía `bp_branch_name`.

**Archivos clave**: `scripts/lib.sh`, `skills/b1-add-worktree/scripts/setup-worktree.sh`, `skills/b7-issue-to-pr/scripts/{diff-summary,guardrails}.sh`, `skills/b10-ship/scripts/epic-diff.sh`, `skills/b2-build-feature/scripts/{check-slice,verify}.sh`.

**Riesgos / consideraciones**: `bp_default_branch` requiere origin/HEAD seteado, `gh` autenticado o una rama local main/master; si nada resuelve, cada script aborta con mensaje claro (antes fallaba silencioso contra `master` inexistente). El branch guard de b2 sigue bloqueando main/master además de la default (superset conservador). b8 conserva su esquema `swarm/<ids>`/`<type>/<theme>` — `bp_branch_name` cubre solo ramas por-issue (b7); límite conocido.

### refactor — review writing-great-skills: descriptions -48% + ruteo single-source + b7-screen-review a agent def

Review completo del plugin contra el framework writing-great-skills (12 reviewers + 12 verificadores adversariales + 1 cross-cutting; 116 findings confirmados aplicados). Cambios principales:

- **Descriptions**: 1199 -> 621 palabras siempre cargadas (-48%). Sinónimos colapsados a un trigger por rama, identidad/pasos movidos al body, 6 descriptions en inglés pasadas a español neutro sin tildes, tildes removidas de b9-close (archivo completo).
- **Ruteo single-source**: description de b10-ship = tabla autoritativa (default + excepciones draft->b7, cluster->b8); b7-issue-to-pr y b8-swarm quedan con deflexión de una línea; resuelta la colisión de triggers b1-triage vs b10 ("Use ALWAYS when a GitHub issue number is mentioned" eliminado); restatements de ruteo de entrada podados de los bodies (b0/b8/b9), cada body conserva solo su frontera de salida.
- **b7-screen-review**: skill -> agent definition (`agents/b7-screen-review.md`, invocado vía `subagent_type: b-pipeline:b7-screen-review` desde b7/b8). Fix del doble stack de browser: agent-browser CLI para todo (cookie, navegación, screenshot a disco); bloque js sleep-only eliminado. `scripts/` y `templates/` del skill quedan en su lugar (b7 los referencia por path).
- **fix b4-pull-request**: contrato `--label` cerrado con b7/b8 (flag documentado + ejemplo gh pr create); 6 ramas ask-the-user del template genérico reemplazadas por una regla headless (context: fork no puede preguntar); `agent: Explore` removido (read-only, mal fit para crear PRs).
- **fix b8-swarm scripts**: lock ahora cubre la ola completa (run.sh liberaba al salir del paso 1, dejando build+PR sin exclusión mutua); flag muerto `--dwell`/`B8_DWELL_SECONDS` eliminado.
- **Progressive disclosure**: b7 gana `references/lane-s.md` y `references/dry-run.md`; b10 gana `references/epic-mode.md`; b0 mueve el script Workflow inline a `scripts/draft-bodies.workflow.js`.
- **README**: sección hooks actualizada a la realidad de hooks.json (2 matchers PreToolUse + SessionStart); tabla de skills a 11 + nota del agente.
- **Higiene frontmatter**: `license: MIT` huerfano fuera de b3, `# prettier-ignore` fuera de b2, comentario documentando model/allowed-tools heredados en b2.

**Archivos clave**: `skills/*/SKILL.md` (los 11), `agents/b7-screen-review.md` (nuevo), `skills/b8-swarm/scripts/{run,guardrails}.sh`, `README.md`.

**Riesgos / consideraciones**: la invocación `b-pipeline:b7-screen-review` requiere sesión nueva para registrar el agente; el fallback sin `auth_cookie` ya no reusa el Chrome real (pantallas protegidas -> `not-evaluated`, mismo routing que antes). Pendiente decisión: b2/b6 siguen sin `model` fijo (heredan sesión, ahora documentado).

## [1.4.1] — 2026-07-03

### fix — codegraph-probe.sh: cache-key por $ROOT + smoke grep solo stderr (#37)

Corrige dos falsos positivos del probe informativo de CodeGraph (findings del review post-merge de PR #36, ninguno bloqueaba pero degradaban a estados enganosos):

- **cache-key**: `state_dir()` derivaba el slug del cache de `CLAUDE_PROJECT_DIR` (constante en la sesión) en vez de `$ROOT`. Dos roots distintos (worktree vs repo principal, o dos worktrees) compartían el mismo archivo de cache y un status contaminaba al otro dentro del TTL. Ahora el slug deriva SIEMPRE de `$ROOT` -> un cache por root.
- **smoke grep**: el grep de `broken` corría sobre stdout+stderr, así cualquier resultado de la query `"the"` con `Error:`/`fatal`/etc. en el código reportaba un backend sano como roto. Ahora solo el exit-code y stderr deciden `broken` (stdout de la query -> `/dev/null`).

**Pantallas afectadas**: — (fix de infra, sin UI)

**Archivos clave**:
- `skills/b1-add-worktree/scripts/codegraph-probe.sh` — `state_dir()` + smoke query

**Riesgos / consideraciones**: Sin riesgos identificados. El probe sigue saliendo 0 siempre; solo cambia cómo se deriva la cache-key y qué fd alimenta la detección de rotura. Verificado con tests: 2 roots -> 2 caches distintos; `rc=0` con `Error:` en resultados -> `ok`; stderr con `SQLITE_CANTOPEN` + `rc=1` -> `broken`.

**Links**: [issue #37](https://github.com/jporre/sveltekit-verticalslices/issues/37) · [PR #48](https://github.com/jporre/sveltekit-verticalslices/pull/48)

## [1.4.0] — 2026-07-03

### epic — Auditoría b-pipeline tier 2: 25 mejoras verificadas (#27)

Cierra el epic #27 completo (25 sub-issues, PRs #38-#46 más los 10 de la primera ola). Consolidado: contrato único de triage con evidencia observable y gates anti-fabricación (#2, #17), b6 con modo light, verdict.sh determinista y CHANGED_SYMBOLS con callers (#3, #4, #21), receta canónica de forms y ruteo bt1-data-table (#5, #20), gates de b7 (verify-port, env-check, regresión obligatoria en fixes, carril rápido S con sonnet) (#6, #7, #16, #18), doc feature.md cableada y scaffold/check-slice codificando slice-spec (#8, #9), codegraph siempre opcional con fallback rg (#10, #22), fin del hand-edit de state.json (#12), secretos nunca en plaintext vía env-probe/block-env-dump (#13), mint-dev-session para el muro OAuth (#14), batch de llamadas gh 9-34x (#15), estados invalid-submit en screen-review (#19), verify.sh con exit codes y browser-gate (#23), lib.sh con contratos inter-skill compartidos (#24), b7 SKILL.md adelgazado y contrato de ruteo b7/b8/b10 en descriptions con b3-security retirado (#25, #26), y doble triage de b0 eliminado (#11). Las entradas siguientes de esta sección corresponden a los sub-issues del epic.

**Links**: [epic #27](https://github.com/jporre/sveltekit-verticalslices/issues/27) · revisión completa en el comentario `## Revision de feature completo` del epic

<!--
  Entrada CHANGELOG generada por b7-issue-to-pr.
  Tono: técnico-analítico para devs futuros leyendo historia.
  Se inserta bajo la sección [Unreleased] del CHANGELOG.md raíz.
-->

### docs(pipeline): contrato de ruteo b7/b8/b10 + tabla README + retirar b3-security (#26)

Tres descriptions se disputaban el prompt "resuelve el issue N" con endpoints distintos (b7 decía "considerar siempre que se mencione issue N", b10 "ship issue N", b8 "SIEMPRE que pidan varias issues") y el router de skills ruteaba por azar. Ahora el contrato es explícito y sin solape: b10-ship es la ENTRADA DEFAULT para trabajo issue-shaped ("resuelve/trabaja/arregla el issue N"), b7-issue-to-pr solo entra directo cuando piden parar en el PR draft (y declara que NO mergea), b8-swarm queda en 3 frases (que/cuando/límite: solo clusters del mismo scope, NO mergea, issues no relacionadas van una por una) y b2 baja a 1 frase que preserva los Two Entry Points y cede el ruteo a los orquestadores. README §7 colapsa ~48 líneas de prosa drifteada a una tabla etapa -> skill -> quien-invoca -> gate, más nota de numeración (prefijos = orden de creación: dos b1, dos b7, sin b5, un solo b3; directorios no se renombran). `skills/b3-security/` se elimina (huérfano: ningún orquestador lo encadenaba y arrastraba contenido muerto tipo la tabla admin@test.com en un proyecto OAuth-only); su único contenido exclusivo, `requireAnyPermission`, se porta al checklist de b6 como apéndice "Patrones de referencia", y se quitan los 2 bullets MongoDB stale del checklist. El Área 3 de b6 colapsa a pointer + tabla clasificación -> severidad (el mapping BLOCKER sobrevive exactamente una vez); la fila security de b2 pasa a ruta relativa del checklist.

**Archivos clave**:
- `skills/b7-issue-to-pr/SKILL.md`, `skills/b10-ship/SKILL.md`, `skills/b8-swarm/SKILL.md`, `skills/b2-build-feature/SKILL.md` — descriptions con contrato de ruteo sin solape (cuando SÍ y cuando NO invocar cada uno)
- `README.md` — §7 prosa -> tabla + nota de numeración; fila b3-security fuera de §6
- `skills/b3-security/SKILL.md` — BORRADO (huérfano)
- `skills/b6-pr-review/references/security-checklist.md` — apéndice requireAnyPermission; bullets MongoDB fuera
- `skills/b6-pr-review/SKILL.md` — Área 3 = pointer al checklist + tabla clasificación -> severidad

**Riesgos / consideraciones**:
Bajo, solo docs/frontmatter. verdict.sh intacto: la tabla del Área 3 usa celdas (`| ... | BLOCKER |`) que no arrancan con `- **`, así que no altera el conteo `grep -cE '^- \*\*BLOCKER\*\*:'`; las instrucciones de formato del reporte quedan byte-idénticas. Grep de b3-security post-cambio: cero referencias activas (solo historia en CHANGELOG). Los 5 PASOS OBLIGATORIOS, B7_DONE y budgets de b7 no cambian — solo la parte de ruteo de su description.

**Links**: [issue #26](https://github.com/jporre/sveltekit-verticalslices/issues/26)

### refactor(b7): adelgazar SKILL.md a ~400 líneas, corregir drift 4v5 pasos, borrar usage.html (#25)

b7 corre como fork y pagaba sus 718 líneas en CADA issue, con el mandato anti-abandono repetido 6+ veces y drift "los 4 pasos" vs "CINCO PASOS" que dejaba ambiguo el set obligatorio. SKILL.md baja a ~650 líneas (la meta de ~400-500 quedó corta: los contratos mergeados post-issue en #43/#44/#45 — lane S, gates de evidencia/regresión, impact drift — se conservan íntegros): las 6 ocurrencias de "los 4 pasos" pasan a "los 5 pasos", se borran las secciones redundantes "Anti-patrón: parches inline en master" y "NO PARAR AQUÍ" (contenido único fusionado a "Qué NO hacer" y al paso 6), los headers 6/8/8b quedan alineados al número de PASO OBLIGATORIO del frontmatter (#3 commit, #4 PR+labels), y la lista canónica de puntos de heartbeat vive solo en el paso 2. Dos bloques bash copy-paste se scriptean en `guardrails.sh`: `worktree-env <dir>` (emite WORKTREE/BRANCH/PORT eval-safe desde `.b7/worktree-ready.json`, reemplaza el eval/sed/awk inline) y `dev-server start|stop <worktree>` (nohup dev.sh + pid + poll ~30s con WARN sin abortar; stop idempotente; mismos paths `.b7/dev-server.*` que consumen b8/b9). `docs/usage.html` (628 líneas, cero referencias) se borra. README §7 Step 3 se alinea con los 5 pasos reales (commit es #3, PR+labels #4, b6-review #5).

**Archivos clave**:
- `skills/b7-issue-to-pr/SKILL.md` — 718 → ~650 líneas; drift 4v5 corregido; dedupe mandato/heartbeat; bloques dev-server/worktree-env reemplazados por llamadas de 1-2 líneas
- `skills/b7-issue-to-pr/scripts/guardrails.sh` — NUEVOS subcomandos `dev-server start|stop` y `worktree-env`; `heartbeat` intacto (formato UTC que parsea b10)
- `skills/b7-issue-to-pr/docs/usage.html` — BORRADO (huérfano)
- `README.md` — §7 Step 3 alineado con los 5 PASO OBLIGATORIO

**Riesgos / consideraciones**:
Bajo. El formato del heartbeat no cambia (verificado con `date -j -u -f`); `dev-server` conserva los paths `.b7/dev-server.{log,pid}` que ya matan b9-close y usa b8-swarm; frontmatter description, B7_DONE, DoD checks 1-8 y budgets quedan byte-idénticos. `worktree-env` exige el marker `worktree-ready.json` (exit 30 si falta) — mismo invariante que verify-worktree.

**Links**: [issue #25](https://github.com/jporre/sveltekit-verticalslices/issues/25)

### refactor(pipeline): lib.sh — contratos inter-skill compartidos (find_pr, b6_verdict, label_event, blocked_by) (#24)

Los contratos entre orquestadores vivían copy-pasteados y drifteaban: el lookup de PR por "Closes #N" existía en variantes (b9 usaba search server-side sin frontera de dígitos + head -1), el sweep de events de labels estaba duplicado, y '## Blocked by' se parseaba con 2 gramáticas distintas — el sed inclusivo de run.sh capturaba el #N de la línea del heading siguiente (deps fantasma), mientras epic-graph.sh tenía el regex python correcto duplicado DOS veces en el mismo archivo. Nuevo `scripts/lib.sh` (raíz del plugin, sourceable, bash 3.2-safe) con 4 funciones: `bp_find_pr <issue> [open|merged]` (frontera `[^0-9]|$`: #261 no matchea #2610), `bp_b6_verdict <pr>` (delega en el lector único verdict.sh read), `bp_label_event <issue|pr> <label>` (UNA llamada --paginate -> `actor<TAB>created_at`; comparación de timestamps en el caller) y `bp_blocked_by` (stdin=body -> deps, lookahead NO inclusivo). `bash lib.sh selftest` corre los fixtures offline de bp_blocked_by (regresión: heading inmediato tras la sección -> cero deps fantasma) y cmd_preflight lo suma a su smoke-test.

**Archivos clave**:
- `scripts/lib.sh` — NUEVO: bp_find_pr, bp_b6_verdict, bp_label_event, bp_blocked_by + selftest con fixtures
- `skills/b10-ship/scripts/run.sh` — find_pr propio y sed inclusivo de deps eliminados; b6_marker vía bp_b6_verdict; lib.sh en el smoke de preflight
- `skills/b10-ship/scripts/epic-graph.sh` — regex duplicado x2 eliminado; deps se resuelven vía bp_blocked_by antes del python
- `skills/b9-close/SKILL.md` — PASO 0 (bp_find_pr open/merged), PASO 2 (bp_b6_verdict), PASO 4 (bp_label_event)
- `skills/b10-ship/SKILL.md` — staleness de epic-approved con snippet bp_label_event

**Riesgos / consideraciones**:
Bajo. Output de `epic-graph.sh 27` verificado byte-idéntico antes/después del refactor (stdout y stderr). lib.sh NO impone set -e/-u al sourcearse (los snippets de SKILL.md corren sin modo estricto). Fuera de alcance declarado: epic-diff.sh conserva su predicado [Cc]loses (necesita campos extra) y las llamadas directas de b7/b6 a verdict.sh read (verdict.sh sigue siendo la fuente única; bp_b6_verdict es el atajo para quien ya sourcea lib.sh).

**Links**: [issue #24](https://github.com/jporre/sveltekit-verticalslices/issues/24)

### feat(b2): verify.sh — el checklist de verificación como script con exit codes y browser-gate por scope de diff (#23)

La verificación de b2 era prosa honor-system triplicada (SKILL.md, checklist, b7): el orden check→format→autofixer→browser se re-derivaba cada run, el grep anti-React era manual y nada delataba pasos saltados. Nuevo `verify.sh` (contrato estilo assert-clean.sh): branch guard (exit 3), `pnpm check:machine` (4), `pnpm format` (no-gate), grep anti-React SOLO en archivos cambiados con file:line (5), `test:unit` condicional al diff (6) y browser-gate required si el diff toca `src/routes/**`, `*.svelte` o `*.remote.ts`. Última línea machine-readable `VERIFY_RESULT branch= check= react= test= browser= svelte_files=<csv>`; autofixer y walkthrough siguen siendo pasos del modelo gatillados por esa línea. Phase 3 de b2 orquesta verify.sh→autofixer→browser; el checklist queda como how-to de agent-browser; b7 usa verify.sh como pasada final pre-commit sin tocar el skip-by-scope del loop.

**Archivos clave**:
- `skills/b2-build-feature/scripts/verify.sh` — NUEVO: 6 gates, exit codes 2-6, línea VERIFY_RESULT
- `skills/b2-build-feature/SKILL.md` — Phase 3 pasa a verify.sh + autofixer sobre `svelte_files` + browser si `required`
- `skills/b2-build-feature/references/verification-checklist.md` — Steps 0-3 y grep absorbidos; queda el walkthrough de agent-browser
- `skills/b7-issue-to-pr/SKILL.md` — pasada final completa = verify.sh antes del paso 6 (commit)

**Riesgos / consideraciones**:
Bajo. El skip-by-scope del loop iterativo de b7 no cambia (sigue alimentando iter-logs/error-hash); verify.sh entra solo como pasada final. Criterios validados en repo sintético: on:click introducido → exit 5 con file:line; diff solo `.remote.ts` → browser=required; diff sin UI ni tests → test=skipped, browser=not-needed, exit 0.

**Links**: [issue #23](https://github.com/jporre/sveltekit-verticalslices/issues/23)


### feat(b2): Phase 1.5 impact check condicional + impact_files en el state de b7 (#22)

Antes se modificaban símbolos existentes (helpers de `$lib`, `*.remote.ts` con consumidores, `schema.ts`) sin mirar quien los consume — drift silencioso hasta el review. b2 gana Phase 1.5 condicional: impact set por símbolo vía `codegraph_impact` (probe `ok`) con fallback `rg -l`, skip explícito para greenfield y gate de scope-growth (archivos fuera del plan se agregan o se declara scope-growth antes de codear). b7 persiste el set en `.b7/state.json` campo `impact_files` vía state-set (bullet en el prompt del agente del paso 4) y en 8c contrasta `git diff --name-only` contra impact_files+files_likely emitiendo la señal `IMPACT_DRIFT` (visible, NO gate).

**Archivos clave**:
- `skills/b2-build-feature/SKILL.md` — Phase 1.5 entre Clarify y Build (trigger, skip greenfield, fallback rg, gate de scope-growth)
- `skills/b7-issue-to-pr/SKILL.md` — paso 4 bullet de persistencia de `impact_files`; 8c bloque de contraste con señal `IMPACT_DRIFT`
- `skills/b7-issue-to-pr/scripts/guardrails.sh` — clave `impact_files` en el scaffold de init-state (whitelist de state-set la acepta)

**Riesgos / consideraciones**:
Bajo. La señal de 8c es informativa (el gate duro sigue siendo el budget); codegraph nunca es gate (fallback rg); la clave nueva en el scaffold no la consume ningún template (envsubst la ignora).

**Links**: [issue #22](https://github.com/jporre/sveltekit-verticalslices/issues/22)


### feat(b6): CHANGED_SYMBOLS en pr-context.sh + callers de símbolos modificados (#21)

b6 excluía del análisis los símbolos que el PR modifica y nadie trazaba sus callers fuera del diff (así se escapó la regresión D5). `pr-context.sh` gana la sección `=== CHANGED_SYMBOLS ===` reutilizando el diff ya capturado: `NEW:`/`MODIFIED:` best-effort (exports en líneas +/- y contexto de hunk headers para modificaciones body-only) más línea `CODEGRAPH: ok|absent` vía el probe informativo de b1. SKILL.md cablea el uso: Área 2 punto 6 traza callers de cada MODIFIED (codegraph si ok, fallback `rg`; call site externo roto por firma nueva = BLOCKER) y Área 5 paso 2 usa codegraph como primario con las recetas Grep degradadas a fallback.

**Archivos clave**:
- `skills/b6-pr-review/scripts/pr-context.sh` — sección CHANGED_SYMBOLS al final (reusa `$DIFF`, sin llamadas gh extra)
- `skills/b6-pr-review/SKILL.md` — Paso 1 documenta la sección; Área 2 punto 6 (callers de MODIFIED); Área 5 paso 2 (codegraph primario, Grep fallback)

**Riesgos / consideraciones**:
Bajo. Detección best-effort solo para exports JS/TS; con codegraph ausente todo funciona vía rg (codegraph nunca es gate). Hallazgos se reportan dentro de '## 2. Calidad del Codigo' — cero impacto en los parsers de verdict.sh/b7/b9/b10.

**Links**: [issue #21](https://github.com/jporre/sveltekit-verticalslices/issues/21)


### feat(b7): carril rápido S — classify-run + lane S|M|L (#16)

classify-run asigna lane S/M/L; carril S usa render mecánico de screens, agente sonnet, 3 iteraciones y b6 --light. M/L byte-idénticos.
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

Cierra el gap de ruteo: el skill `bt1-data-table` solo se mencionaba en la tabla de skills auxiliares de b2, sin que triage ni los prompts de build de b7/b8 lo referenciaran. Se agrega la propiedad opcional `data_table: boolean` por pantalla en el contrato de triage y se propaga hasta los prompts de implementación. b1 marca `data_table: true` cuando la pantalla lista datos tabulares (columnas, orden, filtros o paginación en el acceptance criteria); b7 (paso 4) y b8 (prompt de build) inyectan una cláusula condicional: para esas pantallas el sub-agente invoca `bt1-data-table` vía Skill tool si está disponible, con fallback documentado a shadcn Table + paginación server-side según tamaño. Solo schema y texto de prompts, sin lógica nueva.

**Archivos clave**:
- `skills/b7-issue-to-pr/templates/triage-output.schema.json` — propiedad `data_table: boolean` (default false) por pantalla con description del criterio
- `skills/b1-triage-issue/SKILL.md` — criterio para marcar `data_table` al poblar pantallas tabulares
- `skills/b7-issue-to-pr/SKILL.md` — paso 4: cláusula condicional `data_table=true` en el prompt del sub-agente
- `skills/b8-swarm/SKILL.md` — misma cláusula en el prompt de build secuencial

**Riesgos / consideraciones**:
Bajo. `data_table` es opcional con default `false`: triage que no lo emite conserva el comportamiento actual y validate-triage pasa con y sin el flag (schema parsea con `json.load`). No hay ruteo forzado — el sub-agente cae al fallback shadcn Table si el skill no está disponible.

**Links**: [issue #20](https://github.com/jporre/sveltekit-verticalslices/issues/20)

### feat — vocabulario de states alineado + estado invalid-submit en screen-review (#19)

Screen-review ya no se limita al golden path. Se alinea el vocabulario de `states_required` entre el triage schema y screen-review, y se agrega el estado `invalid-submit`: submit con requeridos vacíos debe mostrar errores visibles; si el botón submit está `disabled` y por eso no aparece ningún error, es el anti-patrón de la receta de forms (`disabled={submitting}`, nunca `disabled={!isFormValid}`) y se marca `passed: false`. El enum de `states_required` pasa a `[golden, empty, loading, error, success, permission-denied, invalid-submit]` con default `[golden]`, y b7 deja de hardcodear `states=golden`: pasa los `states_required` reales de cada pantalla con fallback golden.

**Archivos clave**:
- `skills/b7-issue-to-pr/templates/triage-output.schema.json` — enum + default `[golden]` + description exigiendo `invalid-submit` en forms de crear/editar
- `skills/b7-screen-review/SKILL.md` — Step 3: estado `invalid-submit` (submit vacío → errores visibles; disabled sin errores = passed:false) + mapeo legacy (`success` ≡ `golden`, `permission-denied` → not-evaluated)
- `skills/b7-issue-to-pr/SKILL.md` — prompt del sub-agente pasa `states_required` con fallback golden; ejemplo de triage con `states_required: [golden, invalid-submit]`

**Riesgos / consideraciones**:
Bajo. Solo schema y documentación de skills, sin código ejecutable. Triage sin `states_required` conserva el comportamiento actual (golden) vía el default del schema y el fallback del prompt. Schema parsea con `json.load`.

**Links**: [issue #19](https://github.com/jporre/sveltekit-verticalslices/issues/19)

### feat — gate de test de regresión para runs type:fix (#18)

Todo run `type: fix` debe incluir un test de regresión (el que falla sin el fix y pasa con él). b7 inyecta un item `regression-test` al `plan[]` cuando el triage es `fix`, gateado por `plan-check` (DoD #6) sin lógica nueva; DoD gana un check #8 que degrada el run a `needs-human-review` (sin abortar) si el diff `master..HEAD` no toca ningún archivo `.(test|spec).`. Un waiver explícito (`plan-done regression-test` con `note: waived: <razon>`) cierra el item pero mantiene el status en `needs-human-review` para que un humano confirme. b6 detecta el mismo caso en el PR: `pr-context.sh` emite `FIX_REGRESSION_GATE` con `FIX_WITHOUT_TEST=true` cuando el headRef es `fix/*` y el diff no toca tests, y el Área 2 emite un WARNING pidiendo el test o justificación.

**Archivos clave**:
- `skills/b7-issue-to-pr/SKILL.md` — paso 1 inyecta `regression-test` al plan[] + documenta waiver; DoD check #8 (`FIX_SIN_TEST` → needs-human-review)
- `skills/b6-pr-review/scripts/pr-context.sh` — sección `FIX_REGRESSION_GATE` con `FIX_WITHOUT_TEST` al final de CLASSIFY_FILES
- `skills/b6-pr-review/SKILL.md` — Paso 1 lista `FIX_REGRESSION_GATE`; Área 2 emite WARNING si `FIX_WITHOUT_TEST=true`

**Riesgos / consideraciones**:
Bajo. El gate b7 es la fuente determinística (inyección al plan + DoD #8); b6 es una segunda red en el PR, no bloquea (WARNING). La detección de test es por patrón `.(test|spec).` — un proyecto con otra convención de nombres de test escaparía el gate. `bash -n` OK sobre `pr-context.sh`.

**Links**: [issue #18](https://github.com/jporre/sveltekit-verticalslices/issues/18)

### feat — triage de bugs con evidencia observable + gate anti-fabricación (#17)

Endurece el triage de `type: fix`: un bug ya no es `ready` por afirmar un síntoma, necesita al menos un artefacto observado. b1-triage gana Step 4e evidence-first (error exacto / salida / `path:linea` en `evidence.observed`, o degrada a needs-info con la verificación pendiente como pregunta), un probe de codegraph inline en Step 4 con fallback rg y `grounding_source`, y un gate anti-fabricación en `files_likely` (paths existentes deben venir de output de herramienta; archivos nuevos van como glob marcado). El schema compartido gana `evidence {observed, source}`, `grounding_source` y un `if type==fix then required evidence`. b7 agrega un gate determinístico vía jq en el paso 1: `fix` sin `evidence.observed` se trata como needs-info y baila antes de abrir worktree/PR.

**Archivos clave**:
- `skills/b7-issue-to-pr/templates/triage-output.schema.json` — `evidence`, `grounding_source`, `if/then` fix→evidence, nueva description de `files_likely`
- `skills/b1-triage-issue/SKILL.md` — Step 4 probe codegraph + gate anti-fabricación, Step 4e evidence-first, Step 7 sección Evidencia
- `skills/b1-triage-issue/references/comment-templates.md` — ejemplo Ready bug con `### Evidencia` citando output observado
- `skills/b7-issue-to-pr/SKILL.md` — paso 1 gate jq (fix sin evidence.observed → needs-info)

**Riesgos / consideraciones**:
El subset de `validate-triage` (guardrails.sh) no evalúa `if/then`; la obligatoriedad de `evidence` para bugs la aplica el gate jq de b7. Verificado: schema parsea, `validate-triage` sigue OK sobre triages existentes y rechaza claves desconocidas, el gate jq baila un `fix` sin `evidence.observed` y deja pasar uno con evidencia.

**Links**: [issue #17](https://github.com/jporre/sveltekit-verticalslices/issues/17)

### perf — batch de llamadas gh en topología de epics (#15)

Reutiliza los objetos completos del endpoint REST `sub_issues` (antes se descartaba todo salvo `.number` y se re-pegaba un `gh issue view` por sub-issue) y colapsa loops N+1 en una sola llamada. Sobre el epic #27 (25 sub-issues): `epic-graph.sh` 28->3 procesos gh, `epic-diff.sh` 103->3. Las deps de `run.sh` pasan a una query `gh api graphql` aliaseada; `b9-close` PASO 4 fusiona los dos `--paginate` idénticos sobre el endpoint de events en uno que emite `actor<TAB>created_at`.

**Archivos clave**:
- `skills/b10-ship/scripts/epic-graph.sh` — NDJSON directo con `state|ascii_upcase` (preserva el contrato OPEN de `epic-state.sh`); fallback por body intacto
- `skills/b10-ship/scripts/epic-diff.sh` — captura `sub_issues` una vez, lookups jq en memoria
- `skills/b10-ship/scripts/run.sh` — deps del reconcile vía una query graphql aliaseada
- `skills/b9-close/SKILL.md` — PASO 4 fusiona dos `--paginate` en uno

**Riesgos / consideraciones**:
Bajo. Outputs verificados byte-idénticos vs versión previa sobre epic #27. Un dep inexistente en `run.sh` degrada a "sin deps abiertas" (misma tolerancia previa).

**Links**: [issue #15](https://github.com/jporre/sveltekit-verticalslices/issues/15) · [PR #42](https://github.com/jporre/sveltekit-verticalslices/pull/42)


<!--
  Entrada CHANGELOG generada por b7-issue-to-pr.
  Tono: técnico-analítico para devs futuros leyendo historia.
  Se inserta bajo la sección [Unreleased] del CHANGELOG.md raíz.
-->

### feat(screen-review): mint-dev-session.sh — sesión dev scriptada (#14)

Nuevo `mint-dev-session.sh` (mint/verify/cleanup) que inserta una sesión válida en la DB del worktree para que screen-review pase el muro OAuth sin login manual. `mint` genera token base64url, deriva sessionId = sha256(token) hex (patrón Lucia v3), inserta en `app.user_session` (24h) vía node del worktree, y emite SOLO la línea `B7_SESSION_COOKIE=auth-session=<token>`. `verify` clasifica 200/permiso/inválida; `cleanup` borra por hash. b7-screen-review des-depreca `auth_cookie` e inyecta la cookie vía `document.cookie` en el mismo origen; b7-issue-to-pr 5.1 intenta mint+verify con fallback limpio al Chrome real y 5.9 hace cleanup siempre.

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

2 hooks nuevos (env-probe.sh, block-env-dump.sh) + wiring en hooks.json (Bash y Read) + nota de convención en guardrails.sh.
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



