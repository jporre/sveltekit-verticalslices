#!/usr/bin/env bash
# Regresion issue #54 y su follow-up: verify-worktree vs symlinks de config local.
#
# #54: el gate contaba TODOS los archivos de config local del repo padre para exigir
# symlinks, incluidos los trackeados que nunca se symlinkean -> false-fail exit 31.
# Follow-up: los symlinks ahora los crea el hook PostToolUse link-worktree-env.sh
# (no setup-worktree.sh), que puede no haber corrido; el gate 3 degrada a WARN y
# nunca puede fallar por symlinks faltantes.
#
# Uso: bash skills/b7-issue-to-pr/tests/verify-worktree-tracked-env.test.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARDRAILS="$SCRIPT_DIR/../scripts/guardrails.sh"
CFG=".env"                       # patron de config local que verify-worktree inspecciona
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fails=0
assert_exit() { # <esperado> <real> <mensaje>
  if [ "$1" = "$2" ]; then
    echo "ok   - $3"
  else
    echo "FAIL - $3 (esperado exit $1, real $2)"
    fails=$((fails + 1))
  fi
}

# Repo padre minimo con UN archivo de config local trackeado (patron .env.example).
parent="$TMP/parent"
mkdir -p "$parent"
git -C "$parent" init -q
git -C "$parent" config user.email t@t.local
git -C "$parent" config user.name t
printf 'FOO=bar\n' > "$parent/${CFG}.example"
git -C "$parent" add -A
git -C "$parent" commit -qm init

# Worktree provisionado como lo deja setup-worktree.sh: sin symlink del archivo trackeado.
wt="$TMP/worktrees/54-fixture"
mkdir -p "$(dirname "$wt")"
git -C "$parent" worktree add -q "$wt" -b fixture
mkdir -p "$wt/.b7" "$wt/node_modules"
printf '{}\n' > "$wt/.b7/worktree-ready.json"
printf '#!/usr/bin/env bash\n' > "$wt/dev.sh"
chmod +x "$wt/dev.sh"

rc=0; bash "$GUARDRAILS" verify-worktree "$wt" >/dev/null 2>&1 || rc=$?
assert_exit 0 "$rc" "archivo de config trackeado sin symlink no debe fallar el gate"

# Un archivo NO trackeado sin symlink degrada a WARN, nunca exit 31: el symlink lo
# crea el hook link-worktree-env.sh y su ausencia no es culpa del worktree.
printf 'FOO=bar\n' > "$parent/${CFG}.local"
rc=0; out="$(bash "$GUARDRAILS" verify-worktree "$wt" 2>&1)" || rc=$?
assert_exit 0 "$rc" "archivo no trackeado sin symlink no bloquea (gate degradado a WARN)"
if printf '%s' "$out" | grep -q "WARN parent has 1 untracked"; then
  echo "ok   - emite WARN por symlinks faltantes"
else
  echo "FAIL - falta el WARN de symlinks faltantes"
  fails=$((fails + 1))
fi

# Con el symlink presente no hay WARN y sigue pasando.
ln -sf "$parent/${CFG}.local" "$wt/${CFG}.local"
rc=0; out="$(bash "$GUARDRAILS" verify-worktree "$wt" 2>&1)" || rc=$?
assert_exit 0 "$rc" "archivo no trackeado con symlink pasa el gate"
if printf '%s' "$out" | grep -q "WARN parent has"; then
  echo "FAIL - WARN inesperado con symlink presente"
  fails=$((fails + 1))
else
  echo "ok   - sin WARN con symlink presente"
fi

git -C "$parent" worktree remove --force "$wt" >/dev/null 2>&1 || true
[ "$fails" -eq 0 ] || { echo "$fails assertion(s) fallaron"; exit 1; }
echo "verify-worktree-tracked-env: OK"
