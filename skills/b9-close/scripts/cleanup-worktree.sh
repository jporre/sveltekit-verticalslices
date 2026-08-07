#!/usr/bin/env bash
# cleanup-worktree.sh <worktree-path> [--branch <name>]
#
# Camino SANCIONADO de limpieza de worktrees (b9 PASO 6 y janitor de b10).
# Nunca rm -rf a mano desde el chat: este script encapsula el borrado con guardas.
#
#   1. Mata el dev server del worktree si quedó vivo (.b7/dev-server.pid).
#   2. Worktree REGISTRADO: si el porcelain trae cambios -> exit 6 (el caller debe
#      rescatar vía b3/rescue branch ANTES); limpio -> git worktree remove
#      (--force solo con porcelain vacío). NUNCA rm -rf sobre uno registrado.
#   3. Directorio HUÉRFANO (no registrado): solo se borra si parece artefacto de
#      worktree — contiene un archivo .git con línea gitdir: — y nunca fuera de él.
#   4. git worktree prune + borrado opcional de la rama local (--branch).
#
# Exit: 0 ok | 2 uso | 6 código sin commitear (rescatar primero) | 1 no removible
set -euo pipefail

WT="${1:-}"; shift || true
BRANCH=""
while [ $# -gt 0 ]; do
  case "$1" in
    --branch) BRANCH="${2:?--branch requiere un valor}"; shift 2 ;;
    *) echo "Usage: $0 <worktree-path> [--branch <name>]" >&2; exit 2 ;;
  esac
done
[ -n "$WT" ] || { echo "Usage: $0 <worktree-path> [--branch <name>]" >&2; exit 2; }

REPO_MAIN="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: correr desde el repo principal" >&2; exit 2; }
case "$WT" in "$REPO_MAIN") echo "ABORT: el path ES el repo principal" >&2; exit 2 ;; esac

[ -f "$WT/.b7/dev-server.pid" ] && kill "$(cat "$WT/.b7/dev-server.pid")" 2>/dev/null || true

if git -C "$REPO_MAIN" worktree list --porcelain | grep -qxF "worktree $WT"; then
  # Registrado: proteger trabajo sin commitear (el rescue es del caller, con b3).
  if [ -n "$(git -C "$WT" status --porcelain 2>/dev/null | grep -vE '^\?\? \.b7/' || true)" ]; then
    git -C "$WT" status --porcelain
    echo "ABORT: cambios sin commitear — rescatar primero (b3 / rescue branch)" >&2
    exit 6
  fi
  if ! git -C "$REPO_MAIN" worktree remove "$WT" 2>/dev/null; then
    git -C "$REPO_MAIN" worktree remove "$WT" --force
  fi
elif [ -d "$WT" ]; then
  # Huérfano: solo borrar lo que demuestra ser un worktree (archivo .git con gitdir:).
  if [ -f "$WT/.git" ] && grep -q '^gitdir:' "$WT/.git"; then
    rm -rf "$WT"
    echo "huérfano borrado: $WT"
  else
    echo "ABORT: $WT no parece un worktree (sin archivo .git/gitdir) — no se borra" >&2
    exit 1
  fi
else
  echo "skip: $WT no existe"
fi

git -C "$REPO_MAIN" worktree prune
[ -n "$BRANCH" ] && git -C "$REPO_MAIN" branch -D "$BRANCH" 2>/dev/null || true
echo "CLEANUP_OK worktree=$WT branch=${BRANCH:-kept}"
