#!/usr/bin/env bash
# Vectores de hooks/block-env-dump.sh. Uso: bash hooks/tests/block-env-dump.test.sh
# Sale con 1 si algún vector no da el exit code esperado (0 = permite, 2 = bloquea).
set -u
HOOK="${HOOK:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/hooks/block-env-dump.sh}"
fail=0
check() { # <esperado> <bash|read> <comando o path>
  local want="$1" kind="$2" val="$3" json got
  if [ "$kind" = bash ]; then
    json=$(jq -cn --arg c "$val" '{tool_name:"Bash",tool_input:{command:$c}}')
  else
    json=$(jq -cn --arg p "$val" '{tool_name:"Read",tool_input:{file_path:$p}}')
  fi
  printf '%s' "$json" | bash "$HOOK" >/dev/null 2>&1; got=$?
  if [ "$got" = "$want" ]; then
    echo "ok    [$kind] $val"
  else
    echo "FAIL  [$kind] $val  (esperado $want, obtuvo $got)"; fail=1
  fi
}

echo "== deben BLOQUEAR (exit 2)"
check 2 bash 'cat .env'
check 2 bash 'grep FOO .env'
check 2 bash 'head -n 3 .env.local'
check 2 bash 'sudo cat /srv/app/.env'
check 2 bash 'echo hola; cat .env'
check 2 bash 'cat ./.env | head -5'
check 2 bash 'echo $(cat .env)'
check 2 bash 'FOO=1 tail .env'
check 2 bash 'pnpm build && awk -F= "{print}" .env.production'
check 2 bash 'printenv'
check 2 bash 'printenv DATABASE_URL'
check 2 bash 'env | grep DB'
check 2 read '/repo/.env'
check 2 read '/repo/.env.production'

echo "== deben PERMITIR (exit 0)"
check 0 bash 'cat .env.example'
check 0 bash 'source .env && pnpm dev'
check 0 bash "bash -c 'source .env; psql \"\$DATABASE_URL\" -X -A -c \"select 1\"' | grep -c row"
check 0 bash "bash -c 'source .env; psql \"\$DATABASE_URL\" -c \"select 1\"' | head -3"
check 0 bash 'node -e "console.log(process.env.X)"'
check 0 bash 'grep -rn process.env.DATABASE_URL src/ | head'
check 0 bash 'env VAR=x cmd'
check 0 bash 'sed -n "1,20p" hooks/block-env-dump.sh'
check 0 bash 'cat src/lib/env.ts'
check 0 bash 'git diff -- .env.example'
check 0 bash 'ls -la .env'
check 0 bash 'perl -pi -e "s/x/y/" memory/hook-block-env-dump-bash.md && grep -n env memory/*.md'
check 0 read '/repo/.env.example'
check 0 read '/repo/src/lib/env.ts'

[ "$fail" = 0 ] && echo "TODOS OK" || echo "HAY FALLAS"
exit "$fail"
