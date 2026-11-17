#!/usr/bin/env bash
# check-slice.sh — valida la conformidad de un cambio contra references/slice-spec.md
# de forma MECÁNICA (lo que el juicio LLM no necesita mirar). Corre sobre el diff.
#
# Uso: bash check-slice.sh [base-ref]
#   base-ref  rama/commit base a comparar (default: rama default del repo via
#             bp_default_branch). Compara el working tree contra el merge-base, así cubre tanto cambios
#             ya commiteados en la rama como cambios sin commitear (pre-commit b2).
#
# Checklist mecánico (slice-spec.md, checklist de conformidad):
#   1. Nada NUEVO bajo src/lib/features/ (tolerancia legacy: EDITAR ahí es OK).
#   2. Ningún *.remote.ts bajo src/lib/server/. Ninguna carpeta server/ NUEVA dentro de
#      src/routes/ (no protege nada; canónico: src/routes/<feature>/data.remote.ts y
#      <nombre>.server.ts). Agregar a un server/ que ya existía = tolerancia legacy.
#   3. Ningún .js NUEVO bajo src/routes/ (siempre .ts).
#   4. (WARNING) Archivos NUEVOS en $lib fuera de la tabla de excepciones del spec.
#   5. (WARNING) +page.server.ts / +layout.server.ts / +page.ts NUEVOS (sin load() para datos).
#
# Exit codes estables:
#   0  sin violaciones (puede haber WARNINGs)
#   1  1+ violaciones
#   2  error de uso / entorno
# Última línea: SLICE_CHECK ok | SLICE_CHECK violations=<n>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${CLAUDE_PLUGIN_ROOT:-$SCRIPT_DIR/../../..}/scripts/lib.sh"

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: no es un repo git" >&2; exit 2; }
cd "$REPO_ROOT"

BASE="${1:-}"
if [ -z "$BASE" ]; then
  BASE="$(bp_default_branch 2>/dev/null || true)"
fi
[ -z "$BASE" ] && { echo "ERROR: no se pudo determinar base-ref (probar: check-slice.sh <base>)" >&2; exit 2; }

MB="$(git merge-base "$BASE" HEAD 2>/dev/null)" || { echo "ERROR: base-ref inválido: $BASE" >&2; exit 2; }

# name-status del working tree vs merge-base: A=added, M=modified, D=deleted, R=renamed.
# git diff NO lista archivos untracked (nuevos sin `git add`); los sumamos como A
# para que el check funcione tanto pre-commit (b2) como sobre commits (b6).
CHANGED="$(git diff --name-status "$MB")"
TAB="$(printf '\t')"
UNTRACKED="$(git ls-files --others --exclude-standard | sed "s/^/A${TAB}/")"
[ -n "$UNTRACKED" ] && CHANGED="${CHANGED:+$CHANGED
}${UNTRACKED}"

violations=0
warnings=0
viol() { echo "VIOLATION: $*"; violations=$((violations + 1)); }
warn() { echo "WARNING:   $*"; warnings=$((warnings + 1)); }

while IFS=$'\t' read -r status path rest; do
  [ -z "${status:-}" ] && continue
  # Renombrados (Rxxx) traen 'path' = origen y 'rest' = destino.
  case "$status" in
    R*) path="$rest"; status="A" ;;
  esac
  [ -z "${path:-}" ] && continue
  base="$(basename "$path")"

  # --- Check 2a: ningún remote bajo src/lib/server/ (el cliente lo importa) ---
  case "$path" in
    src/lib/server/*.remote.ts|src/lib/server/**/*.remote.ts)
      viol "*.remote.ts no puede vivir bajo src/lib/server/ (el cliente lo importa): $path" ;;
  esac

  # Solo los cambios que AGREGAN archivos disparan los checks de estructura.
  # (EDITAR un archivo existente = M/D => tolerancia legacy, no es violación.)
  [ "$status" = "A" ] || continue

  # --- Check 2b: ninguna carpeta server/ NUEVA dentro de src/routes/ ---
  case "$path" in
    src/routes/*/server/*)
      sdir="${path%%/server/*}/server"
      git cat-file -e "$MB:$sdir" 2>/dev/null \
        || viol "carpeta server/ NUEVA dentro de src/routes (no protege nada; canónico: <feature>/data.remote.ts y <nombre>.server.ts): $path" ;;
  esac

  # --- Check 3: siempre .ts, nunca .js ---
  case "$path" in
    src/routes/*.js) viol "archivo .js NUEVO (siempre .ts): $path" ;;
  esac

  # --- Check 5 (WARNING): sin load() para datos ---
  case "$base" in
    +page.server.ts|+layout.server.ts|+page.ts)
      warn "$base NUEVO — los datos llegan por remote functions, no por load(): $path" ;;
  esac

  # --- Check 1: nada nuevo bajo src/lib/features/ ---
  case "$path" in
    src/lib/features/*)
      viol "feature NUEVO bajo src/lib/features/ (prohibido; va colocado en src/routes/): $path"
      continue ;;
  esac

  # --- Check 4 (WARNING): $lib nuevo fuera de la tabla de excepciones ---
  case "$path" in
    src/lib/components/ui/*) : ;;                 # shadcn-svelte
    src/lib/server/db/*|src/lib/server/db.ts) : ;; # conexión/schema DB
    src/lib/*)
      warn "archivo NUEVO en \$lib — justificar como transversal 3+ features o mover al slice: $path" ;;
  esac
done <<< "$CHANGED"

echo ""
if [ "$violations" -eq 0 ]; then
  echo "SLICE_CHECK ok"
  exit 0
fi
echo "SLICE_CHECK violations=${violations}"
exit 1
