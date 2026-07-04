#!/usr/bin/env bash
# diff-summary.sh — resumen compacto del diff de un worktree vs su base.
#
# Output diseñado para que el LLM lo cite como contexto sin tener que leer
# `git diff` completo (que en features grandes son miles de líneas).
#
# Genera:
#   <worktree>/.b7/diff-stat.txt    — git diff --stat (tamaño por archivo)
#   <worktree>/.b7/diff-files.txt   — git diff --name-status (A/M/D)
#   <worktree>/.b7/diff-summary.md  — markdown human-readable agrupado por tipo de archivo
#
# Usage: diff-summary.sh <worktree>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${CLAUDE_PLUGIN_ROOT:-$SCRIPT_DIR/../../..}/scripts/lib.sh"

WT="${1:-}"
if [ -z "$WT" ] || [ ! -d "$WT" ]; then
  echo "diff-summary.sh: missing or invalid worktree: $WT" >&2
  exit 2
fi

cd "$WT"
mkdir -p .b7

# Rama base resuelta via bp_default_branch (nunca asumir master).
DEFAULT_BRANCH="$(bp_default_branch 2>/dev/null || true)"
if [ -z "$DEFAULT_BRANCH" ]; then
  echo "diff-summary.sh: no se pudo resolver la rama default (bp_default_branch)" >&2
  exit 3
fi
BASE="$(git merge-base HEAD "$DEFAULT_BRANCH" 2>/dev/null || echo)"
if [ -z "$BASE" ]; then
  echo "diff-summary.sh: no merge-base with $DEFAULT_BRANCH" >&2
  exit 3
fi

git diff --stat "$BASE" -- > .b7/diff-stat.txt
git diff --name-status "$BASE" -- > .b7/diff-files.txt

# Agrupado por tipo de archivo (features colocados en src/routes) para ubicar cambios.
{
  echo "# Resumen de cambios vs base"
  echo
  echo "Base: \`$(git rev-parse --short "$BASE")\`  ·  Branch: \`$(git rev-parse --abbrev-ref HEAD)\`"
  echo

  for layer_label in \
    "Datos (remote functions):src/routes/.*\.remote\." \
    "Server (page.server / *.server):src/routes/.*\.server\." \
    "Schemas (validación):src/routes/.*/schemas\." \
    "Types:src/routes/.*-types\." \
    "Pantallas y componentes:src/routes/.*\.svelte$" \
    "DB (drizzle schema):src/lib/server/db/" \
    "Compartido (\$lib):src/lib/" \
    "Tests:\.(test|spec)\." \
    "Docs:\.(md|html)$" ; do
    label="${layer_label%%:*}"
    pattern="${layer_label#*:}"
    matches="$(awk -v p="$pattern" '$2 ~ p { print "- `" $2 "` (" $1 ")" }' .b7/diff-files.txt || true)"
    if [ -n "$matches" ]; then
      echo "## $label"
      echo "$matches"
      echo
    fi
  done

  echo "## Stat"
  echo
  echo '```'
  cat .b7/diff-stat.txt
  echo '```'
} > .b7/diff-summary.md

echo "diff-summary: wrote .b7/diff-summary.md ($(wc -l < .b7/diff-summary.md) lines)"
