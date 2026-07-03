#!/usr/bin/env bash
# pr-context.sh — Recolecta todo el contexto de un PR para revision
# Uso: bash pr-context.sh <PR_NUMBER> [--light]
#   --light: fuerza modo light (modo efectivo = flag O size-gate)
set -euo pipefail

PR="${1:?Uso: pr-context.sh <PR_NUMBER> [--light]}"
FORCE_LIGHT=0
[ "${2:-}" = "--light" ] && FORCE_LIGHT=1

# Meta una sola vez: sirve para PR_META y para el size-gate (adds+dels/files).
META=$(gh pr view "$PR" --json number,title,body,author,state,baseRefName,headRefName,additions,deletions,changedFiles,labels,createdAt,url)
ADD=$(echo "$META" | jq -r '.additions // 0')
DEL=$(echo "$META" | jq -r '.deletions // 0')
NFILES=$(echo "$META" | jq -r '.changedFiles // 0')

# Size-gate: light si el PR es chico (adds+dels<300 && files<5), sino full.
# Modo efectivo = flag --light O gate.
MODE=full
if [ "$FORCE_LIGHT" = 1 ] || { [ $((ADD + DEL)) -lt 300 ] && [ "$NFILES" -lt 5 ]; }; then
  MODE=light
fi

# Lista de archivos y diff completo: una sola llamada a cada modo del comando (2 en total).
FILES=$(gh pr diff "$PR" --name-only)
DIFF=$(gh pr diff "$PR")

echo "=== REVIEW_MODE ==="
echo "$MODE"

echo ""
echo "=== PR_META ==="
echo "$META"

echo ""
echo "=== PR_FILES ==="
echo "$FILES"

# En light el size-gate ya acota el PR; el stat per-archivo es redundante.
if [ "$MODE" != light ]; then
  echo ""
  echo "=== PR_DIFF_STAT ==="
  echo "$DIFF" | git apply --stat 2>/dev/null || echo "(stat no disponible)"
fi

echo ""
echo "=== PR_COMMITS ==="
gh pr view "$PR" --json commits --jq '.commits[] | "\(.oid[0:7]) \(.messageHeadline)"'

echo ""
echo "=== PR_DIFF ==="
echo "$DIFF"

echo ""
echo "=== PR_CHECKS ==="
gh pr checks "$PR" 2>/dev/null || echo "(sin checks)"

echo ""
echo "=== CLASSIFY_FILES ==="
# Clasifica archivos cambiados por tipo para guiar la revision
echo "$FILES" | while read -r f; do
  [ -z "$f" ] && continue
  case "$f" in
    *+page.server.ts)      echo "LOAD_SERVER: $f" ;;
    *+page.ts)             echo "LOAD_UNIVERSAL: $f" ;;
    *+layout.server.ts)    echo "LAYOUT_SERVER: $f" ;;
    *+layout.ts)           echo "LAYOUT_UNIVERSAL: $f" ;;
    *+server.ts)           echo "API_ENDPOINT: $f" ;;
    *.remote.ts)           echo "REMOTE_FUNCTION: $f" ;;
    *.server.ts)           echo "SERVER_ONLY: $f" ;;
    *.svelte)              echo "SVELTE_COMPONENT: $f" ;;
    *schemas.ts|*schema.ts) echo "SCHEMA: $f" ;;
    *.ts)                  echo "TYPESCRIPT: $f" ;;
    *.css)                 echo "STYLE: $f" ;;
    *.md)                  echo "DOCS: $f" ;;
    *)                     echo "OTHER: $f" ;;
  esac
done

echo ""
echo "=== FIX_REGRESSION_GATE ==="
# Gate de regresion: un PR fix/* debe tocar un test. Si headRef es fix/* y ningun
# archivo cambiado matchea \.(test|spec)\. -> FIX_WITHOUT_TEST=true. B6 Area 2 emite
# WARNING pidiendo el test o una justificacion explicita.
HEAD_REF=$(echo "$META" | jq -r '.headRefName // ""')
if printf '%s\n' "$HEAD_REF" | grep -qE '^fix/' && ! printf '%s\n' "$FILES" | grep -qE '\.(test|spec)\.'; then
  echo "FIX_WITHOUT_TEST=true"
else
  echo "FIX_WITHOUT_TEST=false"
fi

echo ""
echo "=== CHANGED_SYMBOLS ==="
# Simbolos exportados tocados por el diff (best-effort, JS/TS). Reusa $DIFF.
# NEW = agregado sin version eliminada; MODIFIED = firma tocada (linea +/-) o
# cuerpo tocado (contexto del hunk header — cubre modificaciones body-only).
EXPORT_RE='export[[:space:]]+(async[[:space:]]+)?(function|const)[[:space:]]+[A-Za-z_$][A-Za-z0-9_$]*'
HUNK_RE='(function|const)[[:space:]]+[A-Za-z_$][A-Za-z0-9_$]*'
sym_names() { # $1: regex; stdin: lineas; stdout: nombres de simbolo unicos ordenados
  grep -Eo "$1" | sed -E 's/.*(function|const)[[:space:]]+//' | sort -u
}
ADDED=$(echo "$DIFF" | grep -E '^\+' | sym_names "$EXPORT_RE" || true)
REMOVED=$(echo "$DIFF" | grep -E '^[-]' | sym_names "$EXPORT_RE" || true)
HUNK_CTX=$(echo "$DIFF" | grep -E '^@@ ' | sed -E 's/^@@[^@]*@@ ?//' | sym_names "$HUNK_RE" || true)
NEW=$(comm -23 <(echo "$ADDED") <(echo "$REMOVED") | grep -v '^$' || true)
SIG_MOD=$(comm -12 <(echo "$ADDED") <(echo "$REMOVED") | grep -v '^$' || true)
MODIFIED=$(printf '%s\n%s\n' "$SIG_MOD" "$HUNK_CTX" | sort -u | comm -23 - <(echo "$NEW") | grep -v '^$' || true)
if [ -n "$NEW" ]; then echo "$NEW" | sed 's/^/NEW: /'; fi
if [ -n "$MODIFIED" ]; then echo "$MODIFIED" | sed 's/^/MODIFIED: /'; fi
if [ -z "$NEW$MODIFIED" ]; then echo "(sin simbolos exportados detectados)"; fi

# CODEGRAPH: ok solo si el probe de b1 (informativo, nunca gate) responde ok;
# cualquier otro estado (stale/missing/broken o sin probe) => absent.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROBE="$SCRIPT_DIR/../../b1-add-worktree/scripts/codegraph-probe.sh"
CG_STATUS=absent
if [ -f "$PROBE" ]; then
  st=$(bash "$PROBE" 2>/dev/null | tail -1 | sed -n 's/^CODEGRAPH_STATUS=\([a-z]*\).*/\1/p' || true)
  if [ "${st:-}" = "ok" ]; then CG_STATUS=ok; fi
fi
echo "CODEGRAPH: $CG_STATUS"
