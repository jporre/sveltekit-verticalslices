#!/usr/bin/env bash
# PreToolUse hook — bloquea dumps de archivos .env en plaintext.
#
# Lee el JSON del hook por stdin, extrae tool_input y, si hay match, imprime un
# hint corto a stderr + exit 2 (bloquea la tool).
#
# Motivo (incidente real, sesión 80744a45): un `cat .env` imprimió secretos en
# plaintext. link-worktree-env.sh symlinkea los .env* a cada worktree, así que
# el riesgo existe en todos. Para diagnosticar credenciales SIN exponerlas:
# hooks/env-probe.sh (fingerprints, no valores).
#
# Matchers (ver hooks.json):
#   - Bash: por SEGMENTO del comando (se parte en saltos de línea ; | & ( ) `),
#           bloquea si el segmento empieza con un verbo de dump y entre sus
#           argumentos hay un path .env sensible. Además `printenv` y `env` a secas.
#   - Read: bloquea file_path que apunte a un .env sensible.
#
# NO bloquea:
#   - `cat .env.example` / `.env.sample`            (no son secretos)
#   - `source .env` / `. .env`                      (carga sin imprimir)
#   - `bash -c 'source .env; psql …' | grep x`      (el verbo no recibe el .env)
#   - `grep process.env.FOO src/`                   (process.env no es un path)
#   - `env VAR=x cmd`                               (env como runner)
#
# Precisión sobre cobertura ciega: la versión anterior bloqueaba cualquier
# comando donde ".env" y un verbo de dump coincidieran en el texto completo,
# lo que frenaba consultas legítimas 3-4 veces por sesión. El modo de falla
# sigue siendo negar: ante duda (segmento raro, subshell), se bloquea.

set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PROBE="${PLUGIN_ROOT}/hooks/env-probe.sh"

input="$(cat)"

# --- extraer campos del tool_input (jq > python3 > raw) ---
_field() {
  local path="$1"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$input" | jq -r "$path // \"\"" 2>/dev/null || true
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$input" | python3 -c "
import json,sys
try: d=json.load(sys.stdin)
except Exception: print(''); sys.exit()
ti=d.get('tool_input',{})
key='$path'.split('.')[-1]
print(ti.get(key,'') or '')
" 2>/dev/null || true
  else
    printf '%s' "$input"
  fi
}

cmd="$(_field '.tool_input.command')"
file_path="$(_field '.tool_input.file_path')"

# --- helper: ¿el texto contiene un path .env sensible? ---
# ".env" debe abrir token/path: no lo precede un alfanumérico (descarta process.env, dotenv).
# Bare ".env" (fin o seguido de algo que no sea . _ - alfanumérico) o ".env.<sufijo>"
# con sufijo distinto de example/sample.
_is_sensitive_env_path() {
  local p="$1"
  if printf '%s' "$p" | grep -Eq '(^|[^A-Za-z0-9_])\.env([^A-Za-z0-9._-]|$)'; then
    return 0
  fi
  local m sfx
  while IFS= read -r m; do
    [ -z "$m" ] && continue
    sfx="${m##*.env.}"
    case "$sfx" in
      example|sample) ;;
      *) return 0 ;;
    esac
  done < <(printf '%s' "$p" | grep -Eo '(^|[^A-Za-z0-9_])\.env\.[A-Za-z0-9_-]+' || true)
  return 1
}

# --- helper: ¿este segmento es <verbo de dump> ... <path .env sensible>? ---
_segment_dumps_env() {
  local seg="$1" w base
  while :; do
    seg="${seg#"${seg%%[![:space:]]*}"}"
    [ -z "$seg" ] && return 1
    w="${seg%%[[:space:]]*}"
    case "$w" in
      sudo|command|builtin|xargs|nice|nohup|time) seg="${seg#"$w"}"; continue ;;
      [A-Za-z_]*=*) seg="${seg#"$w"}"; continue ;;
    esac
    break
  done
  base="${w##*/}"
  case "$base" in
    cat|bat|less|more|head|tail|strings|xxd|od|nl|tac) ;;
    # El primer argumento no-opción es patrón/programa, no archivo (#70): se
    # salta. Con -e/-f el patrón va en la opción y no hay posicional que saltar.
    grep|egrep|fgrep|awk|sed)
      local rest="" t skip=1
      set -f
      for t in ${seg#"$w"}; do
        case "$t" in
          -e|-f|--regexp*|--file*|--expression*) skip=0 ;;
          -*) ;;
          *) if [ "$skip" = 1 ]; then skip=0; continue; fi; rest="$rest $t" ;;
        esac
      done
      set +f
      _is_sensitive_env_path "$rest"; return ;;
    *) return 1 ;;
  esac
  _is_sensitive_env_path "${seg#"$w"}"
}

# Quita el cuerpo de los heredocs (<<X / <<'X' / <<-"X" … X): es datos, no comandos (#70).
_strip_heredocs() {
  awk '
    d != "" { t = $0; if (strip) sub(/^\t+/, "", t); if (t == d) d = ""; next }
    { print; l = $0; gsub(/<<</, "   ", l)
      if (match(l, /<<-?[ \t]*["\047]?[A-Za-z_][A-Za-z0-9_]*["\047]?/)) {
        h = substr(l, RSTART, RLENGTH); strip = (h ~ /^<<-/)
        gsub(/^<<-?[ \t]*|["\047]/, "", h); d = h
      }
    }'
}

_cmd_dumps_env() {
  local seg
  while IFS= read -r seg; do
    if _segment_dumps_env "$seg"; then return 0; fi
  done < <(printf '%s\n' "$cmd" | _strip_heredocs | tr ';|&()`\n' '\n\n\n\n\n\n\n')
  return 1
}

_block() {
  cat >&2 <<MSG
BLOCKED: $1
Sin exponer valores: bash "${PROBE}" .env [VAR…]  (fingerprints: set/len/sha256_8).
Permitido: cat .env.example, source .env, env VAR=x cmd.
MSG
  exit 2
}

# ============================ Matcher: Read ============================
if [ -n "$file_path" ]; then
  if _is_sensitive_env_path "$file_path"; then
    _block "Read de ${file_path} leería secretos en plaintext."
  fi
  exit 0
fi

# ============================ Matcher: Bash ============================
[ -z "$cmd" ] && exit 0

# (1) Verbo de dump con un .env sensible como argumento, por segmento.
if _cmd_dumps_env; then
  _block "dump de un archivo .env en:  ${cmd}"
fi

# (2) printenv (a secas, con args o con pipe) — siempre vuelca el entorno.
if printf '%s' "$cmd" | grep -Eq '(^|[|&;[:space:]()])printenv([[:space:]]|$|\|)'; then
  _block "printenv vuelca variables del entorno:  ${cmd}"
fi

# (3) env a secas o con pipe (pero NO `env VAR=x cmd`).
if printf '%s' "$cmd" | grep -Eq '(^|[|&;[:space:]()])env([[:space:]]*$|[[:space:]]*\|)'; then
  _block "env sin asignaciones vuelca el entorno:  ${cmd}"
fi

exit 0
