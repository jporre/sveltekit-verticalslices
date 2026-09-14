#!/usr/bin/env bash
# Regresión issue #59: state_dir con el slug de Claude Code y único por repo.
#
# Antes: slug con sed 's|/|-|g' (conservaba '_' y '.') y show-toplevel del cwd —
# cada worktree estrenaba un dir en ~/.claude/projects (361 dirs basura) y ningún
# state dir coincidía con el de los transcripts (Claude Code / cost-report.py usan
# [^A-Za-z0-9] -> '-'). Ahora bp_state_dir (scripts/lib.sh) resuelve al repo
# principal vía git-common-dir y usa el mismo slug.
#
# Uso: bash skills/b7-issue-to-pr/tests/state-dir-slug.test.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
G7="$PLUGIN_ROOT/skills/b7-issue-to-pr/scripts/guardrails.sh"
G8="$PLUGIN_ROOT/skills/b8-swarm/scripts/guardrails.sh"
PROBE="$PLUGIN_ROOT/skills/b1-add-worktree/scripts/codegraph-probe.sh"
TMP="$(mktemp -d)"; TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

# Aislado: HOME temporal (nada toca ~/.claude real) y gh apagado (sin red).
export HOME="$TMP/home"; mkdir -p "$HOME/.claude/projects"
unset CLAUDE_PROJECT_DIR
mkdir -p "$TMP/bin"; printf '#!/bin/sh\nexit 1\n' > "$TMP/bin/gh"; chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"

fails=0
ok()   { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; fails=$((fails + 1)); }

# Repo principal con '_' y '.' en el path + worktree bajo worktrees/x.
main="$TMP/a/b_c.d"
mkdir -p "$main"
git -C "$main" init -q
git -C "$main" config user.email t@t.local
git -C "$main" config user.name t
git -C "$main" commit -q --allow-empty -m init
wt="$main/worktrees/x"
git -C "$main" worktree add -q "$wt" -b x

# Slug de referencia: la función slug() de cost-report.py (= Claude Code).
expected="$HOME/.claude/projects/$(python3 - "$PLUGIN_ROOT/scripts/cost-report.py" "$main" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("cr", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(m.slug(sys.argv[2]))
PY
)"

from_main="$(cd "$main" && bash "$G7" state-dir)"
from_wt="$(cd "$wt" && bash "$G7" state-dir)"
if [ "$from_main" = "$expected" ]; then ok "b7 state-dir desde el repo = slug de cost-report.py ($(basename "$expected"))"; else fail "b7 state-dir desde el repo: '$from_main' != '$expected'"; fi
if [ "$from_wt" = "$expected" ]; then ok "b7 state-dir desde el worktree resuelve al repo principal"; else fail "b7 state-dir desde el worktree: '$from_wt' != '$expected'"; fi
case "$(basename "$from_main")" in
  *_*|*.*) fail "el slug conserva '_' o '.': $from_main" ;;
  *)       ok "slug sin '_' ni '.'" ;;
esac

# b8 (y b10, que llama a b8 state-dir) usan el mismo cálculo.
from_b8="$(cd "$wt" && bash "$G8" state-dir)"
if [ "$from_b8" = "$expected" ]; then ok "b8 state-dir = b7 state-dir"; else fail "b8 state-dir: '$from_b8' != '$expected'"; fi

# CLAUDE_PROJECT_DIR apuntando a un worktree (hooks) también resuelve al padre.
from_env="$(cd "$TMP" && CLAUDE_PROJECT_DIR="$wt" bash "$G7" state-dir)"
if [ "$from_env" = "$expected" ]; then ok "CLAUDE_PROJECT_DIR=<worktree> resuelve al repo principal"; else fail "CLAUDE_PROJECT_DIR=<worktree>: '$from_env'"; fi

# Criterio: invocar desde el worktree NO estrena dirs en ~/.claude/projects
# (guardrails state-dir + context-snapshot, que llama al probe, + el probe directo).
before="$(ls "$HOME/.claude/projects" | sort)"
( cd "$wt" && bash "$G7" state-dir >/dev/null; bash "$G7" context-snapshot "$TMP/snap" >/dev/null 2>&1; bash "$PROBE" "$wt" >/dev/null )
after="$(ls "$HOME/.claude/projects" | sort)"
if [ "$before" = "$after" ]; then
  ok "guardrails + codegraph-probe desde el worktree: 0 dirs nuevos"
else
  fail "dirs nuevos en ~/.claude/projects: $(comm -13 <(echo "$before") <(echo "$after") | tr '\n' ' ')"
fi

# El cache del probe sigue siendo por root (#37): main y worktree no comparten archivo.
c_wt="$(ls "$expected"/codegraph-probe-*.txt 2>/dev/null | wc -l | tr -d ' ')"
bash "$PROBE" "$main" >/dev/null
c_both="$(ls "$expected"/codegraph-probe-*.txt 2>/dev/null | wc -l | tr -d ' ')"
if [ "$c_wt" -ge 1 ] && [ "$c_both" -gt "$c_wt" ]; then
  ok "codegraph-probe: un cache por root dentro del mismo state dir ($c_both archivos)"
else
  fail "codegraph-probe: caches por root esperados (worktree=$c_wt, +main=$c_both)"
fi

[ "$fails" -eq 0 ] || { echo "$fails assertion(s) fallaron"; exit 1; }
echo "state-dir-slug: OK"
