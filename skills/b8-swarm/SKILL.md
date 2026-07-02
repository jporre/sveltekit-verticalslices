---
name: b8-swarm
description: 'Resuelve un CLUSTER de issues RELACIONADAS en UN SOLO PR (no uno por issue). Toma N issues que tocan la misma area —refactors de un mismo feature, una migracion en varios pasos, una serie "Fase X.Y"— y produce: 1 worktree, 1 rama, 1 commit por issue, 1 PR draft con `Closes #` para cada issue, 1 b6-pr-review del diff combinado. b9-close mergea una vez y cierra todas. Evita el conflicto inter-PR que aparece cuando issues relacionadas se abren como PRs separados (el segundo choca con el primero ya mergeado). Orquesta sub-skills via el tool Workflow: triage en paralelo (read-only) + build secuencial sobre la rama compartida. NO mergea (eso es b9-close, con ojo humano). Usalo SIEMPRE que pidan trabajar varias issues/tareas juntas, en batch, "en una sola PR", "todas estas tareas relacionadas", una serie de fases, o pasen una lista de numeros de issue para resolver de una. Encadena: b1-triage-issue, b1-add-worktree, b2-build-feature, b7-screen-review, b3-git-commit, b4-pull-request, b6-pr-review. PROHIBIDO: paralelizar el build de issues relacionadas (tocan los mismos archivos), abrir un PR por issue, o mergear.'
allowed-tools: Bash, Read, Edit, Write, Skill, Agent, Workflow
model: opus
effort: medium
---

# b8-swarm — cluster de issues relacionadas → UN PR

Toma un grupo de issues **relacionadas** y las resuelve como **un solo cambio coherente**: un worktree, una rama, un commit por issue, un PR draft que las cierra todas, una review. El merge final (1 vez, cerrando todas) lo hace `b9-close` con aprobacion humana.

## Por que un PR y no N

El modelo viejo de b8 corria un `b7-issue-to-pr` por issue → **N PRs independientes**. Cuando las issues son **relacionadas** (tocan los mismos archivos), eso genera conflictos: el PR #2 se basa en master viejo y choca con el #1 ya mergeado, forzando rebase manual. Caso real (2026-06-02): #188/#189/#190 eran refactors del mismo `dispatcher/`; como PRs separados, #214 conflictó con #212/#213 ya en master.

En **un PR** los cambios componen sobre una rama: sin conflicto inter-PR, una review del cambio completo, un merge atomico. Ese es el punto de este skill.

> Cuando las issues NO estan relacionadas (features independientes, areas distintas), **no** las metas en un PR — usá `b7-issue-to-pr` una por una. b8 es para clusters cohesivos.

## Contexto de ejecucion: main loop, no fork

Este skill **no** declara `context: fork`. Corre en el contexto principal **a proposito**: el tool `Workflow` —eje de la orquestacion— vive en el main loop y **no esta disponible en ejecuciones forkeadas** (comprobado en 2 runs el 2026-06-02; el fork degradaba a Skill secuencial sin journaling). La isolacion de contexto la da el propio Workflow: cada `agent()` es un subagente cuyos tool-calls verbosos no contaminan la conversacion; el main solo ve los resultados estructurados.

## Lo que b8 NO hace

- **No paraleliza el build de issues relacionadas.** Comparten worktree y archivos: dos builds simultaneos se pisan. El build es **secuencial** (`for...of await`), commit por issue. Solo el **triage** es paralelo (read-only). Paralelizar el build solo seria valido para issues disjuntas — y esas no van en el mismo PR.
- **No abre un PR por issue.** Un cluster = un PR. Si te encontras abriendo varios PRs, no es b8.
- **No mergea.** El PR queda draft + b6-review adjunto. Merge + cierre + limpieza = `b9-close`, con ojo humano.
- **No es un loop sobre b7.** b8 es hermano de b7, no lo invoca. Ambos pegan los mismos sub-skills (b1/b2/b3/b4/b6) a distinta cardinalidad: b7 = 1 issue → 1 PR; b8 = cluster → 1 PR. No copies logica de b7; invocá los sub-skills.

## Argumentos

```
--issues=N1,N2,...        cluster explicito (orden = orden de build)
[--theme=<slug>]          tema para la rama: <type>/<theme>. Sin esto: swarm/<ids>
[--max=N]                 cap de issues (default 5). Aplica al backlog, no a --issues.
[--label=ready,auto-pr]   query del backlog si no se pasa --issues
[--dry-run | --wet]       dry-run = arma la rama en el worktree, SIN PR/labels/comentarios
[--on-error=continue|abort]  que hacer si un issue falla el build (default continue)
[--no-screens]            saltar review visual aunque haya screens
```

**Argumentos recibidos en esta invocacion:**

```text
$ARGUMENTS
```

> El placeholder `$ARGUMENTS` es la via por la que los flags tipeados llegan al skill — el harness lo sustituye. Si aparece vacio, usar defaults y, sin `--issues`, sacar la cola del backlog.

Defaults: `--wet`, `--max=5`, `--on-error=continue`, `--label=ready,auto-pr`. Sin `--issues`, la cola sale del backlog (`guardrails.sh backlog`).

### dry-run vs wet

- `--wet` (default): flujo completo — triage, worktree, build+commits, screen-review, PR draft, labels, b6-review.
- `--dry-run`: triage + worktree + build + commits **locales**. **NO** abre PR, **NO** mueve labels, **NO** comenta en los issues. Deja la rama lista para inspeccionar (`git -C <worktree> log master..HEAD`, `git diff master`). Para validar el cambio combinado antes de publicar.

## Flujo

### 1. Preflight + cola (`scripts/run.sh`)

`scripts/run.sh <args>` corre los pasos no-LLM:
- Preflight (`guardrails.sh preflight`): kill-switch (`b8.STOP`/`b7.STOP`), `gh auth`, working tree del repo principal **limpio**, lock libre, backpressure.
- Construye la cola: de `--issues` (en orden) o del backlog (`guardrails.sh backlog <label> <max>`, oldest-first, filtra `do-not-automate` y `<!-- no-auto-pr -->`).
- Escribe el scaffold del reporte y emite lineas parseables: `B8_LOCK`, `B8_RUN_REPORT`, `B8_MODE`, `B8_ON_ERROR`, `B8_THEME`, `B8_QUEUE_BEGIN/END`.

Si preflight falla, reportar el exit code y salir. No arreglar el estado subyacente.

### 2. Worktree unico (`b1-add-worktree`, 1 vez)

Decidir la rama **antes** del worktree:
- Con `--theme=<slug>` → rama `<type>/<theme>` (type lo afinás tras el triage; arrancá con `refactor/` si dudás, es el caso comun de cluster).
- Sin `--theme` → rama `swarm/<ids-ordenados>` (ej. `swarm/192-193`). El titulo/cuerpo del PR igual llevan un resumen humano derivado del triage.

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cat "$HOME/.claude/b-pipeline.root" 2>/dev/null || ls -d "$HOME"/.claude/plugins/marketplaces/b-pipeline* 2>/dev/null | head -1)}"
BRANCH="refactor/<theme>"   # o swarm/<ids>
OUT=$(bash "$PLUGIN_ROOT/skills/b1-add-worktree/scripts/setup-worktree.sh" "$BRANCH" master --headless)
LINE=$(echo "$OUT" | grep '^WORKTREE_READY ' || true)
[ -z "$LINE" ] && { echo "ABORT: worktree no creado"; exit 1; }
eval "$(echo "$LINE" | sed 's/^WORKTREE_READY //' | tr ' ' '\n' | awk -F= '{print "WT_"toupper($1)"="$2}')"
export WORKTREE="$WT_DIR" BRANCH="$WT_BRANCH" PORT="$WT_PORT"
mkdir -p "$WORKTREE/.b7"
```

**Prohibido `git worktree add` directo** (hay un hook que lo bloquea). Siempre `setup-worktree.sh`.

### 3 + 4. Triage paralelo → build secuencial (tool `Workflow`)

Una sola invocacion del `Workflow` con dos fases. Pasale el cluster + el worktree + la rama como `args`. Ver "Script de referencia". Resumen:

- **Fase `triage` (paralela, read-only):** un `agent()` por issue corriendo `b1-triage-issue`, escribiendo `.b7/triage-<n>.json` en el worktree. Cada uno devuelve `{issue, verdict, type, scope, screens, plan}`. Read-only: **no editan codigo**. Paralelo seguro (cada uno escribe su propio archivo).
- Gate: descartar issues con `verdict != ready` (se anotan como skipped en el reporte; no entran al `Closes`).
- **Fase `build` (SECUENCIAL):** `for...of await` por issue ready. Cada `agent()`:
  1. corre `b2-build-feature` leyendo `.b7/triage-<n>.json`, sobre el worktree compartido (feature colocado en `src/routes` + Remote Functions, sin state global, errores `error(STATUS,{message,code})`);
  2. valida con skip-by-scope (`check:machine`/`lint`/`test` solo si el diff toca `.ts/.svelte/.js`);
  3. al verde, commitea **solo los cambios de ese issue** con `b3-git-commit`, scope `(#N)`;
  4. si no llega a verde dentro del budget, **revierte sus cambios sin commitear** (`git -C <worktree> checkout -- . && git clean -fd`) y devuelve `status:failed` — asi un issue fallido no deja basura en la rama ni entra al `Closes`.

El build es secuencial porque las issues relacionadas tocan los mismos archivos; el commit-por-issue mantiene cada uno atomico y reversible.

### 5. Review visual (union de pantallas, 1 pasada)

Si algun triage trae `screens[]` y no se paso `--no-screens` (y no es `--dry-run`):
- Juntar todas las `screens[]` de los triages ready, **deduplicar por `route`**.
- Levantar el dev server del worktree (`nohup ./dev.sh > .b7/dev-server.log 2>&1 & echo $! > .b7/dev-server.pid`), esperar a que responda en `$PORT`.
- Un `Agent(general-purpose)` con `b7-screen-review` por pantalla unica (reusa el Chrome real; `auth-required` → `not-evaluated`, no `fail`). Cargar las MCP tools de claude-in-chrome con ToolSearch primero.
- Apagar el dev server al terminar (`kill $(cat .b7/dev-server.pid)`).

Cluster backend puro (sin screens) → saltar, anotar en el reporte. Un `fail` visual con sesion valida → devolver al build de ese issue.

### 6. UN PR draft (`b4-pull-request`, 1 vez) — solo en `--wet`

- `scripts/publish-docs.sh` de b7 NO sirve tal cual (es por-issue). Para b8, armar el cuerpo del PR a mano o con un `agent()` de redaccion (haiku): titulo = resumen del cluster; cuerpo con seccion por issue + **una linea `Closes #N` por cada issue ready commiteado**.
- `b4-pull-request --draft --label auto-pr-bot --body-file <cuerpo>`.
- El PR cierra **todas** las issues `Closes #` al mergear (GitHub las parsea sin importar el merge method).

### 7. Labels + sticky por issue — solo en `--wet`

Por cada issue ready commiteado:
```bash
gh issue edit <N> --remove-label "ready,auto-pr" --add-label "in-review"
gh issue comment <N> --body "🤖 Incluido en PR #<PR> (cluster: #<otros>). Ver ahi el avance."
```
En `--dry-run` se saltan labels y comentarios.

### 8. UNA b6-pr-review — solo en `--wet`

`b6-pr-review` con el numero del PR (review del **diff combinado**, no por issue). Adjuntar como comentario. Findings `high|critical` → volver al build del issue culpable (si el budget alcanza) o marcar `needs-human-review`.

### 9. Reporte + cierre

`record-result.sh <report> <issue> <status> [pr-url] [note]` por issue (ok/skipped/failed). Cerrar con: cola, theme/branch, worktree, PR URL (o "dry-run, sin PR"), outcome por issue, b6 verdict. Liberar lock (el `trap` de `run.sh` ya lo hace en EXIT).

## Script de referencia (Workflow)

Invocar tras crear el worktree (paso 2):

```js
export const meta = {
  name: 'b8-swarm',
  description: 'Triage paralelo + build secuencial de un cluster sobre una rama compartida',
  phases: [
    { title: 'triage', detail: 'b1-triage-issue por issue, paralelo, read-only' },
    { title: 'build', detail: 'b2-build-feature secuencial, commit por issue (#N)' },
  ],
}

// args: { issues:[192,193], worktree:'/abs/path', branch:'refactor/...', dryRun:false, onError:'continue' }
const TRIAGE = {
  type:'object', required:['issue','verdict'],
  properties:{ issue:{type:'number'}, verdict:{enum:['ready','needs-info','reject']},
    type:{type:'string'}, scope:{type:'string'},
    screens:{type:'array'}, plan:{type:'array'}, note:{type:'string'} },
}
const BUILD = {
  type:'object', required:['issue','status'],
  properties:{ issue:{type:'number'}, status:{enum:['ok','failed','skipped']},
    commit:{type:'string'}, files:{type:'number'}, note:{type:'string'} },
}

// IMPORTANTE (quirk del harness, comprobado 2026-06-02): el tool serializa `args`
// como string JSON. Normalizá SIEMPRE antes de usarlo, o `A.issues.map` revienta
// con "undefined is not an object (evaluating 'A.issues.map')".
const A = (typeof args === 'string') ? JSON.parse(args) : (args || {})

phase('triage')
const triages = (await parallel(A.issues.map(n => () =>
  agent(
    `Triage del issue #${n} con el skill b1-triage-issue. Escribí ${A.worktree}/.b7/triage-${n}.json ` +
    `siguiendo el schema de b1. Es READ-ONLY: no edites código. ` +
    `Devolvé {issue:${n}, verdict, type, scope, screens, plan, note}.`,
    { label:`triage:#${n}`, phase:'triage', schema:TRIAGE }
  )
))).filter(Boolean)

const ready = triages.filter(t => t.verdict === 'ready')
log(`triage: ${ready.length}/${A.issues.length} ready`)

phase('build')
const builds = []
for (const n of A.issues) {                       // SECUENCIAL: comparten worktree
  const t = ready.find(x => x.issue === n)
  if (!t) { builds.push({ issue:n, status:'skipped', note:'triage no-ready' }); continue }
  const out = await agent(
    `Implementá el issue #${n} en el worktree COMPARTIDO ${A.worktree} (rama ${A.branch}). ` +
    `Usá b2-build-feature leyendo ${A.worktree}/.b7/triage-${n}.json. Feature colocado en src/routes + Remote Functions. ` +
    `Validá (check:machine/lint/test, skip-by-scope). Al verde, commiteá SOLO los cambios de este ` +
    `issue con b3-git-commit, scope (#${n}). Si NO llegás a verde dentro del budget: revertí tus ` +
    `cambios sin commitear (git checkout -- . && git clean -fd) y devolvé status:failed — no dejes ` +
    `basura en la rama. Devolvé {issue:${n}, status, commit, files, note}.`,
    { label:`build:#${n}`, phase:'build', schema:BUILD }
  )
  builds.push(out ?? { issue:n, status:'failed', note:'agente nulo' })
  log(`#${n} → ${out?.status ?? 'failed'}`)
  if (A.onError === 'abort' && out?.status !== 'ok') break
}

return { triages, builds }
```

Invocacion: `Workflow({ script:<lo de arriba>, args:{ issues:[192,193], worktree:WORKTREE, branch:BRANCH, dryRun:false, onError:'continue' } })`.

El valor devuelto (`{triages, builds}`) alimenta los pasos 5–9 en el main context.

## Scripts disponibles

| Script | Hace |
|---|---|
| `scripts/run.sh` | Preflight + lock + cola + scaffold del reporte. Emite `B8_LOCK/RUN_REPORT/MODE/ON_ERROR/THEME/QUEUE_*`. |
| `scripts/guardrails.sh` | `state-dir`, `killswitch`, `acquire-lock`, `release-lock`, `backpressure`, `preflight`, `backlog <label> <max>`. |
| `scripts/record-result.sh <report> <issue> <status> [pr-url] [note]` | Anexa fila de resultado por issue al reporte. |

(`invoke-b7.sh` fue **eliminado**: b8 ya no invoca b7.)

## Definition of Done de una ola

Al cerrar (exito o abort), b8 debe haber:

1. Liberado el lock (`b8.lock` borrado).
2. Escrito `b8-runs/<stamp>.md` con: cola, theme/branch, worktree, outcome por issue, PR URL (o "dry-run").
3. En `--wet`: dejado **1 PR draft** con `Closes #` por cada issue ready, labels de esos issues en `in-review`, b6-review adjunto.
4. En `--dry-run`: dejado el worktree con la rama combinada lista para inspeccion (`git log master..HEAD`), sin tocar GitHub.
5. Si abortó: motivo claro (kill-switch, backpressure, tree sucio, build fallido con `--on-error=abort`).

**Frases prohibidas al cerrar:**
- "Abrí PRs N, M, K" → b8 abre **un** PR. Si abriste varios, el diseño se rompió.
- "Pendiente mergear el PR" → esperado; el merge es `b9-close` con ojo humano, no pendiente de b8.
- "Listo para correr b6 sobre el PR" → b8 ya lo corre (paso 8) en `--wet`.

## Dependencia: b9-close con multiples `Closes #`

`b9-close` ya itera **todos** los `Closes #` del PR (variable `$ISSUES` de su PASO 0): GitHub cierra todos los issues al mergear y b9 limpia labels y reporta cada uno. No se requiere limpieza manual post-merge para PRs cluster.

## Variables de entorno

| Var | Default | Para que |
|---|---|---|
| `B8_MAX_PER_WAVE` | 5 | Cap de issues del backlog si no se pasa `--max`. |
| `B8_DEFAULT_LABEL` | `ready,auto-pr` | Label query del backlog. |
| `B7_MAX_OPEN_PRS` | 3 | Backpressure heredado. Casi moot (b8 = 1 PR/ola), pero corta si ya hay 3 PRs `auto-pr-bot` abiertos. |
| `CLAUDE_PROJECT_DIR` | _(Claude Code)_ | State-dir / lock / runs. |

## Kill-switch

```bash
touch "$CLAUDE_PROJECT_DIR/b8.STOP"   # corta antes del proximo issue del build
rm "$CLAUDE_PROJECT_DIR/b8.STOP"      # rehabilita
```

Se chequea en preflight y conviene re-chequearlo entre issues del build (un `guardrails.sh killswitch` al tope de cada iteracion del `for`). No mata el build en curso; corta antes del siguiente.

## Anti-patrones

- **Paralelizar el build.** Issues relacionadas comparten archivos: builds concurrentes se pisan. Build secuencial, triage paralelo. (Si fueran disjuntas, no irian en el mismo PR.)
- **Un PR por issue.** Es el modelo viejo y la causa del conflicto inter-PR. b8 = 1 PR.
- **Loopear b7.** b7 hace su propio worktree/PR/labels — incompatible con el PR unico. Invocá los sub-skills (b1/b2/b3/b4/b6), no b7.
- **Mergear en la ola.** Ningun PR del bot va a master sin ojo humano. Merge = `b9-close`.
- **Meter issues no relacionadas en el cluster.** Si no tocan la misma area, son PRs separados (b7), no un combinado.
- **Dejar un issue fallido a medias en la rama.** Build fallido → revertir sin commitear; nunca commitear codigo rojo "para arreglar despues".
