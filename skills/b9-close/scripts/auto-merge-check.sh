#!/usr/bin/env bash
# auto-merge-check — condiciones determinísticas del canal auto-merge de b9 (PASO 4).
#
# Single source of truth de las condiciones del canal: b9 SKILL las cita, no las
# re-implementa (antes: ~80 líneas de bash duplicadas en la prosa). Semántica
# EXACTA de la versión inline, default-deny: ante duda, DESCALIFICADO.
#
# Uso:
#   auto-merge-check <PR> <EPIC_N> <ISSUES...>     # ISSUES = "Closes #N" del PR (PASO 0)
#
# Emite (stdout, parseable):
#   DESCALIFICADO: <razón>          por cada condición fallida (las de condición 4/4b
#                                   con veto persistente también emiten AM_LABEL_HUMAN=1)
#   AM_RESULT=qualified|disqualified
#   AM_ACTOR=<login>                quien puso epic-auto-merge en el epic (condición 1)
#   AM_LABEL_HUMAN=1                aplicar needs-human-review a los issues del PR
#   AM_B6_STALE=1                   push posterior a la review — el orquestador aplica la
#                                   excepción de sync de artefactos del PASO 2 y re-invoca
#   SR=done-ok|done-fail|skipped-<r>|n/a|unknown
#   CI_DESC="CI ok"|"CI n/a (sin checks)"
#
# Exit codes (precedencia de fallas):
#   0  qualified — todas las condiciones pasaron
#   1  disqualified (catch-all: condiciones 1, 2+3, 4, 4b, ISSUES vacío)
#   2  skip este PR — CI PENDING o mergeable != MERGEABLE (el drain sigue con el próximo)
#   3  ABORT — CI FAILURE/ERROR (corta el drenaje; en desatendido nunca se pregunta)

set -uo pipefail

PR="${1:-}"
EPIC_N="${2:-}"
shift 2 2>/dev/null || true
ISSUES="${*:-}"

if [ -z "$PR" ] || [ -z "$EPIC_N" ]; then
  echo "usage: auto-merge-check <PR> <EPIC_N> <ISSUES...>" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"
. "$PLUGIN_ROOT/scripts/lib.sh"

DISQ=0
LABEL_HUMAN=0
STALE=0
SR="unknown"
CI_DESC="CI n/a (sin checks)"
ACTOR=""

disq() { echo "DESCALIFICADO: $1"; DISQ=1; }

# --- Condición 1: label epic-auto-merge en el EPIC, puesto por actor humano no-bot ---
HAS_AM=$(gh issue view "$EPIC_N" --json labels --jq '[.labels[].name] | contains(["epic-auto-merge"])' 2>/dev/null || echo false)
AM_EV=$(bp_label_event "$EPIC_N" epic-auto-merge 2>/dev/null || true)
ACTOR="${AM_EV%%$'\t'*}"
case "$ACTOR" in *"[bot]"|"") HAS_AM=false ;; esac
if [ "$HAS_AM" != "true" ]; then
  disq "epic #$EPIC_N sin label epic-auto-merge puesto por humano"
fi

# --- Condiciones 2+3: TODOS los issues del PR son sub-issues del epic, sin veto ---
# Excluir el closing_slice es responsabilidad de b10 (NUNCA pasa --auto-merge al
# despacharlo); el rechazo issue==epic de abajo es cinturón adicional.
if [ -z "$ISSUES" ]; then
  disq "PR #$PR sin 'Closes #N' parseable — pertenencia no verificable"
fi
for i in $ISSUES; do
  if [ "$i" = "$EPIC_N" ]; then disq "#$i ES el epic #$EPIC_N"; continue; fi
  P=$(gh api "repos/{owner}/{repo}/issues/${i}/parent" --jq '.number' 2>/dev/null || true)
  [ "$P" = "$EPIC_N" ] || disq "#$i no es sub-issue de #$EPIC_N (parent=${P:-ninguno})"
  NHR=$(gh issue view "$i" --json labels --jq '[.labels[].name] | contains(["needs-human-review"])' 2>/dev/null || echo false)
  [ "$NHR" = "true" ] && disq "#$i tiene needs-human-review — veto absoluto"
done

# --- Condición 4: review b6 con blockers=0, sin condición humana, y fresca ---
V="$(bp_b6_verdict "$PR" 2>/dev/null || true)"
BV_BLOCKERS="$(printf '%s' "$V" | grep -oE 'blockers=[0-9]+' | head -1 | cut -d= -f2)"
BV_HUMAN="$(printf '%s' "$V" | grep -oE 'human=[a-z]+' | head -1 | cut -d= -f2)"
if [ -z "$V" ] || [ -z "$BV_BLOCKERS" ]; then
  disq "sin review b6 publicada (exit 3) — el canal auto-merge exige veredicto"
elif [ "$BV_BLOCKERS" != "0" ]; then
  disq "review b6 con blockers=$BV_BLOCKERS"
elif [ "$BV_HUMAN" = "required" ]; then
  disq "b6 exige validación humana — el canal auto-merge no puede satisfacerla"
  LABEL_HUMAN=1
fi

B6_AT=$(gh pr view "$PR" --json comments,reviews \
  --jq '[(.comments[]?, .reviews[]?) | select(.body | test("b6:verdict=")) | (.createdAt // .submittedAt)] | max // empty' 2>/dev/null || true)
LAST_PUSH=$(gh pr view "$PR" --json commits --jq '[.commits[].committedDate] | max' 2>/dev/null || true)
if [ -n "$B6_AT" ] && [ -n "$LAST_PUSH" ] && [[ "$LAST_PUSH" > "$B6_AT" ]]; then
  # Push posterior a la review: el marker no cubre HEAD. El orquestador aplica la
  # excepción de sync de artefactos del PASO 2 (diff solo CHANGELOG/.b7/docs → re-invocar;
  # código → re-correr b6 --light y re-invocar). Default-deny hasta entonces.
  disq "push posterior a la review b6 — aplicar excepción de sync del PASO 2 y re-invocar"
  STALE=1
fi

# --- Condición 4b: marker screen-review de b7 en el PR ---
SR_LINE=$(gh pr view "$PR" --json comments \
  --jq '[.comments[].body | select(test("b7:screen-review="))] | last // empty' \
  | grep -oE 'b7:screen-review=[a-z-]+( screens=[0-9]+)?( result=[a-z]+)?( reason=[a-z-]+)?' | tail -1 || true)
case "$SR_LINE" in
  *"result=fail"*)
    SR="done-fail"
    disq "screen-review result=fail — un Veredicto: fail NUNCA se auto-mergea"
    LABEL_HUMAN=1
    ;;
  *"b7:screen-review=done"*"result=ok"*)
    SR="done-ok"
    ;;
  *"b7:screen-review=skipped"*)
    SR="skipped-$(printf '%s' "$SR_LINE" | grep -oE 'reason=[a-z-]+' | cut -d= -f2)"
    # skip declarado no bloquea (mismo criterio que el WARNING de b6)
    ;;
  *)
    # Marker ausente o =done sin result= (formato viejo): no verificable.
    # UI regex idéntica a la de pr-context.sh de b6; fallo de comando ≠ ausencia de UI.
    DIFF_FILES="$(gh pr diff "$PR" --name-only 2>/dev/null || true)"
    if [ -z "$DIFF_FILES" ] && ! gh pr diff "$PR" --name-only >/dev/null 2>&1; then
      disq "marker screen-review no verificable y gh pr diff falló — default-deny"
    elif printf '%s\n' "$DIFF_FILES" | grep -qE '(^|/)src/routes/|\.svelte$|\.remote\.ts$'; then
      disq "marker screen-review ausente/ilegible con UI en el diff — cae al canal humano"
    else
      SR="n/a"
    fi
    ;;
esac

# --- Condición 5: CI y mergeable (disposición propia: ABORT / skip) ---
CI_JSON=$(gh pr view "$PR" --json mergeable,statusCheckRollup \
  --jq '{mergeable, checks: [.statusCheckRollup[]? | {status: (.status // .state), conclusion: (.conclusion // .state)}]}' 2>/dev/null || echo "{}")
if printf '%s' "$CI_JSON" | jq -e '[.checks[]? | select((.conclusion // "") == "FAILURE" or (.conclusion // "") == "ERROR")] | length > 0' >/dev/null 2>&1; then
  echo "ABORT: CI FAILURE en PR #$PR — drenaje del epic #$EPIC_N cortado, notificar"
  exit 3
fi
if printf '%s' "$CI_JSON" | jq -e '[.checks[]? | select((.conclusion // "") == "" and ((.status // "") == "" or (.status // "") == "IN_PROGRESS" or (.status // "") == "QUEUED" or (.status // "") == "PENDING"))] | length > 0' >/dev/null 2>&1; then
  echo "SKIP: CI PENDING en PR #$PR — reintento en el próximo drain (CI PENDING nunca mergea)"
  exit 2
fi
MERGEABLE="$(printf '%s' "$CI_JSON" | jq -r '.mergeable // ""')"
if [ -n "$MERGEABLE" ] && [ "$MERGEABLE" != "MERGEABLE" ]; then
  echo "SKIP: PR #$PR mergeable=$MERGEABLE — queda para humano"
  exit 2
fi
CHECK_COUNT="$(printf '%s' "$CI_JSON" | jq -r '[.checks[]?] | length' 2>/dev/null || echo 0)"
[ "${CHECK_COUNT:-0}" -gt 0 ] && CI_DESC="CI ok"

# --- Resultado ---
if [ "$DISQ" = 1 ]; then
  echo "AM_RESULT=disqualified"
  [ "$LABEL_HUMAN" = 1 ] && echo "AM_LABEL_HUMAN=1"
  [ "$STALE" = 1 ] && echo "AM_B6_STALE=1"
  echo "SR=$SR"
  echo "CI_DESC=$CI_DESC"
  exit 1
fi

echo "AM_RESULT=qualified"
echo "AM_ACTOR=$ACTOR"
echo "SR=$SR"
echo "CI_DESC=$CI_DESC"
exit 0
