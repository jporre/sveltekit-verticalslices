#!/usr/bin/env bash
# Entry-point shell de b8-swarm para los pasos no-LLM:
#   - parsear args
#   - preflight (kill-switch, lock, gh auth, working tree, backpressure)
#   - construir cola desde gh issue list
#   - imprimir B8_QUEUE / B8_RUN_REPORT / B8_LOCK como ultimas lineas parseables
#
# El loop de invocaciones a b7-issue-to-pr lo maneja Claude leyendo SKILL.md.
# Este script solo sirve para arrancar la ola con guardarrailes ya verificados.
#
# Usage:
#   run.sh [--max=N] [--issues=N1,N2,...] [--dry-run] [--on-error=continue|abort]
#          [--dwell=SECONDS] [--label=LABEL]
#
# Exit codes:
#   0  ok
#   2  bad args
#   12 gh auth fail
#   17 backpressure
#   18 working tree dirty
#   20 kill-switch
#   21 lock held
#   22 backlog vacio

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARDRAILS="$SCRIPT_DIR/guardrails.sh"

MAX="${B8_MAX_PER_WAVE:-5}"
ISSUES=""
MODE="wet"
ON_ERROR="continue"
DWELL="${B8_DWELL_SECONDS:-10}"
LABEL="${B8_DEFAULT_LABEL:-ready,auto-pr}"
THEME=""

for arg in "$@"; do
  case "$arg" in
    --max=*)        MAX="${arg#--max=}" ;;
    --issues=*)     ISSUES="${arg#--issues=}" ;;
    --theme=*)      THEME="${arg#--theme=}" ;;
    --dry-run)      MODE="dry-run" ;;
    --wet)          MODE="wet" ;;
    --on-error=*)   ON_ERROR="${arg#--on-error=}" ;;
    --dwell=*)      DWELL="${arg#--dwell=}" ;;
    --no-screens)   : ;;  # consumido por el LLM driver, no afecta la cola
    --label=*)      LABEL="${arg#--label=}" ;;
    --*)
      echo "run.sh: unknown flag: $arg" >&2
      exit 2
      ;;
    *)
      echo "run.sh: extra positional arg: $arg" >&2
      exit 2
      ;;
  esac
done

case "$ON_ERROR" in
  continue|abort) ;;
  *) echo "run.sh: --on-error must be continue|abort, got: $ON_ERROR" >&2; exit 2 ;;
esac

if ! "$GUARDRAILS" preflight; then
  exit $?
fi

LOCK_PATH="$("$GUARDRAILS" acquire-lock)"
trap '"$GUARDRAILS" release-lock' EXIT

STATE_DIR="$("$GUARDRAILS" state-dir)"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
RUN_DIR="$STATE_DIR/b8-runs"
mkdir -p "$RUN_DIR"
RUN_REPORT="$RUN_DIR/${STAMP}.md"

# Construir cola
if [ -n "$ISSUES" ]; then
  QUEUE="$(echo "$ISSUES" | tr ',' '\n' | sed 's/^ *//;s/ *$//' | grep -v '^$' | head -n "$MAX")"
else
  QUEUE="$("$GUARDRAILS" backlog "$LABEL" "$MAX")"
fi

if [ -z "$QUEUE" ]; then
  echo "b8: backlog vacio (label=$LABEL)" >&2
  cat > "$RUN_REPORT" <<EOF
# b8 swarm ${STAMP}

- mode: ${MODE}
- max: ${MAX}
- label: ${LABEL}
- on-error: ${ON_ERROR}
- dwell: ${DWELL}s
- started: $(date -u +%FT%TZ)
- status: aborted (empty backlog)
EOF
  exit 22
fi

QUEUE_COUNT="$(echo "$QUEUE" | wc -l | tr -d ' ')"

cat > "$RUN_REPORT" <<EOF
# b8 swarm ${STAMP} — cluster → 1 PR

- mode: ${MODE}
- max: ${MAX}
- label: ${LABEL}
- theme: ${THEME:-'(swarm/<ids>)'}
- on-error: ${ON_ERROR}
- started: $(date -u +%FT%TZ)
- cluster (${QUEUE_COUNT}):
$(echo "$QUEUE" | sed 's/^/  - #/')

## Resultados por issue

_(el LLM va llenando esto via record-result.sh)_

EOF

# Salida parseable para el LLM driver
echo "B8_LOCK=${LOCK_PATH}"
echo "B8_RUN_REPORT=${RUN_REPORT}"
echo "B8_MODE=${MODE}"
echo "B8_ON_ERROR=${ON_ERROR}"
echo "B8_THEME=${THEME}"
echo "B8_QUEUE_COUNT=${QUEUE_COUNT}"
echo "B8_QUEUE_BEGIN"
echo "$QUEUE"
echo "B8_QUEUE_END"
