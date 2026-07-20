#!/usr/bin/env bash
# SessionStart hook: persiste la raíz del plugin en ~/.claude/b-pipeline.root.
#
# Por qué existe: los snippets bash de los SKILL.md corren en el Bash tool SIN
# CLAUDE_PLUGIN_ROOT en su entorno, y la ruta de instalación varía por máquina
# (marketplace clone, cache, checkout dev). El harness SÍ expande
# ${CLAUDE_PLUGIN_ROOT} al invocar este hook desde hooks.json, y además este
# script puede auto-ubicarse — así que acá, y solo acá, sabemos la ruta real.
# Los snippets la leen con:
#   PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cat "$HOME/.claude/b-pipeline.root" 2>/dev/null || ...glob...)}"
#
# Silencioso a propósito: el stdout de SessionStart se inyecta al contexto.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -d "$ROOT/skills" ] || exit 0   # sanity: no escribir basura si la estructura no calza
mkdir -p "$HOME/.claude"
printf '%s\n' "$ROOT" > "$HOME/.claude/b-pipeline.root"
exit 0
