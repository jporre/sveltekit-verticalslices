---
name: b7-issue-to-pr
description: 'Pipeline autónomo issue -> PR DRAFT centrado en pantallas; se detiene en el PR draft, NO mergea. Entrada directa SOLO cuando el usuario quiere parar en el PR: "issue N hasta PR", "abre PR del issue N", "sin merge". NO es la entrada default de "resuelve/trabaja/arregla el issue N" — eso rutea a b10-ship (que invoca este skill como fase de build); un cluster de issues relacionadas en un solo PR es b8-swarm.'
allowed-tools: Bash, Read, Edit, Write, Skill, Agent
context: fork
model: opus
effort: medium
---

# Pipeline autónomo Issue → PR (b7) — orientado a pantallas

Glue skill que encadena skills existentes. **No duplicar lógica de los skills encadenados**: si se necesita triage, invocar `b1-triage-issue`; si se necesita worktree, `b1-add-worktree`; etc. El valor de este skill es la **orquestación**, los **budgets**, el **flujo por pantallas (features colocados en `src/routes`)** y el **rastro documental triple**.

> En este proyecto "tarea" = issue de GitHub. Tratar ambos términos como sinónimos.

## Los 5 pasos obligatorios — NO saltarse

Invocar este skill con un número de issue ejecuta los 5 pasos en orden, incluso si el usuario añade instrucciones inline en el mismo prompt (van a `user_directives` como contexto de la implementación — no son atajos). Si un paso falla por entorno (auth, permisos, locks), abortar y reportar — no continuar saltándolo.

1. **Worktree** — `b1-add-worktree --headless`; branch `feat/<issue>-<slug>` o `fix/<issue>-<slug>`. Prohibido editar el repo principal en la rama default; si no se puede crear el worktree, abortar antes de tocar archivos.
2. **Comentario sticky en el issue al iniciar** — `publish-docs.sh milestone started` + `issue-comment` (marker `<!-- b7:status -->`).
3. **Commit(s) via b3-git-commit** — conventional commits por agrupación temática; sin mensajes inventados.
4. **PR draft + labels sincronizadas** — `b4-pull-request --draft` con cuerpo de `publish-docs.sh pr-body` (incluye `Closes #<issue>`); labels `ready/auto-pr → in-progress → in-review`; sticky actualizado con link al PR.
5. **b6-pr-review sobre el PR recién abierto** — veredicto publicado en el PR; findings de severidad alta bloquean (re-iterar o escalar a humano).

Verificación observable de cada paso: ver DEFINITION OF DONE. Si alguno no se completa con éxito, el run se reporta `aborted` con razón clara — no como completado.

## DEFINITION OF DONE — checklist verificable

Antes de devolver el resumen final al usuario, el orquestador **debe** correr estos checks observables y exhibir el resultado de cada uno. Si alguno falla, el run no terminó:

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cat "$HOME/.claude/b-pipeline.root" 2>/dev/null || ls -d "$HOME"/.claude/plugins/marketplaces/b-pipeline* 2>/dev/null | head -1)}"
. "$PLUGIN_ROOT/scripts/lib.sh"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-$(bp_default_branch)}"   # rama base real — nunca asumir master
# 1. Worktree existe, fue creado por setup-worktree.sh, y la rama está sobre la rama default
bash "$PLUGIN_ROOT/skills/b7-issue-to-pr/scripts/guardrails.sh" verify-worktree "$WORKTREE"
git -C "$WORKTREE" rev-parse --abbrev-ref HEAD       # feat/<N>-... o fix/<N>-...
# 2. Comentario sticky en el issue
gh issue view <N> --json comments -q '.comments[].body' | grep -q '<!-- b7:status -->'
# 3. Commits existen (al menos uno) y la rama default no se tocó
git -C "$WORKTREE" log "$DEFAULT_BRANCH"..HEAD --oneline | wc -l   # >= 1
git -C "$REPO_MAIN" status --porcelain                  # vacío
# 4. PR draft abierto y labels del issue sincronizadas
gh pr list --head "$(git -C "$WORKTREE" rev-parse --abbrev-ref HEAD)" --json number,isDraft,url
gh issue view <N> --json labels -q '.labels[].name'     # contiene "in-review", no "ready"/"auto-pr"
# 5. b6-pr-review ejecutado, veredicto publicado en el PR (lector unico del marker)
bash "$PLUGIN_ROOT/skills/b6-pr-review/scripts/verdict.sh" read <PR>   # exit 0 obligatorio (exit 3 = sin review)
# 6. Plan estructurado completo (todos los items done o plan vacío)
bash "$PLUGIN_ROOT/skills/b7-issue-to-pr/scripts/publish-docs.sh" plan-check --worktree "$WORKTREE"   # exit 0 obligatorio
# 7. Worktree limpio post-commit (NADA fuera del commit — exit 0 obligatorio)
bash "$PLUGIN_ROOT/skills/b1-add-worktree/scripts/assert-clean.sh" "$WORKTREE" --fix
# 8. Gate de regresion: un fix cuyo diff no toca ningun test degrada a needs-human-review (NO aborta)
if [ "$(jq -r '.type' "$WORKTREE/.b7/triage.json")" = "fix" ] \
   && ! git -C "$WORKTREE" diff --name-only "$DEFAULT_BRANCH"..HEAD | grep -qE '\.(test|spec)\.'; then
  echo "FIX_SIN_TEST — fix sin test de regresion; status=needs-human-review"
fi
# 9. Screen-review verificable: JSON de review por cada pantalla del triage, o SKIPPED.json con
#    reason valido (exit 8 = run invalido: falta review sin skip valido, o algun verdict=fail)
bash "$PLUGIN_ROOT/skills/b7-issue-to-pr/scripts/guardrails.sh" screens-check "$WORKTREE"
```

Si el check 7 sale 6 (código sin commitear), volver a invocar `b3-git-commit` en el worktree y pushear — el run NO está terminado con trabajo fuera del commit. Si sale 7 (artefactos persistentes que `--fix` no pudo excluir), listarlos en el run-report como warning y continuar — mismo criterio que b9 PASO 1.5: los artefactos no invalidan el run.

Si el check 8 imprime `FIX_SIN_TEST`, el run no aborta pero su status final es `needs-human-review` (no `ok`): un fix que no toca tests necesita que un humano confirme que la ausencia de regresión es aceptable. Si hubo waiver explícito, la degradación es la misma (ver "Waiver explícito" en el paso 1).

Si el check 9 sale 8, el run NO está terminado: falta el JSON de review de alguna pantalla sin skip válido, o hay un `verdict: fail` sin resolver — volver al paso 5 (o al loop del paso 4 si el fail es de criterio visual) antes de cerrar. Exit 3 = rama base irresoluble en el cross-check (problema de entorno, no del run): también bloquea — parar con diagnóstico, no adivinar. `not-evaluated` NO es fail (pass-through con nota). Con `triage.screens[]` vacío o ausente, `screens-check` sale 0 directo sin exigir artefactos.

**Última línea OBLIGATORIA del run** (la parsean orquestadores como b10-ship; fallback de ellos: `gh pr list --search "Closes #N"` + labels del issue):

```
B7_DONE issue=<N> pr=<url|none> status=ok|needs-human-review|bailed|aborted screens=<ok|skipped-<r>|fail|none> [lane=<S|M|L>]
```

El token `screens=` es **obligatorio**, formato k=v sin espacios (el parser tolerante de b10 ignora tokens que no necesita). Valores: `ok` = cada pantalla del triage tiene su JSON de review sin ningún `verdict: fail`; `skipped-<r>` = existe `.b7/review/SKIPPED.json` y `<r>` es su `reason` (ej. `screens=skipped-no-port`); `fail` = algún review quedó en `verdict: fail`; `none` = triage sin screens (`screens[]` vacío o ausente).

El token `lane=<S|M|L>` es **opcional** (carril asignado en el paso 1b). Los orquestadores lo ignoran si no lo necesitan; el parser tolerante de b10 ya lo cubre.

Si **cualquiera** de estos comandos no devuelve lo esperado, NO usar las frases prohibidas (ver abajo) — completar el paso faltante y volver a verificar.

### Frases prohibidas al cerrar el run

Estas frases significan "abandoné a mitad de camino" y son síntoma del bug que este skill busca evitar. Si estás por escribirlas, el run no está terminado — ejecuta el paso pendiente:

- "Ready for b3-git-commit + b4-pull-request"
- "Listo para commit / Listo para PR"
- "Pendiente: abrir PR / correr review"
- "Próximos pasos: <algo del pipeline>"
- "Worktree con cambios sin commitear" (excepto en `--dry-run` explícito)

En `--wet` el cierre válido es: branch + commits + PR URL + review adjunto + labels actualizadas. En `--dry-run` el cierre válido es: branch + commits opcionales + worktree listo para inspección + label `in-progress` + comentario sticky.

## Argumentos

```
<issue> [--dry-run | --wet] [--max-iterations=N] [--budget-files=N] [--no-pr]
        [--no-screens] [--light-review] [--no-changelog] [--lang=es|en]
        [--directives="<texto>"] [--force-complex]
```

> `--light-review` y `--no-changelog` son los flags del modo rápido de epic (los pasa b10 junto con `--no-screens`): el primero fuerza `b6 --auto --light` en 8c para TODO carril; el segundo salta la entrada de CHANGELOG en el paso 6 (el registro va en el rollup del cierre del epic). Fuera de modo epic no se usan.

**Argumentos recibidos en esta invocación:** `$ARGUMENTS`

> Este skill corre en `context: fork`: el subagente solo ve el cuerpo de este `SKILL.md`. El placeholder `$ARGUMENTS` de arriba es la ÚNICA forma de que el número de issue (y flags) lleguen al fork — el harness lo sustituye por lo tipeado. El primer token de `$ARGUMENTS` es el número de issue; el resto son flags. Si `$ARGUMENTS` aparece vacío o sin sustituir, abortar con error claro pidiendo el número.

Defaults: `--wet`, `--max-iterations=6`, `--budget-files=25`, sin `--no-pr`, screens habilitadas, `--lang` autodetectado del issue.

Si no se entrega número de issue, abortar con error claro.

### Directivas inline del usuario

Texto adicional en el mismo prompt (ej. `/b7-issue-to-pr #121 agregale el campo rut a la tabla`) se trata como `--directives` y se anexa a `.b7/triage.json` bajo `user_directives`; los sub-agentes de implementación lo leen junto con el cuerpo del issue. No altera la obligatoriedad de los 5 pasos — refina el scope, no lo atajea.

### `--dry-run` vs `--wet`

- `--wet` (default): ejecuta los 5 pasos completos. Worktree creado, issue comentado, código implementado, PR draft abierto, labels sincronizadas.
- `--dry-run`: ejecuta los pasos 1 y 2 (worktree + comentario inicial) y la implementación, pero **no** abre PR ni mueve labels al estado `in-review`. El comentario sticky del paso 2 indica claramente que el run fue dry-run y el worktree quedó disponible para inspección manual.

## Principio de Diseño: enfocado en pantallas (colocado en src/routes)

Cada feature se evalúa, diseña, programa, revisa y aprueba como **pantallas y/o flujos de pantallas tal como las usaría alguien en la app**. Esto es **obligatorio**:

- El triage debe identificar `screens[]` con `route`, `user_journey`, `acceptance_criteria_visual` y `success_metrics`.
- La implementación coloca cada pantalla en su carpeta de ruta `src/routes/<feature>/`: la UI va directo en `+page.svelte`, los datos en `server/data.remote.ts`, y los componentes del feature en `ui/<Componente>.svelte` (PascalCase). Spec canónica del layout (regla 99%, excepciones `$lib`, tolerancia legacy `src/lib/features/`, doc `docs/<feature>.md`): `$PLUGIN_ROOT/skills/b2-build-feature/references/slice-spec.md`.
- La revisión usa el agente del plugin `b7-screen-review` por cada pantalla declarada (un Agent call por pantalla).
- El reporte y los artefactos documentales hablan en lenguaje de pantallas y flujos, no de funciones internas.

Si el triage no produce `screens[]` (porque la tarea es backend puro o de infra), `b7` igual corre pero sin paso de revisión visual: marca `screens: []` y deja constancia en el run-report. En ese caso NO se escribe `SKIPPED.json` (`screens-check` sale 0 solo) y `B7_DONE` lleva `screens=none`.

## Optimización de tokens — patrones obligatorios

Estos patrones reducen tokens sin perder calidad. Los demás patrones (log-filter, error-hash, skip-by-scope, sub-agentes, contexto cacheado, reporte por script) están definidos en el paso donde se usan.

| # | Patrón | Cómo se aplica |
|---|--------|----------------|
| 1 | Cachear el issue una sola vez | `guardrails.sh cache-issue <N>` escribe `.b7/issue.json`; sub-skills lo leen del disco. |
| 2 | Triage estructurado | `b1-triage-issue` emite `.b7/triage.json` (schema en `templates/triage-output.schema.json`). |
| 3 | Output JSON en headless | En `claude -p`, emitir solo eventos `{event,iter,status,...}` cuando se imprima estado intermedio. |

## Workflow

### 0. Pre-flight (`scripts/guardrails.sh preflight <issue>`)

Ejecuta preflight. Sale non-zero si:

- `gh auth status` falla
- el issue está cerrado, tiene label `do-not-automate`, o contiene `<!-- no-auto-pr -->`
- ya hay ≥3 PRs abiertos con label `auto-pr-bot` (backpressure — `B7_MAX_OPEN_PRS`)
- existe el kill-switch `~/.claude/projects/<slug>/b7.STOP`
- el working tree del repo principal está sucio
- otro `b7` corre (lock file)

Si preflight falla, reportar y salir. No intentar arreglar el estado subyacente.

Tras preflight verde, **tomar el lock** — preflight solo CHEQUEA, no adquiere. En headless lo adquiere `run.sh` (y persiste `lock_file` en el state del scratch); si el state ya trae `lock_file`, NO re-adquirir. En la vía Skill (sin `run.sh`), adquirirlo explícito:

```bash
# Default: lock global b7.lock. Con B7_PARALLEL=1 (wave-build): shard b7-issue-<N>.lock.
LOCK_PATH="$(bash "$PLUGIN_ROOT/skills/b7-issue-to-pr/scripts/guardrails.sh" acquire-lock "$$" <N>)"
LOCK_PATH="${LOCK_PATH#B7_LOCK_FILE=}"   # prefijo solo con B7_PARALLEL=1; strip no-op en legacy
```

Anotar `lock_file: <LOCK_PATH>` en `state.json` apenas `init-state` lo cree — toda ruta terminal libera leyendo ese campo (ver Manejo de errores).

Tras un preflight verde, cachear el contexto una sola vez. Son **subcomandos separados** (preflight NO los corre — solo valida); `run.sh` los invoca después de preflight, o el orquestador los corre a mano:

- `guardrails.sh cache-issue <N> <out-dir>` → `<out-dir>/issue.json` (evita re-pegarle a `gh issue view` desde cada sub-skill)
- `guardrails.sh context-snapshot <out-dir>` → `<out-dir>/context.md`: volcado mínimo del proyecto (stack, aliases, layout colocado). **No usa LLM**, es plantilla + sustituciones.

`<out-dir>` arranca en el scratch del run y se mueve al `.b7/` del worktree tras crearlo (paso 2).

### 1. Triage

Invocar `b1-triage-issue` con el número de issue. Pedirle explícitamente que escriba `.b7/triage.json` siguiendo el schema. Campos clave:

```json
{
  "verdict": "ready|needs-info|duplicate|blocked|closed",
  "type": "feat|fix|chore|docs",
  "scope": "<feature-name>",
  "language": "es|en",
  "files_likely": ["src/routes/<feature>/*"],
  "screens": [{
    "name": "BandejaTareasPage", "route": "/tareas",
    "user_journey": "Usuario abre /tareas, filtra por estado, ...",
    "acceptance_criteria_visual": ["Tabla muestra ...", "Botón ..."],
    "success_metrics": ["Filtro responde <200ms", "..."],
    "states_required": ["golden", "invalid-submit"]
  }],
  "security_review_required": false,
  "estimated_complexity": "simple|medium|complex",
  "plan": [
    {"id": "schema-rut", "desc": "Agregar columna rut a ta_persona + migración", "done": false},
    {"id": "ui-form",    "desc": "Input rut en PersonaFormPage con validación", "done": false}
  ]
}
```

Tras escribir `.b7/triage.json`, **validar mecánicamente** contra el schema antes de seguir: `bash scripts/guardrails.sh validate-triage .b7/triage.json`. Si sale exit 4 (verdict/complexity fuera del enum, falta un required, o clave desconocida por `additionalProperties:false`), el triage es inválido — corregirlo y re-validar; no continuar con un artefacto que los sub-skills no van a poder consumir.

**Gate de evidencia para bugs (determinístico, vía jq).** `validate-triage` no evalúa el `if/then` del schema (`type=fix` exige `evidence`), así que b7 lo aplica acá — un bug sin artefacto observado no debe consumir un run de implementación:

```bash
if [ "$(jq -r '.type' .b7/triage.json)" = "fix" ] \
   && [ -z "$(jq -r '.evidence.observed // empty' .b7/triage.json)" ]; then
  echo "GATE_FAIL fix sin evidence.observed — se trata como needs-info"
  # mismo trato que verdict != ready: comentar en el issue (idioma = .language)
  # que falta evidencia observable, liberar lock, salir 0. Sin worktree ni PR.
fi
```

El `plan[]` es la lista accionable que el orquestador planifica **antes de implementar** y verifica **al cierre** (gate DoD #6). Mantener 3–8 items; nada de micro-tareas. Los sub-agentes marcan progreso con:

```bash
scripts/publish-docs.sh plan-done <id> --worktree "$WORKTREE"
```

Cada `plan-done` re-renderiza `state.plan_block` y queda reflejado en el sticky comment del issue en el próximo `publish-docs.sh issue-comment` (o `all`). Si al cerrar quedan items pendientes, `plan-check` sale 5 y el run no es válido.

**Gate de regresión para bugs (determinístico, vía jq).** Si `type == fix`, inyectar un item `regression-test` al `plan[]` antes de implementar — así el gate DoD #6 (`plan-check`) obliga a que exista un test de regresión sin lógica nueva. Solo agregarlo si no está ya presente:

```bash
if [ "$(jq -r '.type' .b7/triage.json)" = "fix" ] \
   && ! jq -e '.plan[] | select(.id=="regression-test")' .b7/triage.json >/dev/null 2>&1; then
  tmp=$(mktemp)
  jq '.plan += [{"id":"regression-test","desc":"Test que falla sin el fix y pasa con el","done":false}]' \
    .b7/triage.json > "$tmp" && mv "$tmp" .b7/triage.json
fi
```

**Waiver explícito.** Si el fix genuinamente no admite test (p.ej. cambio de infra sin harness), cerrar el item con razón — nunca `done` en silencio:

```bash
scripts/publish-docs.sh plan-done regression-test --worktree "$WORKTREE"   # note: waived: <razon>
```

El waiver deja `plan-check` verde (item done) pero el status final del run es `needs-human-review`, no `ok` — un humano confirma que la ausencia de test es aceptable; la razón va en el sticky comment y el run-report.

Si `verdict != "ready"`: comentar en el issue (en su idioma — `language` del JSON) que el bot bailó, liberar lock, salir 0.

Si `security_review_required: true`: forzar `--no-pr` y marcar para revisión humana en el reporte.

Si `estimated_complexity == "complex"` y NO se pasó `--force-complex`: comentar y bailar (excede el alcance del bot). Con `--force-complex` (lo pasa b10-ship tras confirmación humana explícita): continuar, pero registrar en el sticky y el run-report que el run corre fuera del alcance default — los budgets siguen aplicando.

#### 1b. Clasificar el carril del run (lane S/M/L)

Tras el gate de complejidad (y solo si el run continúa), asignar el **carril** que gobierna cuánto paga el run — un fix de 1 línea no debe pagar el pipeline completo (esqueletos LLM, opus, 6 iteraciones, b6 full):

```bash
bash "$PLUGIN_ROOT/skills/b7-issue-to-pr/scripts/guardrails.sh" \
  classify-run "$WORKTREE/.b7/triage.json" "$WORKTREE/.b7/state.json"   # emite RUN_LANE=S|M|L
```

Reglas: `lane=L` si `estimated_complexity == complex`; `lane=S` si `== simple` **y** `files_likely` tiene ≤5 entradas; `lane=M` en cualquier otro caso. El script persiste `lane` en `state.json`. **Los carriles M y L son byte-idénticos al comportamiento histórico** — no cambian nada. Si el carril es **S**, leer `references/lane-s.md` en este punto: ahí viven co-locadas TODAS sus optimizaciones (render mecánico de screens, agente sonnet, 3 iteraciones, skip condicional del review visual, `b6 --light`); los pasos 3, 4, 5 y 8c solo dejan un pointer.

Reflejar el carril en el sticky del issue (`publish-docs.sh state-set lane=<S|M|L>` ya lo trae de `state.json`; el sticky lo muestra en el próximo `issue-comment`).

> El `classify-run` corre acá porque necesita `state.json` y `triage.json` ya sembrados en el worktree. Si por orden de pasos aún no existe el worktree cuando llegas a esta clasificación, corre `classify-run` inmediatamente después del paso 2 (worktree) y antes del paso 3.

### 2. Worktree headless — PASO OBLIGATORIO #1

**Prohibido `git worktree add` directo.** Hay un PreToolUse hook que bloquea esa llamada — si la intentas, vas a recibir un error. Usar SIEMPRE `setup-worktree.sh`.

Patrón obligatorio (copiar tal cual, no parafrasear):

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cat "$HOME/.claude/b-pipeline.root" 2>/dev/null || ls -d "$HOME"/.claude/plugins/marketplaces/b-pipeline* 2>/dev/null | head -1)}"
. "$PLUGIN_ROOT/scripts/lib.sh"
DEFAULT_BRANCH="$(bp_default_branch)"   # rama base real del repo — nunca asumir master
# Patron del nombre configurable via `git config b-pipeline.branchPattern` (default {type}/{issue}-{slug})
BRANCH="$(bp_branch_name <type> <issue> <short-slug>)"   # <type> = feat|fix según triage.type
OUT=$(bash "$PLUGIN_ROOT/skills/b1-add-worktree/scripts/setup-worktree.sh" "$BRANCH" --headless)
echo "$OUT"
LINE=$(echo "$OUT" | grep '^WORKTREE_READY ' || true)
if [ -z "$LINE" ]; then
  echo "ABORT: setup-worktree.sh did not emit WORKTREE_READY — worktree not safely created" >&2
  exit 1
fi
# WORKTREE/BRANCH/PORT desde el marker .b7/worktree-ready.json (via guardrails.sh)
WT_DIR="${LINE#WORKTREE_READY dir=}"; WT_DIR="${WT_DIR%% *}"
ENV_OUT="$(bash "$PLUGIN_ROOT/skills/b7-issue-to-pr/scripts/guardrails.sh" worktree-env "$WT_DIR")" || {
  echo "ABORT: worktree-env fallo (marker ausente o incompleto) — exit 30" >&2; exit 30; }
eval "$ENV_OUT"
export WORKTREE BRANCH PORT DEFAULT_BRANCH

# Hard gate: refuse to continue if the worktree isn't fully provisioned.
bash "$PLUGIN_ROOT/skills/b7-issue-to-pr/scripts/guardrails.sh" verify-worktree "$WORKTREE" || exit 31
```

Sin `WORKTREE_READY` no hay `$WORKTREE` exportado → ninguna escritura posterior puede apuntar a un destino válido. `verify-worktree` además rechaza worktrees que estén fuera de `<parent>/worktrees/`, sin `dev.sh`, sin symlinks `.env*` o sin `node_modules`.

Crear `.b7/` dentro del worktree (excluido vía el exclude por-worktree que siembra `setup-worktree.sh`). Mover los artefactos `.b7/issue.json`, `.b7/triage.json`, `.b7/context.md` al worktree. **Sembrar el heartbeat de inmediato** (la reconciliación de b10 lo usa para distinguir runs vivos de zombies — sin él, un run muerto en fases tempranas es invisible):

```bash
bash "$PLUGIN_ROOT/skills/b7-issue-to-pr/scripts/guardrails.sh" heartbeat "$WORKTREE"
```

El subcomando escribe `.b7/heartbeat` (formato UTC exacto que parsea b10) y además toca `b7.lock` — la staleness del lock es por mtime, un run vivo lo mantiene fresco. **Puntos de latido** (lista canónica): al sembrar acá, al inicio de cada iteración del paso 4, al inicio del paso 5.0, al completar cada pantalla en 5.2, y antes de invocar b6 en 8c.

**Verificación previa a cualquier escritura:** después de `verify-worktree OK`, toda invocación de Edit/Write/Bash debe operar sobre `$WORKTREE`. Si en algún momento `pwd` reporta el repo principal, detenerse — la siguiente escritura sería un parche en la rama default.

### 2b. Comentario inicial en el issue — PASO OBLIGATORIO #2

Inmediatamente después de crear el worktree, avanzar el milestone (sin hand-edit del JSON) y renderizar el sticky:

```bash
scripts/publish-docs.sh milestone started       --worktree "$WORKTREE"
scripts/publish-docs.sh state-set mode=wet branch="$BRANCH" worktree_dir="$WORKTREE" --worktree "$WORKTREE"
scripts/publish-docs.sh issue-comment            --worktree "$WORKTREE"
```

> NOTA: `milestone <name> [N]` (started, triage-done, worktree-ready, iter-green N, screens-reviewed, committed, pr-opened) y `state-set key=value [...]` escriben `.b7/state.json` por ti — NO editar el JSON a mano. `state-set` rechaza claves que no existan en el scaffold (atrapa typos que renderizarían vacío). Subcomandos completos: `changelog | issue-comment | pr-body | all | aborted | bailed | state-set | milestone | plan-render | plan-done | plan-check`.

Esto postea (o edita in-place, ver paso 7) el comentario sticky en el issue indicando: branch creado, modo (`--wet`/`--dry-run`), directivas inline si las hay, ETA estimado por complexity.

También en este punto se actualizan labels del issue (si las labels destino no existen, crearlas con `gh label create` antes):

```bash
gh issue edit <N> --remove-label "ready,auto-pr" --add-label "in-progress"
```

### 3. Diseño de pantallas (rápido, en línea)

Antes de implementar, para cada `screen` del triage producir un esqueleto en `.b7/screens/<Name>.md`:

- Layout en términos de componentes shadcn-svelte (`Card.Root`, `Table.Root`, `Tabs.Root`, etc.)
- Lista de remote functions necesarias (`get_*`, `create_*`, `update_*`)
- Estados a mostrar: los `states_required` de la pantalla en el triage (golden, empty, loading, error, success, permission-denied, invalid-submit); fallback `golden` si el triage no los trae
- Dónde vive cada archivo (todo colocado en `src/routes/<feature>/...`)

Esto es entrada para b2 y para la revisión visual posterior. **Texto plano, no markdown rico** — no consume tokens reformateando.

**Carril S:** render mecánico de los esqueletos sin LLM — bloque exacto en `references/lane-s.md`. En carriles M y L el diseño es la pasada en línea descrita arriba.

### 4. Implementación (loop bounded)

**Carril S:** invocar el agente `agents/b7-impl-s.md` (`model: sonnet`) en vez de `b2-build-feature`, con hard stop de iterations en 3 — detalle en `references/lane-s.md`.

**Carriles M y L:** invocar `b2-build-feature` **vía sub-agente** (`Agent(subagent_type=general-purpose)`) y 6 iteraciones (sin cambios). En cualquier carril, pasar al agente de implementación:

- Ruta a `.b7/triage.json`
- Ruta a `.b7/screens/`
- Ruta a `.b7/context.md`
- Indicación: respetar layout colocado (feature en `src/routes/<feature>/`), usar Remote Functions Pattern, no introducir state global, errores con `error(STATUS, {message,code})`.
- Si alguna pantalla del triage tiene form de crear/editar: pointer a `$PLUGIN_ROOT/skills/b2-build-feature/references/forms-recipe.md` (campos nativos vs shadcn no-nativos con hidden-input, `issues()`/aria-invalid siempre visibles, regla `disabled={submitting}` NUNCA `disabled={!isFormValid}`).
- Si alguna pantalla del triage trae `data_table: true`: instruir al sub-agente a invocar el skill `bt1-data-table` (vía Skill tool) para esa tabla si está disponible; fallback documentado si no lo está: shadcn Table + paginación server-side según tamaño del dataset.
- **Impact set (Phase 1.5 de b2):** si el plan modifica símbolos existentes (helper de `$lib`, `*.remote.ts` con consumidores, `schema.ts`), correr la Phase 1.5 (impact set vía `codegraph_impact` si el probe dio `CODEGRAPH_STATUS=ok`, fallback `rg -l '<simbolo>' src`) y persistirlo ANTES de implementar: `scripts/publish-docs.sh state-set impact_files=<csv-de-archivos> --worktree "$WORKTREE"` (`impact_files=[]` si greenfield). Si el impact set trae archivos fuera del plan, declarar el scope-growth en el sticky (`publish-docs.sh issue-comment`) antes de codear — no tocar archivos no planificados en silencio.

Después de cada pasada del sub-agente, ejecutar el bloque de validación. **Skip-by-scope** primero:

```bash
. "$PLUGIN_ROOT/scripts/lib.sh"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-$(bp_default_branch)}"
changed=$(git -C "$WORKTREE" diff --name-only "$(git -C "$WORKTREE" merge-base HEAD "$DEFAULT_BRANCH")")
echo "$changed" | grep -qE '\.(ts|svelte|js)$' && RUN_CHECK=1 || RUN_CHECK=0
echo "$changed" | grep -qE '\.(test|spec)\.' && RUN_TEST=1 || RUN_TEST=0
echo "$changed" | grep -qE '\.(ts|svelte|js|css)$' && RUN_LINT=1 || RUN_LINT=0
```

Al inicio de CADA iteración, tocar el heartbeat: `guardrails.sh heartbeat "$WORKTREE"` (lista canónica de latidos en el paso 2).

Solo re-correr los comandos que estaban rojos en `.b7/iter-status.json` (o todos en iter 1):

```bash
[ "$RUN_CHECK" = 1 ] && pnpm check:machine -- --threshold error 2>&1 | tee .b7/iter-$N-check.log
[ "$RUN_LINT"  = 1 ] && pnpm lint -- --quiet 2>&1               | tee .b7/iter-$N-lint.log
[ "$RUN_TEST"  = 1 ] && pnpm test:unit -- --run --reporter=dot 2>&1 | tee .b7/iter-$N-test.log
```

Si alguno falla:

1. Filtrar log: `scripts/log-filter.sh .b7/iter-$N-<cmd>.log > .b7/iter-$N-<cmd>.tail`
2. Hash: `scripts/error-hash.sh .b7/iter-$N-<cmd>.log > .b7/iter-$N-<cmd>.hash`
3. Si el hash coincide con `.b7/iter-$((N-1))-<cmd>.hash` → **abort por no-progress**.
4. Si no, alimentar al sub-agente solo el `.tail` (no el log completo) + delta del plan en `.b7/plan.md`.

Parar el loop cuando todos los comandos habilitados estén verdes en una pasada final completa, OR cuando se trip un hard stop. La pasada final completa es `verify.sh` de b2 (corre TODOS los gates: branch guard, check:machine, format, grep anti-React scoped al diff, test:unit condicional y browser-gate) — el skip-by-scope de arriba NO se toca: sigue gobernando las iteraciones y alimentando iter-logs/error-hash:

```bash
# cwd DEBE ser el worktree — corrido desde el repo principal el gate evalua la rama default y da falsos exit 3
(cd "$WORKTREE" && bash "$PLUGIN_ROOT/skills/b2-build-feature/scripts/verify.sh")
# exit 0 + VERIFY_RESULT ... = habilitado para el paso 6 (commit); exit 3-6 = volver al loop
```

Hard stops:

| Hard stop          | Default | Acción |
|--------------------|---------|--------|
| iterations         | 6 (3 en carril S) | Abort, comentar issue, save state |
| files changed      | 25      | Abort, comentar issue, save state |
| lines added (net)  | 1500    | Abort, comentar issue, save state |
| wall-clock         | 30 min  | Abort, comentar issue, save state |
| error hash repeat  | 1       | Abort por no-progress |

`scripts/guardrails.sh check-budget <worktree>` mide files/lines.

### 5. Revisión visual de pantallas (sub-agente por pantalla)

**Rampa de entrada — evaluar en orden.** Todo skip legítimo escribe `$WORKTREE/.b7/review/SKIPPED.json` con schema `{"reason": "<r>"}` y `<r>` del enum CERRADO `no-screens-flag | lane-s-no-ui | no-port | dry-run` (ningún otro valor), y luego salta a 5.9. Snippet canónico de escritura:

```bash
mkdir -p "$WORKTREE/.b7/review"
printf '{"reason": "%s"}\n' "<r>" > "$WORKTREE/.b7/review/SKIPPED.json"
```

1. `triage.screens[]` vacío o ausente → NO escribir `SKIPPED.json` (backend puro no paga fricción; `screens-check` sale 0 directo). Saltar el paso 5 completo.
2. Se pasó `--no-screens` → escribir `SKIPPED.json` con `reason=no-screens-flag` y saltar a 5.9.
3. Modo `--dry-run` → escribir `SKIPPED.json` con `reason=dry-run` y saltar a 5.9.
4. **Carril S:** el skip lo decide ÚNICAMENTE el script de `references/lane-s.md` — correr ese script; si imprime su mensaje de skip (diff sin `*.svelte`, `*.remote.ts` ni `src/routes/`), escribir `SKIPPED.json` con `reason=lane-s-no-ui` y saltar a 5.9. Sin ese output, la revisión corre — NO es juicio del modelo. En carriles M y L nunca se salta por este criterio.

Sin skip de la rampa, continuar con 5.0.

#### 5.0 Levantar el dev server del worktree (OBLIGATORIO antes del review)

**Causa histórica de que las pantallas nunca se revisaran:** nadie levantaba el dev server del worktree, así que `b7-screen-review` hacía `curl localhost:<port>` → sin respuesta → abortaba `fail`. Levantarlo acá:

```bash
# start: nohup ./dev.sh (log y pid en .b7/dev-server.*), poll del puerto hasta
# B7_DEV_SERVER_WAIT_SECS (default 120, deadline por tiempo transcurrido — lo implementa guardrails.sh).
# Si no responde: WARN sin abortar — verify-port abajo decide si se omiten screens.
bash "$PLUGIN_ROOT/skills/b7-issue-to-pr/scripts/guardrails.sh" dev-server start "$WORKTREE"
# Gate DURO: no basta con que algo responda en el puerto — tiene que ser ESTE
# worktree. verify-port compara el cwd del proceso listener con $WORKTREE
# (exit 40 = nadie escucha, exit 41 = lo sirve otro checkout, p.ej. la rama default).
RC=0
bash "$PLUGIN_ROOT/skills/b7-issue-to-pr/scripts/guardrails.sh" verify-port "$PORT" "$WORKTREE" || RC=$?
if [ "$RC" = 40 ]; then
  # exit 40: UN reintento (dev-server start + verify-port). Nunca mas de uno.
  bash "$PLUGIN_ROOT/skills/b7-issue-to-pr/scripts/guardrails.sh" dev-server start "$WORKTREE"
  RC=0
  bash "$PLUGIN_ROOT/skills/b7-issue-to-pr/scripts/guardrails.sh" verify-port "$PORT" "$WORKTREE" || RC=$?
fi
if [ "$RC" != 0 ]; then
  mkdir -p "$WORKTREE/.b7/review"
  printf '{"reason": "no-port"}\n' > "$WORKTREE/.b7/review/SKIPPED.json"
  echo "WARN: verify-port fallo (:${PORT} no sirve el worktree, exit $RC) — screens se omiten; SKIPPED.json reason=no-port"
fi
```

Reglas por exit code:

- **Exit 40** (nadie escucha): UN reintento como en el bloque de arriba — `dev-server start` + `verify-port`, nunca más de uno. Si persiste, escribir `SKIPPED.json` con `reason=no-port`, dejar nota explícita en el run-report y saltar a 5.9 (no abortar el run completo).
- **Exit 41** (el puerto lo sirve otro checkout): NO reintentar y NO matar el listener — puede ser el dev server legítimo de otra sesión b7/b8/b10 paralela; resolverlo queda manual, como hoy. Escribir `SKIPPED.json` con `reason=no-port`, nota en el run-report y saltar a 5.9.

**No revisar pantallas contra un server que no sea el del worktree** — ese fue el incidente que este gate previene (screen-review contra la rama default).

#### 5.1 Auth: estrategia declarada del repo, con fallback

**Primero, leer la estrategia que el repo declara** — sección `## Auth de pruebas (browser)` de su CLAUDE.md (la instala b-setup-or-fix; formato `clave: valor`). El método de auth depende del proyecto, su DB y sus criterios de seguridad — NO asumir uno:

```bash
sed -n '/^## Auth de pruebas/,/^## /p' "$WORKTREE/CLAUDE.md"
```

Dispatch por `estrategia:`:

- **`dev-user`** → el primer agente navega `login_url:` y llena el form con los VALORES de las env vars que `credenciales:` nombra (leerlas del entorno; NUNCA imprimirlas ni pegarlas en logs). Las cookies de esa sesión sirven para el resto del run.
- **`dev-endpoint`** → `curl -si "http://localhost:${PORT}<endpoint>"` captura el `Set-Cookie` → esa es `AUTH_COOKIE`. El endpoint solo existe en dev (404 en prod por diseño).
- **`session-mint`** → flujo A de abajo (`email_seed:` alimenta `B7_SESSION_EMAIL` si el entorno no lo trae).
- **`manual-cookies`** → en sesión interactiva: pedir al usuario UN login manual en el browser y reusar las cookies de esa sesión. Headless: pantallas protegidas → `not-evaluated (auth-required)` + nota en el run-report (no es `fail`).

Sin sección declarada: flujo A→B histórico de abajo, y dejar en el run-report: "declara `## Auth de pruebas (browser)` en CLAUDE.md (b-setup-or-fix modo base) para que los runs no improvisen el método".

**A. Intentar sesión scriptada (`mint-dev-session.sh`).** Inserta una fila de sesión válida en la DB del worktree y devuelve la cookie — sin ritual manual. Requiere `B7_SESSION_USER_ID` o `B7_SESSION_EMAIL` en el entorno del run:

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/skills/b-pipeline}"
MINT="$PLUGIN_ROOT/skills/b7-screen-review/scripts/mint-dev-session.sh"
AUTH_COOKIE=""
if COOKIE_LINE=$(bash "$MINT" mint "$WORKTREE" 2>>"$WORKTREE/.b7/dev-server.log"); then
  AUTH_COOKIE="${COOKIE_LINE#B7_SESSION_COOKIE=}"   # -> auth-session=<token>
  # Verificar contra una ruta protegida real del feature (usar la route de la 1a pantalla):
  if B7_SESSION_COOKIE="$AUTH_COOKIE" bash "$MINT" verify "http://localhost:${PORT}<primera-route>"; then
    echo "auth scriptada OK — se pasa auth_cookie a los sub-agentes"
  else
    echo "verify no dio 200 — descarto la cookie, sigo con flujo B (sin cookie)"
    AUTH_COOKIE=""
  fi
else
  echo "mint no disponible (sin B7_SESSION_USER_ID/EMAIL o DATABASE_URL) — flujo B (sin cookie)"
fi
```

`mint` sale 3 (fallback limpio) si faltan `B7_SESSION_USER_ID`/`B7_SESSION_EMAIL` o `DATABASE_URL` — **no** es error; simplemente no hay cookie y se sigue con el flujo B.

**B. Fallback: correr sin cookie.** Si no hubo cookie, el agente abre la ruta igual (browser propio vía `agent-browser`; no reusa la sesión del Chrome real). Dejar UNA línea en el run-report y en el sticky comment del issue:

> Pantallas protegidas quedaron `not-evaluated`: configura `B7_SESSION_USER_ID`/`B7_SESSION_EMAIL` + `DATABASE_URL` y re-corre para evaluarlas con sesión scriptada.

Si una pantalla vuelve `auth-required` (redirección a login, sin cookie), **no** es `fail` del feature: marcar la pantalla como `not-evaluated (auth-required)` en el run-report y seguir. Solo cuenta como `fail` un criterio visual incumplido con sesión válida.

> Restricción conocida (fuera de alcance de #14): la cookie es host-scoped (`localhost`). Si b7 y b8-swarm mintean en paralelo contra el mismo host, la última cookie pisa a las demás. Wiring de mint en b8-swarm es follow-up.

#### 5.2 Lanzar un sub-agente por pantalla

Para cada pantalla, lanzar **un agente del plugin** `b-pipeline:b7-screen-review` en paralelo (un Agent call por pantalla en el mismo turno):

```
Agent(
  subagent_type="b-pipeline:b7-screen-review",
  description="Visual review <ScreenName>",
  prompt="screen=<Name> route=<route> port=<PORT> worktree=$WORKTREE criteria_file=.b7/screens/<Name>.md out_dir=.b7/review states=<states_required de la pantalla, join por coma; fallback golden> auth_cookie=<AUTH_COOKIE>. Output: .b7/review/<Name>.json + .b7/review/<Name>-*.png"
)
```

Pasar `auth_cookie=<AUTH_COOKIE>` solo si 5.1-A dio una cookie válida (verify=200); si `AUTH_COOKIE` quedó vacío, omitir el param y las pantallas protegidas vuelven `auth-required` → `not-evaluated`.

`b7-screen-review` produce por pantalla:
- `<Name>.json`: `{verdict: pass|fail|warn, findings: [...], screenshots: [...]}` — campo aditivo `"infra_fail": true` cuando el review no corrió por falla de infra pura (ver agente)
- Una o más PNGs (golden path + edge cases)

Si alguna pantalla retorna `fail` (criterio visual incumplido con sesión válida), devolver findings al loop de implementación (paso 4) y rebudgetear iteración. Si retorna `warn` o `not-evaluated`, agregar al PR como nota pero seguir. `warn` con `"infra_fail": true` NO rebudgetea el paso 4: tratar la pantalla como `not-evaluated` con nota explícita en el run-report Y en el sticky comment del issue — mismo trato que el fallo de verify-port en 5.0 (el problema es de infra, no del código).

#### 5.9 Apagar el dev server y borrar la sesión scriptada

Pase lo que pase con el review, apagar el server que se levantó en 5.0 **y** borrar SIEMPRE la sesión que se minteó en 5.1-A (si la hubo). Ambos cleanups son idempotentes:

```bash
# Borrar la sesión scriptada (no falla si no se minteó ninguna).
bash "$PLUGIN_ROOT/skills/b7-screen-review/scripts/mint-dev-session.sh" cleanup "$WORKTREE" || true
# Apagar el dev server (silencioso si no hay pid file).
bash "$PLUGIN_ROOT/skills/b7-issue-to-pr/scripts/guardrails.sh" dev-server stop "$WORKTREE"
```

### 6. Commit — PASO OBLIGATORIO #3

Precondición anclada a comando: el paso 6 corre **solo si** `bash "$PLUGIN_ROOT/skills/b7-issue-to-pr/scripts/guardrails.sh" screens-check "$WORKTREE"` sale 0 (exit 8 = run inválido: falta JSON de review sin skip válido, o algún `verdict: fail` — volver al paso 5, o al loop del paso 4 si el fail es de criterio visual; exit 3 = rama base irresoluble, parar con diagnóstico). "screens pass/warn" NO se declara de memoria: lo verifica el comando.

Si step 4 verde (pasada final `verify.sh` exit 0) AND budgets OK AND `screens-check` exit 0:

- `b3-git-commit` agrupa cambios temáticos.
- **Antes** de invocarlo, asegurar entrada en `CHANGELOG.md` usando `scripts/publish-docs.sh changelog` (lee `.b7/state.json`) — **salvo con `--no-changelog`** (modo epic: el registro va en el rollup del cierre; cada slice tocando CHANGELOG generaba conflicto aditivo entre PRs de la misma ola).

En modo `--dry-run`, saltarse el commit y avisar al usuario que el worktree quedó con cambios sin commitear para inspección. En `--wet`, el commit NO cierra el run: continuar directo al paso 7 (publish-docs) → 8 (PR draft) → 8b (labels) → 8c (b6-pr-review).

### 7. Publicar documentación (script, sin LLM)

`scripts/publish-docs.sh all` ejecuta tres outputs en una sola pasada determinística:

1. **`CHANGELOG.md`** — entrada analítica (what/why/risk/issue link). Template: `templates/changelog-entry.md`.
2. **Comentario en el issue** — informativo en el idioma del issue, con estado, links al PR (si existe), thumbnails de pantallas. Sticky: usa marker `<!-- b7:status -->` para editar el mismo comentario en vez de spamear (`gh api` patch). Template: `templates/issue-comment.md`.
3. **Cuerpo del PR** — release notes con tono comercial (qué obtiene el usuario, no qué función se tocó). Template: `templates/pr-release-notes.md`.

Las tres salidas se generan desde el mismo `.b7/state.json` para garantizar consistencia. Sub-agentes no participan acá. `publish-docs.sh` es **idempotente**: re-correrlo con el mismo `state.json` produce los mismos outputs.

### 8. PR draft — PASO OBLIGATORIO #4

Si NOT `--dry-run` y NOT `--no-pr`: invocar `b4-pull-request` con `--draft --label auto-pr-bot --body-file .b7/pr-body.md`. El cuerpo ya viene de `publish-docs.sh`. Para las screenshots de `b7-screen-review`: ejecutar el `attach.sh` que deja cada review, que postea un comentario informativo en el PR con los nombres de los PNG + puntero al run-report (GH REST no permite inline upload de imágenes en comentarios; las imágenes embebidas se ven en el run-report HTML local).

**Marker de screen-review (OBLIGATORIO, apenas existe el PR y ANTES de invocar b6 en 8c).** Postear como comentario del PR el marker que consume el gate SCREEN_EVIDENCE de b6 — formato exacto, sin variaciones. El enum de `reason` del marker es un superset del de `SKIPPED.json` (que queda en 4 valores): `no-screens-flag | lane-s-no-ui | no-port | dry-run | triage-empty | infra-fail`. `triage-empty` e `infra-fail` son marker-only — NUNCA escribir `SKIPPED.json` con esos valores.

El marker `done` lleva SIEMPRE el token `result=ok|fail` — la misma clasificación que `B7_DONE screens=` (`fail` = algún review útil quedó en `verdict: fail`). Es la señal durable que consume la condición 4b del canal auto-merge de b9: un marker `done` sin `result=` (formato viejo) se trata como no verificable, no como ok.

```bash
if [ -f "$WORKTREE/.b7/review/SKIPPED.json" ]; then
  reason=$(jq -r '.reason' "$WORKTREE/.b7/review/SKIPPED.json")
  gh pr comment "$PR_NUMBER" --body "<!-- b7:screen-review=skipped reason=${reason} -->"
elif [ "$(jq -r '.screens | length' "$WORKTREE/.b7/triage.json")" -eq 0 ]; then
  # triage sin screens: marker-only, sin SKIPPED.json
  gh pr comment "$PR_NUMBER" --body "<!-- b7:screen-review=skipped reason=triage-empty -->"
else
  n=$(find "$WORKTREE/.b7/review" -maxdepth 1 -name '*.json' ! -name 'SKIPPED.json' | wc -l | tr -d ' ')
  pngs=$(find "$WORKTREE/.b7/review" -maxdepth 1 -name '*.png' | wc -l | tr -d ' ')
  utiles=$(find "$WORKTREE/.b7/review" -maxdepth 1 -name '*.json' ! -name 'SKIPPED.json' \
    -exec jq -r '.infra_fail // false' {} + | grep -cv '^true$' || true)
  fails=$(find "$WORKTREE/.b7/review" -maxdepth 1 -name '*.json' ! -name 'SKIPPED.json' \
    -exec jq -r 'select((.infra_fail // false) | not) | .verdict // empty' {} + | grep -c '^fail$' || true)
  if [ "$pngs" -gt 0 ] && [ "$utiles" -gt 0 ]; then
    # done SOLO con evidencia util: >=1 PNG y >=1 review sin infra_fail
    res=ok; [ "$fails" -gt 0 ] && res=fail
    gh pr comment "$PR_NUMBER" --body "<!-- b7:screen-review=done screens=${n} result=${res} -->"
  else
    # cero PNG en .b7/review/ o todos los JSON con infra_fail:true
    gh pr comment "$PR_NUMBER" --body "<!-- b7:screen-review=skipped reason=infra-fail -->"
  fi
fi
```

El PR debe incluir:
- `Closes #<issue>` (cierra el issue automáticamente al mergear) + link al run report
- Secciones: "Pantallas entregadas" (thumbnails si aplica), "Notas de release" (lo que ve el usuario), "Cambios técnicos" (resumen, links a archivos)
- Sección "Directivas inline del usuario" si `triage.user_directives` no está vacío — cita textual de lo que pidió el invocador, para que el reviewer entienda el scope
- Checklist de revisión (incluye revisar screenshots adjuntos)

### 8b. Sincronizar estado del issue — PASO OBLIGATORIO #4 (labels)

Apenas el PR queda abierto:

```bash
gh issue edit <N> --remove-label "in-progress" --add-label "in-review"
# milestone pr-opened + link al PR (sin hand-edit del JSON) y re-render del sticky:
scripts/publish-docs.sh milestone pr-opened --worktree "$WORKTREE"
scripts/publish-docs.sh state-set pr_url="$PR_URL" pr_number="$PR_NUMBER" pr_link="$PR_URL" --worktree "$WORKTREE"
scripts/publish-docs.sh issue-comment --worktree "$WORKTREE"
```

Estado final esperado del issue: label `in-review`, comentario apuntando al PR, sin labels obsoletas (`ready`, `auto-pr`). Los pasos 8 y 8b son inseparables: si el `gh issue edit` falla, reportarlo en el run report como warning — no continuar como si todo estuviera bien. Cuando el PR mergea, el `Closes #<issue>` cierra el issue automáticamente.

**Frontera de salida:** b7 termina en PR draft + review adjunto y NO mergea; el merge, cierre del PR y limpieza del worktree son de `b9-close`, con aprobación humana.

### 8c. Auto-review del PR — PASO OBLIGATORIO #5

**Contraste de impacto (señal, NO gate):** antes de invocar b6, contrastar el diff real contra `impact_files` (state.json) + `files_likely` (triage.json). Archivos fuera del set esperado indican scope-growth no declarado:

```bash
. "$PLUGIN_ROOT/scripts/lib.sh"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-$(bp_default_branch)}"
python3 - "$WORKTREE" "$DEFAULT_BRANCH" <<'PY'
import json, os, subprocess, sys
wt, default_branch = sys.argv[1:3]
def load(p, d):
    try: return json.load(open(os.path.join(wt, p)))
    except Exception: return d
state, triage = load(".b7/state.json", {}), load(".b7/triage.json", {})
raw = state.get("impact_files", "")
expected = {f for f in raw.replace(",", " ").split() if f and f not in ("[]", "-")}
expected |= set(triage.get("files_likely", []))
base = subprocess.run(["git","-C",wt,"merge-base","HEAD",default_branch], capture_output=True, text=True).stdout.strip()
diff = subprocess.run(["git","-C",wt,"diff","--name-only",base], capture_output=True, text=True).stdout.split("\n")
outside = [f for f in diff if f and f not in expected and not f.startswith(".b7/") and f != "CHANGELOG.md"]
print("IMPACT_DRIFT: " + (" ".join(outside) if outside else "none"))
PY
```

Si `IMPACT_DRIFT` lista archivos, emitir la señal visible: línea de warning en consola, nota en el run-report y mención en el sticky del issue. NO abortar el run por esto — el gate duro sigue siendo el budget (files/lines); esto expone drift silencioso al reviewer.

Apenas el PR está abierto (incluso draft), invocar `b6-pr-review "<PR> --auto"`. **Carril S o flag `--light-review`:** agregar `--light` (carril S: ver `references/lane-s.md`; `--light-review` lo pasa b10 en modo rápido — el pase profundo lo hace el epic-review). Carriles M y L sin esos flags: sin `--light` (review completo, sin cambios). **b6 en modo `--auto` publica el reporte por sí mismo** (`gh pr comment` con el marker `<!-- b6:verdict=... -->`) — NO volver a postearlo desde acá (doble posteo). Verificar que quedó publicado:

```bash
bash "$PLUGIN_ROOT/skills/b6-pr-review/scripts/verdict.sh" read <PR> \
  || echo "WARN: b6 no publico el veredicto (exit 3) — postear .b7/review/pr-<PR>.md como fallback"
```

Reglas (el veredicto b6 se computa de los counts; leer el marker con `verdict.sh read`, nunca parsear a mano):
- `blockers > 0` en el `B6_VERDICT` → re-iterar implementación (volver a paso 4) si el budget lo permite; si no, escalar a humano y marcar el run como `needs-human-review` en el reporte.
- `blockers == 0` con `warnings > 0` → quedan visibles en el PR como sugerencias; no bloquean.
- Saltarse este paso solo si `--no-pr` (porque no hay PR que revisar).

### 9. Run report

Renderizado por script (`scripts/render-report.sh`) desde `.b7/state.json` y `templates/run-report.md`. Path: `~/.claude/projects/<slug>/b7-runs/<UTC-timestamp>-issue-<N>.md`. Incluye: issue, verdict, branch, iteraciones, files/lines, tail del último log, PR URL, abort reason, wall-clock, **tabla de pantallas con veredicto + path a screenshot**.

### 10. Después de un dry-run

Solo en `--dry-run`: leer y seguir `references/dry-run.md` (qué se mantiene, qué se saltó, qué decirle al usuario para promover a PR).

## Sub-agentes y routing de modelo

| Paso | Sub-agente | Modelo | Razón |
|------|-----------|--------|-------|
| 4 Implementación | `Agent(general-purpose)` | opus (sonnet en carril S) | Aislar contexto de exploración + tool calls verbosos. Orquestador solo recibe resumen. |
| 5 Revisión visual | `Agent(b-pipeline:b7-screen-review)` — agente del plugin | sonnet (multimodal, no necesita opus) | Toolset de browser (`agent-browser`) es independiente. Paralelizar por pantalla. Output binario (PNG) no contamina contexto. |
| Triage (`b1-triage-issue`) | Skill directo | opus (decisión de scope) | Determinístico y rápido; sub-agente sería overkill. |
| Commit / PR / log summarizers | Skill directo | haiku cuando sea posible | Idem. |

## Manejo de errores

- Toda ruta de abort debe (a) `publish-docs.sh aborted` (que actualiza el comentario del issue + entry en CHANGELOG con `[Aborted]`), (b) escribir el run report, (c) liberar el lock con `guardrails.sh release-lock "$(jq -r '.lock_file // empty' .b7/state.json)"`.
- **El lock NO se libera solo.** `run.sh` lo deja retenido a propósito para la fase LLM (y persiste su path en `state.json.lock_file`); toda ruta terminal (éxito, abort, bail) debe invocar `guardrails.sh release-lock "$(jq -r '.lock_file // empty' .b7/state.json)"` — libera SOLO el shard de este run. Si `lock_file` está vacío o `state.json` no existe todavía, `release-lock` sin arg (legacy `b7.lock`). Fallback: un lock sin tocar por 2h (`B7_LOCK_STALE_SECS`) se recupera en el próximo preflight — el heartbeat de cada iteración lo mantiene fresco en runs vivos.
- Si `publish-docs.sh` falla (p.ej. `gh` cae), no bloquear el resto del cierre — log a stderr y continuar.

## Invocación headless

```bash
# Default (wet) — corre los 5 pasos completos: worktree, sticky, commits, PR+labels, review
claude -p --permission-mode acceptEdits "Use skill b7-issue-to-pr with arguments: 142"
# Flags combinables con el numero de issue:
#   --directives='agregale columna rut'   directivas inline del usuario
#   --dry-run                             inspeccionar antes de PR
#   --no-screens                          issue puramente backend
```

Cuando el usuario invoca de forma interactiva con texto pegado (`/b7-issue-to-pr #121 hola agrega el campo X`), el skill interpreta `121` como issue y el resto como `--directives`. El pipeline corre los 5 pasos igual que en headless.

## Qué NO hacer

- No escribir lógica propia de triage. Usar `b1-triage-issue`.
- No escribir mensajes de commit propios. Usar `b3-git-commit`.
- No bypassear budgets re-corriendo con números más altos. Hitar un budget = el issue es más grande de lo que el bot debería atacar; escalar a humano.
- No modificar `package.json`, lockfiles, `.env*`, `*.pem`, `*.key`, `secrets/`, configs de build/CI ni `scripts/*.sh`. El hook `pre-commit-budget.sh` (instalado automáticamente por `setup-worktree.sh`, scope por-worktree) los rechaza en el commit. Bypass solo humano con `B7_BUDGET_OVERRIDE=1`.
- No leer `git diff` ni logs completos. Usar `.b7/diff-stat.txt`, `Read` con `offset/limit`, y `scripts/log-filter.sh`.
- No saltarse `b7-screen-review` cuando hay `screens[]` en triage — la revisión visual es parte de la calidad mínima del PR. **Únicas excepciones:** las rampas de skip del paso 5 (`no-screens-flag | lane-s-no-ui | no-port | dry-run`), y cada una escribe `.b7/review/SKIPPED.json` — ningún skip queda sin artefacto parseable.

## Referencias

- `templates/` — triage-output.schema.json (schema de `.b7/triage.json`), issue-comment.md, pr-release-notes.md, changelog-entry.md, run-report.md
- `scripts/` — guardrails.sh, publish-docs.sh, log-filter.sh, error-hash.sh, diff-summary.sh (produce `.b7/diff-stat.txt`), render-report.sh (usos en los pasos del workflow)
- `references/` — lane-s.md (optimizaciones del carril S), dry-run.md (cierre de un dry-run)
