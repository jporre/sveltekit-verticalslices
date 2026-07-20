#!/usr/bin/env bash
# verify.sh — checklist de verificación de b2 como script machine-falla.
# Corre en el repo del feature (app SvelteKit), sobre el diff vs merge-base.
#
# Uso: bash verify.sh [base-ref]
#   base-ref  rama/commit base a comparar (default: rama default del repo via
#             bp_default_branch).
#
# Gates en orden (para en el primero que falla):
#   1. branch guard: rama actual == rama default (o main/master) -> exit 3
#   2. pnpm check:machine                               -> exit 4
#   3. pnpm format (auto-fix, no-gate)
#   4. grep anti-React SOLO en archivos cambiados       -> exit 5 (con file:line)
#      .svelte: on:click | export let | useState | useEffect | onClick=
#      .ts:     useState | useEffect | onClick=
#   5. pnpm test:unit SOLO si el diff toca .test./.spec. -> exit 6
#   6. browser-gate: required si el diff toca src/routes/**, *.svelte o *.remote.ts
#   2 = error de uso / entorno
#
# Última línea machine-readable (gates no corridos quedan en "-"):
#   VERIFY_RESULT branch=ok|fail check=ok|fail react=ok|fail test=ok|skipped|fail browser=required|not-needed svelte_files=<csv>
# Autofixer (sobre svelte_files) y walkthrough en browser (si browser=required)
# siguen siendo pasos del modelo gatillados por esta línea.
set -euo pipefail

BRANCH_S="-"; CHECK_S="-"; REACT_S="-"; TEST_S="-"; BROWSER_S="-"; SVELTE_CSV=""

result() {
  echo "VERIFY_RESULT branch=$BRANCH_S check=$CHECK_S react=$REACT_S test=$TEST_S browser=$BROWSER_S svelte_files=$SVELTE_CSV"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${CLAUDE_PLUGIN_ROOT:-$SCRIPT_DIR/../../..}/scripts/lib.sh"

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: no es un repo git" >&2; exit 2; }
cd "$REPO_ROOT"

DEFAULT_BRANCH="$(bp_default_branch 2>/dev/null || true)"

# --- Gate 1: branch guard (rama default + main/master como superset conservador) ---
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if { [ -n "$DEFAULT_BRANCH" ] && [ "$BRANCH" = "$DEFAULT_BRANCH" ]; } \
  || [ "$BRANCH" = "master" ] || [ "$BRANCH" = "main" ]; then
  echo "FAIL: rama actual es '$BRANCH' — crear branch primero, p.ej. git checkout -b feat/<issue>-<slug> (patrón configurable via git config b-pipeline.branchPattern; ver bp_branch_name en scripts/lib.sh)" >&2
  BRANCH_S=fail; result; exit 3
fi
BRANCH_S=ok

# --- Scope: archivos cambiados vs merge-base + untracked (mismo criterio que check-slice.sh) ---
BASE="${1:-$DEFAULT_BRANCH}"
[ -n "$BASE" ] || { echo "ERROR: no se pudo determinar base-ref (probar: verify.sh <base>)" >&2; exit 2; }
MB="$(git merge-base "$BASE" HEAD 2>/dev/null)" || { echo "ERROR: base-ref inválido: $BASE" >&2; exit 2; }
CHANGED="$(git diff --name-only "$MB"; git ls-files --others --exclude-standard)"

# svelte_files: csv de .svelte cambiados (input del autofixer), presente aun en fails.
SVELTE_CSV="$(printf '%s\n' "$CHANGED" | grep -E '\.svelte$' | paste -s -d, -)" || true

# --- Gate 2: type check ---
if ! pnpm check:machine; then
  echo "FAIL: pnpm check:machine con errores" >&2
  CHECK_S=fail; result; exit 4
fi
CHECK_S=ok

# --- Paso 3: format (auto-fix, sin gate ni output que revisar) ---
pnpm format >/dev/null 2>&1 || echo "WARN: pnpm format falló (no-gate)" >&2

# --- Gate 4: grep anti-React scoped al diff ---
REACT_HITS=""
while IFS= read -r f; do
  [ -n "$f" ] && [ -f "$f" ] || continue
  case "$f" in
    *.svelte) pat='on:click|export let |useState|useEffect|onClick=' ;;
    *.ts)     pat='useState|useEffect|onClick=' ;;
    *)        continue ;;
  esac
  hits="$(grep -nHE "$pat" "$f" || true)"
  [ -n "$hits" ] && REACT_HITS="${REACT_HITS}${hits}"$'\n'
done <<EOF
$CHANGED
EOF
if [ -n "$REACT_HITS" ]; then
  echo "FAIL: patrones React/Svelte4 en archivos cambiados (file:line):" >&2
  printf '%s' "$REACT_HITS" >&2
  REACT_S=fail; result; exit 5
fi
REACT_S=ok

# --- Gate 5: test:unit SOLO si el diff toca tests ---
if printf '%s\n' "$CHANGED" | grep -qE '\.(test|spec)\.'; then
  if ! pnpm test:unit -- --run --reporter=dot; then
    echo "FAIL: pnpm test:unit con fallas" >&2
    TEST_S=fail; result; exit 6
  fi
  TEST_S=ok
else
  TEST_S=skipped
fi

# --- Gate 6: browser-gate por scope del diff ---
# Un *.remote.ts cambia lo que la pantalla muestra: también exige browser.
if printf '%s\n' "$CHANGED" | grep -qE '^src/routes/|\.svelte$|\.remote\.ts$'; then
  BROWSER_S=required
else
  BROWSER_S=not-needed
fi

result
exit 0
