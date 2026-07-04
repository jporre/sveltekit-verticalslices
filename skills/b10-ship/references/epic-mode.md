## Modo epic (`--epic=<N>`)

El epic es un tracking issue con sub-issues nativos de GitHub (vincular una vez con `epic-link.sh`). Las dependencias finas viven en la seccion `## Blocked by` de cada body.

### Loop principal

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cat "$HOME/.claude/b-pipeline.root" 2>/dev/null || ls -d "$HOME"/.claude/plugins/marketplaces/b-pipeline* 2>/dev/null | head -1)}"
EPIC_SCRIPTS="$PLUGIN_ROOT/skills/b10-ship/scripts"
bash "$EPIC_SCRIPTS/epic-state.sh" <EPIC>    # snapshot PARALELO: topologia + reconcile live por sub-issue
```

`epic-state.sh` reemplaza a llamar `epic-graph.sh` + reconciliar issue por issue. Combina la **topologia** (waves, deps, `closing_slice`) con el **estado live** de cada sub-issue (`phase`, `pr`, `b6`, `worktree`, `zombie`) reconciliado **en paralelo** (read-only, acotado a `B10_RECONCILE_PARALLEL=8`). Una pasada da el grafo entero con su fase actual. Salida: el JSON de `epic-graph` con un objeto `live` por issue, mas la linea `B10_EPIC_STATE epic=N waves=K open=n closeable=<csv> buildable=<csv> blocked=<csv>`.

> `epic-graph.sh` sigue existiendo y es lo que `epic-state.sh` usa internamente para la topologia; invocarlo directo solo si querés la topologia cruda sin el estado live (p.ej. debug del calculo de waves).

Con el snapshot en mano, despachar fases — **leer una vez, actuar en paralelo donde sea read-only, serializar lo que toca la rama default o el worktree**:

1. **Drain-first:** ANTES de lanzar builds, cerrar lo cerrable — los issues que el snapshot marca `closeable` (phase=close: PR abierto con veredicto b6 `blockers=0`, o PR mergeado con issue abierto). Las **decisiones** de cierre ya vienen del snapshot (b6 + labels) y pueden mirarse juntas; el **merge en si va serial** (b9 uno a uno — dos merges concurrentes a la rama default se pisan). Cada cierre libera backpressure y desbloquea dependencias.
2. **Detectar el slice de cierre** (`closing_slice` del snapshot): el issue cuyas deps cubren al resto del grafo — frecuentemente es el PROPIO epic. NUNCA construirlo sin el gate de epic-review (abajo). Cuando es el epic mismo, tras el gate se corre la cadena single-issue sobre el numero del epic.
3. **Triagear la ola en paralelo:** los issues `buildable` cuya fase es `triage` (aun sin veredicto) se triagean **todos juntos** via Workflow (read-only, ver "Triage paralelo de una ola"). Devuelve `{issue, verdict, complexity, scope}` por issue — el insumo para decidir build vs cluster sin pagar N triages secuenciales.
4. **Siguiente ola — build:** issues con todas sus deps `CLOSED` y sin PR propio, ya triageados.
   - Ola con 1 issue, o issues `complex` → cadena single-issue por issue, **secuencial** (ver "Paralelismo").
   - Ola con ≥2 issues independientes `simple|medium`, **del mismo `scope`** (b8 exige cohesion tematica — issues de scopes distintos NUNCA van al mismo PR) y flag `--cluster` → `Skill b-pipeline:b8-swarm "--issues=<csv> --theme=<scope>"` (1 worktree, 1 PR combinado, commits por issue; el b9 multi-Closes limpia todo al mergear). Issues de la ola con scope distinto van por la cadena single-issue.
5. Repetir mientras haya issues desbloqueados y el backpressure lo permita. Un issue frenado (needs-info, complex, zombie) NO bloquea a sus hermanos independientes. **Re-correr `epic-state.sh` al inicio de cada iteracion del loop** (tras drenar o construir algo cambia el grafo) — es barato (paralelo) y mantiene las decisiones sobre estado fresco.
6. Al final, reportar el estado del grafo completo: cerrados / en PR / frenados (con razon) / bloqueados.

### Paralelismo: que corre junto y que no

Regla unica: **read-only paraleliza, escritura a la rama default/worktree serializa.**

| Fase | Paraleliza | Por que |
| --- | --- | --- |
| Reconcile / snapshot del grafo | **Si** (`epic-state.sh`, bash ThreadPool) | Solo lee GitHub + worktrees locales. N issues → ~1 RTT. |
| Triage de una ola | **Si** (Workflow, 1 `agent()` por issue) | b1-triage es read-only; cada agente escribe su propio `triage-<n>.json`. |
| Epic-review (diff + walkthrough) | **Si** parcial (Agent opus para el diff mientras se prepara el worktree) | El analisis del diff no toca estado. |
| **Build** (b7 single-issue) | **NO** | b7 toma `b7.lock` global: solo un build a la vez. Ademas backpressure corta a 3 PRs `auto-pr-bot` abiertos. |
| **Build** (b8 cluster) | **NO entre clusters** (b8 ya paraleliza su triage interno) | Mismo lock + worktree compartido por cluster. |
| **Merge / close** (b9) | **NO** | Dos merges concurrentes a la rama default conflictuan. Serial, uno a uno. |

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

> No metas `b7-issue-to-pr` dentro del `parallel()` — chocarian en `b7.lock`.

### Epic-review — gate antes del slice de cierre

Cuando solo queda el slice de cierre y el epic NO tiene label `epic-approved`:

```bash
bash "$EPIC_SCRIPTS/epic-diff.sh" <EPIC> > /tmp/epic-<EPIC>-diff.md
```

Lanzar un Agent (model opus) con: (a) el diff agregado, (b) el plan doc referenciado en los bodies (`docs/plans/*.md`), (c) los acceptance criteria de cada sub-issue. El reporte DEBE incluir:

1. **Matriz de cobertura** cubierto/parcial/ausente por decision del plan y por slice.
2. **Walkthrough en browser del flujo COMPLETO integrado** sobre la rama default actualizada: worktree temporal (`setup-worktree.sh epic-review-<EPIC> --headless`, sin arg de rama base — defaultea a `bp_default_branch`), `./dev.sh`, y el contrato de `b7-screen-review` recorriendo el flujo punta a punta. El diff valida codigo contra intencion; solo el browser valida la experiencia.
3. Gaps concretos → sugerir issues nuevos.

> **Solapar el analisis con la preparacion del browser:** el Agent del diff (parte 1, read-only) no toca estado — lanzalo `run_in_background` y, mientras corre, andá levantando el worktree temporal + `./dev.sh` para el walkthrough (parte 2). Cuando el diff termina, ya tenés el server arriba. Asi el gate de epic-review no paga diff-luego-server en serie.

Postear el reporte como comentario en el epic (`## Revision de feature completo`), notificar y PARAR. El humano aprueba agregando el label `epic-approved` al epic (o crea los issues de gap). El proximo re-run de `--epic` detecta el label y procede con el slice de cierre.

**Staleness del label** (mismo criterio que `merge-approved` en b9): verificar que el evento `labeled` de `epic-approved` sea (a) de actor humano no-bot y (b) POSTERIOR al ultimo comentario `## Revision de feature completo`. Si el reporte es mas nuevo que el label (hubo re-revision tras cambios), remover el label y re-pedir aprobacion.

```bash
. "$PLUGIN_ROOT/scripts/lib.sh"                      # PLUGIN_ROOT resuelto en el loop principal
APPROVAL=$(bp_label_event <EPIC> epic-approved)      # "actor<TAB>created_at" del ultimo labeled (vacio si no hubo)
ACTOR="${APPROVAL%%$'\t'*}"; LABELED_AT="${APPROVAL#*$'\t'}"
case "$ACTOR" in *"[bot]"|"") echo "sin aprobacion humana valida" ;; esac
LAST_REVIEW=$(gh issue view <EPIC> --json comments \
  --jq '[.comments[] | select(.body | contains("## Revision de feature completo")) | .createdAt] | max // empty')
[ -n "$LAST_REVIEW" ] && [[ "$LAST_REVIEW" > "$LABELED_AT" ]] && \
  { gh issue edit <EPIC> --remove-label epic-approved; echo "epic-approved STALE — re-pedir aprobacion"; }
```

**Al cerrar el epic completo:** entrada rollup en CHANGELOG (`### epic — <titulo> (#N)`) + `Skill informe-semanal "--feature <EPIC>"` (informe comercial consolidado, SIEMPRE en epics).
