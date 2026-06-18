#!/usr/bin/env bash
set -euo pipefail

# epic-state.sh <epic> [--max-parallel=N]
#
# Snapshot COMPLETO y PARALELO de un epic para que b10-ship planifique en una pasada.
# Combina dos fuentes:
#   1. Topologia (epic-graph.sh): waves, deps, closing_slice. Determinista.
#   2. Estado live por sub-issue (run.sh reconcile <n>): phase, pr, b6, worktree, zombie.
#      Read-only y por-issue independiente -> se corre EN PARALELO (bounded), cortando
#      el wall-clock de N*RTT (reconcile secuencial, varias llamadas gh c/u) a ~RTT.
#
# Solo se reconcilian los sub-issues OPEN (los accionables). Los CLOSED salen del grafo
# con phase=done sin gastar llamadas. El epic mismo (si es closing_slice) se reconcilia.
#
# Output: JSON a stdout (el mismo shape de epic-graph + un objeto "live" por issue):
#   {
#     "epic": N, "closing_slice": N|null,
#     "issues": [ { issue,title,state,labels,deps,wave,
#                   "live": { phase, pr, pr_state, b6, worktree, zombie, blocked_open, needs_info } } ]
#   }
#   Ademas una linea final parseable:
#     B10_EPIC_STATE epic=N waves=K open=<n> closeable=<n> buildable=<csv> blocked=<csv>
#
# Exit: hereda de epic-graph (3 sin subs, 4 ciclo); 2 args.

[ -n "${1:-}" ] || { echo "Usage: $0 <epic> [--max-parallel=N]" >&2; exit 2; }
EPIC="$1"; shift || true

MAXP="${B10_RECONCILE_PARALLEL:-8}"
for arg in "$@"; do
  case "$arg" in
    --max-parallel=*) MAXP="${arg#*=}" ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GRAPH="$SCRIPT_DIR/epic-graph.sh"
RUN="$SCRIPT_DIR/run.sh"
[ -f "$GRAPH" ] || { echo "ERROR: falta epic-graph.sh junto a este script" >&2; exit 2; }
[ -f "$RUN" ]   || { echo "ERROR: falta run.sh junto a este script" >&2; exit 2; }

# 1. Topologia (determinista). Si falla, propagar su exit (3/4).
GRAPH_JSON="$(bash "$GRAPH" "$EPIC")" || exit $?

# 2. Reconcile live en paralelo, fusionado en el grafo via python.
GRAPH_JSON="$GRAPH_JSON" RUN="$RUN" MAXP="$MAXP" python3 - <<'PY'
import json, os, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

graph = json.loads(os.environ["GRAPH_JSON"])
run = os.environ["RUN"]
maxp = max(1, int(os.environ.get("MAXP", "8")))

def reconcile(n):
    """Corre run.sh reconcile <n> y parsea las lineas B10_* a un dict 'live'."""
    r = subprocess.run(["bash", run, "reconcile", str(n)],
                       capture_output=True, text=True)
    live = {"phase": None, "pr": None, "pr_state": None, "b6": None,
            "worktree": None, "zombie": False, "blocked_open": None,
            "needs_info": None}
    for line in (r.stdout or "").splitlines():
        line = line.strip()
        if "=" not in line:
            continue
        key, _, val = line.partition("=")
        if key == "B10_PHASE":            live["phase"] = val.strip()
        elif key == "B10_PR":             live["pr"] = val.strip()
        elif key == "B10_PR_MERGED":      live["pr"] = val.split()[0]; live["phase"] = live["phase"] or "close"
        elif key == "B10_PR_STATE":       live["pr_state"] = val.strip()
        elif key == "B10_B6":             live["b6"] = val.strip()
        elif key == "B10_WORKTREE":       live["worktree"] = val.split()[0]
        elif key == "B10_ZOMBIE":         live["zombie"] = True
        elif key == "B10_BLOCKED_BY":     live["blocked_open"] = val.strip()
        elif key == "B10_NEEDS_INFO_ANSWERED": live["needs_info"] = val.strip()
    if r.returncode != 0 and not live["phase"]:
        live["phase"] = "error"
        live["note"] = (r.stderr or "").strip()[:200]
    return n, live

# Solo reconciliar lo accionable (OPEN). CLOSED -> done sin llamada.
to_reconcile = [it["issue"] for it in graph["issues"] if it.get("state") == "OPEN"]
results = {}
if to_reconcile:
    with ThreadPoolExecutor(max_workers=min(maxp, len(to_reconcile))) as ex:
        for n, live in ex.map(lambda n: reconcile(n), to_reconcile):
            results[n] = live

for it in graph["issues"]:
    if it.get("state") == "OPEN":
        it["live"] = results.get(it["issue"], {"phase": "unknown"})
    else:
        it["live"] = {"phase": "done", "pr": None, "b6": None, "worktree": None,
                      "zombie": False, "blocked_open": None, "needs_info": None}

# Clasificacion para el resumen (lo que el skill usa para despachar fases).
# La fase ya viene resuelta por run.sh reconcile (incluye el chequeo de blockers de b6).
closeable, buildable, blocked = [], [], []
for it in graph["issues"]:
    if it.get("state") != "OPEN":
        continue
    ph = it["live"].get("phase")
    if ph == "close":
        closeable.append(it["issue"])
    elif ph == "blocked":
        blocked.append(it["issue"])
    elif ph in ("triage", "build", "verify"):
        buildable.append(it["issue"])

open_n = sum(1 for it in graph["issues"] if it.get("state") == "OPEN")
print(json.dumps(graph, ensure_ascii=False, indent=1))
print(f"B10_EPIC_STATE epic={graph['epic']} "
      f"waves={(max((it['wave'] for it in graph['issues']), default=-1) + 1)} "
      f"open={open_n} "
      f"closeable={','.join(map(str, closeable)) or '-'} "
      f"buildable={','.join(map(str, buildable)) or '-'} "
      f"blocked={','.join(map(str, blocked)) or '-'}")
PY
