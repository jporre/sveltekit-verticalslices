#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash) — block direct `git worktree add` calls.
#
# Bundled with the b-pipeline plugin so the guard ships on every install (the old
# guard lived in the user's global ~/.claude/hooks and never traveled with the plugin).
#
# Worktrees MUST be created via b1-add-worktree/setup-worktree.sh, which:
#   - places the worktree under <parent>/worktrees/<slug>/
#   - symlinks every .env* from the parent
#   - picks a free dev port and writes dev.sh
#   - runs pnpm install
#   - installs the per-worktree pre-commit budget hook
#   - writes .b7/worktree-ready.json marker (guardrails.sh verify-worktree checks it)
#
# A direct `git worktree add` skips all of that and yields an unusable worktree.
#
# The matcher in hooks.json already restricts this to Bash tool calls, so there is
# no tool_name check here. setup-worktree.sh's own internal `git worktree add` runs
# in a subprocess invisible to PreToolUse, so the legitimate path keeps working.
#
# Safety stance: this OVER-blocks (it also fires when a command merely mentions the
# literal string, e.g. inside a grep pattern). For a guard, over-blocking is the safe
# failure mode — dodge a false positive by not putting the literal three-word string
# in the command, or by routing through setup-worktree.sh.

set -euo pipefail

# Auto-ubicacion: este script vive en <plugin-root>/hooks/, asi que la raiz es el
# directorio padre. No depende de CLAUDE_PLUGIN_ROOT ni de rutas de instalacion.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

input="$(cat)"

# Extract the command. The Bash matcher guarantees this hook only runs for Bash, so we
# only need tool_input.command. Prefer jq, then python3; if neither exists, scan the raw
# payload (still safe — it can only over-block).
if command -v jq >/dev/null 2>&1; then
  cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null || true)"
elif command -v python3 >/dev/null 2>&1; then
  cmd="$(printf '%s' "$input" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null || true)"
else
  cmd="$input"
fi

# Match `git worktree add` with a word boundary before `git`, tolerating extra whitespace.
if printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_/-])git[[:space:]]+worktree[[:space:]]+add'; then
  # Escape hatch: allow when the command is invoking setup-worktree.sh (its own internal
  # call, or a human pasting it inline).
  if printf '%s' "$cmd" | grep -q 'setup-worktree\.sh'; then
    exit 0
  fi
  cat >&2 <<MSG
BLOCKED: direct \`git worktree add\` is not allowed.

Use b1-add-worktree instead:
  bash "${PLUGIN_ROOT}/skills/b1-add-worktree/scripts/setup-worktree.sh" "<branch>" --headless

Reason: direct \`git worktree add\` creates a worktree without:
  - .env* symlinks (no secrets, dev server cannot connect to DB)
  - dev.sh with a free port (collides with parent repo on 6025)
  - pnpm install (no node_modules)
  - per-worktree pre-commit budget hook
  - .b7/worktree-ready.json marker (guardrails.sh verify-worktree will reject it)

This was the root cause of the b7 #171 broken-worktree bug. Do not bypass.
MSG
  exit 2
fi

exit 0
