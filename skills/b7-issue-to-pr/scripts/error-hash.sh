#!/usr/bin/env bash
# error-hash.sh — firma estable de las primeras N líneas de error de un log.
#
# Si el hash de la iteración N coincide con el de la iteración N-1, el bot
# está estancado: aborta para no quemar iteraciones repitiendo el mismo intento.
#
# Normaliza paths absolutos, números de línea y timestamps para que el hash
# sea estable entre intentos del mismo bug.
#
# Usage: error-hash.sh <log-path> [n-errors]
#   n-errors default: 3

set -euo pipefail

LOG="${1:-}"
N="${2:-3}"

if [ -z "$LOG" ] || [ ! -f "$LOG" ]; then
  echo "error-hash.sh: missing or invalid log path: $LOG" >&2
  exit 2
fi

PATTERNS='Error|error TS[0-9]+|✘|✗|FAIL |Cannot find|is not assignable|SyntaxError|TypeError'

grep -E "$PATTERNS" "$LOG" \
  | head -n "$N" \
  | sed -E 's|/[A-Za-z0-9_./-]+/|/|g; s|:[0-9]+:[0-9]+|:L:C|g; s|:[0-9]+|:L|g; s|[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.Z-]+||g; s|0x[0-9a-fA-F]+|0xADDR|g' \
  | shasum -a 256 \
  | awk '{print $1}'
