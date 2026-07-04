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

1. **Drain-first:** ANTES de lanzar builds, cerrar lo cerrable — los issues que el snapshot marca `closeable` (phase=close: PR abierto con veredicto b6 `blockers=0`, o PR mergeado con issue abierto). Las **decisiones** de cierre vienen del snapshot (`b6` + `B10_APPROVED` + `B10_DIRTY` del reconcile) y se miran juntas; el **merge en si va serial** (b9 uno a uno — dos merges concurrentes a la rama default se pisan). Ruteo exacto en "Drain-first — ruteo con el snapshot" (abajo). Cada cierre libera backpressure y desbloquea dependencias.
2. **Detectar el slice de cierre** (`closing_slice` del snapshot): el issue cuyas deps cubren al resto del grafo — frecuentemente es el PROPIO epic. NUNCA construirlo sin el gate de epic-review (abajo). Cuando es el epic mismo, tras el gate se corre la cadena single-issue sobre el numero del epic.
3. **Triagear la ola en paralelo:** los issues `buildable` cuya fase es `triage` (aun sin veredicto) se triagean **todos juntos** via Workflow (read-only, ver "Triage paralelo de una ola"). Devuelve `{issue, verdict, complexity, scope}` por issue — el insumo para decidir build vs cluster sin pagar N triages secuenciales. Si la ola trae issues `complex`, resolver el gate en UNA pasada, no per-issue (ver "Batch de aprobaciones por ola", momento 1).
3.5. **Verify de la ola:** issues con `live.phase=verify` y `live.b6=absent` (PR abierto sin marker de review) se revisan **todos juntos** via Workflow (ver "Verify de la ola (Workflow)"). Los `verify` con `blockers>0` NUNCA se re-reviewan: label `needs-human-review` + comentario resumen desde el main context (igual que la fase 4 single-issue). Ojo: el csv `buildable` de la linea `B10_EPIC_STATE` mezcla `triage|build|verify` — filtrar por el objeto `live` del JSON, no por el csv.
4. **Siguiente ola — build:** issues con todas sus deps `CLOSED` y sin PR propio, ya triageados. Despachar con el cap de la iteracion (ver "Cap dinamico de backpressure").
   - Ola con 1 issue, o issues `complex` → cadena single-issue por issue, **secuencial** (ver "Paralelismo").
   - Ola con ≥2 issues independientes `simple|medium`, **del mismo `scope`** (b8 exige cohesion tematica — issues de scopes distintos NUNCA van al mismo PR) y flag `--cluster` → `Skill b-pipeline:b8-swarm "--issues=<csv> --theme=<scope>"` (1 worktree, 1 PR combinado, commits por issue; el b9 multi-Closes limpia todo al mergear). Issues de la ola con scope distinto van por la cadena single-issue.
   - Ola con ≥2 issues elegibles de scopes DISTINTOS y sharding de lock disponible (`B7_PARALLEL=1`) → builds en paralelo opt-in (ver "Wave-build (Workflow, opt-in)"). Sin esa precondicion: secuencial como arriba.
5. **Fin de ola:** los `needs-human-review` acumulados de la ola se resuelven en UNA pasada (ver "Batch de aprobaciones por ola", momento 2). Repetir mientras haya issues desbloqueados y el backpressure lo permita. Un issue frenado (needs-info, complex, zombie) NO bloquea a sus hermanos independientes. **Re-correr `epic-state.sh` al inicio de cada iteracion del loop** (tras drenar o construir algo cambia el grafo) — es barato (paralelo) y mantiene las decisiones sobre estado fresco.
6. Al final, reportar el estado del grafo completo: cerrados / en PR / frenados (con razon) / bloqueados.

### Drain-first — ruteo con el snapshot

`run.sh reconcile` emite, cuando phase=close con PR abierto, `B10_APPROVED=true|false|stale` (label `merge-approved`: actor humano no-bot y `labeled_at` posterior al ultimo push) y `B10_DIRTY=true|false` (porcelain del worktree; sin worktree = `false` — un PR sin checkout local no tiene nada que sincronizar y entra igual al ruteo). El snapshot RUTEA, JAMAS autoriza: b9 re-valida label + staleness + CI por si mismo antes de mergear. Prohibido `gh pr merge` o cualquier bypass de b9 desde aca; remover labels stale de un PR es trabajo EXCLUSIVO de b9.

`epic-auto-merge` vigente = label en el EPIC con actor humano no-bot (`bp_label_event <EPIC> epic-auto-merge`, mismo check de actor que `epic-approved`). Re-verificar en CADA iteracion — el humano puede removerlo en cualquier momento.

Despachar los closeable en este orden (b9 SIEMPRE serial, uno a uno; NUNCA dentro de un `parallel()`):

1. `B10_PR_MERGED` (mergeado con issue abierto) → `Skill b-pipeline:b9-close "<PR>"` directo — solo limpieza, sin gate de merge.
2. `B10_APPROVED=true` y `B10_DIRTY=false` → `Skill b-pipeline:b9-close "<PR>"` uno a uno (b9 re-valida el label en su PASO 4 — el snapshot solo ordeno la cola).
3. `B10_DIRTY=true` → b9 completo AUNQUE no este aprobado: su PASO 1.5 sincroniza el worktree y re-reviewa light ANTES de pedir aprobacion. Pedir aprobacion sobre un PR sin sync genera labels que el push posterior invalida (staleness) — churn puro.
4. Con `epic-auto-merge` vigente: el resto de los closeable del epic con `blockers=0` → `Skill b-pipeline:b9-close "<PR> --auto-merge --epic=<EPIC>"` serial, uno a uno. NUNCA el `closing_slice` (b10 jamas le pasa `--auto-merge`; el cinturon de b9 solo rechaza issue==epic — cuando el slice NO es el propio epic, esta exclusion es la UNICA guarda). Reglas de corte: `mergeable != MERGEABLE` → saltar ese PR (queda para humano) y seguir con el siguiente; algun check de CI en FAILURE o merge rechazado por branch protection → cortar el drenaje COMPLETO y notificar (en desatendido FAILURE nunca es "preguntar").
5. Resto no aprobados (sin `epic-auto-merge` vigente, o `B10_APPROVED=false|stale` fuera del set drenable): desde el main context `gh pr edit <PR> --add-label awaiting-approval` (write idempotente sobre PRs distintos — el UNICO write permitido fuera de b9) + UNA `PushNotification` batch con la lista completa de PRs esperando `merge-approved`, incluyendo los saltados por `mergeable` con su razon. Cada PR frenado queda con marker visible en GitHub, no solo la notificacion.

### Cap dinamico de backpressure (solo modo epic)

El default `B7_MAX_OPEN_PRS=3` corta olas grandes aunque el drain este automatizado. En cada iteracion del loop, DESPUES de que drain-first se ejecuto y mergeo lo closeable, calcular:

```
CAP = min(max(3, buildable_de_la_ola + PRs_bot_abiertos_no_drenables), 8)
```

- **Precondicion dura:** el cap sube SOLO si el drain de ESTA iteracion se ejecuto y mergeo lo closeable. Si b9 no pudo mergear (branch protection, conflicto, sin aprobacion), la siguiente iteracion vuelve al default 3.
- **Prefijo INLINE por invocacion**, NUNCA `export` (el estado del shell no persiste entre llamadas Bash): `B7_MAX_OPEN_PRS=$CAP bash "$B8_GUARD" backpressure` — igual en CADA invocacion de guardrails que b10 corre en esta iteracion.
- Al despachar la cadena single-issue, indicar en el prompt del skill que su preflight corra con `B7_MAX_OPEN_PRS=$CAP bash .../skills/b7-issue-to-pr/scripts/guardrails.sh preflight <N>` (mismo prefijo inline).
- PRs con veredicto `blockers>0` cuentan contra el cap A PROPOSITO: 3+ PRs atascados frenan la ola aunque el cap sea 8 — backpressure deseado, no bug.
- Fuera de modo epic nada cambia: default 3 intacto, cero cambios de script.

### Paralelismo: que corre junto y que no

Regla unica: **read-only paraleliza, escritura a la rama default/worktree serializa.**

| Fase | Paraleliza | Por que |
| --- | --- | --- |
| Reconcile / snapshot del grafo | **Si** (`epic-state.sh`, bash ThreadPool) | Solo lee GitHub + worktrees locales. N issues → ~1 RTT. |
| Triage de una ola | **Si** (Workflow, 1 `agent()` por issue) | b1-triage es read-only; cada agente escribe su propio `triage-<n>.json`. |
| Verify de una ola (b6) | **Si** (Workflow, 1 `agent()` por PR) | b6 es read-only sobre el repo; single-writer por repo+PR (`/tmp/pr-review-<repo>-<PR>.md`) y comenta solo SU PR. Unico write: commit+push en SU worktree/rama. |
| Epic-review (diff + walkthrough) | **Si** parcial (Agent opus para el diff mientras se prepara el worktree) | El analisis del diff no toca estado. |
| **Build** (b7 single-issue) | **NO por default / Si opt-in** (wave-build con `B7_PARALLEL=1`) | Default: b7 toma `b7.lock` global — un build a la vez — y backpressure corta a 3 PRs `auto-pr-bot` abiertos. Con sharding de lock (`b7-issue-<N>.lock`) + setup serial + slots dimensionados: ver "Wave-build (Workflow, opt-in)". NO para complex, migraciones, mismo scope ni el closing_slice. |
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

> No metas `b7-issue-to-pr` ni `b8-swarm` dentro del `parallel()` con el lock global default — chocarian en `b7.lock`. Sigue PROHIBIDO sin el sharding de lock; la UNICA via valida de builds paralelos es "Wave-build (Workflow, opt-in)" con `B7_PARALLEL=1` y sus precondiciones.

### Batch de aprobaciones por ola

Las decisiones humanas per-issue se agrupan en DOS momentos por ola — cada uno cuando SU evidencia ya existe. Ninguna opcion se auto-aprueba: cada item del multiSelect es decision humana individual, con su evidencia visible en la opcion (aprobar sin leer no es aprobar). En headless: consumir los labels sin preguntar (mismo canal asincrono que `merge-approved`).

**Momento 1 — post-triage (paso 3): complex de la ola.** UNA `AskUserQuestion` multiSelect con las decisiones complex pendientes ("forzar b7 / saltar" por issue), mostrando por opcion `scope`, `files_likely` y la razon del triage (todo existe post-triage: viene del `{issue, verdict, complexity, scope}` del Workflow y del comentario de b1 en el issue). "Forzar" → label `force-complex-ok` al sub-issue y despachar `Skill b-pipeline:b7-issue-to-pr "<N> --lang=es --force-complex"` directo — la fase 2 de la cadena single-issue detecta el label valido y no re-pregunta.

**Momento 2 — fin de ola (paso 5): waivers de regresion.** UNA `AskUserQuestion` multiSelect con los `needs-human-review` acumulados de la ola ("aceptar waiver / exigir test" por issue), mostrando la razon del waiver del sticky comment y el resumen del diff — esa evidencia recien existe post-build. "Aceptar" → label `regression-waiver-ok` al sub-issue Y REMOVER `needs-human-review` del issue — ese label es veto absoluto del canal auto-merge de b9 y deja el reconcile frenado; sin removerlo el waiver no destraba nada. Con ambos hechos, el proximo re-run reconcilia y el issue sigue su cadena (verify → close). "Exigir test" → re-despachar b7 indicando en el prompt que el waiver NO va: test de regresion obligatorio. `regression-waiver-ok` JAMAS se pone en triage: solo despues de que existen la razon del waiver y el diff.

**Validacion de ambos labels** (mismo patron que `epic-approved`, ver "Staleness del label" abajo): `bp_label_event <issue> <label>` con actor humano no-bot Y `labeled_at` POSTERIOR al evento que aprueban — el ultimo comentario de triage (`## Evaluacion de Issue`) para `force-complex-ok`; el sticky con FIX_SIN_TEST/waiver para `regression-waiver-ok`. Si el evento es mas nuevo que el label: remover el label y re-pedir. Un label puesto por bot o anterior a su evidencia es invalido.

El batch REUBICA gates existentes, no crea ni elimina gates. No toca: serializacion de builds, merges seriales de b9, gate `epic-approved`, gate `merge-approved`. Modo single-issue sin cambios (fuera de la consulta del label en fase 2).

### Verify de la ola (Workflow)

Corre entre drain-first y build (paso 3.5): un PR que sale con `blockers=0` entra al drain de la PROXIMA iteracion. b6 cumple la regla "read-only paraleliza": single-writer por repo+PR y comenta solo SU PR.

**Elegibilidad:** SOLO issues con `live.phase=verify` y `live.b6=absent` — PR abierto sin marker, tipico camino de recuperacion (b7 crasheado entre abrir el PR y su paso 8c, o PR manual; en flujo sano b7 ya dejo el marker). `blockers>0` NUNCA se re-reviewa (churn de veredictos + pisa estado que un humano ya esta mirando): label `needs-human-review` + comentario desde el main context. Con backpressure default los elegibles son ≤3; con cap dinamico, tandas de maximo 4 (rate-limit de gh).

```js
export const meta = {
  name: 'b10-wave-verify',
  description: 'Review b6 en paralelo de los PRs de la ola sin marker',
  phases: [{ title: 'verify', detail: 'b6-pr-review por PR, paralelo, single-writer por repo+PR' }],
}

const A = (typeof args === 'string') ? JSON.parse(args) : (args || {})
const VERDICT = {
  type: 'object', required: ['pr', 'verdict', 'blockers'],
  properties: {
    pr: { type: 'number' }, verdict: { type: 'string' },
    blockers: { type: 'number' }, warnings: { type: 'number' },
  },
}

phase('verify')
const verdicts = (await parallel(A.prs.map(p => () =>
  agent(
    (p.worktree
      ? `cd ${p.worktree} — OBLIGATORIO: check-slice compara el HEAD del cwd; desde el repo principal ` +
        `seria la rama default contra si misma (no-op silencioso). ` +
        `Corre bash ${A.assert_clean} ${p.worktree} --fix; si sale exit 6: Skill b3-git-commit en el ` +
        `worktree + push (el PR debe contener TODO ANTES del review). `
      : '') +
    `Luego Skill b6-pr-review "${p.pr} --auto" — SIN --light forzado: el size-gate de pr-context decide. ` +
    `Devolve {pr:${p.pr}, verdict, blockers, warnings} parseado de la linea B6_VERDICT.`,
    { label: `verify:#${p.pr}`, phase: 'verify', schema: VERDICT }
  )
))).filter(Boolean)

return { verdicts }
```

Invocacion: `Workflow({ script:<lo de arriba>, args:{ assert_clean:"<PLUGIN_ROOT>/skills/b1-add-worktree/scripts/assert-clean.sh", prs:[{pr:312, worktree:"/abs/wt/312-foo"}, {pr:315, worktree:null}] } })` — `worktree` sale de `live.worktree` del snapshot. Con `{verdicts}` en mano: `blockers=0` → closeable en la proxima iteracion; `blockers>0` → `needs-human-review` desde el main context. El marker lo estampa `verdict.sh` dentro de b6 (stamp + check de coherencia, igual que hoy) — un review a medias sin marker queda `absent` en el proximo `epic-state.sh` y se reintenta. NUNCA `b9-close`, `b7-issue-to-pr` ni `b8-swarm` dentro de este `parallel()`.

### Wave-build (Workflow, opt-in)

Builds de una ola en paralelo. **PRECONDICION DURA — sin ella, builds secuenciales como hoy:** `B7_PARALLEL=1` en el entorno del run + puertos unicos por worktree (`setup-worktree.sh` ya excluye los puertos reclamados por los markers `.b7/worktree-ready.json` de worktrees hermanos). El cableado del shard de lock cubre AMBAS vias: en headless `run.sh` de b7 pasa el issue a `acquire-lock` y persiste `lock_file` en `state.json`; en la via Skill (la que usan los agentes de este workflow) el paso 0 de b7 adquiere el shard explicito — por eso el prompt del agente DEBE prefijar `B7_PARALLEL=1` inline en cada comando de guardrails, incluido `acquire-lock`. `release-lock <lock-file>` borra solo SU shard; el janitor de b10 es shard-aware. Verificacion previa: solo que el flag vaya en el entorno/prompt del agente.

**Dimensionar ANTES de lanzar** (elimina el TOCTOU de backpressure sin serializar — los slots se deciden en el main context, nunca en N preflights concurrentes):

```bash
open=$(gh pr list --state open --label auto-pr-bot --json number | jq length)
# slots = min(B7_MAX_OPEN_PRS - open, B10_WAVE_MAX (default 2), cantidad de elegibles)
```

`slots <= 1` → build secuencial como hoy (paso 4). La lista `issues` del Workflow ya va recortada a `slots` en el main context.

**Elegibilidad (todas obligatorias):** `verdict=ready`; complexity `simple|medium` — NUNCA `complex` (su gate humano no se bypassea); scopes DISTINTOS entre si (mismo scope → b8-swarm, paso 4); `files_likely` sin interseccion entre los issues de la ola; sin migraciones (`files_likely`/plan tocando `schema.ts` o el dir de migraciones — la DB dev es compartida via symlinks `.env`; si un build genera una migracion inesperada mid-run, ese run baila y se re-corre serial); NUNCA el `closing_slice` (gate de epic-review intocable).

**FASE 1 — setup SECUENCIAL (main context):** `setup-worktree.sh` por issue, uno a uno — `git worktree add` y el preflight de tree limpio operan sobre el index/refs del repo principal compartido.

**FASE 2 — builds en paralelo (Workflow):**

```js
export const meta = {
  name: 'b10-wave-build',
  description: 'Builds b7 en paralelo de una ola elegible (locks per-issue)',
  phases: [{ title: 'build', detail: 'cadena b7 por issue, paralelo, lock b7-issue-<N>' }],
}

const A = (typeof args === 'string') ? JSON.parse(args) : (args || {})
const BUILD = {
  type: 'object', required: ['issue', 'status'],
  properties: {
    issue: { type: 'number' }, pr: { type: 'string' },
    status: { type: 'string' }, lane: { type: 'string' },
  },
}

phase('build')
const builds = (await parallel(A.issues.map(i => () =>
  agent(
    `Corre la cadena b7 del issue #${i.n}: Skill b7-issue-to-pr "${i.n} --lang=es". ` +
    `El worktree YA existe en ${i.worktree} (setup previo secuencial) — b7 lo detecta y retoma. ` +
    `Prefija B7_PARALLEL=1 INLINE en cada comando bash de guardrails de b7 (nunca export). ` +
    `Escribi SOLO en tu worktree. Devolve {issue:${i.n}, pr, status} parseado de la linea B7_DONE.`,
    { label: `build:#${i.n}`, phase: 'build', schema: BUILD }
  )
))).filter(Boolean)

return { builds }
```

Invocacion: `Workflow({ script:<lo de arriba>, args:{ issues:[{n:262, worktree:"/abs/wt/262-foo"}, {n:263, worktree:"/abs/wt/263-bar"}] } })` — la lista ya recortada a `slots`, worktrees creados en FASE 1.

- `verify-port` sigue siendo gate duro por pantalla (evita revisar el checkout equivocado). Cada agente escribe SOLO en su worktree — vigilado por verify-worktree y el DoD check 3 de b7 (porcelain vacio en el repo principal): mantener esos checks.
- Sesiones: el mint per-worktree no se pisa en DB (token/hash por worktree, cleanup por hash propio) y la sesion de browser es per-run (`b7-<worktree>-<screen>`), pero rige la restriccion documentada de b7 sobre mint paralelo contra el mismo host: si los browsers comparten cookie jar de localhost, un review puede correr con la sesion de otro run — aceptable solo si toda la ola usa el mismo `B7_SESSION_USER_ID`.
- El merge sigue serial via b9 FUERA del Workflow: NUNCA `b9-close` ni `gh pr merge` dentro del `parallel()`.

### Epic-review — gate antes del slice de cierre

Cuando solo queda el slice de cierre y el epic NO tiene label `epic-approved`:

```bash
bash "$EPIC_SCRIPTS/epic-diff.sh" <EPIC> > /tmp/epic-<EPIC>-diff.md
```

Lanzar un Agent (model opus) con: (a) el diff agregado, (b) el plan doc referenciado en los bodies (`docs/plans/*.md`), (c) los acceptance criteria de cada sub-issue. El reporte DEBE incluir:

1. **Matriz de cobertura** cubierto/parcial/ausente por decision del plan y por slice.
2. **Tabla consolidada de sub-PRs mergeados** — una fila por sub-PR del epic ya mergeado, columnas: PR, issue, veredicto b6 (blockers), CI, diffstat, via de merge (`merge-approved` por @actor / auto-merge via `epic-auto-merge`). Si CUALQUIER sub-PR entro por auto-merge la tabla es OBLIGATORIA, no recomendada: es el UNICO punto donde el humano ve esos sub-PRs antes de aprobar el cierre — sin ella aprueba ciego.
3. **Walkthrough en browser del flujo COMPLETO integrado** sobre la rama default actualizada: worktree temporal (`setup-worktree.sh epic-review-<EPIC> --headless`, sin arg de rama base — defaultea a `bp_default_branch`), `./dev.sh`, y el contrato de `b7-screen-review` recorriendo el flujo punta a punta. El diff valida codigo contra intencion; solo el browser valida la experiencia.
4. Gaps concretos → sugerir issues nuevos.

> **Solapar el analisis con la preparacion del browser:** el Agent del diff (parte 1, read-only) no toca estado — lanzalo `run_in_background` y, mientras corre, andá levantando el worktree temporal + `./dev.sh` para el walkthrough (parte 2). Cuando el diff termina, ya tenés el server arriba. Asi el gate de epic-review no paga diff-luego-server en serie.

**Check duro del walkthrough — pre-posteo, observable** (patron pre-flight de `b7-screen-review`: abortar con fail, nunca skip): ANTES de postear el reporte, verificar en disco que existen los PNG del walkthrough en el out_dir del worktree temporal — `ls <out_dir>/*.png` con >=1 captura por pantalla del flujo recorrido — y que el reporte tiene seccion de walkthrough con los paths de las capturas y el resultado por criterio. El texto del reporte NO cuenta como evidencia: el check es sobre archivos en disco (si se satisface escribiendo prosa, no es check). Si falta evidencia: NO postear el reporte NI pedir aprobacion — agregar label `awaiting-walkthrough` al epic y comentar la razon concreta (agent-browser ausente / dev.sh no levanta / credenciales), patron identico a `awaiting-approval` de b9. Falta de server o credenciales NO degrada el gate a diff-only: bloquea con estado visible.

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
