#!/usr/bin/env bash
# env-probe.sh — diagnostica claves de un archivo .env SIN imprimir sus valores.
#
# Por cada clave imprime solo un fingerprint:
#     NAME set=yes|no len=NN sha256_8=xxxxxxxx
#
# len   = largo del valor (0 si la clave no esta seteada)
# sha256_8 = primeros 8 hex del sha256 del valor ("--------" si no seteada)
#
# El incidente real (sesion 80744a45) fue un dump de secretos en plaintext; el bug
# de la credencial GCP truncada se diagnostico por LONGITUD — el fingerprint basta
# para comparar/diagnosticar sin exponer el secreto.
#
# Uso:
#   env-probe.sh <archivo.env>                 # lista TODAS las claves del archivo
#   env-probe.sh <archivo.env> VAR1 VAR2 ...   # solo esas claves (set=no si faltan)
#   env-probe.sh --compare a.env b.env         # diffea por fingerprint (no por valor)
#
# Notas:
# - Soporta lineas `NAME=val`, `export NAME=val`, valores con comillas simples/dobles.
# - Ignora comentarios (#...) y lineas en blanco.

set -euo pipefail

# --- sha256 portable (macOS: shasum; linux: sha256sum) ---
_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  else
    shasum -a 256 | awk '{print $1}'
  fi
}

# Fingerprint de un valor (recibido por stdin para no exponerlo en argv/ps).
_fp8() { _sha256 | cut -c1-8; }

# Parsea un archivo .env a lineas "NAME<TAB>VALUE". No imprime valores; solo se usa
# internamente. Quita `export `, comillas envolventes y comentarios/blancos.
_parse_env() {
  local file="$1"
  # Leer linea por linea preservando el valor tal cual (sin word-splitting).
  while IFS= read -r line || [ -n "$line" ]; do
    # trim leading whitespace
    line="${line#"${line%%[![:space:]]*}"}"
    [ -z "$line" ] && continue
    case "$line" in
      \#*) continue ;;
    esac
    line="${line#export }"
    line="${line#export	}"
    case "$line" in
      *=*) : ;;
      *) continue ;;
    esac
    local name="${line%%=*}"
    local val="${line#*=}"
    # trim trailing whitespace del nombre
    name="${name%"${name##*[![:space:]]}"}"
    name="${name#"${name%%[![:space:]]*}"}"
    [ -z "$name" ] && continue
    # quitar comillas envolventes del valor (una sola capa)
    case "$val" in
      \"*\") val="${val#\"}"; val="${val%\"}" ;;
      \'*\') val="${val#\'}"; val="${val%\'}" ;;
    esac
    printf '%s\t%s\n' "$name" "$val"
  done < "$file"
}

# Devuelve el valor (por stdout) de una clave en un archivo, exit 1 si no existe.
_value_of() {
  local file="$1" key="$2" found=1 out=""
  while IFS=$'\t' read -r n v; do
    if [ "$n" = "$key" ]; then out="$v"; found=0; fi
  done < <(_parse_env "$file")
  [ "$found" -eq 0 ] || return 1
  printf '%s' "$out"
}

# Imprime la linea de fingerprint para (key, presente?, valor).
_print_fp() {
  local key="$1" present="$2" val="${3-}"
  if [ "$present" = "yes" ]; then
    local len fp
    len="${#val}"
    fp="$(printf '%s' "$val" | _fp8)"
    printf '%s set=yes len=%s sha256_8=%s\n' "$key" "$len" "$fp"
  else
    printf '%s set=no len=0 sha256_8=--------\n' "$key"
  fi
}

cmd_probe() {
  local file="$1"; shift
  if [ ! -f "$file" ]; then
    echo "env-probe: no existe el archivo: $file" >&2
    exit 2
  fi
  if [ "$#" -eq 0 ]; then
    # Todas las claves del archivo, en orden de aparicion.
    while IFS=$'\t' read -r n v; do
      _print_fp "$n" "yes" "$v"
    done < <(_parse_env "$file")
  else
    # Solo las claves pedidas.
    local key val
    for key in "$@"; do
      if val="$(_value_of "$file" "$key")"; then
        _print_fp "$key" "yes" "$val"
      else
        _print_fp "$key" "no"
      fi
    done
  fi
}

cmd_compare() {
  local a="$1" b="$2"
  for f in "$a" "$b"; do
    [ -f "$f" ] || { echo "env-probe: no existe el archivo: $f" >&2; exit 2; }
  done
  # Union de claves (orden estable: primero las de A, luego las nuevas de B).
  local keys=()
  while IFS=$'\t' read -r n v; do keys+=("$n"); done < <(_parse_env "$a")
  while IFS=$'\t' read -r n v; do
    local seen=0 k
    for k in "${keys[@]:-}"; do [ "$k" = "$n" ] && seen=1 && break; done
    [ "$seen" -eq 0 ] && keys+=("$n")
  done < <(_parse_env "$b")

  local key va vb fa fb match
  for key in "${keys[@]:-}"; do
    [ -z "$key" ] && continue
    if va="$(_value_of "$a" "$key")"; then fa="$(printf '%s' "$va" | _fp8)"; else fa="--------"; fi
    if vb="$(_value_of "$b" "$key")"; then fb="$(printf '%s' "$vb" | _fp8)"; else fb="--------"; fi
    if [ "$fa" = "$fb" ]; then match="yes"; else match="no"; fi
    printf '%s a=%s b=%s match=%s\n' "$key" "$fa" "$fb" "$match"
  done
}

main() {
  if [ "$#" -lt 1 ]; then
    cat >&2 <<USAGE
Uso:
  env-probe.sh <archivo.env>                 lista fingerprints de todas las claves
  env-probe.sh <archivo.env> VAR1 VAR2 ...   fingerprints solo de esas claves
  env-probe.sh --compare a.env b.env         diffea dos .env por fingerprint
USAGE
    exit 2
  fi
  case "$1" in
    --compare)
      shift
      [ "$#" -eq 2 ] || { echo "env-probe: --compare requiere exactamente 2 archivos" >&2; exit 2; }
      cmd_compare "$1" "$2"
      ;;
    -h|--help)
      main; exit 0 ;;
    *)
      cmd_probe "$@"
      ;;
  esac
}

main "$@"
