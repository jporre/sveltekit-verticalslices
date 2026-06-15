#!/usr/bin/env bash
# Anexa una fila de resultado al reporte de b8 para un issue dado.
#
# Usage:
#   record-result.sh <run-report> <issue> <status> [pr-url] [note]
#
# status: ok | failed:<code> | skipped:<reason>

set -euo pipefail

REPORT="${1:-}"
ISSUE="${2:-}"
STATUS="${3:-}"
PR_URL="${4:-}"
NOTE="${5:-}"

if [ -z "$REPORT" ] || [ -z "$ISSUE" ] || [ -z "$STATUS" ]; then
  echo "Usage: $0 <run-report> <issue> <status> [pr-url] [note]" >&2
  exit 2
fi

if [ ! -f "$REPORT" ]; then
  echo "record-result: report not found: $REPORT" >&2
  exit 2
fi

TS="$(date -u +%FT%TZ)"
LINE="- [${TS}] #${ISSUE} → ${STATUS}"
[ -n "$PR_URL" ] && LINE="${LINE} · ${PR_URL}"
[ -n "$NOTE" ] && LINE="${LINE} · ${NOTE}"

echo "$LINE" >> "$REPORT"
echo "$LINE"
