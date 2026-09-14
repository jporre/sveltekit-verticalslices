#!/usr/bin/env bash
# Regresión issue #60: fast-path de issues de b0 por script (guardrails.sh triage-from-labels).
#
# Antes: b7/b8/epic-mode spawneaban b1 (fork Explore) por cada issue de b0 aunque el
# research se saltara; el mapeo labels → triage estaba duplicado (prosa de b1 + bash
# de b10 run.sh, ya drifteado: lane:b11) y label `bug` caía en bail:fix-sin-evidence.
#
# Uso: bash skills/b7-issue-to-pr/tests/triage-from-labels.test.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
G="$SCRIPT_DIR/../scripts/guardrails.sh"
B1="$SCRIPT_DIR/../../b1-triage-issue/SKILL.md"
TMP="$(mktemp -d)"; TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME/.claude/projects"

fails=0
ok()   { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; fails=$((fails + 1)); }

# Fixture: sub-issue kind:ui de b0 (formato de slicing-guide.md), sin comentarios humanos.
BODY_UI='## Objetivo\nGestionar productos desde una sola pantalla.\n\n## Pantalla\n- **Ruta**: `/productos`\n  - **Journey**: el usuario ve la tabla, busca/filtra por categoría, crea o edita en un form upsert, elimina con confirmación.\n  - **Criterios de aceptación (visuales)**:\n    - [ ] Tabla con nombre, precio y categoría; estado vacío claro.\n    - [ ] Un único formulario upsert; editar pre-puebla; errores de validación visibles; toast al guardar.\n    - [ ] Diálogo de confirmación antes de borrar; la fila desaparece.\n\n## Seguridad / permisos\nSesión requerida (`+page.server.ts`).\n\n## Archivos previstos\n`src/routes/productos/+page.svelte`, `src/routes/productos/ui/ProductoForm.svelte`, `src/routes/productos/+page.server.ts`.\n\n## Blocked by\n- #261\n\n## Complejidad estimada\nmedium.'
fixture() { # $1=out $2=title $3=labels-json $4=body $5=comments-json
  python3 - "$@" <<'PY'
import json, sys
out, title, labels, body, comments = sys.argv[1:6]
json.dump({"number": 262, "title": title, "state": "OPEN", "createdAt": "2026-09-14T10:00:00Z",
           "author": {"login": "jporre"}, "url": "https://github.com/x/y/issues/262",
           "labels": [{"name": l} for l in json.loads(labels)],
           "body": body.encode().decode("unicode_escape").encode("latin-1").decode("utf-8"),
           "comments": json.loads(comments)}, open(out, "w"), ensure_ascii=False)
PY
}

# 1. kind:ui → triage.json válido (validate-triage) con screens[] que screens-check reconoce.
wt="$TMP/wt"; mkdir -p "$wt/.b7/review"
fixture "$TMP/ui.json" "feat(productos): pantalla /productos" '["feature","scope:productos","medium","ready","kind:ui"]' "$BODY_UI" '[]'
line="$(bash "$G" triage-from-labels "$TMP/ui.json" "$wt/.b7/triage.json")"
case "$line" in "TRIAGE_FROM_LABELS=ok complexity=medium scope=productos type=feat screens=1 plan="*) ok "kind:ui → $line" ;; *) fail "kind:ui: '$line'" ;; esac
if bash "$G" validate-triage "$wt/.b7/triage.json" >/dev/null 2>&1; then ok "triage.json pasa validate-triage"; else fail "validate-triage rechazó el triage.json"; fi
if [ "$(jq -r '.screens[0].name + " " + .screens[0].route' "$wt/.b7/triage.json")" = "ProductosPage /productos" ]; then ok "screens[0] = ProductosPage /productos"; else fail "screens: $(jq -c .screens "$wt/.b7/triage.json")"; fi
if [ "$(jq -r '.blocked_by | join(",")' "$wt/.b7/triage.json")" = "261" ]; then ok "blocked_by desde ## Blocked by (bp_blocked_by)"; else fail "blocked_by: $(jq -c .blocked_by "$wt/.b7/triage.json")"; fi
if [ "$(jq '.plan | length' "$wt/.b7/triage.json")" -ge 3 ] && [ "$(jq -r '.plan | map(.id) | unique | length' "$wt/.b7/triage.json")" = "$(jq '.plan | length' "$wt/.b7/triage.json")" ]; then ok "plan[] ≥ 3 items con ids únicos"; else fail "plan: $(jq -c '.plan | map(.id)' "$wt/.b7/triage.json")"; fi
# screens-check exige .b7/review/<screens[].name>.json: sin él falla nombrando la pantalla; con verdict=pass da ok screens=1.
if { bash "$G" screens-check "$wt" 2>&1 || true; } | grep -q "pantalla 'ProductosPage' sin review"; then ok "screens-check exige review de ProductosPage (nombre derivado)"; else fail "screens-check no reclamó ProductosPage"; fi
echo '{"verdict":"pass"}' > "$wt/.b7/review/ProductosPage.json"
sc="$(bash "$G" screens-check "$wt" 2>&1 | grep '^SCREENS_CHECK=')"
if [ "$sc" = "SCREENS_CHECK=ok screens=1" ]; then ok "screens-check: $sc"; else fail "screens-check con review: '$sc'"; fi

# 2. Label bug → type=fix con evidence.observed del body → triage-gates sin bail:fix-sin-evidence.
fixture "$TMP/bug.json" "productos: el filtro no persiste en la URL" '["bug","scope:productos","simple","ready","kind:ui"]' "$BODY_UI" '[]'
bash "$G" triage-from-labels "$TMP/bug.json" "$TMP/bug-triage.json" >/dev/null
gate="$(bash "$G" triage-gates "$TMP/bug-triage.json" 2>/dev/null | grep '^TRIAGE_GATE=')"
if [ "$(jq -r .type "$TMP/bug-triage.json")" = fix ] && [ -n "$(jq -r '.evidence.observed // empty' "$TMP/bug-triage.json")" ]; then ok "bug → type=fix con evidence.observed"; else fail "bug: type=$(jq -r .type "$TMP/bug-triage.json") evidence=$(jq -c .evidence "$TMP/bug-triage.json")"; fi
case "$gate" in *fix-sin-evidence*) fail "triage-gates: $gate" ;; TRIAGE_GATE=*) ok "triage-gates: $gate (sin bail:fix-sin-evidence)" ;; *) fail "triage-gates sin TRIAGE_GATE" ;; esac

# 3. Sin ## Archivos previstos → none (el llamador corre b1) y no escribe archivo.
fixture "$TMP/nofiles.json" "feat(productos): x" '["feature","scope:productos","simple","ready"]' '## Objetivo\nAlgo.\n\n## Complejidad estimada\nsimple.' '[]'
line="$(bash "$G" triage-from-labels "$TMP/nofiles.json" "$TMP/nofiles-triage.json")"
if [ "$line" = "TRIAGE_FROM_LABELS=none reason=sin-archivos-previstos" ] && [ ! -f "$TMP/nofiles-triage.json" ]; then ok "sin ## Archivos previstos → $line"; else fail "sin archivos: '$line'"; fi

# 4. Comentario humano posterior → none (el humano cambió algo; triage completo).
fixture "$TMP/human.json" "feat(productos): x" '["feature","scope:productos","medium","ready","kind:ui"]' "$BODY_UI" '[{"author":{"login":"jporre"},"body":"cambiemos el alcance","createdAt":"2026-09-14T11:00:00Z"}]'
line="$(bash "$G" triage-from-labels "$TMP/human.json")"
if [ "$line" = "TRIAGE_FROM_LABELS=none reason=comentarios-humanos" ]; then ok "comentario humano → none"; else fail "humano: '$line'"; fi
fixture "$TMP/bot.json" "feat(productos): x" '["feature","scope:productos","medium","ready","kind:ui"]' "$BODY_UI" '[{"author":{"login":"github-actions[bot]"},"body":"<!-- b7:sticky -->","createdAt":"2026-09-14T11:00:00Z"}]'
case "$(bash "$G" triage-from-labels "$TMP/bot.json")" in TRIAGE_FROM_LABELS=ok*) ok "comentario de bot/marker no anula el fast-path" ;; *) fail "comentario bot anuló el fast-path" ;; esac

# 5. lane:b11 en la línea de salida (b10 run.sh la reemite como B10_TRIAGE=… lane=b11).
fixture "$TMP/lane.json" "feat(productos): x" '["feature","scope:productos","simple","ready","lane:b11"]' "$BODY_UI" '[]'
case "$(bash "$G" triage-from-labels "$TMP/lane.json")" in "TRIAGE_FROM_LABELS=ok complexity=simple scope=productos lane=b11 "*) ok "lane=b11 en la salida" ;; *) fail "lane: $(bash "$G" triage-from-labels "$TMP/lane.json")" ;; esac

# 6. effort: low en b1.
if [ "$(grep '^effort' "$B1")" = "effort: low" ]; then ok "b1 SKILL.md: effort: low"; else fail "b1 effort: '$(grep '^effort' "$B1")'"; fi

[ "$fails" -eq 0 ] || { echo "$fails assertion(s) fallaron"; exit 1; }
echo "triage-from-labels: OK"
