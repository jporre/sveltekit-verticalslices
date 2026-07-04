---
name: b9-close
description: 'Cierre de un PR ya revisado: mergea a master con aprobacion humana, cierra sus issues y limpia el worktree. Usar cuando pidan "cerrar/mergear el PR N", "finalizar el issue N" (ya implementado), o "limpiar el worktree". PASO 4 del flujo b — corre despues de b7 (implementacion) y b6-pr-review (review); no implementa ni revisa.'
allowed-tools: Bash, Read, AskUserQuestion, Skill, Agent
model: sonnet
---

## Argumentos recibidos

```text
$ARGUMENTS
```

Acepta: numero de issue (`121`), numero de PR (`#170` o `pr 170`), nombre de branch (`feat/121-...`), o nada (autodetecta desde el worktree actual). El primer token decide el modo de resolucion.

---

# b9-close — mergear PR + cerrar issue + limpiar worktree

Cierre del flujo b. El feature ya fue implementado por `b7-issue-to-pr` y revisado por `b6-pr-review`. Este skill **no** reimplementa ni hace review profundo: **gatea** sobre que la revision paso, mergea con **aprobacion humana**, y deja el arbol limpio (PR cerrado, issue cerrado, worktree y branches borrados).

**Filosofia:** ningun PR del bot va a master sin ojo humano.

---

## PASO 0: Resolver PR + branch + worktree + issue

Desde el repo principal. Resolver segun el primer token de `$ARGUMENTS`:

```bash
REPO_MAIN="$(git rev-parse --show-toplevel)"
ARG="<primer-token-de-$ARGUMENTS>"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cat "$HOME/.claude/b-pipeline.root" 2>/dev/null || ls -d "$HOME"/.claude/plugins/marketplaces/b-pipeline* 2>/dev/null | head -1)}"
. "$PLUGIN_ROOT/scripts/lib.sh"

# Modo issue (numero pelado o "issue N"): buscar el PR que lo cierra.
# Usar bp_find_pr, NUNCA gh search a mano: un falso positivo mergea el PR equivocado.
PR=$(bp_find_pr "$ARG" open)
# Modo PR (#N / "pr N"): usar directo.   Modo branch: gh pr list --head <branch>.
# Sin arg: PR=$(gh pr list --head "$(git rev-parse --abbrev-ref HEAD)" --json number --jq '.[0].number')

# Idempotencia: si no hay PR abierto, buscar uno YA MERGEADO (re-run tras crash a
# mitad de limpieza). Si aparece y esta MERGED, saltar directo a PASO 6/7.
[ -z "$PR" ] && PR=$(bp_find_pr "$ARG" merged)

[ -z "$PR" ] && { echo "ABORT: no encontre PR (abierto ni mergeado) para '$ARG'"; exit 1; }

BRANCH=$(gh pr view "$PR" --json headRefName --jq .headRefName)
# TODOS los issues que cierra el PR (los PRs cluster de b8 traen varios "Closes #").
ISSUES=$(gh pr view "$PR" --json body --jq '.body' | grep -oiE 'closes #[0-9]+' | grep -oE '[0-9]+' | sort -un)
ISSUE=$(echo "$ISSUES" | head -1)
WORKTREE=$(git worktree list --porcelain | awk -v b="refs/heads/$BRANCH" '/^worktree /{wt=$2} $0=="branch "b{print wt}')
echo "PR=#$PR  BRANCH=$BRANCH  ISSUES=#$(echo "$ISSUES" | paste -sd, -)  WORKTREE=${WORKTREE:-'(ninguno)'}"
```

Si falta el PR, abortar. El worktree puede no existir (PR creado a mano) — seguir igual, solo no hay nada que limpiar localmente.

## PASO 1: Estado del PR (gate observable)

```bash
gh pr view "$PR" --json number,title,isDraft,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup,labels \
  --jq '{number,title,isDraft,mergeable,mergeStateStatus,reviewDecision,checks:[.statusCheckRollup[]?.conclusion],labels:[.labels[].name]}'
```

- `mergeable != "MERGEABLE"` (conflictos) → PARA, reporta los conflictos. No los resuelvas automatico.
- Checks de CI en `FAILURE` → reporta y pregunta si igual seguir (no bloqueante por si solo; el proyecto puede no tener CI obligatoria).

## PASO 1.5: Sincronizar el worktree (todo commiteado y pusheado ANTES del merge)

Solo si existe `$WORKTREE`. El squash-merge debe incluir TODO el trabajo; cambios sueltos o commits sin push se pierden silenciosamente.

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cat "$HOME/.claude/b-pipeline.root" 2>/dev/null || ls -d "$HOME"/.claude/plugins/marketplaces/b-pipeline* 2>/dev/null | head -1)}"
bash "$PLUGIN_ROOT/skills/b1-add-worktree/scripts/assert-clean.sh" "$WORKTREE" --fix
```

- **exit 6** (codigo sin commitear) → invocar `Skill b-pipeline:b3-git-commit` desde el worktree para commitearlo (b3 garantiza terminar limpio), luego seguir.
- **exit 7** (artefactos persistentes) → reportar, no bloquea.

```bash
# Push incondicional (idempotente, no-op si ya esta al dia). No condicionar a
# `git log origin/B..B`: si el ref remoto local esta stale/pruned, ese check da 0
# y los commits sin push se perderian del squash.
git -C "$WORKTREE" push origin "$BRANCH"
```

**Si este paso commiteo o pusheo algo nuevo, registrarlo** (`SYNCED=1`): el review existente NO cubre esos commits — ver el check de frescura en PASO 2.

## PASO 2: Gate de revision (¿corrio b6?)

```bash
# Lector unico del marker (cubre comentarios Y reviews). NO parsear el marker a mano.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cat "$HOME/.claude/b-pipeline.root" 2>/dev/null || ls -d "$HOME"/.claude/plugins/marketplaces/b-pipeline* 2>/dev/null | head -1)}"
. "$PLUGIN_ROOT/scripts/lib.sh"
bp_b6_verdict "$PR"
# exit 0 -> imprime: B6_VERDICT verdict=.. blockers=N warnings=M pr=P
# exit 3 -> sin marker (no hubo review)
```

- **exit 0** → review presente. Del `B6_VERDICT`: si `blockers > 0` sin resolver, PARA y reporta — devuelve al usuario / a b7, no parchea aca.
- **exit 3** → no hubo review. **Ofrece correrlo ahora** (`Skill b-pipeline:b6-pr-review` con el numero de PR). No mergees sin review.
- **Frescura**: si PASO 1.5 commiteo/pusheo commits nuevos (`SYNCED=1`), el review existente no los cubre — re-correr `Skill b-pipeline:b6-pr-review "<PR> --auto --light"` antes de seguir. El commit de sync suele ser chico; `--light` combina con el size-gate para no re-revisar full una rama ya aprobada.

## PASO 3: Resumen pre-merge

Presenta compacto:

```
PR #<N> «<titulo>»  →  master
Issues:       #<i1>, #<i2>...  (se cierran solos al mergear via "Closes #")
Branch:       <branch>          Worktree: <path o ninguno>
Mergeable:    <estado>          CI: <ok|fail|n/a>
b6-review:    presente (<fecha>) — <K blockers, M warnings>
Estrategia:   squash + delete-branch
```

## PASO 4: Aprobacion humana (OBLIGATORIO — no saltar)

Dos canales validos, en este orden:

**Canal asincrono — label `merge-approved`:** el usuario puede autorizar el merge desde GitHub web/movil agregando el label `merge-approved` al PR (GitHub bloquea aprobar el propio PR via review, por eso el canal es un label). Verificar label Y actor humano:

```bash
HAS_LABEL=$(gh pr view "$PR" --json labels --jq '[.labels[].name] | contains(["merge-approved"])')
if [ "$HAS_LABEL" = "true" ]; then
  # UN solo sweep del endpoint de events via bp_label_event (scripts/lib.sh):
  # emite "actor<TAB>created_at" del ultimo evento labeled (vacio si no hubo).
  PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cat "$HOME/.claude/b-pipeline.root" 2>/dev/null || ls -d "$HOME"/.claude/plugins/marketplaces/b-pipeline* 2>/dev/null | head -1)}"
  . "$PLUGIN_ROOT/scripts/lib.sh"
  APPROVAL=$(bp_label_event "$PR" merge-approved)
  ACTOR="${APPROVAL%%$'\t'*}"          # vacio si no hubo evento labeled
  LABELED_AT="${APPROVAL#*$'\t'}"
  case "$ACTOR" in *"[bot]"|"") HAS_LABEL=false ;; esac   # solo cuenta si lo puso un humano

  # Staleness: el label NO autoriza commits posteriores a su colocacion. Si hubo
  # push despues de poner el label, removerlo y caer al canal interactivo.
  LAST_PUSH=$(gh pr view "$PR" --json commits --jq '[.commits[].committedDate] | max')
  if [ "$HAS_LABEL" = "true" ] && [[ "$LAST_PUSH" > "$LABELED_AT" ]]; then
    gh pr edit "$PR" --remove-label merge-approved
    echo "merge-approved STALE (push posterior al label) — removido; se requiere re-aprobacion"
    HAS_LABEL=false
  fi
fi
```

Si `HAS_LABEL=true` → aprobacion concedida, seguir al PASO 5 sin preguntar (reportar "aprobado via label merge-approved por @$ACTOR"). **La aprobacion via label equivale a "Mergear y limpiar"** (default del pipeline): PASO 6 corre completo.

**Canal interactivo — `AskUserQuestion`:**

> ¿Mergear PR #<N> a master con squash y limpiar el worktree?

Opciones: **Mergear y limpiar** / **Solo mergear (conservar worktree)** / **Cancelar**.

**No mergear sin uno de los dos canales.** En headless sin label y sin canal de respuesta: agregar label `awaiting-approval` al PR, reportar "requiere aprobacion humana — agregar label merge-approved al PR o re-correr en sesion" y abortar.

## PASO 5: Merge + cierre del PR

Solo si el usuario aprobo:

```bash
# Un-draft si esta en draft (no se puede mergear un draft).
gh pr ready "$PR"
# Squash-merge: cierra el PR, borra la rama remota, y "Closes #<issue>" cierra el issue.
gh pr merge "$PR" --squash --delete-branch
```

Verificar (TODOS los issues, no solo el primero — un `Closes` mal formateado deja issues abiertos):

```bash
gh pr view "$PR" --json state,mergedAt --jq '{state,mergedAt}'   # state == MERGED
for i in $ISSUES; do
  S=$(gh issue view "$i" --json state --jq .state)
  [ "$S" = "CLOSED" ] || echo "WARN: issue #$i sigue $S — cerrar a mano (Closes mal formateado?)"
done
```

Si el merge falla (p.ej. requiere aprobacion de reviewer en branch protection), reporta el motivo exacto de `gh` y PARA — no forzar.

## PASO 6: Limpieza local

Solo si existe `$WORKTREE` y (el usuario eligio "Mergear y limpiar" O la aprobacion vino por label `merge-approved`):

```bash
# Apagar cualquier dev server del worktree que haya quedado vivo.
[ -f "$WORKTREE/.b7/dev-server.pid" ] && kill "$(cat "$WORKTREE/.b7/dev-server.pid")" 2>/dev/null || true

# PROHIBIDO remove --force con trabajo sin commitear. Verificar primero:
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cat "$HOME/.claude/b-pipeline.root" 2>/dev/null || ls -d "$HOME"/.claude/plugins/marketplaces/b-pipeline* 2>/dev/null | head -1)}"
bash "$PLUGIN_ROOT/skills/b1-add-worktree/scripts/assert-clean.sh" "$WORKTREE" --fix
```

- **exit 6** (quedo CODIGO sin commitear — no estaba en el merge) → **rescue branch**, nunca descartar:

  ```bash
  TS=$(date +%Y%m%d-%H%M)
  git -C "$WORKTREE" add -A
  git -C "$WORKTREE" commit -m "rescue: cambios sin commitear al cerrar PR #${PR}"
  # GATE DURO: si el push falla (sin red, SSO vencido, branch protegida) el rescate
  # NO esta a salvo — ABORTAR sin remover worktree ni borrar branch local.
  git -C "$WORKTREE" push origin "HEAD:rescue/${BRANCH##*/}-${TS}" || {
    echo "ABORT: push del rescue fallo — NO remover el worktree; reintentar push antes de limpiar"
    exit 1
  }
  echo "RESCUE: trabajo preservado en rama remota rescue/${BRANCH##*/}-${TS} — revisar si era parte del PR"
  ```

  Reportar la rama rescue de forma destacada y recien entonces continuar la limpieza (el trabajo ya esta a salvo en remoto).

- **exit 0** → seguir directo.
- **exit 7** → seguir, pero si los artefactos persistentes estan tracked/staged el `worktree remove` va a fallar y caer en el ABORT del fallback de abajo: es el comportamiento esperado — resolver a mano.

```bash
# Sacar el worktree. Sin --force primero; --force SOLO si el porcelain esta vacio
# (lo unico que queda son artefactos ignorados — seguro de borrar).
if ! git -C "$REPO_MAIN" worktree remove "$WORKTREE" 2>/dev/null; then
  if [ -z "$(git -C "$WORKTREE" status --porcelain)" ]; then
    git -C "$REPO_MAIN" worktree remove "$WORKTREE" --force
  else
    # Posible con exit 7 (artefactos tracked/staged que --fix no pudo excluir):
    # reportar pids/archivos y PARAR sin forzar.
    lsof +D "$WORKTREE" 2>/dev/null | head -10
    git -C "$WORKTREE" status --porcelain
    echo "ABORT: worktree no removible — resolver a mano"; exit 1
  fi
fi
git -C "$REPO_MAIN" worktree prune

# Borrar la rama local (la remota ya la borro --delete-branch).
git -C "$REPO_MAIN" branch -D "$BRANCH" 2>/dev/null || true

# Traer master mergeado al repo principal.
git -C "$REPO_MAIN" checkout master 2>/dev/null || true
git -C "$REPO_MAIN" pull --ff-only
```

## PASO 7: Labels y reporte final

```bash
# Los issues ya se cerraron por "Closes #". Sacar labels de estado intermedio
# de TODOS los issues del PR (los PRs cluster de b8 cierran varios).
for i in $ISSUES; do
  gh issue edit "$i" --remove-label in-review --remove-label in-progress \
    --remove-label auto-pr --remove-label auto-pr-bot 2>/dev/null || true
done
# Limpiar labels de aprobacion del PR si quedaron.
gh pr edit "$PR" --remove-label merge-approved --remove-label awaiting-approval 2>/dev/null || true

# Si algun issue cerrado es sub-issue de un epic, comentar progreso en el epic.
for i in $ISSUES; do
  EPIC=$(gh api "repos/{owner}/{repo}/issues/${i}/parent" --jq '.number' 2>/dev/null || true)
  if [ -n "$EPIC" ]; then
    DONE=$(gh api "repos/{owner}/{repo}/issues/${EPIC}" --jq '.sub_issues_summary | "\(.completed)/\(.total)"' 2>/dev/null || echo "?")
    gh issue comment "$EPIC" --body "✅ Sub-issue #${i} cerrado via PR #${PR}. Progreso del epic: ${DONE}." 2>/dev/null || true
  fi
done
```

Reporte (terminar SIEMPRE con la linea machine-readable):

```
=== PR #<N> CERRADO ===
Merge:        squash a master (<sha corto>)
Issues:       #<i1>, #<i2>... CLOSED
Rama remota:  borrada
Worktree:     removido (<path>) | conservado | n/a
Rama local:   borrada | n/a
master local: actualizado (pull --ff-only)
Rescue:       rescue/<branch>-<ts> | n/a

B9_MERGED pr=<N> sha=<sha-corto> issues=<i1,i2,...>
```

---

## Reglas

- **"tarea N" == issue #N.**
- **Squash por default** (historia limpia en master). Si el usuario pide `--merge` o `--rebase`, respetarlo.
- **No correr `pnpm build`/`check`** aca — eso ya paso en b7/BF. b9 solo cierra.

## Relacion con los otros skills b

- b9-close mergea PRs del pipeline (con `Closes #`). Un merge local manual sin PR queda fuera de este pipeline: hacerlo a mano.
