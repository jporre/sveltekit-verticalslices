#!/usr/bin/env bash
# pre-commit hook for b7's worktrees. Rejects commits that:
#   - touch denylisted paths (package.json, lockfiles, env files, infra/CI configs)
#   - exceed the file-count budget for the branch
#
# Install: AUTOMATIC. b1-add-worktree/setup-worktree.sh wires this in per-worktree
# via `git config --worktree core.hooksPath`, chaining to the repo's prior
# pre-commit (husky/lefthook/native) so lint-staged etc. still run. The main repo
# and sibling worktrees are never touched. No manual symlink step needed.
#
# Bypass (humans only): set B7_BUDGET_OVERRIDE=1 in the environment.

set -euo pipefail

# El hook se ejecuta vía `bash <ruta-en-el-plugin>` (wrapper generado por
# setup-worktree.sh), así que BASH_SOURCE apunta al plugin y lib.sh resuelve.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${CLAUDE_PLUGIN_ROOT:-$SCRIPT_DIR/../../..}/scripts/lib.sh"

BUDGET_FILES="${B7_BUDGET_FILES:-25}"

DENY_REGEX='^(package\.json|pnpm-lock\.yaml|package-lock\.json|yarn\.lock|\.env|\.env\..*|.*\.pem|.*\.key|secrets/.*|svelte\.config\.js|vite\.config\..*|infra/.*|\.github/workflows/.*|scripts/.*\.sh)$'

# Inspect staged changes only — that's what's about to be committed.
staged="$(git diff --cached --name-only)"

if [ -z "$staged" ]; then
  exit 0
fi

bad=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  if [[ "$f" =~ $DENY_REGEX ]]; then
    bad+="  $f"$'\n'
  fi
done <<< "$staged"

if [ -n "$bad" ]; then
  echo "b7 pre-commit-budget: refusing commit; denylisted paths staged:" >&2
  printf '%s' "$bad" >&2
  echo "Set B7_BUDGET_OVERRIDE=1 in env if you really mean it (humans only)." >&2
  if [ "${B7_BUDGET_OVERRIDE:-0}" != "1" ]; then
    exit 1
  fi
fi

# File-count cap across the whole branch (vs the base branch), not just this commit.
# Rama base resuelta vía bp_default_branch (origin/HEAD -> gh -> main|master local);
# si no resuelve, se salta el cap (mismo comportamiento que sin merge-base).
base=""
DEFAULT_BRANCH="$(bp_default_branch 2>/dev/null || true)"
if [ -n "$DEFAULT_BRANCH" ]; then
  base="$(git merge-base HEAD "$DEFAULT_BRANCH" 2>/dev/null || true)"
fi
if [ -n "$base" ]; then
  count="$(git diff --name-only "$base" -- | wc -l | tr -d ' ')"
  if [ "$count" -gt "$BUDGET_FILES" ]; then
    echo "b7 pre-commit-budget: branch touches $count files; cap is $BUDGET_FILES" >&2
    if [ "${B7_BUDGET_OVERRIDE:-0}" != "1" ]; then
      exit 1
    fi
  fi
fi

exit 0
