#!/usr/bin/env bash
# Regresion issue #57: validate-spec.py y exec-spec.sh rechazaban worktrees.
#
# En un worktree `.git` es un gitfile, no un directorio; el check `-d .git`
# fallaba con "REPO no es un repo git" y forzaba el workaround de clonar el
# repo a mano. Ambos scripts validan ahora con `git rev-parse --is-inside-work-tree`.
#
# Uso: bash skills/b11-spec-exec/tests/validate-worktree.test.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATE="$SCRIPT_DIR/../scripts/validate-spec.py"
EXEC="$SCRIPT_DIR/../scripts/exec-spec.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fails=0
check() { # <ok:0|1> <mensaje>
  if [ "$1" = "0" ]; then echo "ok   - $2"; else echo "FAIL - $2"; fails=$((fails + 1)); fi
}

# Repo minimo + worktree (fixture en tmp, patron de verify-worktree-tracked-env.test.sh).
parent="$TMP/parent"
git init -q "$parent"
git -C "$parent" config user.email test@test
git -C "$parent" config user.name test
printf 'hola\nmundo\n' > "$parent/a.txt"
git -C "$parent" -c commit.gpgsign=false add a.txt
git -C "$parent" -c commit.gpgsign=false commit -qm init
wt="$TMP/wt-57"
git -C "$parent" worktree add -q "$wt" -b fixture-57

cat > "$TMP/SPEC.md" <<EOF
REPO: $wt

ARCHIVO: a.txt
BUSCAR:
\`\`\`
hola
\`\`\`
REEMPLAZAR:
\`\`\`
chao
\`\`\`

## Aceptación
\`\`\`
grep -q chao a.txt
\`\`\`

## Estado git esperado
\`\`\`
 M a.txt
\`\`\`
EOF

out="$(python3 "$VALIDATE" "$TMP/SPEC.md" 2>&1)"; rc=$?
echo "$out" | grep -q "SPEC OK"; check $? "validate-spec.py da SPEC OK con REPO: worktree (exit $rc)"

# exec-spec.sh: el gate de repo debe pasar el worktree y frenar recien en el
# gate siguiente (tree sucio, que provocamos a proposito) — nunca en "no es un repo git".
printf 'sucio\n' > "$wt/b.txt"
out="$(bash "$EXEC" "$TMP/SPEC.md" 2>&1)"; rc=$?
echo "$out" | grep -q "REPO no es un repo git" && check 1 "exec-spec.sh acepta el worktree como repo" \
  || check 0 "exec-spec.sh acepta el worktree como repo"
echo "$out" | grep -q "cambios sin commitear"; check $? "exec-spec.sh freno en el gate esperado (tree sucio, exit $rc)"

git -C "$parent" worktree remove --force "$wt" 2>/dev/null || true
[ "$fails" -eq 0 ] && { echo "PASS validate-worktree.test.sh"; exit 0; } || { echo "FAIL ($fails)"; exit 1; }
