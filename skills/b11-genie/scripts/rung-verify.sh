#!/usr/bin/env bash
# ABOUTME: gate mecanico por peldaño de b11-genie — captura baseline de check+build y
# ABOUTME: compara cada peldaño contra el, para no atribuirse errores preexistentes.
# Uso: rung-verify.sh baseline   (correr una vez en FASE 0)
#      rung-verify.sh E<n>       (tras cada peldaño; emite RUNG_VERIFY ok|fail rung=E<n>)
set -uo pipefail

TOP=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
HASH=$(printf '%s' "$TOP" | cksum | cut -d' ' -f1)   # ponytail: hash del path para que repos con igual basename no colisionen en /tmp
STATE="/tmp/b11-genie-$(basename "$TOP")-$HASH.baseline"

# detectar package manager por lockfile
if   [ -f pnpm-lock.yaml ]; then PM=pnpm
elif [ -f bun.lockb ] || [ -f bun.lock ]; then PM=bun
elif [ -f yarn.lock ]; then PM=yarn
else PM=npm; fi

run_check() { # cuenta errores del script check; 999 = script inexistente
  if grep -q '"check"' package.json; then
    local out rc n
    out=$($PM run check 2>&1); rc=$?
    n=$(printf '%s' "$out" | grep -iEo 'found [0-9]+ error' | grep -Eo '[0-9]+' | head -1 || true)
    if [ -n "$n" ]; then echo "$n"
    elif [ "$rc" -eq 0 ]; then echo 0
    else echo 100   # ponytail: check fallo sin resumen parseable (crash, tsc, deps) — cuenta como roto, nunca como limpio
    fi
  else
    echo 999
  fi
}

run_build() { # exit code del build; 999 = script inexistente
  if grep -q '"build"' package.json; then
    $PM run build >/dev/null 2>&1 && echo 0 || echo 1
  else
    echo 999
  fi
}

case "${1:-}" in
  baseline)
    CHECK=$(run_check); BUILD=$(run_build)
    printf 'CHECK_ERRORS=%s\nBUILD_EXIT=%s\n' "$CHECK" "$BUILD" > "$STATE"
    echo "BASELINE check_errors=$CHECK build_exit=$BUILD pm=$PM state=$STATE"
    [ "$CHECK" != 0 ] || [ "$BUILD" != 0 ] && echo "AVISO: baseline con errores preexistentes — los peldaños comparan contra esto, no contra cero"
    exit 0
    ;;
  E1|E2|E3|E4|E5|E6)
    [ -f "$STATE" ] || { echo "RUNG_VERIFY fail rung=$1 reason=sin-baseline (correr 'rung-verify.sh baseline' primero)"; exit 4; }
    . "$STATE"
    CHECK=$(run_check); BUILD=$(run_build)
    # script que no existia en el baseline y ahora si (E1 lo agrego): exigir limpio, no comparar contra 999
    [ "$CHECK_ERRORS" = 999 ] && [ "$CHECK" != 999 ] && CHECK_ERRORS=0
    [ "$BUILD_EXIT" = 999 ] && [ "$BUILD" != 999 ] && BUILD_EXIT=0
    OK=yes
    [ "$CHECK" != 999 ] && [ "$CHECK" -gt "$CHECK_ERRORS" ] && OK=no
    [ "$BUILD" != 999 ] && [ "$BUILD" -gt "$BUILD_EXIT" ] && OK=no
    if [ "$OK" = yes ]; then
      echo "RUNG_VERIFY ok rung=$1 check_errors=$CHECK baseline=$CHECK_ERRORS build=$BUILD"
    else
      echo "RUNG_VERIFY fail rung=$1 check_errors=$CHECK baseline=$CHECK_ERRORS build=$BUILD"
      exit 1
    fi
    ;;
  *)
    echo "uso: rung-verify.sh baseline | rung-verify.sh E<1-6>"; exit 2
    ;;
esac
