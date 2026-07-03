#!/usr/bin/env bash
# PreToolUse hook — bloquea dumps de archivos .env en plaintext.
#
# Estructura calcada de block-git-worktree-add.sh: lee JSON por stdin, extrae el
# tool_input, y en caso de match imprime un hint a stderr + exit 2 (bloquea la tool).
#
# Motivo (incidente real, sesion 80744a45): un `cat .env` imprimio secretos en
# plaintext y el usuario tuvo que interrumpir. setup-worktree.sh symlinkea todos los
# .env* a cada worktree, asi que el riesgo esta en cada worktree. Para diagnosticar
# credenciales SIN exponerlas, usar hooks/env-probe.sh (fingerprints, no valores).
#
# Cubre DOS matchers (ver hooks.json):
#   - Bash: bloquea verbos de dump (cat|bat|less|more|head|tail|grep|awk|sed|strings)
#           sobre archivos .env, y `printenv`/`env` a secas o con pipe.
#   - Read: bloquea file_path que apunte a un .env (sin esto el gate Bash se bypassea
#           leyendo el archivo con el tool Read).
#
# NO bloquea (siguen funcionando):
#   - `cat .env.example` / `.env.sample`  (no son secretos)
#   - `source .env` / `. .env`            (carga sin imprimir)
#   - `env VAR=x cmd`                      (env como runner, no como dump)
#
# Safety stance: over-bloquea a proposito. El modo de falla seguro es negar de mas;
# para un secreto expuesto no hay vuelta atras.

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

# --- helper: un path apunta a un .env sensible? (excluye .example/.sample) ---
_is_sensitive_env_path() {
  local p="$1"
  # bare .env (fin de string o seguido de algo que no sea . _ - alfanumerico)
  if printf '%s' "$p" | grep -Eq '\.env([^A-Za-z0-9._-]|$)'; then
    return 0
  fi
  # .env.<suffix> con suffix != example/sample
  local m sfx
  while IFS= read -r m; do
    [ -z "$m" ] && continue
    sfx="${m#.env.}"
    case "$sfx" in
      example|sample) ;;
      *) return 0 ;;
    esac
  done < <(printf '%s' "$p" | grep -Eo '\.env\.[A-Za-z0-9_-]+' || true)
  return 1
}

_block() {
  cat >&2 <<MSG
BLOCKED: posible dump de secretos desde un archivo .env.

$1

Para diagnosticar credenciales SIN exponer valores, usar env-probe.sh
(imprime solo fingerprints: NAME set=yes|no len=NN sha256_8=xxxxxxxx):

  bash "${PROBE}" .env                 # todas las claves
  bash "${PROBE}" .env VAR1 VAR2        # claves puntuales
  bash "${PROBE}" --compare a.env b.env # diff por fingerprint

Permitido: cat .env.example / .env.sample, source .env, env VAR=x cmd.
MSG
  exit 2
}

# ============================ Matcher: Read ============================
# El tool Read no pasa por Bash; sin este bloqueo el gate se bypassea leyendo .env.
if [ -n "$file_path" ]; then
  if _is_sensitive_env_path "$file_path"; then
    _block "Read de un archivo .env (${file_path}) — leeria secretos en plaintext."
  fi
  # Read de otra cosa: no aplica el resto.
  exit 0
fi

# ============================ Matcher: Bash ============================
[ -z "$cmd" ] && exit 0

# (1) Verbo de dump sobre un archivo .env sensible.
DUMP_VERBS='(cat|bat|less|more|head|tail|grep|egrep|fgrep|awk|sed|strings|xxd|od|nl|tac)'
if printf '%s' "$cmd" | grep -Eq "(^|[|&;[:space:]()])${DUMP_VERBS}([[:space:]]|$)"; then
  if _is_sensitive_env_path "$cmd"; then
    _block "Comando de dump sobre un archivo .env:  ${cmd}"
  fi
fi

# (2) printenv (a secas, con args o con pipe) — siempre vuelca variables del entorno.
if printf '%s' "$cmd" | grep -Eq '(^|[|&;[:space:]()])printenv([[:space:]]|$|\|)'; then
  _block "printenv vuelca variables del entorno (posibles secretos):  ${cmd}"
fi

# (3) env a secas o con pipe (pero NO `env VAR=x cmd`, que solo corre un comando).
if printf '%s' "$cmd" | grep -Eq '(^|[|&;[:space:]()])env([[:space:]]*$|[[:space:]]*\|)'; then
  _block "env sin asignaciones vuelca el entorno (posibles secretos):  ${cmd}"
fi

exit 0
