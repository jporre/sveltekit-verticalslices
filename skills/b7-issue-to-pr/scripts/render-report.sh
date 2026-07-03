#!/usr/bin/env bash
# render-report.sh — renderiza templates/run-report.md desde .b7/state.json sin LLM.
#
# Lee variables de un JSON, exporta como env vars, ejecuta envsubst sobre el
# template. Determinístico: re-correr con el mismo state.json produce el mismo
# output.
#
# Usage: render-report.sh <state-json> <template> <output>

set -euo pipefail

STATE="${1:-}"
TEMPLATE="${2:-}"
OUT="${3:-}"

if [ -z "$STATE" ] || [ ! -f "$STATE" ]; then
  echo "render-report.sh: missing state json: $STATE" >&2
  exit 2
fi
if [ -z "$TEMPLATE" ] || [ ! -f "$TEMPLATE" ]; then
  echo "render-report.sh: missing template: $TEMPLATE" >&2
  exit 2
fi
if [ -z "$OUT" ]; then
  echo "render-report.sh: missing output path" >&2
  exit 2
fi

# Cargar todas las claves top-level del JSON como env vars en MAYÚSCULAS.
# Valores anidados (objetos/arrays) se serializan a JSON string.
eval "$(python3 -c '
import json, sys, shlex
with open("'"$STATE"'") as f:
    data = json.load(f)
for k, v in data.items():
    key = k.upper()
    if isinstance(v, (dict, list)):
        val = json.dumps(v, ensure_ascii=False)
    elif v is None:
        val = ""
    else:
        val = str(v)
    print(f"export {key}={shlex.quote(val)}")
')"

# Gate: detectar ${VARS} del template que NO tienen clave en state.json.
# envsubst las renderizaria vacias sin avisar (blank silencioso). Un placeholder
# "—" es una clave PRESENTE con valor guion — eso NO es undefined y no gatea.
# Exit 4 listando las variables sin respaldo en state.json.
undefined="$(python3 -c '
import json, re, sys
with open("'"$STATE"'") as f:
    data = json.load(f)
present = {k.upper() for k in data.keys()}
tpl = open("'"$TEMPLATE"'").read()
used = set(re.findall(r"\$\{([A-Z_][A-Z0-9_]*)\}", tpl))
missing = sorted(used - present)
print("\n".join(missing))
')"
if [ -n "$undefined" ]; then
  echo "render-report.sh: UNDEFINED template vars (no key in $STATE):" >&2
  echo "$undefined" | sed 's/^/  - /' >&2
  exit 4
fi

# envsubst respeta las vars ya exportadas. Variables no definidas quedan vacías
# (no como literal "${FOO}") gracias a `envsubst < template`.
mkdir -p "$(dirname "$OUT")"
envsubst < "$TEMPLATE" > "$OUT"

echo "render-report: wrote $OUT"
