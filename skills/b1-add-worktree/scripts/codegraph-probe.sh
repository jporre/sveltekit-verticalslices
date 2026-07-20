#!/usr/bin/env bash
# codegraph-probe.sh — probe INFORMATIVO del estado de la db de CodeGraph.
#
# Uso: codegraph-probe.sh [root]
#   root  raíz del repo (default: git toplevel del cwd, o pwd).
#
# Contrato (issue #10 — codegraph es recomendación con fallback rg, NUNCA gate):
# el probe SIEMPRE sale 0. El status NUNCA es un exit code — vive SOLO en la
# última línea, parseable:
#
#     CODEGRAPH_STATUS=ok|stale|missing|broken db_age_days=<n>
#
#   ok      — .codegraph presente, query smoke OK, db fresca vs HEAD.
#   stale   — query smoke OK pero la db quedó detrás de HEAD (sync no la alcanzó).
#   missing — sin .codegraph o sin db (ej. worktree recién creado: db gitignored).
#   broken  — .codegraph presente pero la query smoke falla (backend nativo/WASM roto).
#
# db_age_days = días enteros desde el mtime de la db (-1 si no hay db).
#
# Los callers ELIGEN herramienta según el status; status != ok NUNCA es error:
# si != ok usan rg/grep y NO invocan las tools codegraph_*.
#
# Env knobs:
#   CODEGRAPH_PROBE_TTL         (default 3600)  cache 1h en state-dir
#   CODEGRAPH_PROBE_SMOKE_SECS  (default 15)    timeout de la query smoke
#   CODEGRAPH_PROBE_SYNC_SECS   (default 60)    timeout del intento de sync
#   CODEGRAPH_PROBE_NO_SYNC     (1 = no intentar sync; db atrás de HEAD => stale)
#                                                lo usa setup-worktree.sh (db gitignored)

# NOTA: sin `set -e` a propósito — este script DEBE salir 0 pase lo que pase.
set -u

ROOT="${1:-}"
if [ -z "$ROOT" ]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

CACHE_TTL="${CODEGRAPH_PROBE_TTL:-3600}"
SMOKE_SECS="${CODEGRAPH_PROBE_SMOKE_SECS:-15}"
SYNC_SECS="${CODEGRAPH_PROBE_SYNC_SECS:-60}"

# Timeout portable via perl (NO `timeout`: ausente en macOS base). fork+alarm:
# el hijo hace exec del comando, el padre lo mata con TERM al vencer el alarm y
# devuelve 124. (alarm ANTES de exec NO sobrevive al exec — por eso fork.)
run_timeout() {
  local secs="$1"; shift
  perl -e '
    my $s = shift @ARGV;
    my $pid = fork();
    exit 127 unless defined $pid;
    # Hijo en su propio grupo de procesos: al vencer el timeout matamos TODO el
    # grupo (incluidos nietos), si no un nieto huérfano retiene el fd del `$(...)`
    # y la substitución de comando se cuelga hasta que ese proceso muera.
    if ($pid == 0) { setpgrp(0,0); exec @ARGV or exit 127; }
    local $SIG{ALRM} = sub { kill "TERM", -$pid; kill "KILL", -$pid; };
    alarm $s;
    waitpid($pid, 0);
    my $code = $?;
    alarm 0;
    exit(124) if ($code & 127);
    exit($code >> 8);
  ' "$secs" "$@"
}

# state-dir para el cache (mismo esquema slug que guardrails.sh).
# El slug deriva SIEMPRE de $ROOT (el root probado), NO de CLAUDE_PROJECT_DIR: esa
# variable es constante dentro de una sesión, así que dos roots distintos (worktree
# vs repo principal, o dos worktrees) compartirían el MISMO archivo de cache y un
# status contaminaría al otro durante la ventana de TTL. Cada root => su cache. (issue #37)
state_dir() {
  local slug
  slug="$(printf '%s' "$ROOT" | sed 's|/|-|g')"
  printf '%s/.claude/projects/%s' "$HOME" "$slug"
}
SD="$(state_dir)"
mkdir -p "$SD" 2>/dev/null || true
CACHE="$SD/codegraph-probe.txt"

finish() { # <status> <age_days>
  local line="CODEGRAPH_STATUS=$1 db_age_days=$2"
  printf '%s\n' "$line" > "$CACHE" 2>/dev/null || true
  printf '%s\n' "$line"
  exit 0
}

# Cache 1h: evita repetir smoke+sync dentro de un mismo run.
if [ -f "$CACHE" ]; then
  now=$(date +%s)
  cm=$(stat -f %m "$CACHE" 2>/dev/null || stat -c %Y "$CACHE" 2>/dev/null || echo 0)
  if [ $(( now - cm )) -lt "$CACHE_TTL" ]; then
    cat "$CACHE"
    exit 0
  fi
fi

# Sin CLI codegraph no hay nada que probar.
command -v codegraph >/dev/null 2>&1 || finish missing -1

CG="$ROOT/.codegraph"
DBF=""
[ -d "$CG" ] && DBF="$(find "$CG" -maxdepth 2 -name '*.db' -type f 2>/dev/null | head -1 || true)"

# Sin .codegraph o sin db => missing (correcto en worktrees nuevos: db gitignored).
[ -z "$DBF" ] && finish missing -1

now=$(date +%s)
dbm=$(stat -f %m "$DBF" 2>/dev/null || stat -c %Y "$DBF" 2>/dev/null || echo "$now")
age_days=$(( ( now - dbm ) / 86400 ))

# smoke: query real (usa -p). Solo el exit-code y el STDERR deciden 'broken' — NUNCA
# el contenido de los RESULTADOS de la query (stdout). Con la query genérica "the"
# cualquier snippet legítimo que contenga "Error:", "fatal", etc. hacía matchear el
# grep y reportaba un backend sano como roto (falso positivo). Capturamos solo stderr:
# `2>&1 1>/dev/null` manda stderr a la substitución y stdout (los matches) a /dev/null.
# (issue #37)
err="$(run_timeout "$SMOKE_SECS" codegraph query "the" -p "$ROOT" 2>&1 1>/dev/null)"
rc=$?
if [ "$rc" -ne 0 ] \
   || printf '%s' "$err" | grep -qiE 'unable to open database|SQLITE_CANTOPEN|cannot find module|no such (table|file)|fatal|panic|Error:'; then
  finish broken "$age_days"
fi

# frescura vs HEAD; sync (path posicional) si la db quedó atrás — salvo NO_SYNC.
head_ct="$(git -C "$ROOT" log -1 --format=%ct 2>/dev/null || echo 0)"
status=ok
if [ "$head_ct" -gt "$dbm" ]; then
  if [ "${CODEGRAPH_PROBE_NO_SYNC:-0}" != "1" ]; then
    run_timeout "$SYNC_SECS" codegraph sync "$ROOT" >/dev/null 2>&1 || true
    dbm=$(stat -f %m "$DBF" 2>/dev/null || stat -c %Y "$DBF" 2>/dev/null || echo "$dbm")
    age_days=$(( ( now - dbm ) / 86400 ))
  fi
  [ "$head_ct" -gt "$dbm" ] && status=stale
fi

finish "$status" "$age_days"
