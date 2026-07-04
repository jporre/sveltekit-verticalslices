#!/usr/bin/env bash
# Entry point for b7-issue-to-pr.
#
# This script is the *non-LLM* glue: it parses args, runs preflight, acquires the lock,
# and shells out to the rest of the pipeline. The actual triage / build / commit / PR
# steps are LLM-driven and live in SKILL.md (which Claude follows via the Skill tool).
#
# This script is safe to call from cron / launchd / `claude -p`. It is NOT what runs
# inside a Claude session — Claude reads SKILL.md and invokes the chained skills itself.
# Use this script when you want to do the boring shell-level checks before handing off
# to Claude.
#
# Usage: run.sh <issue> [--dry-run|--wet] [--max-iterations=N] [--budget-files=N] [--no-pr]
# Exit codes: 0 ok, 2 bad args, 10..29 guardrail failures (see guardrails.sh)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARDRAILS="$SCRIPT_DIR/guardrails.sh"

ISSUE=""
# Default matches SKILL.md (--wet). This script never mutates GitHub itself — it runs
# preflight/lock/scaffolding and hands off to the LLM phase, which reads `mode` (from
# state.json / B7_MODE) to decide whether to open a PR. So `mode` here is advisory.
MODE="wet"
MAX_ITER=6
BUDGET_FILES=25
NO_PR=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) MODE="dry-run" ;;
    --wet)     MODE="wet" ;;
    --no-pr)   NO_PR=1 ;;
    --max-iterations=*) MAX_ITER="${arg#--max-iterations=}" ;;
    --budget-files=*)   BUDGET_FILES="${arg#--budget-files=}" ;;
    --*)
      echo "run.sh: unknown flag: $arg" >&2
      exit 2
      ;;
    *)
      if [ -z "$ISSUE" ]; then
        ISSUE="$arg"
      else
        echo "run.sh: extra positional arg: $arg" >&2
        exit 2
      fi
      ;;
  esac
done

if [ -z "$ISSUE" ]; then
  echo "Usage: $0 <issue> [--dry-run|--wet] [--max-iterations=N] [--budget-files=N] [--no-pr]" >&2
  exit 2
fi

export B7_BUDGET_FILES="$BUDGET_FILES"
export B7_MAX_ITER="$MAX_ITER"
export B7_NO_PR="$NO_PR"
export B7_MODE="$MODE"
export B7_ISSUE="$ISSUE"

# 1. Preflight. NO envolver en `if !`: la negacion resetea $? (el bug historico
# hacia `exit $?` = exit 0 tras el echo, y los callers headless veian exito).
"$GUARDRAILS" preflight "$ISSUE" || {
  rc=$?
  echo "run.sh: preflight failed (rc=$rc); refusing to start" >&2
  exit "$rc"
}

# 2. Lock. Owner = $PPID (el proceso que invoco este script: cron/launchd/orquestador),
# que sobrevive al handoff. SIN trap EXIT a proposito: el lock debe sobrevivir a run.sh
# porque la fase LLM lo retiene; se libera con `guardrails.sh release-lock` al cierre
# del run (exito, abort o bail — ver SKILL.md, Manejo de errores).
LOCK_PATH="$("$GUARDRAILS" acquire-lock "$PPID" "$ISSUE")"
# Con B7_PARALLEL=1 acquire-lock emite `B7_LOCK_FILE=<path>` (shard por issue);
# sin flag imprime el path pelado — el strip es no-op.
LOCK_PATH="${LOCK_PATH#B7_LOCK_FILE=}"

STATE_DIR="$("$GUARDRAILS" state-dir)"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
RUN_ID="${STAMP}-issue-${ISSUE}"
RUN_DIR="$STATE_DIR/b7-runs"
mkdir -p "$RUN_DIR"
RUN_REPORT="$RUN_DIR/${RUN_ID}.md"

# Pre-handoff: cachear issue, snapshot de contexto, init state.json.
# Estos artefactos viven en $STATE_DIR/scratch/<RUN_ID>/ hasta que el LLM los
# mueva al worktree (después de b1-add-worktree). Vivirlos primero acá nos
# permite no re-pegarle a `gh issue view` desde cada sub-skill.
SCRATCH_DIR="$STATE_DIR/scratch/$RUN_ID"
mkdir -p "$SCRATCH_DIR"

"$GUARDRAILS" cache-issue "$ISSUE" "$SCRATCH_DIR" || true
"$GUARDRAILS" context-snapshot "$SCRATCH_DIR" || true
"$GUARDRAILS" init-state "$ISSUE" "$SCRATCH_DIR" || true

# Inyectar mode/run_id/run_report/lock_file en el state.json recién creado.
# lock_file persistido: toda ruta terminal de la fase LLM libera ESE shard
# (`release-lock "$(jq -r '.lock_file // empty' .b7/state.json)"` — ver SKILL.md).
python3 - "$SCRATCH_DIR/state.json" "$MODE" "$RUN_ID" "$RUN_REPORT" "$MAX_ITER" "$BUDGET_FILES" "$LOCK_PATH" <<'PY'
import json, sys
p, mode, run_id, report, max_iter, budget_files, lock_file = sys.argv[1:8]
with open(p) as f: d = json.load(f)
d["mode"] = mode
d["run_id"] = run_id
d["run_report_path"] = report
d["max_iter"] = int(max_iter)
d["budget_files"] = int(budget_files)
d["lock_file"] = lock_file
with open(p, "w") as f: json.dump(d, f, ensure_ascii=False, indent=2)
PY

cat > "$RUN_REPORT" <<EOF
# b7 run ${RUN_ID}

- issue: #${ISSUE}
- mode: ${MODE}
- started: $(date -u +%FT%TZ)
- max-iterations: ${MAX_ITER}
- budget-files: ${BUDGET_FILES}
- no-pr: ${NO_PR}
- status: started
- scratch: ${SCRATCH_DIR}

EOF

export B7_SCRATCH_DIR="$SCRATCH_DIR"
export B7_RUN_ID="$RUN_ID"
export B7_RUN_REPORT="$RUN_REPORT"

echo "run.sh: preflight OK; lock=${LOCK_PATH}; report=${RUN_REPORT}; scratch=${SCRATCH_DIR}"
echo "RUN_REPORT=${RUN_REPORT}"
echo "RUN_ID=${RUN_ID}"
echo "SCRATCH_DIR=${SCRATCH_DIR}"

# After this point, the LLM-driven part of the skill takes over. Claude reads SKILL.md
# and invokes b1-triage-issue, b1-add-worktree --headless, b2-build-feature, etc.
# The lock persists past this script ON PURPOSE: every terminal path of the run
# (success, abort, bail) must call `guardrails.sh release-lock`. Staleness fallback:
# a lock untouched for B7_LOCK_STALE_SECS (2h) is reclaimed by the next preflight.
