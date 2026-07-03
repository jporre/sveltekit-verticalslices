---
name: b7-issue-to-pr
description: 'Pipeline autónomo issue → PR centrado en pantallas (Feature-Sliced Design). CINCO PASOS OBLIGATORIOS y no-saltables: (1) crear worktree vía b1-add-worktree (NUNCA editar master directo), (2) comentar avance sticky en el GitHub issue, (3) commit vía b3-git-commit, (4) abrir PR draft vía b4-pull-request con labels sincronizadas (ready/auto-pr → in-progress → in-review), (5) correr b6-pr-review sobre el PR recién abierto. Encadena: b1-triage-issue, b1-add-worktree, b2-build-feature, b7-screen-review, b3-git-commit, b4-pull-request, b6-pr-review. PROHIBIDO terminar el run con frases del tipo "Ready for...", "Listo para commit/PR", "Pendiente b3/b4" — esos pasos son parte del skill y deben ejecutarse aquí. Se usa cuando se invoca con un número de issue, incluso si el usuario añade modificaciones en lenguaje natural en el mismo prompt — los 5 pasos siguen siendo obligatorios. Considerar invocar siempre que se mencione "tarea N" o "issue N" (tarea = issue de GitHub).'
allowed-tools: Bash, Read, Edit, Write, Skill, Agent
context: fork
model: opus
effort: medium
---

# Pipeline autónomo Issue → PR (b7) — orientado a pantallas

Glue skill que encadena skills existentes. **No duplicar lógica de los skills encadenados**: si se necesita triage, invocar `b1-triage-issue`; si se necesita worktree, `b1-add-worktree`; etc. El valor de este skill es la **orquestación**, los **budgets**, el **flujo por pantallas (features colocados en `src/routes`)** y el **rastro documental triple**.

> En este proyecto "tarea" = issue de GitHub. Tratar ambos términos como sinónimos.

## Los 5 pasos obligatorios — NO saltarse

Si invocás este skill, estos 5 pasos **deben** ejecutarse en orden. Si alguno falla por entorno (auth, permisos, locks), abortar y reportar — **no continuar saltándolo**. Esto aplica incluso si el usuario añade instrucciones inline ("agregale el campo X", "cambia el color a Y") junto con el número de issue: la presencia del issue dispara el pipeline completo, las instrucciones inline son contexto adicional para el paso de implementación, no atajos para saltarse el resto.

1. **Worktree de trabajo** — `b1-add-worktree --headless`. Branch `feat/<issue>-<slug>` o `fix/<issue>-<slug>`. **Prohibido editar el repo principal en master.** Toda escritura va al worktree. Si no se puede crear el worktree, abortar antes de tocar archivos.
2. **Comentario sticky en el issue al iniciar** — `publish-docs.sh milestone started` seguido de `publish-docs.sh issue-comment` postea/edita un comentario con marker `<!-- b7:status -->`. Sin este comentario el reportero no sabe que el bot tomó la tarea.
3. **Commit(s) vía b3-git-commit** — agrupa cambios temáticos y produce conventional commits. No commitear con mensajes inventados ni omitir este paso. Se repite por cada agrupación lógica.
4. **PR draft + labels sincronizadas** — `b4-pull-request --draft` con cuerpo de `publish-docs.sh pr-body` (incluye `Closes #<issue>`, release notes, cambios técnicos, screenshots). Labels del issue: `ready/auto-pr → in-progress` al iniciar, `in-progress → in-review` al abrir el PR. Comentario sticky actualizado con link al PR.
5. **b6-pr-review sobre el PR recién abierto** — invocar `b6-pr-review` pasando el número de PR. Adjuntar el resumen al cuerpo del PR (sección `## Auto-review`) o como comentario del PR. Findings de severidad alta bloquean: re-iterar implementación o pedir intervención humana; no marcar el run como completado con findings críticos sin resolver.

Si alguno de estos 5 pasos no se completa con éxito, el run no es válido y debe reportarse como `aborted` con razón clara — no como completado.

## DEFINITION OF DONE — checklist verificable

Antes de devolver el resumen final al usuario, el orquestador **debe** correr estos checks observables y exhibir el resultado de cada uno. Si alguno falla, el run no terminó:

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cat "$HOME/.claude/b-pipeline.root" 2>/dev/null || ls -d "$HOME"/.claude/plugins/marketplaces/b-pipeline* 2>/dev/null | head -1)}"
# 1. Worktree existe, fue creado por setup-worktree.sh, y la rama está sobre master
bash "$PLUGIN_ROOT/skills/b7-issue-to-pr/scripts/guardrails.sh" verify-worktree "$WORKTREE"
git -C "$WORKTREE" rev-parse --abbrev-ref HEAD       # feat/<N>-... o fix/<N>-...
# 2. Comentario sticky en el issue
gh issue view <N> --json comments -q '.comments[].body' | grep -q '<!-- b7:status -->'
# 3. Commits existen (al menos uno) y master no se tocó
git -C "$WORKTREE" log master..HEAD --oneline | wc -l   # >= 1
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
   && ! git -C "$WORKTREE" diff --name-only master..HEAD | grep -qE '\.(test|spec)\.'; then
  echo "FIX_SIN_TEST — fix sin test de regresion; status=needs-human-review"
fi
```

Si el check 7 sale 6 (codigo sin commitear), volver a invocar `b3-git-commit` en el worktree y pushear — el run NO esta terminado con trabajo fuera del commit. Si sale 7 (artefactos persistentes que `--fix` no pudo excluir), listarlos en el run-report como warning y continuar — mismo criterio que b9 PASO 1.5: los artefactos no invalidan el run.

Si el check 8 imprime `FIX_SIN_TEST`, el run no aborta pero su status final es `needs-human-review` (no `ok`): un fix que no toca tests necesita que un humano confirme que la ausencia de regresion es aceptable. Si hubo waiver explicito (`plan-done regression-test` con `note: waived: <razon>`), la degradacion es la misma — el status va a `needs-human-review` con la razon en el reporte.

**Ultima linea OBLIGATORIA del run** (la parsean orquestadores como b10-ship; fallback de ellos: `gh pr list --search "Closes #N"` + labels del issue):

```
B7_DONE issue=<N> pr=<url|none> status=ok|needs-human-review|bailed|aborted [lane=<S|M|L>]
```

El token `lane=<S|M|L>` es **opcional** (carril asignado en el paso 1b). Los orquestadores lo ignoran si no lo necesitan; el parser tolerante de b10 ya lo cubre.

Si **cualquiera** de estos comandos no devuelve lo esperado, NO usar las frases prohibidas (ver abajo) — completar el paso faltante y volver a verificar.

### Frases prohibidas al cerrar el run

Estas frases significan "abandoné a mitad de camino" y son síntoma del bug que este skill busca evitar. Si estás por escribirlas, el run no está terminado — ejecutá el paso pendiente:

- "Ready for b3-git-commit + b4-pull-request"
- "Listo para commit / Listo para PR"
- "Pendiente: abrir PR / correr review"
- "Próximos pasos: <algo del pipeline>"
- "Worktree con cambios sin commitear" (excepto en `--dry-run` explícito)

En `--wet` el cierre válido es: branch + commits + PR URL + review adjunto + labels actualizadas. En `--dry-run` el cierre válido es: branch + commits opcionales + worktree listo para inspección + label `in-progress` + comentario sticky.

### Anti-patrón: parches inline en master

**Falla observada:** usuario invoca `/b7-issue-to-pr #121 por favor agrega el campo X a la tabla` → el modelo trata la frase inline como "tarea simple", edita archivos en el worktree principal (master), corre `pnpm check:machine`, reporta éxito, y omite worktree/issue-comment/PR.

Esto es **incorrecto siempre**. El número de issue dispara los 4 pasos sin excepción. La frase inline es **input adicional** para el paso 4 (Implementación) — se anexa al `triage.json` como `user_directives` y se pasa al sub-agente de `b2-build-feature`. Pero los pasos 1, 2, 3 (worktree, comentario, PR) siguen siendo no-negociables.

Regla operativa: **antes de la primera escritura a archivos, verificar `pwd` — debe ser el worktree, no el repo principal.** Si es el repo principal, detenerse y crear el worktree primero.

## Argumentos

```
<issue> [--dry-run | --wet] [--max-iterations=N] [--budget-files=N] [--no-pr]
        [--no-screens] [--screens-only] [--lang=es|en]
        [--directives="<texto>"] [--force-complex]
```

**Argumentos recibidos en esta invocación:** `$ARGUMENTS`

> Este skill corre en `context: fork`: el subagente sólo ve el cuerpo de este `SKILL.md`. El placeholder `$ARGUMENTS` de arriba es la ÚNICA forma de que el número de issue (y flags) lleguen al fork — el harness lo sustituye por lo tipeado. El primer token de `$ARGUMENTS` es el número de issue; el resto son flags. Si `$ARGUMENTS` aparece vacío o sin sustituir, abortar con error claro pidiendo el número.

Defaults: `--wet`, `--max-iterations=6`, `--budget-files=25`, sin `--no-pr`, screens habilitadas, `--lang` autodetectado del issue.

Si no se entrega número de issue, abortar con error claro.

### Directivas inline del usuario

Cuando el usuario invoca el skill con texto adicional en el mismo prompt (ej. `/b7-issue-to-pr #121 agregale el campo rut a la tabla`), ese texto se trata como `--directives` y se anexa al triage en `.b7/triage.json` bajo la clave `user_directives`. Los sub-agentes de implementación lo leen junto con el cuerpo del issue. **No alteran la obligatoriedad de los 4 pasos** descritos arriba — son refinamientos del scope, no atajos.

### `--dry-run` vs `--wet`

- `--wet` (default): ejecuta los 4 pasos completos. Worktree creado, issue comentado, código implementado, PR draft abierto, labels sincronizadas.
- `--dry-run`: ejecuta los pasos 1 y 2 (worktree + comentario inicial) y la implementación, pero **no** abre PR ni mueve labels al estado `in-review`. Útil para previsualizar diff antes de publicar. El comentario sticky del paso 2 indica claramente que el run fue dry-run y el worktree quedó disponible para inspección manual.

En ningún modo se puede saltar la creación del worktree o el comentario inicial.

## Principio de Diseño: enfocado en pantallas (colocado en src/routes)

Cada feature se evalúa, diseña, programa, revisa y aprueba como **pantallas y/o flujos de pantallas tal como las usaría alguien en la app**. Esto es **obligatorio**:

- El triage debe identificar `screens[]` con `route`, `user_journey`, `acceptance_criteria_visual` y `success_metrics`.
- La implementación coloca cada pantalla en su carpeta de ruta `src/routes/<feature>/`: la UI va directo en `+page.svelte`, los datos en `<feature>.remote.ts`, y los sub-componentes como hermanos PascalCase (sin subcarpeta `ui/`). Spec canonica del layout (regla 99%, excepciones `$lib`, tolerancia legacy `src/lib/features/`, doc `<feature>.md`): `$PLUGIN_ROOT/skills/b2-build-feature/references/slice-spec.md`.
- La revisión usa `b7-screen-review` por cada pantalla declarada (sub-agente con browser MCP).
- El reporte y los artefactos documentales hablan en lenguaje de pantallas y flujos, no de funciones internas.

Si el triage no produce `screens[]` (porque la tarea es backend puro o de infra), `b7` igual corre pero sin paso de revisión visual: marca `screens: []` y deja constancia en el run-report.

## Optimización de tokens — patrones obligatorios

Estos patrones reducen tokens sin perder calidad. Aplican en todos los pasos.

| # | Patrón | Cómo se aplica |
|---|--------|----------------|
| 1 | Cachear el issue una sola vez | `guardrails.sh cache-issue <N>` escribe `.b7/issue.json`; sub-skills lo leen del disco. |
| 2 | Triage estructurado | `b1-triage-issue` emite `.b7/triage.json` (schema en `templates/triage-output.schema.json`). |
| 3 | Tail relevante por error | `scripts/log-filter.sh <log>` extrae líneas con `error/Error/✘/FAIL` + 2 de contexto. Usar SIEMPRE en vez de `tail -n 80`. |
| 4 | Reporters compactos | `pnpm check:machine -- --threshold error`, `pnpm test:unit -- --run --reporter=dot`, `pnpm lint -- --quiet`. |
| 5 | Hash de error para corte | `scripts/error-hash.sh <log>` hashea las primeras 3 firmas; si coincide con la iteración previa → abort. |
| 6 | Re-correr solo lo que falló | Mantener `.b7/iter-status.json` con `{check,lint,test}`. Solo re-correr los rojos hasta verde, después una pasada final completa. |
| 7 | Sub-agente para implementación | Invocar `b2-build-feature` vía `Agent(subagent_type=general-purpose)`; el orquestador recibe solo el resumen final. |
| 8 | Routing por modelo | Implementación: opus. Resumen de logs / commit / release notes: haiku. Triage / decisiones de arquitectura: opus. Revisión visual: sonnet. |
| 9 | Skip por scope de diff | Si `git diff --name-only` no toca `*.ts/*.svelte/*.js` → `SKIP_CHECK=1`. Sin tests tocados → `SKIP_TEST=1`. |
| 10 | Contexto de proyecto cacheado | `.b7/context.md` se genera una vez via `guardrails.sh context-snapshot` (tras preflight) con: stack, aliases, convenciones remote functions, paleta shadcn, paths críticos. Sub-skills lo leen en vez de re-explorar. |
| 11 | Plan compacto entre iteraciones | `.b7/plan.md` versionado por iteración; delta-only (qué se intentó, qué falló, próximo paso). |
| 12 | Diff resumido | `scripts/diff-summary.sh` produce `.b7/diff-stat.txt` (file list + +/-). LLM cita ese archivo, no `git diff` completo. |
| 13 | Reporte renderizado por script | `scripts/render-report.sh` hace `envsubst` sobre `templates/run-report.md` con valores de `.b7/state.json`. Sin tokens del LLM. |
| 14 | Output JSON en headless | En `claude -p`, emitir solo eventos `{event,iter,status,...}` cuando se imprima estado intermedio. |
| 15 | Lectura acotada | Si el log apunta a `path:LINE`, leer el archivo con `Read(offset=LINE-30, limit=80)`, no completo. |

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
  "screens": [
    {
      "name": "BandejaTareasPage",
      "route": "/tareas",
      "user_journey": "Usuario abre /tareas, filtra por estado, ...",
      "acceptance_criteria_visual": ["Tabla muestra ...", "Botón ..."],
      "success_metrics": ["Filtro responde <200ms", "..."]
    }
  ],
  "security_review_required": false,
  "estimated_complexity": "simple|medium|complex",
  "plan": [
    {"id": "schema-rut", "desc": "Agregar columna rut a ta_persona + migración", "done": false},
    {"id": "remote-fn",  "desc": "Actualizar create_persona/update_persona con rut", "done": false},
    {"id": "ui-form",    "desc": "Input rut en PersonaFormPage con validación", "done": false}
  ]
}
```

Tras escribir `.b7/triage.json`, **validar mecánicamente** contra el schema antes de seguir: `bash scripts/guardrails.sh validate-triage .b7/triage.json`. Si sale exit 4 (verdict/complexity fuera del enum, falta un required, o clave desconocida por `additionalProperties:false`), el triage es inválido — corregirlo y re-validar; no continuar con un artefacto que los sub-skills no van a poder consumir.

**Gate de evidencia para bugs (deterministico, via jq).** El subset de `validate-triage` no evalua el `if/then` del schema (`type=fix` exige `evidence`), asi que b7 lo aplica aca: un `fix` sin `evidence.observed` se trata como needs-info y baila — un bug sin artefacto observado no debe consumir un run de implementacion.

```bash
if [ "$(jq -r '.type' .b7/triage.json)" = "fix" ] \
   && [ -z "$(jq -r '.evidence.observed // empty' .b7/triage.json)" ]; then
  echo "GATE_FAIL fix sin evidence.observed — se trata como needs-info"
  # comentar en el issue (idioma = .language) que falta evidencia observable, liberar lock, salir 0.
fi
```

Mismo trato que `verdict != "ready"`: comentar en el issue (en su idioma) que falta la evidencia observable del bug y bailar. No abrir worktree ni PR.

El `plan[]` es la lista accionable que el orquestador planifica **antes de implementar** y verifica **al cierre** (gate DoD #6). Mantener 3–8 items; nada de micro-tareas. Los sub-agentes marcan progreso con:

```bash
scripts/publish-docs.sh plan-done <id> --worktree "$WORKTREE"
```

Cada `plan-done` re-renderiza `state.plan_block` y queda reflejado en el sticky comment del issue en el próximo `publish-docs.sh issue-comment` (o `all`). Si al cerrar quedan items pendientes, `plan-check` sale 5 y el run no es válido.

**Gate de regresion para bugs (deterministico, via jq).** Si `type == fix`, inyectar un item `regression-test` al `plan[]` antes de implementar — asi el gate DoD #6 (`plan-check`) obliga a que exista un test de regresion sin logica nueva. Solo agregarlo si no esta ya presente:

```bash
if [ "$(jq -r '.type' .b7/triage.json)" = "fix" ] \
   && ! jq -e '.plan[] | select(.id=="regression-test")' .b7/triage.json >/dev/null 2>&1; then
  tmp=$(mktemp)
  jq '.plan += [{"id":"regression-test","desc":"Test que falla sin el fix y pasa con el","done":false}]' \
    .b7/triage.json > "$tmp" && mv "$tmp" .b7/triage.json
fi
```

**Waiver explicito.** Si el fix genuinamente no admite test (p.ej. cambio de infra sin harness), cerrar el item con una razon y degradar el run a `needs-human-review` — nunca marcarlo `done` en silencio:

```bash
scripts/publish-docs.sh plan-done regression-test --worktree "$WORKTREE"   # note: waived: <razon>
```

El waiver deja `plan-check` en verde (item done) pero el status final del run es `needs-human-review`, no `ok`: un humano confirma que la ausencia de test es aceptable. La razon del waiver va en el sticky comment y el run-report.

Si `verdict != "ready"`: comentar en el issue (en su idioma — `language` del JSON) que el bot bailó, liberar lock, salir 0.

Si `security_review_required: true`: forzar `--no-pr` y marcar para revisión humana en el reporte.

Si `estimated_complexity == "complex"` y NO se paso `--force-complex`: comentar y bailar (excede el alcance del bot). Con `--force-complex` (lo pasa b10-ship tras confirmacion humana explicita): continuar, pero registrar en el sticky y el run-report que el run corre fuera del alcance default — los budgets siguen aplicando.

#### 1b. Clasificar el carril del run (lane S/M/L)

Tras el gate de complejidad (y solo si el run continua), asignar el **carril** que gobierna cuánto paga el run — un fix de 1 línea no debe pagar el pipeline completo (esqueletos LLM, opus, 6 iteraciones, b6 full):

```bash
bash "$PLUGIN_ROOT/skills/b7-issue-to-pr/scripts/guardrails.sh" \
  classify-run "$WORKTREE/.b7/triage.json" "$WORKTREE/.b7/state.json"   # emite RUN_LANE=S|M|L
```

Reglas: `lane=L` si `estimated_complexity == complex`; `lane=S` si `== simple` **y** `files_likely` tiene ≤5 entradas; `lane=M` en cualquier otro caso. El script persiste `lane` en `state.json`. **Los carriles M y L son byte-idénticos al comportamiento histórico** — no cambian nada. El carril **S** activa las optimizaciones descritas en los pasos 3, 4, 5 y 8c (render mecánico de screens, agente sonnet, 3 iteraciones, `b6 --light`).

Reflejar el carril en el sticky del issue (`publish-docs.sh state-set lane=<S|M|L>` ya lo trae de `state.json`; el sticky lo muestra en el próximo `issue-comment`).

> El `classify-run` corre acá porque necesita `state.json` y `triage.json` ya sembrados en el worktree. Si por orden de pasos aún no existe el worktree cuando llegás a esta clasificación, corré `classify-run` inmediatamente después del paso 2 (worktree) y antes del paso 3.

### 2. Worktree headless — PASO OBLIGATORIO #1

**Prohibido `git worktree add` directo.** Hay un PreToolUse hook que bloquea esa llamada — si la intentás, vas a recibir un error. Usar SIEMPRE `setup-worktree.sh`.

Patrón obligatorio (copiar tal cual, no parafrasear):

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cat "$HOME/.claude/b-pipeline.root" 2>/dev/null || ls -d "$HOME"/.claude/plugins/marketplaces/b-pipeline* 2>/dev/null | head -1)}"
BRANCH="feat/<issue>-<short-slug>"   # o fix/<...> según triage.type
OUT=$(bash "$PLUGIN_ROOT/skills/b1-add-worktree/scripts/setup-worktree.sh" "$BRANCH" master --headless)
echo "$OUT"
LINE=$(echo "$OUT" | grep '^WORKTREE_READY ' || true)
if [ -z "$LINE" ]; then
  echo "ABORT: setup-worktree.sh did not emit WORKTREE_READY — worktree not safely created" >&2
  exit 1
fi
# Parse "WORKTREE_READY dir=<path> branch=<name> port=<n>"
eval "$(echo "$LINE" | sed 's/^WORKTREE_READY //' | tr ' ' '\n' | awk -F= '{print "WT_"toupper($1)"="$2}')"
export WORKTREE="$WT_DIR" BRANCH="$WT_BRANCH" PORT="$WT_PORT"

# Hard gate: refuse to continue if the worktree isn't fully provisioned.
bash "$PLUGIN_ROOT/skills/b7-issue-to-pr/scripts/guardrails.sh" verify-worktree "$WORKTREE" || exit 31
```

Sin `WORKTREE_READY` no hay `$WORKTREE` exportado → ninguna escritura posterior puede apuntar a un destino válido. `verify-worktree` además rechaza worktrees que estén fuera de `<parent>/worktrees/`, sin `dev.sh`, sin symlinks `.env*` o sin `node_modules`.

Crear `.b7/` dentro del worktree (excluido via el exclude por-worktree que siembra `setup-worktree.sh`). Mover los artefactos `.b7/issue.json`, `.b7/triage.json`, `.b7/context.md` al worktree. **Sembrar el heartbeat de inmediato** (la reconciliacion de b10 lo usa para distinguir runs vivos de zombies — sin el, un run muerto en fases tempranas es invisible):

```bash
bash "$PLUGIN_ROOT/skills/b7-issue-to-pr/scripts/guardrails.sh" heartbeat "$WORKTREE"
```

El subcomando escribe `.b7/heartbeat` (formato UTC exacto que parsea b10) y ademas toca `b7.lock` — la staleness del lock es por mtime, un run vivo lo mantiene fresco. Tocar el heartbeat tambien: al inicio del paso 5.0 (antes de levantar el dev server), al completar cada pantalla en 5.2, y antes de invocar b6 en 8c.

**Verificación previa a cualquier escritura:** después de `verify-worktree OK`, toda invocación de Edit/Write/Bash debe operar sobre `$WORKTREE`. Si en algún momento `pwd` reporta el repo principal, detenerse — la siguiente escritura sería un parche en master.

### 2b. Comentario inicial en el issue — PASO OBLIGATORIO #2

Inmediatamente después de crear el worktree, avanzar el milestone (sin hand-edit del JSON) y renderizar el sticky:

```bash
scripts/publish-docs.sh milestone started       --worktree "$WORKTREE"
scripts/publish-docs.sh state-set mode=wet branch="$BRANCH" worktree_dir="$WORKTREE" --worktree "$WORKTREE"
scripts/publish-docs.sh issue-comment            --worktree "$WORKTREE"
```

> NOTA: `milestone <name> [N]` (started, triage-done, worktree-ready, iter-green N, screens-reviewed, committed, pr-opened) y `state-set key=value [...]` escriben `.b7/state.json` por vos — NO editar el JSON a mano. `state-set` rechaza claves que no existan en el scaffold (atrapa typos que renderizarian vacio). Subcomandos completos: `changelog | issue-comment | pr-body | all | aborted | bailed | state-set | milestone | plan-render | plan-done | plan-check`.

Esto postea (o edita, vía marker `<!-- b7:status -->`) un comentario sticky en el issue indicando: branch creado, modo (`--wet`/`--dry-run`), directivas inline si las hay, ETA estimado por complexity. Sin este comentario el usuario que abrió el issue no sabe que el bot lo tomó.

También en este punto se actualizan labels del issue:

```bash
gh issue edit <N> --remove-label "ready,auto-pr" --add-label "in-progress"
```

Si las labels destino no existen en el repo, crearlas con `gh label create` antes.

### 3. Diseño de pantallas (rápido, en línea)

Antes de implementar, para cada `screen` del triage producir un esqueleto en `.b7/screens/<Name>.md`:

- Layout en términos de componentes shadcn-svelte (`Card.Root`, `Table.Root`, `Tabs.Root`, etc.)
- Lista de remote functions necesarias (`get_*`, `create_*`, `update_*`)
- Estados a mostrar: empty, loading, error, success
- Dónde vive cada archivo (todo colocado en `src/routes/<feature>/...`)

Esto es entrada para b2 y para la revisión visual posterior. **Texto plano, no markdown rico** — no consume tokens reformateando.

**Carril S — render MECÁNICO (sin LLM):** si `lane == S`, NO gastar una pasada de modelo diseñando el esqueleto. Renderizar `.b7/screens/<Name>.md` directamente desde `triage.json` — un bloque por cada `screen` con su `route`, `user_journey` y `acceptance_criteria_visual`. El archivo resultante **preserva el contrato `criteria_file`** que consume `b7-screen-review` (mismos campos, mismo path `.b7/screens/<Name>.md`); solo cambia que el contenido sale de sustitución de plantilla en vez de razonamiento. Ejemplo mínimo por pantalla:

```bash
# lane S: render mecanico de cada screen del triage (sin modelo)
python3 - "$WORKTREE/.b7/triage.json" "$WORKTREE/.b7/screens" <<'PY'
import json, os, sys
triage, outdir = sys.argv[1], sys.argv[2]
os.makedirs(outdir, exist_ok=True)
for s in json.load(open(triage)).get("screens", []):
    lines = [f"# {s['name']}  ({s['route']})", "",
             f"Journey: {s.get('user_journey','')}", "", "Criterios visuales:"]
    lines += [f"- {c}" for c in s.get("acceptance_criteria_visual", [])]
    open(os.path.join(outdir, f"{s['name']}.md"), "w").write("\n".join(lines) + "\n")
PY
```

En carriles M y L el diseño sigue siendo la pasada en línea descrita arriba (byte-idéntico al comportamiento histórico).

### 4. Implementación (loop bounded)

**Carril S:** invocar el agente `agents/b7-impl-s.md` (`model: sonnet`) en vez de `b2-build-feature` — es la única vía real de bajar el modelo respecto del opus por defecto de b2. Mismo contrato (feature colocado, Remote Functions, sin state global, errores estructurados), scope acotado, diffs mínimos. Además, en carril S el hard stop de **iterations baja a 3** (salvo `--max-iterations=N` explícito). Carriles M y L: seguir con `b2-build-feature` y 6 iteraciones (sin cambios).

Invocar `b2-build-feature` **vía sub-agente** (`Agent(subagent_type=general-purpose)`) pasándole:

- Ruta a `.b7/triage.json`
- Ruta a `.b7/screens/`
- Ruta a `.b7/context.md`
- Indicación: respetar layout colocado (feature en `src/routes/<feature>/`), usar Remote Functions Pattern, no introducir state global, errores con `error(STATUS, {message,code})`.
- Si alguna pantalla del triage tiene form de crear/editar: pointer a `$PLUGIN_ROOT/skills/b2-build-feature/references/forms-recipe.md` (campos nativos vs shadcn no-nativos con hidden-input, `issues()`/aria-invalid siempre visibles, regla `disabled={submitting}` NUNCA `disabled={!isFormValid}`).

Después de cada pasada del sub-agente, ejecutar el bloque de validación. **Skip-by-scope** primero:

```bash
changed=$(git -C "$WORKTREE" diff --name-only "$(git -C "$WORKTREE" merge-base HEAD master)")
echo "$changed" | grep -qE '\.(ts|svelte|js)$' && RUN_CHECK=1 || RUN_CHECK=0
echo "$changed" | grep -qE '\.(test|spec)\.' && RUN_TEST=1 || RUN_TEST=0
echo "$changed" | grep -qE '\.(ts|svelte|js|css)$' && RUN_LINT=1 || RUN_LINT=0
```

Al inicio de CADA iteracion, tocar el heartbeat (permite a la reconciliacion de b10 distinguir un run vivo de uno zombie, y mantiene fresco el lock):

```bash
bash "$PLUGIN_ROOT/skills/b7-issue-to-pr/scripts/guardrails.sh" heartbeat "$WORKTREE"
```

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

Parar el loop cuando todos los comandos habilitados estén verdes en una pasada final completa, OR cuando se trip un hard stop:

| Hard stop          | Default | Acción |
|--------------------|---------|--------|
| iterations         | 6 (3 en carril S) | Abort, comentar issue, save state |
| files changed      | 25      | Abort, comentar issue, save state |
| lines added (net)  | 1500    | Abort, comentar issue, save state |
| wall-clock         | 30 min  | Abort, comentar issue, save state |
| error hash repeat  | 1       | Abort por no-progress |

`scripts/guardrails.sh check-budget <worktree>` mide files/lines.

### 5. Revisión visual de pantallas (sub-agente por pantalla)

Si `triage.screens[]` no está vacío y no se pasó `--no-screens`:

**Carril S — saltar la revisión visual SOLO si el diff es seguro.** El carril rápido puede omitir el review visual **únicamente** cuando el diff **no toca** `*.svelte` **NI** `*.remote.ts` **NI** nada bajo `src/routes/`. Las memorias del owner exigen browser check en cualquier cambio de UI o de datos que alimentan una pantalla — un `.remote.ts` cambia lo que la pantalla muestra, así que **no** se salta. Regla observable:

```bash
# lane S: decidir si se puede saltar el review visual
LANE=$(python3 -c 'import json;print(json.load(open("'"$WORKTREE"'/.b7/state.json")).get("lane","M"))')
base=$(git -C "$WORKTREE" merge-base HEAD master)
touched_ui=$(git -C "$WORKTREE" diff --name-only "$base" \
  | grep -qE '\.svelte$|\.remote\.ts$|^src/routes/' && echo 1 || echo 0)
if [ "$LANE" = S ] && [ "$touched_ui" = 0 ]; then
  echo "lane S + diff sin UI/remote/routes → skip review visual (nota al run-report)"
  # saltar a 5.9 (nada que apagar) / paso 6
fi
```

Si el diff de un carril S **sí** toca alguno de esos patrones, la revisión visual corre igual que en M/L (no es opcional). En carriles M y L nunca se salta por este criterio.

#### 5.0 Levantar el dev server del worktree (OBLIGATORIO antes del review)

**Causa histórica de que las pantallas nunca se revisaran:** nadie levantaba el dev server del worktree, así que `b7-screen-review` hacía `curl localhost:<port>` → sin respuesta → abortaba `fail`, y b7 seguía sin pantallas. Hay que levantarlo acá.

```bash
# El worktree trae un dev.sh que corre vite en $PORT (puerto propio del worktree).
cd "$WORKTREE"
nohup ./dev.sh > .b7/dev-server.log 2>&1 &
echo $! > .b7/dev-server.pid
# Esperar a que responda (hasta ~40s; vite + primera compilación).
for i in $(seq 1 20); do
  if curl -fsS "http://localhost:${PORT}/" >/dev/null 2>&1; then echo "dev server UP en :${PORT}"; break; fi
  sleep 2
done
# Gate DURO: no basta con que algo responda en el puerto — tiene que ser ESTE
# worktree. verify-port compara el cwd del proceso listener con $WORKTREE
# (exit 40 = nadie escucha, exit 41 = lo sirve otro checkout, p.ej. master).
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/skills/b-pipeline}"
bash "$PLUGIN_ROOT/skills/b7-issue-to-pr/scripts/guardrails.sh" verify-port "$PORT" "$WORKTREE" \
  || { echo "WARN: verify-port fallo (:${PORT} no sirve el worktree) — screens se omiten con nota"; }
```

Si `verify-port` sale non-zero (nadie escucha, o el puerto lo sirve otro cwd que no es el worktree), omitir el review visual con una nota explícita en el run-report (no abortar el run completo) y saltar a 5.9 (no hay nada que apagar si el `pid` no quedó vivo). **No revisar pantallas contra un server que no sea el del worktree** — ese fue el incidente que este gate previene (screen-review contra master).

#### 5.1 Auth: sesión scriptada (preferido) con fallback al Chrome real

La app exige login (OAuth Google/Microsoft) y **no** se hace login interactivo automatizado. Dos caminos, en orden:

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
    echo "verify no dio 200 — descarto la cookie, caigo al Chrome real"
    AUTH_COOKIE=""
  fi
else
  echo "mint no disponible (sin B7_SESSION_USER_ID/EMAIL o DATABASE_URL) — fallback al Chrome real"
fi
```

`mint` sale 3 (fallback limpio) si faltan `B7_SESSION_USER_ID`/`B7_SESSION_EMAIL` o `DATABASE_URL` — **no** es error; simplemente no hay cookie y se sigue con el flujo B.

**B. Fallback: reusar el Chrome real del usuario.** Si no hubo cookie, `claude-in-chrome` opera el navegador real donde el usuario ya tiene (o puede abrir) una sesión válida. Dejar UNA línea en el run-report y en el sticky comment del issue:

> Para revisar las pantallas, abrí `http://localhost:<port>/` en tu Chrome y logueate una vez. Las capturas reusan esa sesión.

Si una pantalla vuelve `auth-required` (redirección a login, sin cookie), **no** es `fail` del feature: marcar la pantalla como `not-evaluated (login pendiente en Chrome)` en el run-report y seguir. Solo cuenta como `fail` un criterio visual incumplido con sesión válida.

> Restricción conocida (fuera de alcance de #14): la cookie es host-scoped (`localhost`). Si b7 y b8-swarm mintean en paralelo contra el mismo host, la última cookie pisa a las demás. Wiring de mint en b8-swarm es follow-up.

#### 5.2 Lanzar un sub-agente por pantalla

Para cada pantalla, lanzar **un sub-agente** con `b7-screen-review` en paralelo (un Agent call por pantalla en el mismo turno):

```
Agent(
  subagent_type="general-purpose",
  description="Visual review <ScreenName>",
  prompt="Use skill b7-screen-review with: screen=<Name> route=<route> port=<PORT> worktree=$WORKTREE criteria_file=.b7/screens/<Name>.md out_dir=.b7/review states=golden auth_cookie=<AUTH_COOKIE>. Si viene auth_cookie inyectala (paso 2a del skill); si no, reusá la sesión del Chrome real (paso 2b) — no hagas login. Cargá primero las MCP tools de claude-in-chrome con ToolSearch. Output: .b7/review/<Name>.json + .b7/review/<Name>-*.png"
)
```

Pasar `auth_cookie=<AUTH_COOKIE>` solo si 5.1-A dio una cookie válida (verify=200); si `AUTH_COOKIE` quedó vacío, omitir el param y el sub-agente cae al Chrome real.

`b7-screen-review` produce por pantalla:
- `<Name>.json`: `{verdict: pass|fail|warn, findings: [...], screenshots: [...]}`
- Una o más PNGs (golden path + edge cases)

Si alguna pantalla retorna `fail` (criterio visual incumplido con sesión válida), devolver findings al loop de implementación (paso 4) y rebudgetear iteración. Si retorna `warn` o `not-evaluated`, agregar al PR como nota pero seguir.

#### 5.9 Apagar el dev server y borrar la sesión scriptada

Pase lo que pase con el review, apagar el server que se levantó en 5.0 **y** borrar SIEMPRE la sesión que se minteó en 5.1-A (si la hubo). El cleanup es idempotente: sin `.b7/dev-session.json` no hace nada.

```bash
# Borrar la sesión scriptada (idempotente; no falla si no se minteó ninguna).
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/skills/b-pipeline}"
bash "$PLUGIN_ROOT/skills/b7-screen-review/scripts/mint-dev-session.sh" cleanup "$WORKTREE" || true

# Apagar el dev server.
[ -f "$WORKTREE/.b7/dev-server.pid" ] && kill "$(cat "$WORKTREE/.b7/dev-server.pid")" 2>/dev/null || true
rm -f "$WORKTREE/.b7/dev-server.pid"
```

### 6. Commit

Si step 4 verde AND budgets OK AND screens pass/warn:

- `b3-git-commit` agrupa cambios temáticos.
- **Antes** de invocarlo, asegurar entrada en `CHANGELOG.md` usando `scripts/publish-docs.sh changelog` (lee `.b7/state.json`).

En modo `--dry-run`, saltarse el commit y avisar al usuario que el worktree quedó con cambios sin commitear para inspección.

**NO PARAR AQUÍ.** "Implementación verde + commit hecho" no es el final del run en modo `--wet`. Continuar directamente al paso 7 (publish-docs) → 8 (PR draft) → 8b (labels) → 8c (b6-pr-review). El error histórico fue reportar éxito tras el paso 6 con frases tipo "Ready for b3-git-commit + b4-pull-request" — esos pasos son responsabilidad de este skill, no del usuario.

### 7. Publicar documentación (script, sin LLM)

`scripts/publish-docs.sh all` ejecuta tres outputs en una sola pasada determinística:

1. **`CHANGELOG.md`** — entrada analítica (what/why/risk/issue link). Template: `templates/changelog-entry.md`.
2. **Comentario en el issue** — informativo en el idioma del issue, con estado, links al PR (si existe), thumbnails de pantallas. Sticky: usa marker `<!-- b7:status -->` para editar el mismo comentario en vez de spamear (`gh api` patch). Template: `templates/issue-comment.md`.
3. **Cuerpo del PR** — release notes con tono comercial (qué obtiene el usuario, no qué función se tocó). Template: `templates/pr-release-notes.md`.

Las tres salidas se generan desde el mismo `.b7/state.json` para garantizar consistencia. Sub-agentes no participan acá.

### 8. PR draft — PASO OBLIGATORIO #3

Si NOT `--dry-run` y NOT `--no-pr`: invocar `b4-pull-request` con `--draft --label auto-pr-bot --body-file .b7/pr-body.md`. El cuerpo ya viene de `publish-docs.sh`. Para las screenshots de `b7-screen-review`: ejecutar el `attach.sh` que deja cada review, que postea un comentario informativo en el PR con los nombres de los PNG + puntero al run-report (GH REST no permite inline upload de imágenes en comentarios; las imágenes embebidas se ven en el run-report HTML local).

El PR debe incluir:
- `Closes #<issue>` (esto cierra automáticamente el issue al mergear el PR)
- Link al run report
- Sección "Pantallas entregadas" con thumbnails (si aplica)
- Sección "Notas de release" (lo que ve el usuario)
- Sección "Cambios técnicos" (resumen, links a archivos)
- Sección "Directivas inline del usuario" si `triage.user_directives` no está vacío — cita textual de lo que pidió el invocador, para que el reviewer entienda el scope
- Checklist de revisión (incluye revisar screenshots adjuntos)

### 8b. Sincronizar estado del issue — PASO OBLIGATORIO #4

Apenas el PR queda abierto:

```bash
gh issue edit <N> --remove-label "in-progress" --add-label "in-review"
# milestone pr-opened + link al PR (sin hand-edit del JSON) y re-render del sticky:
scripts/publish-docs.sh milestone pr-opened --worktree "$WORKTREE"
scripts/publish-docs.sh state-set pr_url="$PR_URL" pr_number="$PR_NUMBER" pr_link="$PR_URL" --worktree "$WORKTREE"
scripts/publish-docs.sh issue-comment --worktree "$WORKTREE"
```

El comentario sticky se edita in-place (no se postea uno nuevo) gracias al marker `<!-- b7:status -->`. Estado final esperado del issue: label `in-review`, comentario apuntando al PR, sin labels obsoletas (`ready`, `auto-pr`).

Cuando el PR mergea, el `Closes #<issue>` cierra el issue automáticamente — no hay que hacer nada manual ahí.

**Paso siguiente (fuera de b7):** el merge + cierre del PR + limpieza del worktree lo hace `b9-close`, con aprobación humana. b7 NO mergea; termina en PR draft + review adjunto.

### 8c. Auto-review del PR — PASO OBLIGATORIO #5

Apenas el PR está abierto (incluso draft), invocar `b6-pr-review "<PR> --auto"`. **Carril S:** invocar `b6-pr-review "<PR> --auto --light"` — el `--light` (size-gate emitido por `pr-context.sh`, issue #3) recorta el review al tamaño chico del diff. Carriles M y L: sin `--light` (review completo, sin cambios). **b6 en modo `--auto` publica el reporte por si mismo** (`gh pr comment` con el marker `<!-- b6:verdict=... -->`) — NO volver a postearlo desde aca (doble posteo). Verificar que quedo publicado:

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

En dry-run el worktree se **mantiene** y los pasos 3 (PR) y 4b (label `in-review`) se saltan, pero los pasos 1, 2, y 4a (label `in-progress` + comentario inicial) ya ocurrieron. Decirle al usuario:

- Path del worktree (para `cd` e inspeccionar).
- Path del run report.
- Path de `.b7/screens/` y `.b7/review/` (mockups + screenshots).
- Estado actual del issue: label `in-progress`, comentario sticky publicado.
- Cómo promover a PR: `cd <worktree>; git status; git diff` + `/b3-git-commit` + `/b4-pull-request`. Acordarse de mover el label a `in-review` después.

## Sub-agentes — cuándo y por qué

| Paso | Sub-agente | Razón |
|------|-----------|-------|
| 4 Implementación | `Agent(general-purpose)` | Aislar contexto de exploración + tool calls verbosos. Orquestador solo recibe resumen. |
| 5 Revisión visual | `Agent(general-purpose)` con `b7-screen-review` | Browser MCP es independiente. Paralelizar por pantalla. Output binario (PNG) no contamina contexto. |
| Triage / Commit / PR | Skill directo | Son determinísticos y rápidos; sub-agente sería overkill. |

## Routing de modelo

`b7` corre en `opus` con `effort: medium` (bajado de `max`). Sub-skills heredan a menos que digan lo contrario:

- `b2-build-feature`: `opus` (implementación necesita razonamiento)
- `b1-triage-issue`: `opus` (decisión de scope)
- `b3-git-commit`, `b4-pull-request`, log summarizers: `haiku` cuando sea posible
- `b7-screen-review`: `sonnet` (multimodal con screenshots, no necesita opus)

Configurable vía env `B7_MODEL_<STEP>` para experimentar.

## Rastro documental triple — invariantes

Cada milestone se avanza con `publish-docs.sh milestone <name>` (`started`, `triage-done`, `worktree-ready`, `iter-green N`, `screens-reviewed`, `committed`, `pr-opened`) y los campos de contenido con `state-set key=value` — nunca hand-editando `.b7/state.json`. Después se invoca `publish-docs.sh issue-comment` (o `all` al cierre; `aborted` en aborts) que **propaga consistentemente** el estado de `.b7/state.json` a:

| Salida | Lenguaje | Audiencia | Foco |
|--------|----------|-----------|------|
| `CHANGELOG.md` | Técnico/análítico | Devs futuros leyendo historia | Qué cambió, por qué, riesgos, link a issue + PR |
| Comentario sticky en issue | Idioma del issue | El usuario que lo creó | Estado actual, próximos pasos, links, thumbnails de pantallas |
| Cuerpo del PR | Comercial / release notes | Reviewers + stakeholders | Qué obtiene el usuario final, valor entregado, demos visuales |

`publish-docs.sh` es **idempotente**: re-correrlo con el mismo `state.json` produce los mismos outputs. El comentario en issue usa marker `<!-- b7:status -->` para editarse in-place via `gh issue comment --edit-last` o `gh api PATCH`.

## Manejo de errores

- Toda ruta de abort debe (a) `publish-docs.sh aborted` (que actualiza el comentario del issue + entry en CHANGELOG con `[Aborted]`), (b) escribir el run report, (c) liberar el lock con `guardrails.sh release-lock`.
- **El lock NO se libera solo.** `run.sh` lo deja retenido a proposito para la fase LLM; toda ruta terminal (exito, abort, bail) debe invocar `guardrails.sh release-lock`. Fallback: un lock sin tocar por 2h (`B7_LOCK_STALE_SECS`) se recupera en el proximo preflight — el heartbeat de cada iteracion lo mantiene fresco en runs vivos.
- Si `publish-docs.sh` falla (p.ej. `gh` cae), no bloquear el resto del cierre — log a stderr y continuar.

## Invocación headless

```bash
# Default (wet) — corre los 4 pasos completos: worktree, comentario, PR, labels
claude -p --permission-mode acceptEdits \
  "Use skill b7-issue-to-pr with arguments: 142"

# Wet con directivas inline del usuario
claude -p --permission-mode acceptEdits \
  "Use skill b7-issue-to-pr with arguments: 142 --directives='agregale columna rut a la tabla'"

# Dry-run para inspeccionar antes de PR
claude -p --permission-mode acceptEdits \
  "Use skill b7-issue-to-pr with arguments: 142 --dry-run"

# Wet sin pantallas (issue puramente backend)
claude -p --permission-mode acceptEdits \
  "Use skill b7-issue-to-pr with arguments: 142 --no-screens"
```

Cuando el usuario invoca de forma interactiva con texto pegado (`/b7-issue-to-pr #121 hola agrega el campo X`), el skill interpreta `121` como issue y el resto como `--directives`. El pipeline corre los 4 pasos igual que en headless.

## Qué NO hacer

- **No editar archivos en master.** Si no se creó el worktree todavía, no se escribe nada. Si la edición falla porque no hay worktree, eso es la señal correcta: crear el worktree primero.
- **No tratar las directivas inline del usuario como un atajo.** Texto extra en el prompt (ej. "agregale el campo X") no convierte el flujo en una edición rápida — pasa a `triage.user_directives` y se ejecuta dentro de los 4 pasos.
- **No abrir el PR sin actualizar labels.** Paso 8 y 8b son inseparables. Si el `gh issue edit` falla, reportarlo en el run report como warning, pero no continuar como si todo estuviera bien.
- No escribir lógica propia de triage. Usar `b1-triage-issue`.
- No llamar `git worktree add` directo. Usar `b1-add-worktree --headless`.
- No escribir mensajes de commit propios. Usar `b3-git-commit`.
- No bypassear budgets re-corriendo con números más altos. Hitar un budget = el issue es más grande de lo que el bot debería atacar; escalar a humano.
- No modificar `package.json`, lockfiles, `.env*`, `*.pem`, `*.key`, `secrets/`, configs de build/CI ni `scripts/*.sh`. El hook `pre-commit-budget.sh` (instalado automaticamente por `setup-worktree.sh`, scope por-worktree) los rechaza en el commit. Bypass solo humano con `B7_BUDGET_OVERRIDE=1`.
- No leer `git diff` completo. Usar `.b7/diff-stat.txt` o `Read` con `offset/limit`.
- No leer logs completos. Usar `scripts/log-filter.sh`.
- No saltarse `b7-screen-review` cuando hay `screens[]` en triage — la revisión visual es parte de la calidad mínima del PR. **Única excepción:** carril S con un diff que no toca `*.svelte` ni `*.remote.ts` ni `src/routes/` (paso 5). Un diff de carril S que sí toca UI/datos NO se salta: las memorias del owner exigen browser check en cualquier cambio de pantalla.
- No forzar el carril S. El carril lo asigna `classify-run` desde `triage.json` (complexity + `files_likely`), no el modelo a ojo. No bajar a sonnet ni recortar iteraciones/review por cuenta propia cuando el run es M/L — eso reintroduce el bug que este carril evita (M/L deben quedar byte-idénticos al comportamiento histórico).
- No editar el comentario del issue manualmente; siempre via `publish-docs.sh` para mantener el marker sticky.

## Referencias

- `templates/triage-output.schema.json` — schema esperado para `.b7/triage.json`
- `templates/issue-comment.md` — template del comentario sticky
- `templates/pr-release-notes.md` — template del cuerpo PR
- `templates/changelog-entry.md` — template de entrada CHANGELOG
- `templates/run-report.md` — template del reporte final
- `scripts/log-filter.sh` — extracción semántica de líneas relevantes
- `scripts/error-hash.sh` — firma de error para detección de no-progress
- `scripts/diff-summary.sh` — resumen compacto del diff vs base
- `scripts/render-report.sh` — render envsubst del run report
- `scripts/publish-docs.sh` — escritura triple coordinada (CHANGELOG + issue + PR)
