#!/usr/bin/env bash
# codegraph-probe.sh — probe INFORMATIVO del estado de la db de CodeGraph.
#
# Uso: codegraph-probe.sh [root]
#   root  raiz del repo (default: git toplevel del cwd, o pwd).
#
# Contrato (issue #10 — codegraph es recomendacion con fallback rg, NUNCA gate):
# el probe SIEMPRE sale 0. El status NUNCA es un exit code — vive SOLO en la
# ultima linea, parseable:
#
#     CODEGRAPH_STATUS=ok|stale|missing|broken db_age_days=<n>
#
#   ok      — .codegraph presente, query smoke OK, db fresca vs HEAD.
#   stale   — query smoke OK pero la db quedo detras de HEAD (sync no la alcanzo).
#   missing — sin .codegraph o sin db (ej. worktree recien creado: db gitignored).
#   broken  — .codegraph presente pero la query smoke falla (backend nativo/WASM roto).
#
# db_age_days = dias enteros desde el mtime de la db (-1 si no hay db).
#
# Los callers ELIGEN herramienta segun el status; status != ok NUNCA es error:
# si != ok usan rg/grep y NO invocan las tools codegraph_*.
#
# Env knobs:
#   CODEGRAPH_PROBE_TTL         (default 3600)  cache 1h en state-dir
#   CODEGRAPH_PROBE_SMOKE_SECS  (default 15)    timeout de la query smoke
#   CODEGRAPH_PROBE_SYNC_SECS   (default 60)    timeout del intento de sync
#   CODEGRAPH_PROBE_NO_SYNC     (1 = no intentar sync; db atras de HEAD => stale)
#                                                lo usa setup-worktree.sh (db gitignored)

# NOTA: sin `set -e` a proposito — este script DEBE salir 0 pase lo que pase.
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
    # grupo (incluidos nietos), si no un nieto huerfano retiene el fd del `$(...)`
    # y la substitucion de comando se cuelga hasta que ese proceso muera.
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
state_dir() {
  local base slug
  base="${CLAUDE_PROJECT_DIR:-$ROOT}"
  slug="$(printf '%s' "$base" | sed 's|/|-|g')"
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

# smoke: query real (usa -p). Si falla, timeout, o emite firma de rotura => broken.
out="$(run_timeout "$SMOKE_SECS" codegraph query "the" -p "$ROOT" 2>&1)"
rc=$?
if [ "$rc" -ne 0 ] \
   || printf '%s' "$out" | grep -qiE 'unable to open database|SQLITE_CANTOPEN|cannot find module|no such (table|file)|fatal|panic|Error:'; then
  finish broken "$age_days"
fi

# frescura vs HEAD; sync (path posicional) si la db quedo atras — salvo NO_SYNC.
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
