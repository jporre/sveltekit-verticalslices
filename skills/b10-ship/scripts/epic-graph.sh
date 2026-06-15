#!/usr/bin/env bash
set -euo pipefail

# epic-graph.sh <epic>
# Construye el grafo de dependencias del epic y lo emite como JSON topo-ordenado.
#
# Fuentes:
#   1. Sub-issues nativos de GitHub (API verificada en este repo).
#   2. Fallback: numeros #N referenciados en el body del epic.
# Dependencias finas: seccion "## Blocked by" del body de cada issue (convencion to-issues).
#
# Output: {"epic":N,"closing_slice":N|null,"issues":[{"issue","title","state","labels","deps","wave"}]}
#   wave 0 = sin deps dentro del grafo; wave K = todas las deps en waves < K.
#   closing_slice = issue cuyas deps cubren >=80% del resto del grafo (ej #271), si existe.
# Exit 3 sin sub-issues | exit 4 ciclo de dependencias.

[ -n "${1:-}" ] || { echo "Usage: $0 <epic>" >&2; exit 2; }
EPIC="$1"
REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"

NUMBERS="$(gh api "repos/${REPO}/issues/${EPIC}/sub_issues" --paginate --jq '.[].number' 2>/dev/null | sort -un || true)"
if [ -z "$NUMBERS" ]; then
  echo "WARN: #$EPIC sin sub-issues nativos — fallback a numeros referenciados en el body" >&2
  NUMBERS="$(gh issue view "$EPIC" --json body --jq .body | grep -oE '#[0-9]+' | tr -d '#' | sort -un | grep -v "^${EPIC}$" || true)"
fi
[ -n "$NUMBERS" ] || { echo "ERROR: no encontre sub-issues para #$EPIC" >&2; exit 3; }

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
# Primer registro: el epic mismo (puede ser tambien el item de cierre, ej #271).
gh issue view "$EPIC" --json number,title,state,labels,body >> "$TMP"
echo >> "$TMP"
for n in $NUMBERS; do
  gh issue view "$n" --json number,title,state,labels,body >> "$TMP"
  echo >> "$TMP"
done

EPIC="$EPIC" python3 - "$TMP" <<'PY'
import json, os, re, sys

records = []
for line in open(sys.argv[1]):
    line = line.strip()
    if line:
        records.append(json.loads(line))

epic_rec, issues = records[0], records[1:]

nodes = {}
for it in issues:
    body = it.get("body") or ""
    m = re.search(r"##+\s*[Bb]locked\s*by:?(.*?)(?=\n##|\Z)", body, re.S)
    deps = sorted({int(x) for x in re.findall(r"#(\d+)", m.group(1))}) if m else []
    nodes[it["number"]] = {
        "issue": it["number"],
        "title": it["title"],
        "state": it["state"],
        "labels": [l["name"] for l in it["labels"]],
        "deps": deps,
    }

nums = set(nodes)
waves, assigned = {}, set()
for _ in range(len(nodes) + 1):
    ready = [n for n in nodes if n not in assigned
             and all(d in assigned or d not in nums for d in nodes[n]["deps"])]
    if not ready:
        break
    wave = 0 if not assigned else max(waves.values()) + 1
    for n in ready:
        deps_in = [d for d in nodes[n]["deps"] if d in nums]
        waves[n] = (max(waves[d] for d in deps_in) + 1) if deps_in else 0
        assigned.add(n)

if len(assigned) != len(nodes):
    sys.stderr.write(f"ERROR: ciclo de dependencias entre {sorted(nums - assigned)}\n")
    sys.exit(4)

# closing slice: deps (dentro del grafo) cubren >=80% del resto
closing = None
for n, node in nodes.items():
    deps_in = [d for d in node["deps"] if d in nums]
    rest = len(nums) - 1
    if rest > 0 and len(deps_in) >= 0.8 * rest:
        closing = n

# Caso comun: el propio epic es ademas el item de cierre (su body declara
# "Blocked by" sobre los sub-issues, ej #271 swap/limpieza).
if closing is None:
    body = epic_rec.get("body") or ""
    m = re.search(r"##+\s*[Bb]locked\s*by:?(.*?)(?=\n##|\Z)", body, re.S)
    epic_deps = {int(x) for x in re.findall(r"#(\d+)", m.group(1))} if m else set()
    if len(epic_deps & nums) >= 0.8 * len(nums):
        closing = epic_rec["number"]

out = {
    "epic": int(os.environ["EPIC"]),
    "closing_slice": closing,
    "issues": sorted(
        [dict(nodes[n], wave=waves[n]) for n in nodes],
        key=lambda x: (x["wave"], x["issue"]),
    ),
}
print(json.dumps(out, ensure_ascii=False, indent=1))
PY
