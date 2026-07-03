#!/usr/bin/env bash
# lib.sh — contratos inter-skill compartidos del pipeline b (bash 3.2-safe).
# Uso: . "$PLUGIN_ROOT/scripts/lib.sh"   |   bash lib.sh selftest
#
# Cada contrato entre orquestadores vive UNA vez aca: el drift copy-paste ya
# fue danino (deps fantasma por gramaticas distintas de '## Blocked by').
#
# Funciones:
#   bp_find_pr <issue> [open|merged]   PR cuyo body cierra el issue, con frontera
#                                      de digitos ([^0-9]|$): #261 NO matchea #2610.
#                                      Imprime el numero o vacio.
#   bp_b6_verdict <pr>                 delega en b6-pr-review/scripts/verdict.sh read
#                                      (lector unico del marker; exit 3 sin marker).
#   bp_label_event <issue|pr> <label>  ultimo evento labeled de ese label, en UNA
#                                      llamada --paginate -> "actor<TAB>created_at"
#                                      (vacio si no hubo). La comparacion de
#                                      timestamps queda en el caller.
#   bp_blocked_by                      stdin=body -> numeros de la seccion
#                                      '## Blocked by', uno por linea, orden
#                                      numerico sin duplicados. Gramatica python
#                                      con lookahead NO inclusivo: un heading
#                                      inmediato despues de la seccion NO aporta
#                                      deps fantasma (bug del sed viejo de run.sh).

# set estricto solo al ejecutar directo (selftest); al sourcear NO se impone
# set -e/-u al caller (los snippets de SKILL.md corren sin modo estricto).
if [ "${BASH_SOURCE[0]}" = "$0" ]; then set -euo pipefail; fi

# Raiz del plugin derivada de la ubicacion de este archivo (<root>/scripts/lib.sh).
_BP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bp_find_pr() {
  local n="$1" state="${2:-open}"
  gh pr list --state "$state" --limit 100 --json number,body \
    --jq "[.[] | select(.body | test(\"[Cc]loses #${n}([^0-9]|$)\"))] | (.[0].number // empty)"
}

bp_b6_verdict() {
  bash "$_BP_ROOT/skills/b6-pr-review/scripts/verdict.sh" read "$1"
}

bp_label_event() {
  local n="$1" label="$2"
  # OJO: gh --paginate aplica el jq POR PAGINA — no usar `last` sobre el array;
  # se emite un valor por evento y el tail -1 se queda con el ultimo.
  gh api "repos/{owner}/{repo}/issues/${n}/events" --paginate \
    --jq ".[] | select(.event==\"labeled\" and .label.name==\"${label}\") | \"\(.actor.login)\t\(.created_at)\"" \
    | tail -1
}

bp_blocked_by() {
  python3 -c '
import re, sys
body = sys.stdin.read()
m = re.search(r"##+\s*[Bb]locked\s*by:?(.*?)(?=\n##|\Z)", body, re.S)
for d in (sorted({int(x) for x in re.findall(r"#(\d+)", m.group(1))}) if m else []):
    print(d)
'
}

# Fixtures de regresion offline (solo bp_blocked_by es pura; el resto pega a gh).
bp_selftest() {
  local fails=0 out
  # Regresion: heading inmediato tras '## Blocked by' -> cero deps fantasma
  # (el sed inclusivo viejo capturaba el #N de la linea del heading siguiente).
  out="$(printf '## Blocked by\n## Referencias #99\n' | bp_blocked_by)"
  [ -z "$out" ] || { echo "lib.sh selftest: deps fantasma '$out' (esperaba vacio)" >&2; fails=1; }
  out="$(printf 'intro #7\n\n## Blocked by\n- #15\n- #4\n- #4\n\n## Otro\n- #99\n' | bp_blocked_by | tr '\n' ',')"
  [ "$out" = "4,15," ] || { echo "lib.sh selftest: esperaba '4,15,' -> '$out'" >&2; fails=1; }
  out="$(printf 'body sin seccion #3\n' | bp_blocked_by)"
  [ -z "$out" ] || { echo "lib.sh selftest: sin seccion debe dar vacio -> '$out'" >&2; fails=1; }
  [ -f "$_BP_ROOT/skills/b6-pr-review/scripts/verdict.sh" ] \
    || { echo "lib.sh selftest: no encuentro verdict.sh desde $_BP_ROOT" >&2; fails=1; }
  [ "$fails" -eq 0 ] || return 1
  echo "BP_LIB=ok"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  case "${1:-}" in
    selftest) bp_selftest ;;
    *) echo "Usage: . lib.sh  |  $0 selftest" >&2; exit 2 ;;
  esac
fi
