#!/usr/bin/env bash
# Regresión issue #59: run report con línea COST por script y abort_reason persistido.
#
# Antes: b7 paso 9 le pedía al LLM anexar `cost-report.py --brief` (0 de 252 run
# reports traían COST) y `publish-docs.sh aborted` no recibía razón — abort_reason
# quedaba vacío en state.json y en el reporte, y el último .tail moría con el
# worktree cuando b9 lo borraba.
#
# Uso: bash skills/b7-issue-to-pr/tests/publish-docs-run-report.test.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
G="$SCRIPT_DIR/../scripts/guardrails.sh"
PD="$SCRIPT_DIR/../scripts/publish-docs.sh"
TMP="$(mktemp -d)"; TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

# Aislado: HOME temporal (sin transcripts => COST n/a; nada toca ~/.claude real) y
# gh apagado (el sticky falla sin bloquear, como con gh caído).
export HOME="$TMP/home"; mkdir -p "$HOME/.claude/projects"
unset CLAUDE_PROJECT_DIR
mkdir -p "$TMP/bin"; printf '#!/bin/sh\nexit 1\n' > "$TMP/bin/gh"; chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"

fails=0
ok()   { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; fails=$((fails + 1)); }
state_val() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$wt/.b7/state.json" "$1"; }

# Worktree mínimo: repo git + .b7/state.json scaffold (init-state) + un .tail de iteración.
wt="$TMP/wt"; mkdir -p "$wt/.b7"
git -C "$wt" init -q
bash "$G" init-state 59 "$wt/.b7" >/dev/null
report="$TMP/runs/20260914T000000Z-issue-59.md"
bash "$PD" state-set run_report_path="$report" run_id=20260914T000000Z-issue-59 --worktree "$wt" >/dev/null
printf 'src/x.ts:1:1 Error TS2322: boom\n' > "$wt/.b7/iter-1-check.tail"

# 1. run-report solo: renderiza en run_report_path y termina con COST (n/a sin transcript).
rc=0; bash "$PD" run-report --worktree "$wt" >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then ok "run-report exit 0"; else fail "run-report exit $rc"; fi
if grep -q '^# b7 run ' "$report" 2>/dev/null; then ok "run report renderizado en run_report_path"; else fail "run report no renderizado en $report"; fi
if grep -qE '^COST (session=|n/a)' "$report" 2>/dev/null; then ok "run report termina con línea COST"; else fail "sin línea COST en el run report"; fi

# 2. aborted "<razón>": abort_reason en state.json y en el reporte; último .tail en last_log_tail.
rc=0; bash "$PD" aborted "budget: 26 archivos > 25" --worktree "$wt" >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then ok "aborted exit 0 (gh caído no bloquea)"; else fail "aborted exit $rc"; fi
if [ "$(state_val abort_reason)" = "budget: 26 archivos > 25" ]; then ok "abort_reason persistido en state.json"; else fail "abort_reason='$(state_val abort_reason)'"; fi
if [ "$(state_val status)" = aborted ]; then ok "status=aborted"; else fail "status='$(state_val status)'"; fi
if grep -q 'budget: 26 archivos > 25' "$report"; then ok "abort_reason en el run report"; else fail "abort_reason no aparece en el run report"; fi
if grep -q 'Error TS2322: boom' "$report"; then ok "último .tail copiado al run report (last_log_tail)"; else fail "el .tail no llegó al run report"; fi
if grep -qE '^COST (session=|n/a)' "$report"; then ok "aborted también deja la línea COST"; else fail "aborted sin línea COST"; fi

# 3. Contraprueba: aborted sin razón conserva la anterior (no la pisa con vacío).
bash "$PD" aborted --worktree "$wt" >/dev/null 2>&1 || true
if [ "$(state_val abort_reason)" = "budget: 26 archivos > 25" ]; then ok "aborted sin razón conserva abort_reason"; else fail "aborted sin razón pisó abort_reason='$(state_val abort_reason)'"; fi

[ "$fails" -eq 0 ] || { echo "$fails assertion(s) fallaron"; exit 1; }
echo "publish-docs-run-report: OK"
