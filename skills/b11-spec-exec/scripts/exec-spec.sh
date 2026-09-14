#!/usr/bin/env bash
# exec-spec.sh — aplica una SPEC de b11-spec-exec con un modelo barato en un proceso `claude -p` aislado.
#
# Uso: exec-spec.sh <SPEC.md> [--model <alias|proveedor/slug>] [--max-turns N] [--repo RUTA] [--out ARCHIVO.json]
#   --model      alias de Claude Code (haiku | sonnet | opus) o slug de OpenRouter (lleva "/", p. ej.
#                z-ai/glm-5.3-flash). Default: $B_PIPELINE_EXEC_MODEL; si no está, z-ai/glm-5.3-flash
#                cuando existe OPENROUTER_API_KEY y haiku en caso contrario.
#   --max-turns  tope de turnos del ejecutor (default 80).
#   --repo       reemplaza la línea REPO: de la spec (pruebas sobre un clon).
#   --out        JSON completo de claude -p (default: <spec>.exec.json junto a la spec; stderr en .stderr.log).
# Un slug de OpenRouter exige OPENROUTER_API_KEY en el entorno: se pasa solo al proceso hijo y nunca se imprime.
# Salida: una línea `EXEC …` machine-readable y el informe del ejecutor. Exit 1 si el ejecutor no terminó ok.
set -euo pipefail

usage() { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; }

SPEC=""; MODEL="${B_PIPELINE_EXEC_MODEL:-}"; MAX_TURNS=80; REPO_OVERRIDE=""; OUT=""
if [ -z "$MODEL" ]; then
  if [ -n "${OPENROUTER_API_KEY:-}" ]; then MODEL="z-ai/glm-5.3-flash"; else MODEL="haiku"; fi
fi
while [ $# -gt 0 ]; do
  case "$1" in
    --model)     MODEL="$2"; shift 2 ;;
    --max-turns) MAX_TURNS="$2"; shift 2 ;;
    --repo)      REPO_OVERRIDE="$2"; shift 2 ;;
    --out)       OUT="$2"; shift 2 ;;
    -h|--help)   usage; exit 0 ;;
    -*)          echo "flag desconocido: $1" >&2; usage >&2; exit 2 ;;
    *)           SPEC="$1"; shift ;;
  esac
done
[ -n "$SPEC" ] && [ -f "$SPEC" ] || { echo "falta la ruta a SPEC.md" >&2; usage >&2; exit 2; }
SPEC="$(cd "$(dirname "$SPEC")" && pwd)/$(basename "$SPEC")"
OUT="${OUT:-${SPEC%.md}.exec.json}"; ERR="${OUT%.json}.stderr.log"

REPO="$(grep -m1 '^REPO:' "$SPEC" | sed -e 's/^REPO:[[:space:]]*//' -e "s#^~#$HOME#" || true)"
[ -n "$REPO" ] || { echo "la spec no tiene línea REPO:" >&2; exit 2; }
WORK="$(mktemp -d -t b11)"
RUN_SPEC="$SPEC"
if [ -n "$REPO_OVERRIDE" ]; then
  RUN_SPEC="$WORK/spec.md"
  sed "s#$REPO#$REPO_OVERRIDE#g" "$SPEC" > "$RUN_SPEC"
  REPO="$REPO_OVERRIDE"
fi
# rev-parse y no -d .git: en worktrees (caso normal del pipeline) .git es un gitfile.
git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "REPO no es un repo git: $REPO" >&2; exit 2; }
if [ -n "$(git -C "$REPO" status --porcelain)" ]; then
  echo "REPO con cambios sin commitear ($REPO); la spec se ensaya y certifica contra HEAD limpio" >&2; exit 2
fi

# Orígenes de las copias → --add-dir, para que Read alcance archivos fuera del repo.
ADD_DIRS=()
while IFS= read -r d; do [ -n "$d" ] && ADD_DIRS+=(--add-dir "$d"); done < <(
  grep '^COPIAR:' "$RUN_SPEC" | sed -E 's/^COPIAR:[[:space:]]*([^[:space:]]+).*/\1/' | sed "s#^~#$HOME#" \
  | while IFS= read -r p; do dirname "$p"; done | sort -u)

MCP="$WORK/mcp.json"; printf '{"mcpServers":{}}\n' > "$MCP"
ENV_ARGS=()
case "$MODEL" in
  */*)
    [ -n "${OPENROUTER_API_KEY:-}" ] || { echo "el modelo $MODEL va por OpenRouter y requiere OPENROUTER_API_KEY en el entorno" >&2; exit 2; }
    ENV_ARGS=("ANTHROPIC_BASE_URL=${OPENROUTER_BASE_URL:-https://openrouter.ai/api}" "ANTHROPIC_AUTH_TOKEN=$OPENROUTER_API_KEY") ;;
esac

START=$(date +%s)
set +e
( cd "$REPO" && env ${ENV_ARGS[@]+"${ENV_ARGS[@]}"} claude -p --model "$MODEL" --max-turns "$MAX_TURNS" \
    --allowedTools "Bash,Read,Edit,Write,Glob,Grep" --strict-mcp-config --mcp-config "$MCP" \
    ${ADD_DIRS[@]+"${ADD_DIRS[@]}"} --output-format json < "$RUN_SPEC" > "$OUT" 2> "$ERR" )
RC=$?
set -e
SECS=$(( $(date +%s) - START ))
rm -rf "$WORK"

set +e
python3 - "$OUT" "$MODEL" "$RC" "$SECS" <<'PY'
import json, os, sys
out, model, rc, secs = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
try:
    d = json.load(open(out))
except Exception as e:
    print(f"EXEC model={model} ok=no rc={rc} error=sin_json ({e})")
    sys.exit(1)
mu = d.get("modelUsage") or {}
name, u = next(iter(mu.items())) if mu else (model, {})
inp, outt = u.get("inputTokens", 0), u.get("outputTokens", 0)
cr, cw = u.get("cacheReadInputTokens", 0), u.get("cacheCreationInputTokens", 0)
# USD por millón (input, output, cache_read, cache_write): lista pública 2026-09.
# Override: B_PIPELINE_EXEC_PRICES=in,out,cr,cw. El total_cost_usd de claude -p no sirve para modelos que no conoce.
TABLA = {"glm-5.3-flash": (0.15, 0.5, 0.03, 0.19), "haiku-4": (1, 5, 0.1, 1.25), "sonnet-5": (2, 10, 0.2, 2.5),
         "opus-5": (5, 25, 0.5, 6.25), "fable-5": (10, 50, 0.25, 12.5)}
env_p = os.environ.get("B_PIPELINE_EXEC_PRICES")
prices = tuple(map(float, env_p.split(","))) if env_p else next((v for k, v in TABLA.items() if k in name), None)
usd = f"{(inp * prices[0] + outt * prices[1] + cr * prices[2] + cw * prices[3]) / 1e6:.3f}" if prices else "n/a"
# denials>0 nunca es ok: el hijo terminó "success" pero le negaron writes → repo intacto y falso positivo.
denials = len(d.get("permission_denials") or [])
ok = rc == 0 and not d.get("is_error") and d.get("subtype") == "success" and denials == 0
print(f"EXEC model={name} ok={'si' if ok else 'no'} subtype={d.get('subtype')} turns={d.get('num_turns')} dur={secs}s "
      f"in={inp} cache_read={cr} cache_write={cw} out={outt} usd_lista={usd} "
      f"denials={denials} json={out}")
print("--- informe del ejecutor ---")
print(d.get("result") or "(sin result)")
sys.exit(0 if ok else 1)
PY
PY_RC=$?
set -e
[ "$PY_RC" -eq 0 ] || { echo "--- stderr del ejecutor (últimas 5 líneas: $ERR) ---"; tail -5 "$ERR"; }
exit "$PY_RC"
