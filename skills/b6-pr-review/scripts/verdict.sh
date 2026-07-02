#!/usr/bin/env bash
set -euo pipefail

# verdict.sh — fuente unica del veredicto de b6-pr-review (bash 3.2-safe).
#
# El veredicto se COMPUTA de los counts del reporte (no del juicio del modelo)
# y hay UN solo lector del marker para b7/b9/b10 (antes: 4 variantes drifteadas).
#
# Regla de veredicto (deterministica):
#   blockers > 0            -> request-changes
#   blockers == 0, warn > 0 -> approve-with-changes
#   blockers == 0, warn == 0-> approve
#
# Formato de finding contable (una linea, al principio de linea):
#   - **BLOCKER**: <texto>
#   - **WARNING**: <texto>
#   - **SUGGESTION**: <texto>
# Se cuentan SOLO estas lineas (no tokens crudos) para no doble-contar la tabla
# resumen (`| Codigo | BLOCKER |`) ni los headers de area.
#
# Marker durable (ultima linea del reporte publicado en el PR):
#   <!-- b6:verdict=approve|approve-with-changes|request-changes blockers=N warnings=M -->
#
# Subcomandos:
#   check <report.md>   cuenta blockers/warnings, computa verdict esperado,
#                       verifica marker vs counts y vs regla. exit 4 en mismatch.
#   read <pr>           un solo `gh pr view --json comments,reviews`; ultimo marker;
#                       imprime `B6_VERDICT verdict=.. blockers=N warnings=M pr=P`.
#                       exit 3 si no hay marker.
#   stamp <report.md>   estampa/reescribe el marker computado al final del reporte.
#
# Exit codes: 0 ok | 2 uso | 3 sin marker (read) | 4 mismatch (check)

usage() {
  echo "Usage: $0 {check <report.md> | read <pr> | stamp <report.md>}" >&2
  exit 2
}

# Cuenta lineas de finding contable de una severidad dada en un archivo.
count_findings() {
  # $1=file  $2=SEVERITY  -> imprime el conteo
  grep -cE "^- \*\*$2\*\*:" "$1" 2>/dev/null || true
}

# Deriva el verdict esperado de los counts.
verdict_for() {
  # $1=blockers $2=warnings
  if [ "$1" -gt 0 ]; then
    echo "request-changes"
  elif [ "$2" -gt 0 ]; then
    echo "approve-with-changes"
  else
    echo "approve"
  fi
}

# Extrae el ultimo marker de stdin. Imprime "verdict blockers warnings" o vacio.
parse_marker() {
  # lee stdin, emite: <verdict> <blockers> <warnings> (una linea) del ultimo marker.
  # `|| true` en el grep: sin match no debe romper el pipeline bajo `pipefail`.
  { grep -oE 'b6:verdict=[a-z-]+ blockers=[0-9]+ warnings=[0-9]+' 2>/dev/null || true; } \
    | tail -1 \
    | sed -E 's/b6:verdict=([a-z-]+) blockers=([0-9]+) warnings=([0-9]+)/\1 \2 \3/'
}

cmd_check() {
  local file="$1"
  [ -f "$file" ] || { echo "verdict.sh: no existe $file" >&2; exit 2; }

  local blockers warnings expected
  blockers="$(count_findings "$file" BLOCKER)"
  warnings="$(count_findings "$file" WARNING)"
  expected="$(verdict_for "$blockers" "$warnings")"

  local marker mv mb mw
  marker="$(parse_marker < "$file")"
  if [ -z "$marker" ]; then
    echo "verdict.sh check: FALTA marker <!-- b6:verdict=... blockers=N warnings=M --> en $file" >&2
    echo "verdict.sh check: counts reales -> blockers=$blockers warnings=$warnings verdict=$expected" >&2
    exit 4
  fi
  mv="$(echo "$marker" | awk '{print $1}')"
  mb="$(echo "$marker" | awk '{print $2}')"
  mw="$(echo "$marker" | awk '{print $3}')"

  local ok=1
  if [ "$mb" != "$blockers" ]; then
    echo "verdict.sh check: MISMATCH blockers marker=$mb real=$blockers" >&2; ok=0
  fi
  if [ "$mw" != "$warnings" ]; then
    echo "verdict.sh check: MISMATCH warnings marker=$mw real=$warnings" >&2; ok=0
  fi
  if [ "$mv" != "$expected" ]; then
    echo "verdict.sh check: MISMATCH verdict marker=$mv esperado=$expected (blockers=$blockers warnings=$warnings)" >&2; ok=0
  fi
  [ "$ok" -eq 1 ] || exit 4
  echo "B6_VERDICT verdict=$mv blockers=$mb warnings=$mw"
}

cmd_read() {
  local pr="$1"
  local bodies marker
  # Un solo llamado a la API. El marker puede vivir en comentarios O en reviews
  # (un review COMMENTED no aparece en .comments).
  bodies="$(gh pr view "$pr" --json comments,reviews \
    --jq '(.comments[]?.body, .reviews[]?.body)' 2>/dev/null || true)"
  marker="$(printf '%s\n' "$bodies" | parse_marker)"
  if [ -z "$marker" ]; then
    echo "verdict.sh read: sin marker b6 en PR #$pr" >&2
    exit 3
  fi
  local v b w
  v="$(echo "$marker" | awk '{print $1}')"
  b="$(echo "$marker" | awk '{print $2}')"
  w="$(echo "$marker" | awk '{print $3}')"
  echo "B6_VERDICT verdict=$v blockers=$b warnings=$w pr=$pr"
}

cmd_stamp() {
  local file="$1"
  [ -f "$file" ] || { echo "verdict.sh: no existe $file" >&2; exit 2; }
  local blockers warnings verdict
  blockers="$(count_findings "$file" BLOCKER)"
  warnings="$(count_findings "$file" WARNING)"
  verdict="$(verdict_for "$blockers" "$warnings")"
  local newmarker="<!-- b6:verdict=$verdict blockers=$blockers warnings=$warnings -->"
  # Borrar cualquier marker previo y anexar el computado al final.
  local tmp; tmp="$(mktemp)"
  grep -vE '<!-- b6:verdict=' "$file" > "$tmp" 2>/dev/null || true
  # sacar lineas en blanco finales, luego anexar
  printf '%s\n\n%s\n' "$(cat "$tmp")" "$newmarker" > "$file"
  rm -f "$tmp"
  echo "B6_VERDICT verdict=$verdict blockers=$blockers warnings=$warnings"
}

[ "$#" -ge 1 ] || usage
sub="$1"; shift || true
case "$sub" in
  check) [ "$#" -ge 1 ] || usage; cmd_check "$1" ;;
  read)  [ "$#" -ge 1 ] || usage; cmd_read "$1" ;;
  stamp) [ "$#" -ge 1 ] || usage; cmd_stamp "$1" ;;
  *) usage ;;
esac
