#!/usr/bin/env bash
# Regresión: error-hash.sh debe distinguir errores distintos de `svelte-check --output
# machine` (líneas `<ts> ERROR …`) y ser estable ante timestamp/posición; antes ningún
# patrón calzaba, el hash era el del vacío y dos iteraciones rojas cualesquiera
# abortaban por no-progress.
#
# Uso: bash skills/b7-issue-to-pr/tests/error-hash.test.sh
set -uo pipefail

H="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../scripts/error-hash.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
EMPTY=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855

fails=0
check() { if [ "$2" = 0 ]; then echo "ok   - $1"; else echo "FAIL - $1"; fails=$((fails + 1)); fi; }

log() { # <archivo> <ts> <l:c> <mensaje>
  printf '%s START "/wt"\n%s ERROR "src/routes/foo/+page.svelte" %s "%s"\n%s COMPLETED 9 FILES 1 ERRORS 0 WARNINGS\n' \
    "$2" "$2" "$3" "$4" "$2" > "$TMP/$1"
}
log a 1590680326290 7:9 "Property 'nombre' does not exist on type 'Tarea'."
log b 1590680399999 12:3 "Property 'nombre' does not exist on type 'Tarea'."
log c 1590680399999 7:9 "Property 'rut' does not exist on type 'Cliente'."
printf 'src/routes/foo/+page.svelte:4:<button on:click={x}>\nVERIFY_RESULT react=fail\n' > "$TMP/d"
printf 'src/routes/bar/+page.svelte:9:  export let id;\nVERIFY_RESULT react=fail\n' > "$TMP/e"

ha="$(bash "$H" "$TMP/a")"; hb="$(bash "$H" "$TMP/b")"; hc="$(bash "$H" "$TMP/c")"
hd="$(bash "$H" "$TMP/d")"; he="$(bash "$H" "$TMP/e")"

[ "$ha" != "$EMPTY" ]; check "error machine de svelte-check produce firma no vacía" $?
[ "$ha" = "$hb" ]; check "mismo error con otro timestamp/posición = mismo hash" $?
[ "$ha" != "$hc" ]; check "errores distintos = hash distinto" $?
[ "$hd" != "$EMPTY" ] && [ "$hd" != "$he" ]; check "sin patrón de error se firma la cola del log, no el vacío" $?

[ "$fails" -eq 0 ] || { echo "$fails assertion(s) fallaron"; exit 1; }
echo "error-hash: OK"
