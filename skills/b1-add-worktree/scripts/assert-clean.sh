#!/usr/bin/env bash
set -euo pipefail

# assert-clean.sh <dir> [--fix]
#
# Verifica que el working tree de <dir> este limpio. Clasifica lo sucio en
# CODIGO (debe commitearse, NUNCA se descarta) vs ARTEFACTOS conocidos del
# pipeline b (generados por b7/screen-review/dev server).
#
# Exit codes (contrato estable — consumidores: b3-git-commit, b7 DoD, b9-close, b10-ship):
#   0 -> limpio (o quedo limpio tras --fix)
#   6 -> sucio con archivos de CODIGO (accion: commitear)
#   7 -> sucio solo con artefactos (sin --fix, o --fix no pudo excluirlos)
#   2 -> uso invalido / no es repo git
#
# --fix: agrega los artefactos a info/exclude (idempotente). NOTA: info/exclude
# es COMPARTIDO entre el repo principal y todos sus worktrees; los patrones que
# se agregan son inertes fuera de un worktree (.b7/, dev.sh, etc. no existen en
# el repo principal). Este script NUNCA borra ni descarta archivos.
#
# Ultima linea machine-readable en exits 0/6/7 (exit 2 = error de uso, sin linea):
#   ASSERT_CLEAN dir=<dir> status=clean|dirty code=N artifacts=M

usage() { echo "Usage: $0 <dir> [--fix]" >&2; exit 2; }

DIR="${1:-}"
[ -n "$DIR" ] || usage
FIX=0
[ "${2:-}" = "--fix" ] && FIX=1

git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1 || { echo "ERROR: $DIR no es un repo git" >&2; exit 2; }

# Patrones de artefactos conocidos. PNGs y LOGs solo en la raiz (screenshots y
# logs sueltos del pipeline); un .png o .log dentro de src/, static/ o tests/
# es CODIGO (asset o fixture legitimo) y jamas se excluye.
is_artifact() {
  case "$1" in
    .b7|.b7/*)                          return 0 ;;
    dev.sh)                             return 0 ;;
    .DS_Store|*/.DS_Store)              return 0 ;;
    dev-server.pid|*/dev-server.pid)    return 0 ;;
    .playwright-mcp/*)                  return 0 ;;
    .git-worktree-exclude)              return 0 ;;
    *.log) case "$1" in */*) return 1 ;; *) return 0 ;; esac ;;
    *.png) case "$1" in */*) return 1 ;; *) return 0 ;; esac ;;
  esac
  return 1
}

classify() {
  CODE_N=0; ART_N=0; CODE_LIST=""; ART_LIST=""
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    p="${line:3}"
    case "$p" in *" -> "*) p="${p##* -> }" ;; esac     # renames: clasificar destino
    p="${p%\"}"; p="${p#\"}"                            # paths con espacios vienen quoted
    if is_artifact "$p"; then
      ART_N=$((ART_N + 1)); ART_LIST="${ART_LIST}${p}"$'\n'
    else
      CODE_N=$((CODE_N + 1)); CODE_LIST="${CODE_LIST}${p}"$'\n'
    fi
  done <<EOF
$(git -C "$DIR" -c core.quotePath=false status --porcelain)
EOF
}

classify

if [ "$CODE_N" -eq 0 ] && [ "$ART_N" -eq 0 ]; then
  echo "ASSERT_CLEAN dir=$DIR status=clean code=0 artifacts=0"
  exit 0
fi

# --fix: mandar artefactos al exclude (solo afecta untracked; idempotente).
# Preferir el exclude POR-WORKTREE (core.excludesFile configurado por setup-worktree.sh)
# para no contaminar el repo principal con wildcards; fallback a info/exclude compartido.
if [ "$ART_N" -gt 0 ] && [ "$FIX" -eq 1 ]; then
  EXCLUDE_FILE="$(git -C "$DIR" config --worktree --get core.excludesFile 2>/dev/null || true)"
  if [ -z "$EXCLUDE_FILE" ]; then
    EXCLUDE_FILE="$(cd "$DIR" && git rev-parse --path-format=absolute --git-path info/exclude 2>/dev/null)" || \
      EXCLUDE_FILE="$(cd "$DIR" && p="$(git rev-parse --git-path info/exclude)"; case "$p" in /*) printf '%s' "$p" ;; *) printf '%s' "$PWD/$p" ;; esac)"
  fi
  mkdir -p "$(dirname "$EXCLUDE_FILE")"
  printf '%s' "$ART_LIST" | while IFS= read -r p; do
    [ -n "$p" ] || continue
    # Anclar a raiz con "/": un patron sin slash inicial matchearia el mismo
    # nombre a cualquier profundidad (semantica gitignore) y podria ocultar codigo.
    pat="/$p"
    case "$p" in .b7|.b7/*) pat="/.b7/" ;; .playwright-mcp/*) pat="/.playwright-mcp/" ;; esac
    grep -qxF "$pat" "$EXCLUDE_FILE" 2>/dev/null || echo "$pat" >> "$EXCLUDE_FILE"
  done
  echo "FIXED: artefactos agregados a $EXCLUDE_FILE"
  classify   # re-clasificar: lo excluido desaparece del porcelain
fi

if [ "$CODE_N" -gt 0 ]; then
  echo "--- CODIGO sin commitear (commitear, NUNCA descartar) ---"
  printf '%s' "$CODE_LIST"
fi
if [ "$ART_N" -gt 0 ]; then
  echo "--- ARTEFACTOS ---"
  printf '%s' "$ART_LIST"
  [ "$FIX" -eq 1 ] && echo "(persisten tras --fix: probablemente tracked o staged — revisar a mano)"
fi

if [ "$CODE_N" -gt 0 ]; then
  echo "ASSERT_CLEAN dir=$DIR status=dirty code=$CODE_N artifacts=$ART_N"
  exit 6
elif [ "$ART_N" -gt 0 ]; then
  echo "ASSERT_CLEAN dir=$DIR status=dirty code=0 artifacts=$ART_N"
  exit 7
fi

echo "ASSERT_CLEAN dir=$DIR status=clean code=0 artifacts=0"
exit 0
