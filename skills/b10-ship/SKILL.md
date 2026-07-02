---
name: b10-ship
description: 'Orquestador del pipeline completo issue -> worktree cerrado. Encadena b1-triage-issue, b7-issue-to-pr, b6-pr-review y b9-close con gates humanos exactos (triage con dudas, pre-merge, epic-review). Use cuando el usuario diga "ship issue N", "lleva el issue N hasta el merge", "/b10-ship N", "procesa el epic N", "drena el epic". Idempotente: re-correr el mismo comando reconcilia el estado desde GitHub y retoma donde quedo. NO implementa, NO revisa, NO mergea por si mismo — solo decide y encadena skills existentes.'
allowed-tools: Bash, Read, Write, Skill, Agent, Workflow, AskUserQuestion
model: sonnet
---

# b10-ship — issue → worktree cerrado

> SIN `context: fork` a proposito: este skill corre en el main loop porque necesita el tool `Workflow` (no existe en forks) y `AskUserQuestion` con el usuario presente. La isolacion la dan los skills encadenados (b7 es fork; los agentes de Workflow son subagentes).

## Argumentos

```
<issue>                  # modo single-issue
--epic=<N>               # modo epic: drena el grafo de sub-issues de N
--dry-run                # solo reporta que haria (reconcile + plan), no ejecuta
--informe                # al cerrar, invocar informe-semanal --feature
--cluster                # en modo epic: olas independientes via b8-swarm (1 PR combinado)
```

El estado canonico vive en GitHub (labels, comentarios con markers, PRs). **Recuperacion universal: re-correr `/b10-ship <mismo arg>`** — la reconciliacion salta a la fase pendiente.

## Cadena single-issue

### 0. Preflight + lock

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cat "$HOME/.claude/b-pipeline.root" 2>/dev/null || ls -d "$HOME"/.claude/plugins/marketplaces/b-pipeline* 2>/dev/null | head -1)}"
B10="$PLUGIN_ROOT/skills/b10-ship/scripts/run.sh"
bash "$B10" preflight        # 20=killswitch, 12=gh auth, 18=tree sucio, 17=backpressure, 2=script faltante
bash "$B10" acquire-lock     # 21=otro run activo (stale a las 6h); emite B10_LOCK_TOKEN
```

- **exit 17 (backpressure, ≥3 PRs auto-pr-bot abiertos):** NO abortar a secas. Listar los PRs abiertos (`gh pr list --label auto-pr-bot`) y ofrecer drenarlos primero (fase close sobre los que tengan aprobacion — ver "drain-first"). El propio gate de merge humano es lo que destraba.
- **exit 18 (working tree del repo principal sucio):** reportar los archivos y parar — b7/b8 abortarian igual a mitad de build.
- **exit 20/21/12:** reportar y parar. **Tras exit 21 NO correr release-lock** — el lock es de otra sesion (puede estar legitimamente retenida en un gate humano).
- Guardar `B10_LOCK_TOKEN` y liberar al terminar con `release-lock <token>` (exito o falla). El token evita borrar el lock de otra sesion.
- **TOCTOU residual:** b7 re-chequea backpressure y tree limpio en SU preflight; si b7 aborta sin sticky comment, la causa probable es ese preflight (estado cambio entre medio) — re-correr `/b10-ship N` reconcilia y reintenta.

### 1. Reconciliar

```bash
bash "$B10" reconcile <N>
```

Saltar a la fase que indica `B10_PHASE=`:

| B10_PHASE | Significado | Accion |
| --- | --- | --- |
| `done` | Issue cerrado | Reportar no-op. Si aparece `B10_WORKTREE` (limpieza pendiente) o `B10_PR_ORPHAN` (PR abierto de un issue cerrado), ofrecer resolverlos via b9. |
| `close` | PR con veredicto b6 `blockers=0` (o `B10_PR_MERGED`: mergeado con issue abierto) | Ir a fase 5 (close). |
| `verify` | PR abierto sin review, o con veredicto `blockers>0` | Ir a fase 4 (verify). |
| `build` | Worktree existe sin PR | Retomar build (fase 3). Si `B10_ZOMBIE=true`: ver "runs zombie". |
| `blocked` | Deps abiertas (`B10_BLOCKED_BY`) o needs-info sin respuesta | Reportar y parar (en modo epic: seguir con otro issue). |
| `triage` | Nada empezado (o needs-info con respuesta nueva) | Fase 2. |

### 2. Triage — gate condicional

```bash
# via Skill tool:
Skill b-pipeline:b1-triage-issue "<N> --auto"
```

Parsear la ultima linea `TRIAGE_RESULT {...}`. **Fallback si falta:** leer labels del issue (`ready`/`needs-info`/`blocked`/`duplicate` + `simple`/`medium`/`complex`).

- `verdict=ready` y complexity `simple|medium` → fase 3.
- `verdict=ready` y complexity `complex` → **GATE**: b7 baila con complejidad complex por politica propia. Preguntar via `AskUserQuestion`: "Issue #N es complex — ¿forzar b7 / construir interactivo (b2) / saltar?". Si elige forzar: `Skill b-pipeline:b7-issue-to-pr "<N> --lang=es --force-complex"` (b7 soporta el flag; los budgets siguen aplicando). En headless: comentar en el issue, no tocar labels, parar.
- `verdict=needs-info|blocked|duplicate|closed` → las preguntas/razones ya quedaron en el issue (las posteo b1). Notificar (PushNotification si esta disponible) y parar. Reanudacion: cuando el reporter responda, el proximo re-run detecta el comentario nuevo (`B10_NEEDS_INFO_ANSWERED=true`) y re-triagea solo.

### 3. Build

```bash
Skill b-pipeline:b7-issue-to-pr "<N> --lang=es"
```

Parsear la ultima linea `B7_DONE issue=<N> pr=<url|none> status=<s>`. **Fallback:** `bash "$B10" reconcile <N>` — si aparece `B10_PR`, el build termino.

- `status=ok` → fase 4.
- `status=needs-human-review` → label ya puesto por b7; notificar y parar (worktree intacto para correccion humana).
- `status=bailed|aborted` → leer la razon del sticky comment del issue; si es budget/no-progress → label `pipeline-failed` + comentario diagnostico (fase, worktree, ultimo error) y parar.

### 4. Verify

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cat "$HOME/.claude/b-pipeline.root" 2>/dev/null || ls -d "$HOME"/.claude/plugins/marketplaces/b-pipeline* 2>/dev/null | head -1)}"
WT=<B10_WORKTREE si existe>
[ -n "$WT" ] && bash "$PLUGIN_ROOT/skills/b1-add-worktree/scripts/assert-clean.sh" "$WT" --fix
# exit 6 -> Skill b-pipeline:b3-git-commit en el worktree + push (el PR debe contener TODO)
```

Veredicto b6: buscar el marker en comentarios del PR (`B10_B6` del reconcile). Si `absent`:

```bash
Skill b-pipeline:b6-pr-review "<PR> --auto"
```

- `blockers=0` → fase 5.
- `blockers>0` → b7 ya re-itero lo que pudo; label `needs-human-review` al issue, comentar resumen de blockers, notificar y parar.

### 5. Close — gate humano SIEMPRE

```bash
Skill b-pipeline:b9-close "<PR>"
```

b9 trae los dos canales de aprobacion (label `merge-approved` asincrono / `AskUserQuestion` en sesion) y TODOS los guardrails de limpieza (rescue branch, multi-Closes, no force-remove). No duplicar nada de eso aqui.

- Usuario ausente y sin label → b9 deja `awaiting-approval` y aborta: notificar con URL del PR y parar. El proximo re-run salta directo a esta fase.
- `B9_MERGED` → si se paso `--informe`: `Skill informe-semanal "--feature <N>"`. Reportar.

### 6. Cierre del run

```bash
bash "$B10" release-lock "$B10_LOCK_TOKEN"   # solo borra si el lock es de esta sesion
```

Ultima linea SIEMPRE:

```
B10_DONE issue=<N> phase_final=<done|stopped-at-*> pr=<url|none>
```

## Modo epic (`--epic=<N>`)

El epic es un tracking issue con sub-issues nativos de GitHub (vincular una vez con `epic-link.sh`). Las dependencias finas viven en la seccion `## Blocked by` de cada body.

### Loop principal

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cat "$HOME/.claude/b-pipeline.root" 2>/dev/null || ls -d "$HOME"/.claude/plugins/marketplaces/b-pipeline* 2>/dev/null | head -1)}"
EPIC_SCRIPTS="$PLUGIN_ROOT/skills/b10-ship/scripts"
bash "$EPIC_SCRIPTS/epic-state.sh" <EPIC>    # snapshot PARALELO: topologia + reconcile live por sub-issue
```

`epic-state.sh` reemplaza a llamar `epic-graph.sh` + reconciliar issue por issue. Combina la **topologia** (waves, deps, `closing_slice`) con el **estado live** de cada sub-issue (`phase`, `pr`, `b6`, `worktree`, `zombie`) reconciliado **en paralelo** (read-only, acotado a `B10_RECONCILE_PARALLEL=8`). Una pasada da el grafo entero con su fase actual — en vez de N reconciles secuenciales (cada uno con varias llamadas gh). Salida: el JSON de `epic-graph` con un objeto `live` por issue, mas la linea `B10_EPIC_STATE epic=N waves=K open=n closeable=<csv> buildable=<csv> blocked=<csv>`.

> `epic-graph.sh` sigue existiendo y es lo que `epic-state.sh` usa internamente para la topologia; invocarlo directo solo si querés la topologia cruda sin el estado live (p.ej. debug del calculo de waves).

Con el snapshot en mano, despachar fases — **leer una vez, actuar en paralelo donde sea read-only, serializar lo que toca master o el worktree**:

1. **Drain-first:** ANTES de lanzar builds, cerrar lo cerrable — los issues que el snapshot marca `closeable` (phase=close: PR abierto con veredicto b6 `blockers=0`, o PR mergeado con issue abierto). Las **decisiones** de cierre ya vienen del snapshot (b6 + labels) y pueden mirarse juntas; el **merge en si va serial** (b9 uno a uno — dos merges concurrentes a master se pisan). Cada cierre libera backpressure y desbloquea dependencias.
2. **Detectar el slice de cierre** (`closing_slice` del snapshot): el issue cuyas deps cubren al resto del grafo — frecuentemente es el PROPIO epic (ej #271, tracking + swap/limpieza a la vez). NUNCA construirlo sin el gate de epic-review (abajo). Cuando es el epic mismo, tras el gate se corre la cadena single-issue sobre el numero del epic.
3. **Triagear la ola en paralelo:** los issues `buildable` cuya fase es `triage` (aun sin veredicto) se triagean **todos juntos** via Workflow (read-only, ver "Triage paralelo de una ola"). Devuelve `{issue, verdict, complexity, scope}` por issue — el insumo para decidir build vs cluster sin pagar N triages secuenciales.
4. **Siguiente ola — build:** issues con todas sus deps `CLOSED` y sin PR propio, ya triageados.
   - Ola con 1 issue, o issues `complex` → cadena single-issue por issue, **secuencial** (b7 toma `b7.lock`; dos builds a la vez no pueden coexistir — ver "Paralelismo").
   - Ola con ≥2 issues independientes `simple|medium`, **del mismo `scope`** (b8 exige cohesion tematica — issues de scopes distintos NUNCA van al mismo PR) y flag `--cluster` → `Skill b-pipeline:b8-swarm "--issues=<csv> --theme=<scope>"` (1 worktree, 1 PR combinado, commits por issue; el b9 multi-Closes limpia todo al mergear). Issues de la ola con scope distinto van por la cadena single-issue.
5. Repetir mientras haya issues desbloqueados y el backpressure lo permita. Un issue frenado (needs-info, complex, zombie) NO bloquea a sus hermanos independientes. **Re-correr `epic-state.sh` al inicio de cada iteracion del loop** (tras drenar o construir algo cambia el grafo) — es barato (paralelo) y mantiene las decisiones sobre estado fresco.
6. Al final, reportar el estado del grafo completo: cerrados / en PR / frenados (con razon) / bloqueados.

### Paralelismo: que corre junto y que no

Regla unica: **read-only paraleliza, escritura a master/worktree serializa.**

| Fase | Paraleliza | Por que |
| --- | --- | --- |
| Reconcile / snapshot del grafo | **Si** (`epic-state.sh`, bash ThreadPool) | Solo lee GitHub + worktrees locales. N issues → ~1 RTT. |
| Triage de una ola | **Si** (Workflow, 1 `agent()` por issue) | b1-triage es read-only; cada agente escribe su propio `triage-<n>.json`. |
| Epic-review (diff + walkthrough) | **Si** parcial (Agent opus para el diff mientras se prepara el worktree) | El analisis del diff no toca estado. |
| **Build** (b7 single-issue) | **NO** | b7 toma `b7.lock` global: solo un build a la vez. Ademas backpressure corta a 3 PRs `auto-pr-bot` abiertos. |
| **Build** (b8 cluster) | **NO entre clusters** (b8 ya paraleliza su triage interno) | Mismo lock + worktree compartido por cluster. |
| **Merge / close** (b9) | **NO** | Dos merges concurrentes a master conflictuan. Serial, uno a uno. |

Por que el build no paraleliza aunque los issues sean disjuntos: el cuello es `b7.lock` (un build activo) + el cap de backpressure, no el grafo. Querer N builds simultaneos exigiria locks por-worktree en b7 — fuera del alcance de b10, que **solo orquesta**. b10 acelera lo que SI es seguro: el planning (snapshot paralelo) y el triage (fan-out). El build queda serial a proposito.

### Triage paralelo de una ola (Workflow)

Cuando una ola trae ≥2 issues en fase `triage`, triagearlos juntos en vez de uno por uno. Una sola invocacion del `Workflow`:

```js
export const meta = {
  name: 'b10-wave-triage',
  description: 'Triage read-only en paralelo de los issues de una ola del epic',
  phases: [{ title: 'triage', detail: 'b1-triage-issue por issue, paralelo, read-only' }],
}

// args llega como string JSON (quirk del harness) — normalizar SIEMPRE.
const A = (typeof args === 'string') ? JSON.parse(args) : (args || {})
const TRIAGE = {
  type: 'object', required: ['issue', 'verdict'],
  properties: {
    issue: { type: 'number' },
    verdict: { enum: ['ready', 'needs-info', 'blocked', 'duplicate', 'closed'] },
    complexity: { enum: ['simple', 'medium', 'complex'] },
    scope: { type: 'string' }, note: { type: 'string' },
  },
}

phase('triage')
const triages = (await parallel(A.issues.map(n => () =>
  agent(
    `Triage del issue #${n} con el skill b1-triage-issue (modo --auto). Es READ-ONLY: ` +
    `NO edites codigo, NO abras worktree. Devolve {issue:${n}, verdict, complexity, scope, note} ` +
    `y dejá el comentario de triage en el issue como hace b1.`,
    { label: `triage:#${n}`, phase: 'triage', schema: TRIAGE }
  )
))).filter(Boolean)

return { triages }
```

Invocacion: `Workflow({ script:<lo de arriba>, args:{ issues:[262,263,264] } })`. El `{triages}` devuelto alimenta la decision build-vs-cluster del paso 4 en el main context. Issues que el snapshot ya trae con veredicto (label `ready`/`needs-info`/…) NO se re-triagean — solo los de fase `triage` sin marker.

> **Build NO va por este Workflow.** El triage es read-only y paraleliza; el build de b7 toma lock y va por `Skill` directo (fork pesado), uno a la vez. No metas `b7-issue-to-pr` dentro del `parallel()` — chocarian en `b7.lock`.

### Epic-review — gate antes del slice de cierre

Cuando solo queda el slice de cierre y el epic NO tiene label `epic-approved`:

```bash
bash "$EPIC_SCRIPTS/epic-diff.sh" <EPIC> > /tmp/epic-<EPIC>-diff.md
```

Lanzar un Agent (model opus) con: (a) el diff agregado, (b) el plan doc referenciado en los bodies (`docs/plans/*.md`), (c) los acceptance criteria de cada sub-issue. El reporte DEBE incluir:

1. **Matriz de cobertura** cubierto/parcial/ausente por decision del plan (ej D1-D10) y por slice.
2. **Walkthrough en browser del flujo COMPLETO integrado** sobre master actualizado: worktree temporal (`setup-worktree.sh epic-review-<EPIC> master --headless`), `./dev.sh`, y el contrato de `b7-screen-review` recorriendo el flujo punta a punta (ej grid → drawer → wizard → comparar). El diff valida codigo contra intencion; solo el browser valida la experiencia.
3. Gaps concretos → sugerir issues nuevos.

> **Solapar el analisis con la preparacion del browser:** el Agent del diff (parte 1, read-only) no toca estado — lanzalo `run_in_background` y, mientras corre, andá levantando el worktree temporal + `./dev.sh` para el walkthrough (parte 2). Cuando el diff termina, ya tenés el server arriba. Asi el gate de epic-review no paga diff-luego-server en serie.

Postear el reporte como comentario en el epic (`## Revision de feature completo`), notificar y PARAR. El humano aprueba agregando el label `epic-approved` al epic (o crea los issues de gap). El proximo re-run de `--epic` detecta el label y procede con el slice de cierre.

**Staleness del label** (mismo criterio que `merge-approved` en b9): verificar que el evento `labeled` de `epic-approved` sea (a) de actor humano no-bot y (b) POSTERIOR al ultimo comentario `## Revision de feature completo`. Si el reporte es mas nuevo que el label (hubo re-revision tras cambios), remover el label y re-pedir aprobacion.

**Al cerrar el epic completo:** entrada rollup en CHANGELOG (`### epic — <titulo> (#N)`) + `Skill informe-semanal "--feature <EPIC>"` (informe comercial consolidado, SIEMPRE en epics).

## Runs zombie

`reconcile` emite `B10_ZOMBIE=true` si el heartbeat del worktree tiene >2h. Tambien: `bash "$B10" janitor` lista todos (y se salta el barrido si hay un `b7.lock` con proceso vivo — un build corriendo NO es zombie aunque su heartbeat se atrase en fases largas como screen-review esperando login). **Nunca barrer con un build potencialmente vivo**: si hay duda (laptop suspendida, sesion colgada), preguntar al usuario antes del sweep. Accion del sweep: commit de lo que haya (`Skill b-pipeline:b3-git-commit`), push de la rama, label `pipeline-failed` + comentario diagnostico en el issue (fase, worktree, ultimo error de `.b7/iter-*.tail`), y recien ahi decidir re-run o escalar.

## Reglas

- **Solo decidir y encadenar.** Cero logica de build/review/merge propia. Si un skill encadenado falla, NO improvisar su trabajo aqui.
- **Gates exactos:** triage solo frena con dudas; merge frena SIEMPRE (humano, via b9); epic-review frena antes del slice destructivo. Nada mas frena.
- **Parser tolerante:** toda linea machine-readable (`TRIAGE_RESULT`, `B7_DONE`, `B6_VERDICT`) tiene fallback a labels/markers de GitHub. Si ambos faltan, parar con diagnostico — no adivinar.
- **Paralelismo solo en read-only.** Snapshot (`epic-state.sh`) y triage de ola (Workflow) corren en paralelo porque solo leen. Build (b7/b8) y merge (b9) van **serial** — lock global + master compartido (ver tabla en "Paralelismo"). Nunca meter un build/merge dentro de un `parallel()`.
- **Workflow tool:** normalizar args con `const A = typeof args === 'string' ? JSON.parse(args) : (args || {})` (el tool serializa como string JSON). Usarlo solo para triages paralelos en modo epic; el build de b7 va por Skill tool directo (fork pesado con lock propio).
- **Notificar en cada freno** (PushNotification si disponible; siempre comentario/label en GitHub) — el usuario debe poder ver POR QUE se detuvo sin leer logs locales.
- **`--dry-run`:** correr preflight + reconcile en single-issue, o `epic-state.sh` en modo epic (snapshot paralelo completo), reportar el plan de fases (incluida la clasificacion closeable/buildable/blocked) y salir sin ejecutar nada.
