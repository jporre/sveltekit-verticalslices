#!/usr/bin/env bash
set -euo pipefail

# epic-diff.sh <epic>
# Insumo para la fase epic-review de b10-ship: reconstruye lo mergeado del epic.
# Emite markdown a stdout con:
#   (a) tabla PR -> issue -> titulo + acceptance criteria (checkboxes del body)
#   (b) ruta(s) del plan doc referenciado en los bodies ("docs/plans/*.md")
#   (c) diff agregado de los squash merges (primer merge^..master, paths tocados)
# Correr desde el repo principal con master actualizado (git pull antes).

[ -n "${1:-}" ] || { echo "Usage: $0 <epic>" >&2; exit 2; }
EPIC="$1"
REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
MAX_DIFF_LINES_PER_FILE="${B10_EPIC_DIFF_MAX_LINES:-400}"

SUBS="$(gh api "repos/${REPO}/issues/${EPIC}/sub_issues" --paginate --jq '.[].number' 2>/dev/null | sort -un || true)"
[ -n "$SUBS" ] || { echo "ERROR: #$EPIC sin sub-issues" >&2; exit 3; }

echo "# Epic #$EPIC — insumo de revision de feature completo"
echo
echo "## Sub-issues y PRs mergeados"
echo

FIRST_SHA=""; ALL_PATHS=""
PRS_JSON="$(gh pr list --state merged --limit 200 --json number,title,body,mergeCommit,files,mergedAt)"

for n in $SUBS; do
  STATE="$(gh issue view "$n" --json state --jq .state)"
  TITLE="$(gh issue view "$n" --json title --jq .title)"
  PR_ROW="$(echo "$PRS_JSON" | jq -r --arg n "$n" \
    '[.[] | select(.body | test("[Cc]loses #\($n)([^0-9]|$)"))] | sort_by(.mergedAt) | (last // empty) | "\(.number)\t\(.mergeCommit.oid)\t\([.files[].path] | join(","))"')"
  if [ -n "$PR_ROW" ]; then
    PR_NUM="$(echo "$PR_ROW" | cut -f1)"
    SHA="$(echo "$PR_ROW" | cut -f2)"
    PATHS="$(echo "$PR_ROW" | cut -f3)"
    ALL_PATHS="${ALL_PATHS}${PATHS},"
    [ -z "$FIRST_SHA" ] && FIRST_SHA="$SHA" || {
      # quedarse con el merge MAS ANTIGUO como base del diff agregado
      if git merge-base --is-ancestor "$SHA" "$FIRST_SHA" 2>/dev/null; then FIRST_SHA="$SHA"; fi
    }
    echo "### #$n — $TITLE  [${STATE}] → PR #$PR_NUM (merge ${SHA:0:8})"
  else
    echo "### #$n — $TITLE  [${STATE}] → SIN PR MERGEADO"
  fi
  # acceptance criteria: checkboxes del body
  gh issue view "$n" --json body --jq .body | grep -E '^\s*- \[[ x]\]' | sed 's/^/  /' || echo "  (sin checkboxes)"
  echo
done

echo "## Plan(es) referenciado(s)"
echo
for n in $SUBS; do gh issue view "$n" --json body --jq .body; done \
  | grep -oE 'docs/plans/[a-zA-Z0-9_-]+\.md' | sort -u | sed 's/^/- /' || echo "- (ninguno encontrado)"
echo

if [ -z "$FIRST_SHA" ]; then
  echo "## Diff agregado: N/A (ningun PR mergeado todavia)"
  exit 0
fi

PATH_LIST="$(echo "$ALL_PATHS" | tr ',' '\n' | grep -v '^$' | sort -u)"
echo "## Diff agregado (${FIRST_SHA:0:8}^..master, $(echo "$PATH_LIST" | wc -l | tr -d ' ') archivos)"
echo
echo '```'
# Split SOLO por newline y sin glob expansion (paths con espacios o [/*).
OLDIFS=$IFS; IFS=$'\n'; set -f
git diff --stat "${FIRST_SHA}^..master" -- $PATH_LIST 2>/dev/null | tail -30
set +f; IFS=$OLDIFS
echo '```'
echo

echo "$PATH_LIST" | while read -r p; do
  [ -n "$p" ] || continue
  echo "### $p"
  echo '```diff'
  git diff "${FIRST_SHA}^..master" -- "$p" 2>/dev/null | head -"$MAX_DIFF_LINES_PER_FILE"
  LINES="$(git diff "${FIRST_SHA}^..master" -- "$p" 2>/dev/null | wc -l | tr -d ' ')"
  [ "$LINES" -gt "$MAX_DIFF_LINES_PER_FILE" ] && echo "... (truncado: $LINES lineas totales, cap $MAX_DIFF_LINES_PER_FILE)"
  echo '```'
  echo
done
