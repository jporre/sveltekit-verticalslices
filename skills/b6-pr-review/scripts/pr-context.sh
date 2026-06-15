#!/usr/bin/env bash
# pr-context.sh — Recolecta todo el contexto de un PR para revision
# Uso: bash pr-context.sh <PR_NUMBER>
set -euo pipefail

PR="${1:?Uso: pr-context.sh <PR_NUMBER>}"

echo "=== PR_META ==="
gh pr view "$PR" --json number,title,body,author,state,baseRefName,headRefName,additions,deletions,changedFiles,labels,createdAt,url

echo ""
echo "=== PR_FILES ==="
gh pr diff "$PR" --name-only

echo ""
echo "=== PR_DIFF_STAT ==="
gh pr diff "$PR" --stat 2>/dev/null || echo "(stat no disponible)"

echo ""
echo "=== PR_COMMITS ==="
gh pr view "$PR" --json commits --jq '.commits[] | "\(.oid[0:7]) \(.messageHeadline)"'

echo ""
echo "=== PR_DIFF ==="
gh pr diff "$PR"

echo ""
echo "=== PR_CHECKS ==="
gh pr checks "$PR" 2>/dev/null || echo "(sin checks)"

echo ""
echo "=== CLASSIFY_FILES ==="
# Clasifica archivos cambiados por tipo para guiar la revision
gh pr diff "$PR" --name-only | while read -r f; do
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
