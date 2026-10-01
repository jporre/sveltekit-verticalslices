#!/usr/bin/env bash
# drive.sh — corre b10-ship sin humano entre olas: cada ola en una sesión headless NUEVA.
#
# Automatiza "una ola por sesión" (epic-mode.md § Reset de contexto): en vez de /clear +
# re-invocar a mano, el driver relanza el harness mientras la última línea sea
# B10_WAVE_DONE. Cada ola arranca con contexto limpio (~30k) en vez de arrastrar 150k+.
# Mismo driver para Claude Code, pi y Codex: el estado vive en GitHub y .b7/, no en la sesión.
#
# Uso:  drive.sh <claude|pi|codex> <args de b10>     p. ej. drive.sh claude --epic=242
# Env:  DRIVE_MODEL      modelo del harness (default: el configurado en el harness)
#       DRIVE_FLAGS      flags extra del CLI (default claude: --permission-mode auto)
#       DRIVE_MAX_WAVES  tope de sesiones (default 10)
#       DRIVE_LOG_DIR    dónde quedan los logs por ola (default: mktemp)
# Salida: B10_DONE … (exit 0) | DRIVE_STOP … + tail del log (exit 1) — gates humanos,
#         needs-info o fallas cortan el loop: el driver nunca decide por el humano.
set -euo pipefail

H="${1:-}"; shift || true
[ -n "$H" ] && [ $# -gt 0 ] || { echo "Uso: $0 <claude|pi|codex> <args de b10>" >&2; exit 2; }
ARGS="$*"
MAX="${DRIVE_MAX_WAVES:-10}"
LOG_DIR="${DRIVE_LOG_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/b10-drive.XXXXXX")}"
mkdir -p "$LOG_DIR"

case "$H" in
  claude) FLAGS="${DRIVE_FLAGS---permission-mode auto}"
          run() { claude -p "/b-pipeline:b10-ship $ARGS" ${DRIVE_MODEL:+--model "$DRIVE_MODEL"} $FLAGS; } ;;
  pi)     FLAGS="${DRIVE_FLAGS:-}"
          run() { pi -p "/skill:b10-ship $ARGS" ${DRIVE_MODEL:+--model "$DRIVE_MODEL"} $FLAGS; } ;;
  codex)  FLAGS="${DRIVE_FLAGS:-}"
          run() { codex exec ${DRIVE_MODEL:+-m "$DRIVE_MODEL"} $FLAGS "Usa el skill b10-ship con los argumentos: $ARGS"; } ;;
  *) echo "drive: harness desconocido '$H' (claude|pi|codex)" >&2; exit 2 ;;
esac
command -v "$H" >/dev/null || { echo "drive: '$H' no está en PATH" >&2; exit 2; }

for ((w = 1; w <= MAX; w++)); do
  log="$LOG_DIR/wave-$w.log"
  run > "$log" 2>&1 || true
  last="$(grep -E '^(B10_DONE|B10_WAVE_DONE)' "$log" | tail -1 || true)"
  case "$last" in
    B10_WAVE_DONE*) echo "drive: sesión $w → $last" ;;
    B10_DONE*)      echo "$last"; exit 0 ;;
    *)              echo "DRIVE_STOP wave=$w log=$log"; tail -n 15 "$log"; exit 1 ;;
  esac
done
echo "DRIVE_STOP max_waves=$MAX log_dir=$LOG_DIR"
exit 1
