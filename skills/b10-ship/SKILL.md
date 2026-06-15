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
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/skills/b-pipeline}"
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
- `verdict=ready` y complexity `complex` → **GATE**: b7 baila con complejidad L por politica propia. Preguntar via `AskUserQuestion`: "Issue #N es complex — ¿forzar b7 / construir interactivo (b2) / saltar?". Si elige forzar: `Skill b-pipeline:b7-issue-to-pr "<N> --lang=es --force-complex"` (b7 soporta el flag; los budgets siguen aplicando). En headless: comentar en el issue, no tocar labels, parar.
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
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/skills/b-pipeline}"
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
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/skills/b-pipeline}"
EPIC_SCRIPTS="$PLUGIN_ROOT/skills/b10-ship/scripts"
bash "$EPIC_SCRIPTS/epic-graph.sh" <EPIC>    # {"epic":N,"closing_slice":N|null,"issues":[{issue,title,state,labels,deps,wave}]} topo-ordenado por wave
```

1. **Drain-first:** ANTES de lanzar builds, cerrar lo cerrable — por cada sub-issue con PR abierto y veredicto b6 presente, correr la fase close (b9 decide con sus canales de aprobacion). Esto libera backpressure y desbloquea dependencias.
2. **Detectar el slice de cierre** (`closing_slice` del epic-graph): el issue cuyas deps cubren al resto del grafo — frecuentemente es el PROPIO epic (ej #271, tracking + swap/limpieza a la vez). NUNCA construirlo sin el gate de epic-review (abajo). Cuando es el epic mismo, tras el gate se corre la cadena single-issue sobre el numero del epic.
3. **Siguiente ola:** issues con todas sus deps `CLOSED` y sin PR propio.
   - Ola con 1 issue, o issues `complex` → cadena single-issue por issue, secuencial.
   - Ola con ≥2 issues independientes `simple|medium`, **del mismo `scope`** (b8 exige cohesion tematica — issues de scopes distintos NUNCA van al mismo PR) y flag `--cluster` → `Skill b-pipeline:b8-swarm "--issues=<csv> --theme=<scope>"` (1 worktree, 1 PR combinado, commits por issue; el b9 multi-Closes limpia todo al mergear). Issues de la ola con scope distinto van por la cadena single-issue.
4. Repetir mientras haya issues desbloqueados y el backpressure lo permita. Un issue frenado (needs-info, complex, zombie) NO bloquea a sus hermanos independientes.
5. Al final, reportar el estado del grafo completo: cerrados / en PR / frenados (con razon) / bloqueados.

### Epic-review — gate antes del slice de cierre

Cuando solo queda el slice de cierre y el epic NO tiene label `epic-approved`:

```bash
bash "$EPIC_SCRIPTS/epic-diff.sh" <EPIC> > /tmp/epic-<EPIC>-diff.md
```

Lanzar un Agent (model opus) con: (a) el diff agregado, (b) el plan doc referenciado en los bodies (`docs/plans/*.md`), (c) los acceptance criteria de cada sub-issue. El reporte DEBE incluir:

1. **Matriz de cobertura** cubierto/parcial/ausente por decision del plan (ej D1-D10) y por slice.
2. **Walkthrough en browser del flujo COMPLETO integrado** sobre master actualizado: worktree temporal (`setup-worktree.sh epic-review-<EPIC> master --headless`), `./dev.sh`, y el contrato de `b7-screen-review` recorriendo el flujo punta a punta (ej grid → drawer → wizard → comparar). El diff valida codigo contra intencion; solo el browser valida la experiencia.
3. Gaps concretos → sugerir issues nuevos.

Postear el reporte como comentario en el epic (`## Revision de feature completo`), notificar y PARAR. El humano aprueba agregando el label `epic-approved` al epic (o crea los issues de gap). El proximo re-run de `--epic` detecta el label y procede con el slice de cierre.

**Staleness del label** (mismo criterio que `merge-approved` en b9): verificar que el evento `labeled` de `epic-approved` sea (a) de actor humano no-bot y (b) POSTERIOR al ultimo comentario `## Revision de feature completo`. Si el reporte es mas nuevo que el label (hubo re-revision tras cambios), remover el label y re-pedir aprobacion.

**Al cerrar el epic completo:** entrada rollup en CHANGELOG (`### epic — <titulo> (#N)`) + `Skill informe-semanal "--feature <EPIC>"` (informe comercial consolidado, SIEMPRE en epics).

## Runs zombie

`reconcile` emite `B10_ZOMBIE=true` si el heartbeat del worktree tiene >2h. Tambien: `bash "$B10" janitor` lista todos (y se salta el barrido si hay un `b7.lock` con proceso vivo — un build corriendo NO es zombie aunque su heartbeat se atrase en fases largas como screen-review esperando login). **Nunca barrer con un build potencialmente vivo**: si hay duda (laptop suspendida, sesion colgada), preguntar al usuario antes del sweep. Accion del sweep: commit de lo que haya (`Skill b-pipeline:b3-git-commit`), push de la rama, label `pipeline-failed` + comentario diagnostico en el issue (fase, worktree, ultimo error de `.b7/iter-*.tail`), y recien ahi decidir re-run o escalar.

## Reglas

- **Solo decidir y encadenar.** Cero logica de build/review/merge propia. Si un skill encadenado falla, NO improvisar su trabajo aqui.
- **Gates exactos:** triage solo frena con dudas; merge frena SIEMPRE (humano, via b9); epic-review frena antes del slice destructivo. Nada mas frena.
- **Parser tolerante:** toda linea machine-readable (`TRIAGE_RESULT`, `B7_DONE`, `B6_VERDICT`) tiene fallback a labels/markers de GitHub. Si ambos faltan, parar con diagnostico — no adivinar.
- **Workflow tool:** normalizar args con `const A = typeof args === 'string' ? JSON.parse(args) : (args || {})` (el tool serializa como string JSON). Usarlo solo para triages paralelos en modo epic; el build de b7 va por Skill tool directo (fork pesado con lock propio).
- **Notificar en cada freno** (PushNotification si disponible; siempre comentario/label en GitHub) — el usuario debe poder ver POR QUE se detuvo sin leer logs locales.
- **`--dry-run`:** correr preflight + reconcile (+ epic-graph en modo epic), reportar el plan de fases y salir sin ejecutar nada.
