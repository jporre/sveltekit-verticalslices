#!/usr/bin/env bash
# Regresión: el hook SessionStart corrido por Codex (cache en ~/.codex) no debe
# pisar ~/.claude/b-pipeline.root — el marker es exclusivo de Claude Code.
#
# Uso: bash hooks/tests/write-root-marker.test.sh
set -uo pipefail

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/write-root-marker.sh"
TMP="$(mktemp -d)"; TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
MARKER="$HOME/.claude/b-pipeline.root"

fails=0
ok()   { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; fails=$((fails + 1)); }

install_at() { mkdir -p "$1/hooks" "$1/skills"; cp "$HOOK" "$1/hooks/"; }

cc="$HOME/.claude/plugins/cache/b-pipeline-market/b-pipeline/9.9.9"
cx="$HOME/.codex/plugins/cache/b-pipeline-market/b-pipeline/9.9.8"
install_at "$cc"; install_at "$cx"

bash "$cc/hooks/write-root-marker.sh"
if [ "$(cat "$MARKER" 2>/dev/null)" = "$cc" ]; then ok "Claude Code escribe el marker"; else fail "marker='$(cat "$MARKER" 2>/dev/null)'"; fi

bash "$cx/hooks/write-root-marker.sh"; rc=$?
if [ "$rc" -eq 0 ]; then ok "hook desde Codex sale 0"; else fail "hook desde Codex exit $rc"; fi
if [ "$(cat "$MARKER")" = "$cc" ]; then ok "Codex no pisa el marker de Claude Code"; else fail "Codex pisó el marker: $(cat "$MARKER")"; fi

[ "$fails" -eq 0 ] || { echo "$fails assertion(s) fallaron"; exit 1; }
echo "write-root-marker: OK"
