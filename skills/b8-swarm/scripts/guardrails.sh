#!/usr/bin/env bash
# b8-swarm guardrails: kill-switch, lock, state-dir, backlog query.
#
# Subcommands:
#   state-dir                              -> echo absolute path al state-dir
#   preflight                              -> kill-switch + lock libre + gh auth + tree limpio
#   acquire-lock                           -> crear lock, escribir pid; echo path
#   release-lock                           -> borrar lock
#   backlog <label> <max>                  -> echo lista de issue numbers (uno por linea)
#   backpressure                           -> exit 0 si hay cuota, exit 17 si lleno
#   killswitch                             -> exit 0 si no hay STOP, exit 20 si lo hay
#
# Exit codes:
#   0  ok
#   2  bad usage
#   12 gh auth fail
#   17 backpressure
#   18 working tree dirty
#   19 env-check fail (runtimes/MCP/gh-token/DB) — delegado a b7 guardrails env-check
#   20 kill-switch active
#   21 lock held by another b8

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Plugin root derivado desde la ubicacion del script (.../skills/b8-swarm/scripts).
# Portable: mismo patron que b10 run.sh. Necesario para invocar el env-check de b7.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"
B7_GUARD="$PLUGIN_ROOT/skills/b7-issue-to-pr/scripts/guardrails.sh"

state_dir() {
  local d="${CLAUDE_PROJECT_DIR:-}"
  if [ -z "$d" ]; then
    # Fallback: ~/.claude/projects/<slug-of-cwd>
    local slug
    slug="$(pwd | sed 's|/|-|g')"
    d="$HOME/.claude/projects/${slug}"
  fi
  mkdir -p "$d"
  echo "$d"
}

cmd_killswitch() {
  local sd; sd="$(state_dir)"
  if [ -f "$sd/b8.STOP" ]; then
    echo "b8: kill-switch active at $sd/b8.STOP" >&2
    return 20
  fi
  if [ -f "$sd/b7.STOP" ]; then
    echo "b8: b7 kill-switch active at $sd/b7.STOP (b7 wont start)" >&2
    return 20
  fi
  return 0
}

cmd_acquire_lock() {
  local sd; sd="$(state_dir)"
  local lock="$sd/b8.lock"
  if [ -f "$lock" ]; then
    local oldpid
    oldpid="$(cat "$lock" 2>/dev/null || echo)"
    if [ -n "$oldpid" ] && kill -0 "$oldpid" 2>/dev/null; then
      echo "b8: another swarm is running (pid $oldpid)" >&2
      return 21
    fi
    # stale lock
    rm -f "$lock"
  fi
  echo "$$" > "$lock"
  echo "$lock"
}

cmd_release_lock() {
  local sd; sd="$(state_dir)"
  rm -f "$sd/b8.lock"
}

cmd_backpressure() {
  local cap="${B7_MAX_OPEN_PRS:-3}"
  local label="${B7_BOT_LABEL:-auto-pr-bot}"
  local open
  open="$(gh pr list --state open --label "$label" --json number --jq 'length' 2>/dev/null || echo 0)"
  if [ "$open" -ge "$cap" ]; then
    echo "b8: backpressure ($open open auto-pr-bot PRs >= cap $cap)" >&2
    return 17
  fi
  return 0
}

cmd_preflight() {
  cmd_killswitch || return $?
  if ! gh auth status >/dev/null 2>&1; then
    echo "b8: gh auth status failed" >&2
    return 12
  fi
  # working tree del repo padre limpio
  if [ -n "$(git status --porcelain 2>/dev/null || true)" ]; then
    echo "b8: working tree is dirty" >&2
    return 18
  fi
  # Env-check inicial (con cache MCP; SIN B_ENV_SKIP_MCP — este es el preflight, no el
  # loop por-issue). Detecta blockers de runtime/MCP/gh/DB antes de arrancar el swarm.
  bash "$B7_GUARD" env-check || return $?
  cmd_backpressure || return $?
  return 0
}

cmd_backlog() {
  local label="${1:-ready,auto-pr}"
  local max="${2:-5}"
  # Query oldest-first (by number ascending), filtrar opt-outs localmente.
  gh issue list \
    --label "$label" \
    --state open \
    --limit 50 \
    --json number,labels,body \
    --jq '.[] | select(
      ([.labels[].name] | index("do-not-automate") | not)
      and ((.body // "") | test("<!-- *no-auto-pr *-->") | not)
    ) | .number' \
    | sort -n \
    | head -n "$max"
}

case "${1:-}" in
  state-dir)       state_dir ;;
  killswitch)      cmd_killswitch ;;
  acquire-lock)    cmd_acquire_lock ;;
  release-lock)    cmd_release_lock ;;
  backpressure)    cmd_backpressure ;;
  preflight)       cmd_preflight ;;
  backlog)         shift; cmd_backlog "$@" ;;
  *)
    echo "Usage: $0 {state-dir|killswitch|acquire-lock|release-lock|backpressure|preflight|backlog <label> <max>}" >&2
    exit 2
    ;;
esac
