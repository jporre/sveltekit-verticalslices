#!/usr/bin/env bash
# project-config.sh — memoria por proyecto del pipeline: .b-pipeline/project.json (#63, mínimo).
# Uso: project-config.sh init [dir]   escribe el archivo si no existe (no pisa)
#      project-config.sh show [dir]   imprime los valores efectivos (K=V)
# Claves v1: pm, port, worktree_port_start, base_branch, cookie_name. Solo valores
# no secretos: nunca credenciales ni valores de .env. Los lectores usan bp_project
# (scripts/lib.sh) y caen al default histórico si la clave falta.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

cmd="${1:-show}"; dir="${2:-.}"
root="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || (cd "$dir" && pwd))"
f="$root/.b-pipeline/project.json"

case "$cmd" in
  init)
    [ -f "$f" ] && { echo "PROJECT_CONFIG=exists path=$f"; exit 0; }
    mkdir -p "$root/.b-pipeline"
    port="$(bp_dev_port "$root")"
    base="$(cd "$root" && bp_default_branch 2>/dev/null || echo main)"
    cat > "$f" <<EOF
{
  "v": 1,
  "pm": "$(bp_pm "$root")",
  "port": $port,
  "worktree_port_start": $((port + 1)),
  "base_branch": "$base",
  "cookie_name": "auth-session"
}
EOF
    echo "PROJECT_CONFIG=created path=$f"
    ;;
  show)
    [ -f "$f" ] || echo "WARN project.json ausente: $f (correr: project-config.sh init)"
    echo "pm=$(bp_pm "$root")"
    echo "port=$(bp_dev_port "$root")"
    echo "worktree_port_start=$(bp_project worktree_port_start 6026 "$root")"
    echo "base_branch=$(cd "$root" && bp_default_branch 2>/dev/null || echo '?')"
    echo "cookie_name=$(bp_project cookie_name auth-session "$root")"
    echo "sk_major=$(bp_sk_major "$root")"
    ;;
  *) echo "uso: project-config.sh init|show [dir]" >&2; exit 2 ;;
esac
