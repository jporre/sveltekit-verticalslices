#!/usr/bin/env bash
# drive.sh: relanza el harness mientras la sesión termine en B10_WAVE_DONE, sale 0 con
# B10_DONE y corta (exit 1) ante cualquier otra salida (gate humano, falla).
#
# Uso: bash skills/b10-ship/tests/drive.test.sh
set -uo pipefail

DRIVE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/drive.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
fails=0
ok()   { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; fails=$((fails + 1)); }

# Harness falso: responde la línea N del guion en la llamada N y registra sus argumentos.
fake() {
  printf '%s\n' "$@" > "$TMP/script"; : > "$TMP/calls"
  for h in claude pi codex; do
    cat > "$TMP/bin/$h" <<SH
#!/usr/bin/env bash
echo "\$*" >> "$TMP/calls"
n=\$(wc -l < "$TMP/calls"); echo "trabajando…"; sed -n "\${n}p" "$TMP/script"
SH
    chmod +x "$TMP/bin/$h"
  done
}
export PATH="$TMP/bin:$PATH" DRIVE_LOG_DIR="$TMP/logs"

fake "B10_WAVE_DONE epic=9 wave=1 next=x" "B10_WAVE_DONE epic=9 wave=2 next=x" "B10_DONE issue=9 phase_final=done pr=none"
out="$(bash "$DRIVE" claude --epic=9)"; rc=$?
[ "$rc" -eq 0 ] && ok "claude: exit 0 al llegar a B10_DONE" || fail "claude: exit $rc"
[ "$(wc -l < "$TMP/calls" | tr -d ' ')" = 3 ] && ok "claude: 3 sesiones nuevas (2 olas + cierre)" || fail "claude: $(wc -l < "$TMP/calls") sesiones"
grep -q -- '-p /b-pipeline:b10-ship --epic=9 --permission-mode auto' "$TMP/calls" && ok "claude: -p con el slash del plugin y permiso auto por default" || fail "claude: args $(head -1 "$TMP/calls")"
printf '%s\n' "$out" | tail -1 | grep -q '^B10_DONE' && ok "claude: última línea B10_DONE" || fail "claude: salida '$out'"

fake "B10_WAVE_DONE epic=9 wave=1 next=x" "AWAITING epic-approved: gate humano"
bash "$DRIVE" pi --epic=9 >/dev/null; rc=$?
[ "$rc" -eq 1 ] && ok "pi: corta con exit 1 en un gate humano" || fail "pi: exit $rc"
[ "$(wc -l < "$TMP/calls" | tr -d ' ')" = 2 ] && grep -q -- '-p /skill:b10-ship --epic=9' "$TMP/calls" && ok "pi: /skill:b10-ship y no relanza tras el gate" || fail "pi: llamadas $(cat "$TMP/calls")"

fake "B10_WAVE_DONE wave=1" "B10_WAVE_DONE wave=2" "B10_WAVE_DONE wave=3"
DRIVE_MAX_WAVES=2 DRIVE_MODEL=gpt-x bash "$DRIVE" codex --epic=9 >/dev/null; rc=$?
[ "$rc" -eq 1 ] && [ "$(wc -l < "$TMP/calls" | tr -d ' ')" = 2 ] && ok "codex: respeta DRIVE_MAX_WAVES" || fail "codex: exit $rc, $(wc -l < "$TMP/calls") sesiones"
grep -q -- '^exec -m gpt-x Usa el skill b10-ship con los argumentos: --epic=9' "$TMP/calls" && ok "codex: exec con modelo y prompt" || fail "codex: args $(head -1 "$TMP/calls")"

bash "$DRIVE" nope --epic=9 >/dev/null 2>&1; [ $? -eq 2 ] && ok "harness desconocido → exit 2" || fail "harness desconocido no sale 2"

[ "$fails" -eq 0 ] || { echo "$fails assertion(s) fallaron"; exit 1; }
echo "drive: OK"
