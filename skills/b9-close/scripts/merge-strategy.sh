#!/usr/bin/env bash
# merge-strategy.sh — estrategia de merge según el historial del repo (#69).
# Uso: merge-strategy.sh [limit]   (cwd = repo; default limit=10)
# Salida: MERGE_STRATEGY=squash|rebase|merge MERGE_STRATEGY_SRC="<origen>"
# Clasifica los últimos PRs mergeados por su merge commit:
#   2 padres -> merge; titular con "(#<pr>)" -> squash; resto -> rebase.
# Gana la mayoría entre las que el repo permite; sin historial -> squash.
set -uo pipefail
limit="${1:-10}"

allowed="$(gh api 'repos/{owner}/{repo}' --jq '[(if .allow_squash_merge then "squash" else empty end),(if .allow_rebase_merge then "rebase" else empty end),(if .allow_merge_commit then "merge" else empty end)]|join(" ")' 2>/dev/null)"
allowed="${allowed:-squash rebase merge}"

counts="$(gh pr list --state merged --limit "$limit" --json number,mergeCommit 2>/dev/null \
  | python3 -c '
import json, subprocess, sys
c = {"squash": 0, "rebase": 0, "merge": 0}
for pr in json.load(sys.stdin):
    sha = (pr.get("mergeCommit") or {}).get("oid")
    if not sha:
        continue
    out = subprocess.run(["git", "log", "-1", "--format=%P%x00%s", sha], capture_output=True, text=True).stdout
    if not out:  # commit no está local: preguntar a la API
        out = subprocess.run(["gh", "api", "repos/{owner}/{repo}/commits/" + sha, "--jq",
            "([.parents[].sha]|join(\" \")) + \"\\u0000\" + (.commit.message|split(\"\\n\")[0])"],
            capture_output=True, text=True).stdout
    parents, _, subject = out.strip().partition("\x00")
    if len(parents.split()) > 1:
        c["merge"] += 1
    elif "(#%s)" % pr["number"] in subject:
        c["squash"] += 1
    elif parents:
        c["rebase"] += 1
print(" ".join(f"{k}={v}" for k, v in c.items()))
' 2>/dev/null)"

best="" bestn=0 total=0
for kv in $counts; do
  k="${kv%%=*}"; n="${kv#*=}"; total=$((total + n))
  case " $allowed " in *" $k "*) [ "$n" -gt "$bestn" ] && { best="$k"; bestn="$n"; } ;; esac
done

if [ -z "$best" ]; then
  case " $allowed " in *" squash "*) best=squash ;; *) best="${allowed%% *}" ;; esac
  echo "MERGE_STRATEGY=$best MERGE_STRATEGY_SRC=\"default (sin historial)\""
else
  echo "MERGE_STRATEGY=$best MERGE_STRATEGY_SRC=\"$bestn/$total PRs recientes\""
fi
