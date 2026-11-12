#!/usr/bin/env bash
# Regresión: los gates que corren ANTES del commit (ui-touched, screens-check,
# check-budget) deben ver archivos nuevos sin trackear; `git diff <base>` solo no
# los lista y un feature greenfield pasaba como "sin UI" y con budget 0.
# También: dod-check emite DOD/DOD_SUMMARY aunque assert-clean salga != 0.
#
# Uso: bash skills/b7-issue-to-pr/tests/untracked-diff.test.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARDRAILS="$SCRIPT_DIR/../scripts/guardrails.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fails=0
check() { # <mensaje> <condición ya evaluada: 0|1>
  if [ "$2" = 0 ]; then echo "ok   - $1"; else echo "FAIL - $1"; fails=$((fails + 1)); fi
}

wt="$TMP/repo"
git init -q -b main "$wt"
git -C "$wt" config user.email t@t.local
git -C "$wt" config user.name t
printf '/.b7/\n' > "$wt/.gitignore"
git -C "$wt" add -A && git -C "$wt" commit -qm init
git -C "$wt" checkout -q -b feat/1-x
mkdir -p "$wt/src/routes/foo" "$wt/.b7/review"
printf 'a\nb\nc\n' > "$wt/src/routes/foo/+page.svelte"   # nuevo, sin git add
cd "$wt"

out="$(bash "$GUARDRAILS" ui-touched "$wt" 2>&1)"
[ "$out" = "UI_TOUCHED=1" ]; check "ui-touched ve el .svelte sin trackear ($out)" $?

out="$(bash "$GUARDRAILS" check-budget "$wt" 2>&1)"
printf '%s' "$out" | grep -q 'files=1 added=3 '; check "check-budget cuenta archivo y líneas sin trackear ($out)" $?

printf '{"screens":[{"name":"Foo","route":"/foo"}]}\n' > "$wt/.b7/triage.json"
printf '{"reason":"lane-s-no-ui"}\n' > "$wt/.b7/review/SKIPPED.json"
rc=0; bash "$GUARDRAILS" screens-check "$wt" >/dev/null 2>&1 || rc=$?
[ "$rc" = 8 ]; check "screens-check rechaza skip lane-s-no-ui con UI sin trackear (exit $rc)" $?

rc=0; out="$(bash "$GUARDRAILS" dod-check "$wt" 1 none 2>/dev/null)" || rc=$?
printf '%s' "$out" | grep -q '^DOD .*7=fail' && printf '%s' "$out" | grep -q '^DOD_SUMMARY=fail' && [ "$rc" = 1 ]
check "dod-check reporta 7=fail con código sin commitear en vez de morir (exit $rc)" $?

[ "$fails" -eq 0 ] || { echo "$fails assertion(s) fallaron"; exit 1; }
echo "untracked-diff: OK"
