#!/usr/bin/env bash
# diff-summary.sh — resumen compacto del diff de un worktree vs su base.
#
# Output diseñado para que el LLM lo cite como contexto sin tener que leer
# `git diff` completo (que en features grandes son miles de líneas).
#
# Genera:
#   <worktree>/.b7/diff-stat.txt    — git diff --stat (tamaño por archivo)
#   <worktree>/.b7/diff-files.txt   — git diff --name-status (A/M/D)
#   <worktree>/.b7/diff-summary.md  — markdown human-readable agrupado por capa FSD
#
# Usage: diff-summary.sh <worktree>

set -euo pipefail

WT="${1:-}"
if [ -z "$WT" ] || [ ! -d "$WT" ]; then
  echo "diff-summary.sh: missing or invalid worktree: $WT" >&2
  exit 2
fi

cd "$WT"
mkdir -p .b7

BASE="$(git merge-base HEAD master 2>/dev/null || echo)"
if [ -z "$BASE" ]; then
  echo "diff-summary.sh: no merge-base with master" >&2
  exit 3
fi

git diff --stat "$BASE" -- > .b7/diff-stat.txt
git diff --name-status "$BASE" -- > .b7/diff-files.txt

# Agrupado por capa FSD para que el reviewer humano (y el LLM) ubique cambios.
{
  echo "# Resumen de cambios vs base"
  echo
  echo "Base: \`$(git rev-parse --short "$BASE")\`  ·  Branch: \`$(git rev-parse --abbrev-ref HEAD)\`"
  echo

  for layer_label in \
    "UI (componentes y pantallas):src/lib/features/.*/ui/" \
    "Datos (remote functions):src/lib/features/.*/data\.remote\." \
    "Server (services / page.server):src/lib/features/.*/server/" \
    "Schemas (validación):src/lib/features/.*/schemas\." \
    "Types:src/lib/features/.*/types\." \
    "Rutas (+page wrappers):src/routes/" \
    "DB (drizzle schema):src/lib/server/db/" \
    "Componentes compartidos:src/lib/components/" \
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
