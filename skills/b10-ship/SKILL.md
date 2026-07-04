---
name: b10-ship
description: 'Orquestador del pipeline issue -> worktree cerrado. ENTRADA DEFAULT para trabajo issue-shaped: cualquier pedido de resolver/trabajar/shipear UN issue ("resuelve el issue N") o de drenar un epic ("procesa el epic N") sin pedir parar en el PR draft rutea aqui. Idempotente: re-correr el mismo comando retoma donde quedo. NO usar si piden explicitamente parar en el PR draft (eso es b7-issue-to-pr) ni para un cluster de issues relacionadas en un solo PR (eso es b8-swarm).'
allowed-tools: Bash, Read, Write, Skill, Agent, Workflow, AskUserQuestion, PushNotification
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
bash "$B10" preflight        # 20=killswitch, 12=gh auth, 18=tree sucio, 17=backpressure, 19=env-check, 2=script faltante
bash "$B10" acquire-lock     # 21=otro run activo (stale a las 6h); emite B10_LOCK_TOKEN
```

- **exit 17 (backpressure, ≥3 PRs auto-pr-bot abiertos):** NO abortar a secas. Listar los PRs abiertos (`gh pr list --label auto-pr-bot`) y ofrecer drenarlos primero (fase close sobre los que tengan aprobacion — ver "drain-first"). El propio gate de merge humano es lo que destraba.
- **exit 18 (working tree del repo principal sucio):** reportar los archivos y parar — b7/b8 abortarian igual a mitad de build.
- **exit 20/21/12/19:** reportar y parar. **Tras exit 21 NO correr release-lock** — el lock es de otra sesion (puede estar legitimamente retenida en un gate humano).
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

Parsear la ultima linea `B7_DONE issue=<N> pr=<url|none> status=<s>`. b7 puede anexar un token opcional `lane=<S|M|L>` (carril del run; ver b7 paso 1b) — es informativo y el parser tolerante ya lo cubre (tokens `k=v` desconocidos se ignoran). No es obligatorio ni cambia el routing de esta fase. **Fallback:** `bash "$B10" reconcile <N>` — si aparece `B10_PR`, el build termino.

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

Leer `references/epic-mode.md` ANTES de despachar — loop principal, paralelismo, triage paralelo de ola y gate de epic-review viven ahi.

## Runs zombie

`reconcile` emite `B10_ZOMBIE=true` si el heartbeat del worktree tiene >2h. Tambien: `bash "$B10" janitor` lista todos (y se salta el barrido si hay un `b7.lock` con proceso vivo — un build corriendo NO es zombie aunque su heartbeat se atrase en fases largas como screen-review esperando login). **Nunca barrer con un build potencialmente vivo**: si hay duda (laptop suspendida, sesion colgada), preguntar al usuario antes del sweep. Accion del sweep: commit de lo que haya (`Skill b-pipeline:b3-git-commit`), push de la rama, label `pipeline-failed` + comentario diagnostico en el issue (fase, worktree, ultimo error de `.b7/iter-*.tail`), y recien ahi decidir re-run o escalar.

## Reglas

- **Solo decidir y encadenar.** Cero logica de build/review/merge propia. Si un skill encadenado falla, NO improvisar su trabajo aqui.
- **Gates:** solo los definidos en las fases. Nada mas frena — no inventar gates nuevos.
- **Parser:** si la linea machine-readable Y su fallback de labels/markers faltan, parar con diagnostico — no adivinar.
- **Notificar en cada freno** (PushNotification si disponible; siempre comentario/label en GitHub) — el usuario debe poder ver POR QUE se detuvo sin leer logs locales.
- **`--dry-run`:** correr preflight + reconcile en single-issue, o `epic-state.sh` en modo epic (snapshot paralelo completo), reportar el plan de fases (incluida la clasificacion closeable/buildable/blocked) y salir sin ejecutar nada.
