#!/usr/bin/env bash
set -euo pipefail

# epic-link.sh <epic> <issue> [<issue> ...]
# One-shot: vincula issues como sub-issues NATIVOS de GitHub bajo el epic y
# le pone el label "epic" al tracking issue. Idempotente: los ya vinculados
# se saltan con nota. Desde ahí, sub_issues_summary del epic muestra progreso
# nativo (completed/total/percent_completed) en la UI de GitHub.

[ $# -ge 2 ] || { echo "Usage: $0 <epic> <issue> [<issue> ...]" >&2; exit 2; }

EPIC="$1"; shift
REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"

# Sin add-label "epic" acá: en el path b0 create-epic.sh ya lo pone al crear, y en
# el path --from=<issue> el contrato es NO tocar labels del issue origen.

# Sub-issues ya vinculados (por número), para idempotencia.
EXISTING="$(gh api "repos/${REPO}/issues/${EPIC}/sub_issues" --paginate --jq '.[].number' 2>/dev/null | tr '\n' ' ' || true)"

OK=0; SKIP=0; FAIL=0
for n in "$@"; do
  case " $EXISTING " in *" $n "*)
    echo "skip: #$n ya es sub-issue de #$EPIC"; SKIP=$((SKIP+1)); continue ;;
  esac
  ID="$(gh api "repos/${REPO}/issues/${n}" --jq .id)"
  if gh api -X POST "repos/${REPO}/issues/${EPIC}/sub_issues" -F sub_issue_id="$ID" >/dev/null 2>&1; then
    echo "ok:   #$n vinculado a #$EPIC"; OK=$((OK+1))
  else
    echo "FAIL: #$n no se pudo vincular (¿permisos del token? ¿ya tiene otro parent?)" >&2; FAIL=$((FAIL+1))
  fi
done

echo "EPIC_LINK epic=$EPIC ok=$OK skip=$SKIP fail=$FAIL"
[ "$FAIL" -eq 0 ]
