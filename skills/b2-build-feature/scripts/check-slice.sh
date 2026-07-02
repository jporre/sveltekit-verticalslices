#!/usr/bin/env bash
# check-slice.sh — valida la conformidad de un cambio contra references/slice-spec.md
# de forma MECANICA (lo que el juicio LLM no necesita mirar). Corre sobre el diff.
#
# Uso: bash check-slice.sh [base-ref]
#   base-ref  rama/commit base a comparar (default: main o master, el que exista).
#             Compara el working tree contra el merge-base, asi cubre tanto cambios
#             ya commiteados en la rama como cambios sin commitear (pre-commit b2).
#
# Checklist mecanico (slice-spec.md, checklist de conformidad):
#   1. Nada NUEVO bajo src/lib/features/ (tolerancia legacy: EDITAR ahi es OK).
#   2. Remote nombrado: sin data.remote.ts; ningun *.remote.ts bajo src/lib/server/.
#   3. Feature NUEVO (slice colocado con +page.svelte/*.remote.ts nuevos) trae su .md.
#   4. (WARNING) Archivos NUEVOS en $lib fuera de la tabla de excepciones del spec.
#
# Exit codes estables:
#   0  sin violaciones (puede haber WARNINGs)
#   1  1+ violaciones
#   2  error de uso / entorno
# Ultima linea: SLICE_CHECK ok | SLICE_CHECK violations=<n>
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: no es un repo git" >&2; exit 2; }
cd "$REPO_ROOT"

BASE="${1:-}"
if [ -z "$BASE" ]; then
  for b in main master; do
    if git show-ref -q --verify "refs/heads/$b"; then BASE="$b"; break; fi
  done
fi
[ -z "$BASE" ] && { echo "ERROR: no se pudo determinar base-ref (probar: check-slice.sh <base>)" >&2; exit 2; }

MB="$(git merge-base "$BASE" HEAD 2>/dev/null)" || { echo "ERROR: base-ref invalido: $BASE" >&2; exit 2; }

# name-status del working tree vs merge-base: A=added, M=modified, D=deleted, R=renamed.
# git diff NO lista archivos untracked (nuevos sin `git add`); los sumamos como A
# para que el check funcione tanto pre-commit (b2) como sobre commits (b6).
CHANGED="$(git diff --name-status "$MB")"
UNTRACKED="$(git ls-files --others --exclude-standard | sed 's/^/A\t/')"
[ -n "$UNTRACKED" ] && CHANGED="${CHANGED:+$CHANGED
}${UNTRACKED}"

violations=0
warnings=0
viol() { echo "VIOLATION: $*"; violations=$((violations + 1)); }
warn() { echo "WARNING:   $*"; warnings=$((warnings + 1)); }

# Recolecta carpetas de slices nuevos (para el check 3), sin duplicados.
new_slice_dirs=""

while IFS=$'\t' read -r status path rest; do
  [ -z "${status:-}" ] && continue
  # Renombrados (Rxxx) traen 'path' = origen y 'rest' = destino.
  case "$status" in
    R*) path="$rest"; status="A" ;;
  esac
  [ -z "${path:-}" ] && continue
  base="$(basename "$path")"

  # --- Check 2: remote nombrado ---
  if [ "$base" = "data.remote.ts" ]; then
    viol "remote generico prohibido (usar <feature>.remote.ts): $path"
  fi
  case "$path" in
    src/lib/server/*.remote.ts|src/lib/server/**/*.remote.ts)
      viol "*.remote.ts no puede vivir bajo src/lib/server/ (el cliente lo importa): $path" ;;
  esac

  # Solo los cambios que AGREGAN archivos disparan los checks de estructura.
  # (EDITAR un archivo existente = M/D => tolerancia legacy, no es violacion.)
  [ "$status" = "A" ] || continue

  # --- Check 1: nada nuevo bajo src/lib/features/ ---
  case "$path" in
    src/lib/features/*)
      viol "feature NUEVO bajo src/lib/features/ (prohibido; va colocado en src/routes/): $path"
      continue ;;
  esac

  # --- Check 4 (WARNING): $lib nuevo fuera de la tabla de excepciones ---
  case "$path" in
    src/lib/components/ui/*) : ;;                 # shadcn-svelte
    src/lib/server/db/*) : ;;                     # conexion/schema DB
    src/lib/*)
      warn "archivo NUEVO en \$lib — justificar como transversal 3+ features o mover al slice: $path" ;;
  esac

  # --- Recolecta slices nuevos para el check 3 ---
  case "$path" in
    src/routes/*)
      dir="$(dirname "$path")"
      if [ "$base" = "+page.svelte" ] || [[ "$base" == *.remote.ts ]]; then
        case " $new_slice_dirs " in *" $dir "*) : ;; *) new_slice_dirs="$new_slice_dirs $dir" ;; esac
      fi ;;
  esac
done <<< "$CHANGED"

# --- Check 3: cada slice nuevo trae un .md colocado ---
for dir in $new_slice_dirs; do
  if ! ls "$REPO_ROOT/$dir"/*.md >/dev/null 2>&1; then
    viol "feature NUEVO sin doc <feature>.md colocado: $dir/"
  fi
done

echo ""
if [ "$violations" -eq 0 ]; then
  echo "SLICE_CHECK ok"
  exit 0
fi
echo "SLICE_CHECK violations=${violations}"
exit 1
