#!/usr/bin/env bash
# Regresion issue #56: render-report.sh publicaba los comentarios HTML de guia
# de las plantillas en CHANGELOG, PR body y sticky, y el gate de vars exigia
# claves de state para vars que solo viven dentro de comentarios.
#
# Fix: strip de comentarios HTML (preservando markers <!-- b7:* -->) ANTES del
# gate y del envsubst.
#
# Uso: bash skills/b7-issue-to-pr/tests/render-strip-comments.test.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RENDER="$SCRIPT_DIR/../scripts/render-report.sh"
TEMPLATES="$SCRIPT_DIR/../templates"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fails=0
ok()   { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; fails=$((fails + 1)); }

# State sintetico: claves = vars usadas FUERA de comentarios en las 4 plantillas
# (mismo strip que aplica render-report.sh). Si el gate exigiera vars de
# comentarios, el render abortaria con exit 4 y el test falla.
python3 - "$TEMPLATES" "$TMP/state.json" <<'PY'
import json, re, sys, pathlib
tpl_dir, out = pathlib.Path(sys.argv[1]), sys.argv[2]
keys = set()
for name in ("changelog-entry.md", "pr-release-notes.md", "issue-comment.md", "run-report.md"):
    tpl = (tpl_dir / name).read_text()
    tpl = re.sub(r"<!--(?!\s*b7:).*?-->", "", tpl, flags=re.S)
    keys |= set(re.findall(r"\$\{([A-Z_][A-Z0-9_]*)\}", tpl))
state = {k.lower(): f"VAL_{k}" for k in sorted(keys)}
pathlib.Path(out).write_text(json.dumps(state))
PY

for tpl in changelog-entry pr-release-notes issue-comment run-report; do
  out="$TMP/$tpl.out.md"
  rc=0; bash "$RENDER" "$TMP/state.json" "$TEMPLATES/$tpl.md" "$out" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "$tpl: render exit $rc (gate exige vars que solo viven en comentarios?)"
    continue
  fi
  # Criterio 1: ningun <!-- salvo markers b7:*
  if grep -oE '<!--[^>]*' "$out" | grep -qvE '^<!--[[:space:]]*b7:'; then
    fail "$tpl: quedan comentarios HTML de guia en el render"
  else
    ok "$tpl: render sin comentarios de guia"
  fi
  # Leak: ningun valor de state dentro de un comentario (no deben quedar comentarios con VAL_)
  if grep -E '<!--.*VAL_' "$out" >/dev/null; then
    fail "$tpl: valor de state filtrado dentro de un comentario"
  fi
done

# Criterio 2: <!-- b7:status --> sigue siendo la PRIMERA linea del sticky
# (publish-docs.sh lo localiza via startswith).
first="$(head -n 1 "$TMP/issue-comment.out.md" 2>/dev/null || true)"
if [ "$first" = "<!-- b7:status -->" ]; then
  ok "issue-comment: marker b7:status es la primera linea"
else
  fail "issue-comment: primera linea es '$first', no el marker b7:status"
fi

# Criterio 3 (contraprueba): el gate SIGUE atrapando vars reales sin clave.
printf '{}\n' > "$TMP/empty-state.json"
rc=0; bash "$RENDER" "$TMP/empty-state.json" "$TEMPLATES/issue-comment.md" "$TMP/x.md" >/dev/null 2>&1 || rc=$?
if [ "$rc" = 4 ]; then
  ok "gate sigue abortando (exit 4) con vars reales sin clave en state"
else
  fail "gate no aborto con state vacio (exit $rc, esperado 4)"
fi

[ "$fails" -eq 0 ] || { echo "$fails assertion(s) fallaron"; exit 1; }
echo "render-strip-comments: OK"
