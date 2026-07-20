---
name: b9-close
description: 'Cierre de un PR ya revisado: mergea a la rama default con aprobación humana, cierra sus issues y limpia el worktree. Usar cuando pidan "cerrar/mergear el PR N", "finalizar el issue N" (ya implementado), o "limpiar el worktree". PASO 4 del flujo b — corre después de b7 (implementación) y b6-pr-review (review); no implementa ni revisa.'
allowed-tools: Bash, Read, AskUserQuestion, Skill, Agent
model: sonnet
---

## Argumentos recibidos

```text
$ARGUMENTS
```

Acepta: número de issue (`121`), número de PR (`#170` o `pr 170`), nombre de branch (`feat/121-...`), o nada (autodetecta desde el worktree actual). El primer token decide el modo de resolución.

Flags (después del target): `--auto-merge --epic=<N>` — siempre en par; activan el canal auto-merge de PASO 4 (drains desatendidos de epic, los pasa b10). `--auto-merge` sin `--epic=<N>` es inválido: abortar de inmediato con `ABORT: --auto-merge requiere --epic=<N>`. Los gates de PASO 1 y PASO 2 corren igual con o sin flags.

---

# b9-close — mergear PR + cerrar issue + limpiar worktree

Cierre del flujo b. El feature ya fue implementado por `b7-issue-to-pr` y revisado por `b6-pr-review`. Este skill **no** reimplementa ni hace review profundo: **gatea** sobre que la revisión pasó, mergea con **aprobación humana**, y deja el árbol limpio (PR cerrado, issue cerrado, worktree y branches borrados).

**Filosofía:** ningún PR del bot va a la rama default sin autorización humana — por PR (label `merge-approved` o respuesta interactiva) o delegada a nivel de epic vía label `epic-auto-merge` (canal auto-merge de PASO 4, re-verificado en cada corrida).

---

## PASO 0: Resolver PR + branch + worktree + issue

Desde el repo principal. Resolver según el primer token de `$ARGUMENTS`:

```bash
REPO_MAIN="$(git rev-parse --show-toplevel)"
ARG="<primer-token-de-$ARGUMENTS>"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cat "$HOME/.claude/b-pipeline.root" 2>/dev/null || ls -d "$HOME"/.claude/plugins/marketplaces/b-pipeline* 2>/dev/null | head -1)}"
. "$PLUGIN_ROOT/scripts/lib.sh"

# Modo issue (número pelado o "issue N"): buscar el PR que lo cierra.
# Usar bp_find_pr, NUNCA gh search a mano: un falso positivo mergea el PR equivocado.
PR=$(bp_find_pr "$ARG" open)
# Modo PR (#N / "pr N"): usar directo.   Modo branch: gh pr list --head <branch>.
# Sin arg: PR=$(gh pr list --head "$(git rev-parse --abbrev-ref HEAD)" --json number --jq '.[0].number')

# Idempotencia: si no hay PR abierto, buscar uno YA MERGEADO (re-run tras crash a
# mitad de limpieza). Si aparece y está MERGED, saltar directo a PASO 6/7.
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

- `mergeable != "MERGEABLE"` (conflictos) → PARA, reporta los conflictos. No los resuelvas automático.
- Checks de CI en `FAILURE` → reporta y pregunta si igual seguir (no bloqueante por sí solo; el proyecto puede no tener CI obligatoria). Con `--auto-merge` NUNCA preguntar: cortar el drenaje y notificar (regla del canal auto-merge, PASO 4).

## PASO 1.5: Sincronizar el worktree (todo commiteado y pusheado ANTES del merge)

Solo si existe `$WORKTREE`. El squash-merge debe incluir TODO el trabajo; cambios sueltos o commits sin push se pierden silenciosamente.

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cat "$HOME/.claude/b-pipeline.root" 2>/dev/null || ls -d "$HOME"/.claude/plugins/marketplaces/b-pipeline* 2>/dev/null | head -1)}"
bash "$PLUGIN_ROOT/skills/b1-add-worktree/scripts/assert-clean.sh" "$WORKTREE" --fix
```

- **exit 6** (código sin commitear) → invocar `Skill b-pipeline:b3-git-commit` desde el worktree para commitearlo (b3 garantiza terminar limpio), luego seguir.
- **exit 7** (artefactos persistentes) → reportar, no bloquea.

```bash
# Push incondicional (idempotente, no-op si ya está al día). No condicionar a
# `git log origin/B..B`: si el ref remoto local está stale/pruned, ese check da 0
# y los commits sin push se perderían del squash.
git -C "$WORKTREE" push origin "$BRANCH"
```

**Si este paso commiteó o pusheó algo nuevo, registrarlo** (`SYNCED=1`): el review existente NO cubre esos commits — ver el check de frescura en PASO 2.

## PASO 2: Gate de revisión (¿corrió b6?)

```bash
# Lector único del marker (cubre comentarios Y reviews). NO parsear el marker a mano.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cat "$HOME/.claude/b-pipeline.root" 2>/dev/null || ls -d "$HOME"/.claude/plugins/marketplaces/b-pipeline* 2>/dev/null | head -1)}"
. "$PLUGIN_ROOT/scripts/lib.sh"
bp_b6_verdict "$PR"
# exit 0 -> imprime: B6_VERDICT verdict=.. blockers=N warnings=M pr=P
# exit 3 -> sin marker (no hubo review)
```

- **exit 0** → review presente. Del `B6_VERDICT`: si `blockers > 0` sin resolver, PARA y reporta — devuelve al usuario / a b7, no parchea acá.
- **exit 3** → no hubo review. **Ofrece correrlo ahora** (`Skill b-pipeline:b6-pr-review` con el número de PR). No mergees sin review.
- **Frescura**: si PASO 1.5 commiteó/pusheó commits nuevos (`SYNCED=1`), el review existente no los cubre — re-correr `Skill b-pipeline:b6-pr-review "<PR> --auto --light"` antes de seguir. El commit de sync suele ser chico; `--light` combina con el size-gate para no re-revisar full una rama ya aprobada.

## PASO 3: Resumen pre-merge

Presenta compacto:

```
PR #<N> «<titulo>»  →  <rama-default>
Issues:       #<i1>, #<i2>...  (se cierran solos al mergear vía "Closes #")
Branch:       <branch>          Worktree: <path o ninguno>
Mergeable:    <estado>          CI: <ok|fail|n/a>
b6-review:    presente (<fecha>) — <K blockers, M warnings>
Estrategia:   squash + delete-branch
```

Con `--auto-merge` emitir el mismo resumen igual (queda como registro del drain) y seguir de inmediato al PASO 4 sin esperar respuesta.

## PASO 4: Aprobación humana (OBLIGATORIO — no saltar)

Tres canales válidos, en este orden:

**Canal asíncrono — label `merge-approved`:** el usuario puede autorizar el merge desde GitHub web/móvil agregando el label `merge-approved` al PR (GitHub bloquea aprobar el propio PR vía review, por eso el canal es un label). Verificar label Y actor humano:

```bash
HAS_LABEL=$(gh pr view "$PR" --json labels --jq '[.labels[].name] | contains(["merge-approved"])')
if [ "$HAS_LABEL" = "true" ]; then
  # UN solo sweep del endpoint de events vía bp_label_event (scripts/lib.sh):
  # emite "actor<TAB>created_at" del último evento labeled (vacío si no hubo).
  PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cat "$HOME/.claude/b-pipeline.root" 2>/dev/null || ls -d "$HOME"/.claude/plugins/marketplaces/b-pipeline* 2>/dev/null | head -1)}"
  . "$PLUGIN_ROOT/scripts/lib.sh"
  APPROVAL=$(bp_label_event "$PR" merge-approved)
  ACTOR="${APPROVAL%%$'\t'*}"          # vacío si no hubo evento labeled
  LABELED_AT="${APPROVAL#*$'\t'}"
  case "$ACTOR" in *"[bot]"|"") HAS_LABEL=false ;; esac   # solo cuenta si lo puso un humano

  # Staleness: el label NO autoriza commits posteriores a su colocación. Si hubo
  # push después de poner el label, removerlo y caer al canal interactivo.
  LAST_PUSH=$(gh pr view "$PR" --json commits --jq '[.commits[].committedDate] | max')
  if [ "$HAS_LABEL" = "true" ] && [[ "$LAST_PUSH" > "$LABELED_AT" ]]; then
    gh pr edit "$PR" --remove-label merge-approved
    echo "merge-approved STALE (push posterior al label) — removido; se requiere re-aprobación"
    HAS_LABEL=false
  fi
fi
```

Si `HAS_LABEL=true` → aprobación concedida, seguir al PASO 5 sin preguntar (reportar "aprobado vía label merge-approved por @$ACTOR"). **La aprobación vía label equivale a "Mergear y limpiar"** (default del pipeline): PASO 6 corre completo.

**Canal auto-merge — flags `--auto-merge --epic=<N>`:** solo para drains desatendidos de un epic (los despacha b10). El flag es input NO confiable: b9 verifica TODO por sí mismo, en cada corrida (el label de confianza es removible en cualquier momento). Default-deny: este canal cubre SOLO el happy path — cualquier condición fallida impide el auto-merge; la disposición exacta (skip, corte de drenaje o caída a canales humanos) la fija la precedencia de fallas al final del canal. Seis condiciones, TODAS obligatorias:

```bash
EPIC_N="<N-del-flag-epic>"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cat "$HOME/.claude/b-pipeline.root" 2>/dev/null || ls -d "$HOME"/.claude/plugins/marketplaces/b-pipeline* 2>/dev/null | head -1)}"
. "$PLUGIN_ROOT/scripts/lib.sh"
AM_OK=true

# 1. Confianza: label epic-auto-merge en el EPIC, puesto por actor humano no-bot.
HAS_AM=$(gh issue view "$EPIC_N" --json labels --jq '[.labels[].name] | contains(["epic-auto-merge"])')
AM_EV=$(bp_label_event "$EPIC_N" epic-auto-merge)
AM_ACTOR="${AM_EV%%$'\t'*}"
case "$AM_ACTOR" in *"[bot]"|"") HAS_AM=false ;; esac
[ "$HAS_AM" = "true" ] || { echo "DESCALIFICADO: epic #$EPIC_N sin label epic-auto-merge puesto por humano"; AM_OK=false; }

# 2+3. Pertenencia la verifica b9, NO el caller: TODOS los issues del PR (ISSUES de
#      PASO 0) deben ser sub-issues de EPIC_N — uno solo fuera descalifica el PR
#      entero (cubre PRs cluster de b8 con varios "Closes #"). Excluir el
#      closing_slice es responsabilidad de b10 (tiene el snapshot y NUNCA pasa
#      --auto-merge al despacharlo); el rechazo issue==epic de abajo es cinturón
#      adicional, no la garantía. Ninguno puede tener needs-human-review (veto
#      absoluto: seguridad, FIX_SIN_TEST — estado persistente que deja b7).
# Guard: con ISSUES vacío (PR sin "Closes #N" parseable) el loop no itera y las
# condiciones 2+3 pasarían de forma vacua — descalificar explícito ANTES del loop.
[ -z "$ISSUES" ] && { echo "DESCALIFICADO: PR #$PR sin 'Closes #N' parseable — pertenencia no verificable"; AM_OK=false; }
for i in $ISSUES; do
  [ "$i" = "$EPIC_N" ] && { echo "DESCALIFICADO: #$i ES el epic #$EPIC_N"; AM_OK=false; continue; }
  P=$(gh api "repos/{owner}/{repo}/issues/${i}/parent" --jq '.number' 2>/dev/null || true)
  [ "$P" = "$EPIC_N" ] || { echo "DESCALIFICADO: #$i no es sub-issue de #$EPIC_N (parent=${P:-ninguno})"; AM_OK=false; }
  NHR=$(gh issue view "$i" --json labels --jq '[.labels[].name] | contains(["needs-human-review"])')
  [ "$NHR" = "true" ] && { echo "DESCALIFICADO: #$i tiene needs-human-review — veto absoluto"; AM_OK=false; }
done

# 4. Frescura de la review: timestamp del comentario/review que porta el marker b6
#    vs último push del PR (mismo patrón de staleness que merge-approved).
B6_AT=$(gh pr view "$PR" --json comments,reviews \
  --jq '[(.comments[]?, .reviews[]?) | select(.body | test("b6:verdict=")) | (.createdAt // .submittedAt)] | max // empty')
LAST_PUSH=$(gh pr view "$PR" --json commits --jq '[.commits[].committedDate] | max')
```

- **Condición 4 — review con blockers=0 y fresca:** `bp_b6_verdict "$PR"` (corrido en PASO 2) con `blockers=0`; exit 3 (sin review) o `blockers>0` → DESCALIFICADO. Si `[[ "$LAST_PUSH" > "$B6_AT" ]]` (hubo push después de la review — el marker no cubre HEAD) → NO abortar: re-correr `Skill b-pipeline:b6-pr-review "<PR> --auto --light"` (mismo patrón de frescura de PASO 2), re-leer `bp_b6_verdict` y `B6_AT`; si persisten blockers>0 → DESCALIFICADO.
- **Condición 5 — CI y mergeable:**

  ```bash
  gh pr view "$PR" --json mergeable,statusCheckRollup \
    --jq '{mergeable, checks: [.statusCheckRollup[]? | {status: (.status // .state), conclusion: (.conclusion // .state)}]}'
  ```

  - Algún check con conclusion `FAILURE`/`ERROR` → **cortar el drenaje**: `echo "ABORT: CI FAILURE en PR #$PR — drenaje del epic #$EPIC_N cortado, notificar"; exit 1`. En desatendido NUNCA preguntar.
  - Algún check sin concluir (`IN_PROGRESS`/`QUEUED`/`PENDING`/conclusion vacía) → saltar este PR (reintento en el próximo drain). CI PENDING nunca mergea: skip, no merge optimista.
  - `mergeable != "MERGEABLE"` → saltar este PR (queda para humano).
  - Sin checks (lista vacía) → condición cumplida (proyecto sin CI obligatoria).
- **Condición 6 — serial:** NUNCA paralelizar b9; un merge a la vez a la rama default. b10 despacha los PRs del drain uno a uno.

Si `AM_OK=true` y las seis condiciones pasaron → aprobación concedida. Reportar "aprobado vía canal auto-merge: label epic-auto-merge en epic #$EPIC_N por @$AM_ACTOR". **Equivale a "Mergear y limpiar"**: PASO 5 y PASO 6 corren completos (rescue branch y prohibición de `--force` intactos). Después del merge de PASO 5, postear el audit trail en el PR:

```bash
gh pr comment "$PR" --body "auto-merged bajo epic-auto-merge #${EPIC_N} (b6 blockers=0, CI ok)"
```

**Precedencia de fallas:** las fallas con disposición propia de la condición 5 van primero y NO caen al catch-all — CI FAILURE corta el drenaje (ABORT); CI PENDING y `mergeable != "MERGEABLE"` saltan ESTE PR: reportar el skip y terminar sin merge (el PR queda para los canales humanos; el drain sigue con el próximo). Catch-all para el resto (guard de ISSUES vacío, condiciones 1-4): reportar cada línea DESCALIFICADO y caer al canal interactivo.

**Canal interactivo — `AskUserQuestion`:**

> ¿Mergear PR #<N> a la rama default con squash y limpiar el worktree?

Opciones: **Mergear y limpiar** / **Solo mergear (conservar worktree)** / **Cancelar**.

**No mergear sin uno de los tres canales.** En headless sin label `merge-approved`, sin canal auto-merge satisfecho y sin canal de respuesta: agregar label `awaiting-approval` al PR, reportar "requiere aprobación humana — agregar label merge-approved al PR o re-correr en sesión" y abortar. Excepciones bajo `--auto-merge`: CI FAILURE no deja `awaiting-approval` — corta el drenaje con ABORT (condición 5); los saltos por CI PENDING o `mergeable != "MERGEABLE"` tampoco la dejan — terminan con reporte de skip (precedencia de fallas arriba).

## PASO 5: Merge + cierre del PR

Solo con aprobación concedida por alguno de los tres canales del PASO 4:

```bash
# Un-draft si está en draft (no se puede mergear un draft).
gh pr ready "$PR"
# Squash-merge: cierra el PR, borra la rama remota, y "Closes #<issue>" cierra el issue.
gh pr merge "$PR" --squash --delete-branch
```

Verificar (TODOS los issues, no solo el primero — un `Closes` mal formateado deja issues abiertos):

```bash
gh pr view "$PR" --json state,mergedAt --jq '{state,mergedAt}'   # state == MERGED
for i in $ISSUES; do
  S=$(gh issue view "$i" --json state --jq .state)
  [ "$S" = "CLOSED" ] || echo "WARN: issue #$i sigue $S — cerrar a mano (¿Closes mal formateado?)"
done
```

Si el merge falla (p.ej. requiere aprobación de reviewer en branch protection), reporta el motivo exacto de `gh` y PARA — no forzar.

## PASO 6: Limpieza local

Solo si existe `$WORKTREE` y (el usuario eligió "Mergear y limpiar" O la aprobación vino por label `merge-approved` O por el canal auto-merge):

```bash
# Apagar cualquier dev server del worktree que haya quedado vivo.
[ -f "$WORKTREE/.b7/dev-server.pid" ] && kill "$(cat "$WORKTREE/.b7/dev-server.pid")" 2>/dev/null || true

# PROHIBIDO remove --force con trabajo sin commitear. Verificar primero:
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cat "$HOME/.claude/b-pipeline.root" 2>/dev/null || ls -d "$HOME"/.claude/plugins/marketplaces/b-pipeline* 2>/dev/null | head -1)}"
bash "$PLUGIN_ROOT/skills/b1-add-worktree/scripts/assert-clean.sh" "$WORKTREE" --fix
```

- **exit 6** (quedó CÓDIGO sin commitear — no estaba en el merge) → **rescue branch**, nunca descartar:

  ```bash
  TS=$(date +%Y%m%d-%H%M)
  git -C "$WORKTREE" add -A
  git -C "$WORKTREE" commit -m "rescue: cambios sin commitear al cerrar PR #${PR}"
  # GATE DURO: si el push falla (sin red, SSO vencido, branch protegida) el rescate
  # NO está a salvo — ABORTAR sin remover worktree ni borrar branch local.
  git -C "$WORKTREE" push origin "HEAD:rescue/${BRANCH##*/}-${TS}" || {
    echo "ABORT: push del rescue falló — NO remover el worktree; reintentar push antes de limpiar"
    exit 1
  }
  echo "RESCUE: trabajo preservado en rama remota rescue/${BRANCH##*/}-${TS} — revisar si era parte del PR"
  ```

  Reportar la rama rescue de forma destacada y recién entonces continuar la limpieza (el trabajo ya está a salvo en remoto).

- **exit 0** → seguir directo.
- **exit 7** → seguir, pero si los artefactos persistentes están tracked/staged el `worktree remove` va a fallar y caer en el ABORT del fallback de abajo: es el comportamiento esperado — resolver a mano.

```bash
# Sacar el worktree. Sin --force primero; --force SOLO si el porcelain está vacío
# (lo único que queda son artefactos ignorados — seguro de borrar).
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

# Borrar la rama local (la remota ya la borró --delete-branch).
git -C "$REPO_MAIN" branch -D "$BRANCH" 2>/dev/null || true

# Traer la rama default mergeada al repo principal (bp_default_branch viene de
# scripts/lib.sh, ya sourceado en PASO 0/2).
DEFAULT_BRANCH="$(bp_default_branch)" || echo "WARN: rama default no resuelta — saltar sync local"
if [ -n "$DEFAULT_BRANCH" ]; then
  git -C "$REPO_MAIN" checkout "$DEFAULT_BRANCH" 2>/dev/null || true
  git -C "$REPO_MAIN" pull --ff-only
fi
```

## PASO 7: Labels y reporte final

```bash
# Los issues ya se cerraron por "Closes #". Sacar labels de estado intermedio
# de TODOS los issues del PR (los PRs cluster de b8 cierran varios).
for i in $ISSUES; do
  gh issue edit "$i" --remove-label in-review --remove-label in-progress \
    --remove-label auto-pr --remove-label auto-pr-bot 2>/dev/null || true
done
# Limpiar labels de aprobación del PR si quedaron.
gh pr edit "$PR" --remove-label merge-approved --remove-label awaiting-approval 2>/dev/null || true

# Si algún issue cerrado es sub-issue de un epic, comentar progreso en el epic.
for i in $ISSUES; do
  EPIC=$(gh api "repos/{owner}/{repo}/issues/${i}/parent" --jq '.number' 2>/dev/null || true)
  if [ -n "$EPIC" ]; then
    DONE=$(gh api "repos/{owner}/{repo}/issues/${EPIC}" --jq '.sub_issues_summary | "\(.completed)/\(.total)"' 2>/dev/null || echo "?")
    gh issue comment "$EPIC" --body "✅ Sub-issue #${i} cerrado vía PR #${PR}. Progreso del epic: ${DONE}." 2>/dev/null || true
  fi
done
```

Reporte (terminar SIEMPRE con la línea machine-readable):

```
=== PR #<N> CERRADO ===
Merge:        squash a la rama default (<sha corto>)
Issues:       #<i1>, #<i2>... CLOSED
Rama remota:  borrada
Worktree:     removido (<path>) | conservado | n/a
Rama local:   borrada | n/a
rama default local: actualizada (pull --ff-only)
Rescue:       rescue/<branch>-<ts> | n/a

B9_MERGED pr=<N> sha=<sha-corto> issues=<i1,i2,...>
```

---

## Reglas

- **"tarea N" == issue #N.**
- **Squash por default** (historia limpia en la rama default). Si el usuario pide `--merge` o `--rebase`, respetarlo.
- **No correr `pnpm build`/`check`** acá — eso ya pasó en b7/BF. b9 solo cierra.

## Relación con los otros skills b

- b9-close mergea PRs del pipeline (con `Closes #`). Un merge local manual sin PR queda fuera de este pipeline: hacerlo a mano.
