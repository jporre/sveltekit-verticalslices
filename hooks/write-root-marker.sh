#!/usr/bin/env bash
# SessionStart hook: persiste la raiz del plugin en ~/.claude/b-pipeline.root.
#
# Por que existe: los snippets bash de los SKILL.md corren en el Bash tool SIN
# CLAUDE_PLUGIN_ROOT en su entorno, y la ruta de instalacion varia por maquina
# (marketplace clone, cache, checkout dev). El harness SI expande
# ${CLAUDE_PLUGIN_ROOT} al invocar este hook desde hooks.json, y ademas este
# script puede auto-ubicarse — asi que aca, y solo aca, sabemos la ruta real.
# Los snippets la leen con:
#   PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cat "$HOME/.claude/b-pipeline.root" 2>/dev/null || ...glob...)}"
#
# Silencioso a proposito: el stdout de SessionStart se inyecta al contexto.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -d "$ROOT/skills" ] || exit 0   # sanity: no escribir basura si la estructura no calza
mkdir -p "$HOME/.claude"
printf '%s\n' "$ROOT" > "$HOME/.claude/b-pipeline.root"
exit 0
