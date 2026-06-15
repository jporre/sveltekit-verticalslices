#!/usr/bin/env bash
# log-filter.sh — extracción semántica de líneas relevantes de un log.
#
# Reemplaza el patrón anti-token "tail -n 80" que arrastra ruido (dots de
# progreso, "Loaded vite config", etc.). Devuelve solo líneas con señal de
# error + 2 de contexto antes/después.
#
# Usage: log-filter.sh <log-path> [max-lines]
#   max-lines default: 60

set -euo pipefail

LOG="${1:-}"
MAX="${2:-60}"

if [ -z "$LOG" ] || [ ! -f "$LOG" ]; then
  echo "log-filter.sh: missing or invalid log path: $LOG" >&2
  exit 2
fi

# Patrones de error de svelte-check, vitest, eslint, tsc, pnpm.
PATTERNS='Error|error TS[0-9]+|✘|✗|FAIL |fail:|Cannot find|is not assignable|has no exported|Unexpected token|SyntaxError|TypeError|throws|expected.*received|Missing|undefined .* property'

# Si no hay matches, devolver las últimas N líneas como fallback (ej: timeout sin mensaje claro).
if ! grep -qE "$PATTERNS" "$LOG"; then
  tail -n "$MAX" "$LOG"
  exit 0
fi

# Extraer matches con contexto, dedupe por línea, cortar al máximo.
grep -nE "$PATTERNS" -A 2 -B 1 "$LOG" \
  | awk '!seen[$0]++' \
  | tail -n "$MAX"
