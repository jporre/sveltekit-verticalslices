#!/usr/bin/env bash
# local-ci.sh — la suite completa del proyecto, local, sin GitHub Actions.
# Uso: local-ci.sh [dir] [--skip-check]   (default: cwd; dir = repo o worktree de la app)
# Corre, en orden y parando en la primera falla, los scripts que el package.json
# declare: check:machine (o check) -> test:unit (o test) -> build.
# --skip-check: el llamador ya pasó check:machine sobre este mismo árbol (b7 tras
# verify.sh verde); el paso se reporta `check:verified` y no se repite.
# Salida: tail del log si falla + última línea machine-readable:
#   LOCAL_CI=pass|fail steps=check:ok,test:ok,build:skip log=<path>
# Exit 0 pass, 1 fail, 2 sin package.json.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

dir=. skip_check=0
for a in "$@"; do case "$a" in --skip-check) skip_check=1 ;; *) dir="$a" ;; esac; done
dir="$(cd "$dir" && pwd)" || exit 2
[ -f "$dir/package.json" ] || { echo "LOCAL_CI=fail steps= log= (sin package.json en $dir)"; exit 2; }
pm="$(bp_pm "$dir")"
log="${TMPDIR:-/tmp}/local-ci-$(bp_slug "$dir").log"
: >"$log"

has() { python3 -c 'import json,sys; sys.exit(0 if sys.argv[2] in json.load(open(sys.argv[1])).get("scripts",{}) else 1)' "$dir/package.json" "$1"; }
pick() { for s in "$@"; do has "$s" && { echo "$s"; return; }; done; }

steps="" st=pass
run() {  # run <nombre> <script|vacío>
  local name="$1" s="$2"
  [ "$st" = fail ] && return
  if [ -z "$s" ]; then steps="$steps,$name:skip"; return; fi
  echo "=== $pm run $s ===" >>"$log"
  if (cd "$dir" && CI=true "$pm" run "$s") >>"$log" 2>&1; then
    steps="$steps,$name:ok"
  else
    steps="$steps,$name:fail"; st=fail
  fi
}

if [ "$skip_check" = 1 ]; then steps=",check:verified"; else run check "$(pick check:machine check)"; fi
run test "$(pick test:unit test)"   # CI=true: vitest corre sin watch
run build "$(pick build)"

[ "$st" = fail ] && tail -40 "$log"
echo "LOCAL_CI=$st steps=${steps#,} log=$log"
[ "$st" = pass ]
