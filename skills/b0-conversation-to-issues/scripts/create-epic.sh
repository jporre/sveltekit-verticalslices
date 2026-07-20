#!/usr/bin/env bash
set -euo pipefail

# create-epic.sh <plan.json> [--dry-run]
#
# Crea la estructura de issues que consume b10-ship --epic a partir de un PLAN JSON.
# El LLM (skill b0-conversation-to-issues) razona el slicing y escribe el plan; este
# script hace el trabajo mecánico/determinístico contra GitHub:
#
#   1. Asegura que existan todas las labels (las crea si faltan).
#   2. Crea cada sub-issue EN ORDEN, resolviendo deps de slice-id -> #número real.
#      Las deps se materializan como una sección "## Blocked by\n- #N" en el body
#      (convención que parsea epic-graph.sh de b10).
#   3. Crea el issue epic de tracking (rollup con checklist de los sub-issues).
#   4. Vincula los sub-issues como sub-issues NATIVOS bajo el epic vía epic-link.sh.
#
# Idempotencia-lite: si ya existe un issue ABIERTO con título idéntico, lo reusa
# (no duplica) y resuelve las deps contra ese número. Re-correr no spamea.
#
# Schema del plan (ver references/slicing-guide.md):
#   {
#     "lang": "es",
#     "epic": {                       // omitir o null => no se crea epic (issues sueltos)
#       "title": "...",
#       "body": "...",                // opcional; si falta se genera un rollup
#       "labels": ["scope:x"],
#       "closing_slice": "epic"|null  // "epic" => el epic depende de TODOS los subs
#     },                              //            (se vuelve el closing_slice de b10)
#     "issues": [                     // ORDEN TOPOLÓGICO: una dep siempre va antes
#       { "id":"s1", "title":"...", "body":"...", "labels":["feature","scope:x"],
#         "blocked_by":[] },
#       { "id":"s2", "title":"...", "body":"...", "labels":[...],
#         "blocked_by":["s1"] }
#     ]
#   }
#
# Output: líneas "ok:/skip:" por issue + última línea machine-readable:
#   B0_DONE epic=<N|none> issues=<csv> waves=<n> mode=<created|dry-run>
#
# Exit: 2 args | 3 plan inválido | 5 fallo gh create | 6 epic-link fallo (no fatal: se reporta)

[ -n "${1:-}" ] || { echo "Usage: $0 <plan.json> [--dry-run]" >&2; exit 2; }
PLAN="$1"
[ -f "$PLAN" ] || { echo "ERROR: plan no encontrado: $PLAN" >&2; exit 2; }
DRY=0
[ "${2:-}" = "--dry-run" ] && DRY=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# epic-link.sh vive en b10-ship; reusar en vez de duplicar el linkeo nativo.
EPIC_LINK="$SCRIPT_DIR/../../b10-ship/scripts/epic-link.sh"
if [ ! -f "$EPIC_LINK" ]; then
  PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cat "$HOME/.claude/b-pipeline.root" 2>/dev/null || ls -d "$HOME"/.claude/plugins/marketplaces/b-pipeline* 2>/dev/null | head -1)}"
  EPIC_LINK="$PLUGIN_ROOT/skills/b10-ship/scripts/epic-link.sh"
fi

command -v gh >/dev/null || { echo "ERROR: gh no esta en PATH" >&2; exit 2; }
gh auth status >/dev/null 2>&1 || { echo "ERROR: gh no autenticado (gh auth login)" >&2; exit 2; }

PLAN="$PLAN" DRY="$DRY" EPIC_LINK="$EPIC_LINK" python3 - <<'PY'
import json, os, re, subprocess, sys, tempfile

plan_path = os.environ["PLAN"]
dry = os.environ["DRY"] == "1"
epic_link = os.environ["EPIC_LINK"]

try:
    plan = json.load(open(plan_path))
except Exception as e:
    sys.stderr.write(f"ERROR: plan JSON invalido: {e}\n"); sys.exit(3)

issues = plan.get("issues") or []
epic = plan.get("epic")
lang = plan.get("lang", "es")
if not issues:
    sys.stderr.write("ERROR: el plan no tiene issues\n"); sys.exit(3)

# --- validación: ids únicos, deps conocidas y topológicamente anteriores ---
ids = [it.get("id") for it in issues]
if any(not i for i in ids):
    sys.stderr.write("ERROR: todo issue necesita 'id'\n"); sys.exit(3)
if len(set(ids)) != len(ids):
    sys.stderr.write(f"ERROR: ids duplicados en el plan: {ids}\n"); sys.exit(3)
idset = set(ids)
seen = set()
for it in issues:
    if not it.get("title") or not it.get("body"):
        sys.stderr.write(f"ERROR: issue '{it.get('id')}' sin title/body\n"); sys.exit(3)
    for d in it.get("blocked_by", []):
        if d not in idset:
            sys.stderr.write(f"ERROR: '{it['id']}' depende de id desconocido '{d}'\n"); sys.exit(3)
        if d not in seen:
            sys.stderr.write(
                f"ERROR: '{it['id']}' depende de '{d}' que aparece después — "
                f"el array 'issues' debe estar en orden topológico (deps primero)\n")
            sys.exit(3)
    seen.add(it["id"])

# --- waves (mismo criterio que epic-graph.sh: wave = max(dep.wave)+1) ---
wave = {}
for it in issues:
    deps = it.get("blocked_by", [])
    wave[it["id"]] = (max(wave[d] for d in deps) + 1) if deps else 0
n_waves = (max(wave.values()) + 1) if wave else 0

# --- dry-run: mostrar el plan agrupado por wave, no tocar GitHub ---
if dry:
    print(f"PLAN (dry-run) — {len(issues)} issues, {n_waves} olas")
    if epic:
        cs = " [closing_slice]" if epic.get("closing_slice") == "epic" else ""
        print(f"  epic: {epic.get('title','(rollup auto)')}{cs}")
    for w in range(n_waves):
        print(f"  ola {w}:")
        for it in issues:
            if wave[it["id"]] == w:
                deps = it.get("blocked_by", [])
                dtxt = f"  (blocked_by: {', '.join(deps)})" if deps else ""
                labs = ",".join(it.get("labels", []))
                print(f"    - [{it['id']}] {it['title']}  <{labs}>{dtxt}")
    print(f"B0_DONE epic={'(auto)' if epic else 'none'} issues={len(issues)} waves={n_waves} mode=dry-run")
    sys.exit(0)

def sh(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)

# --- asegurar labels (crear las faltantes con color neutro) ---
# Los sub-issues se estampan con "ready" (nacen de b0 = grounding + gate humano ya
# pagados) para que el early-exit de b1 --auto los reuse sin re-triagear. El epic NO
# lo lleva: su triage corre en epic-review.
want = {"ready"}
for it in issues:
    want |= set(it.get("labels", []))
if epic:
    want |= set(epic.get("labels", []))
    want.add("epic")
r = sh(["gh", "label", "list", "--limit", "200", "--json", "name"])
have = {x["name"] for x in json.loads(r.stdout)} if r.returncode == 0 and r.stdout.strip() else set()
for lab in sorted(want - have):
    sh(["gh", "label", "create", lab, "--color", "BFD4F2", "--description", "b0-conversation-to-issues"])

# --- idempotencia-lite: indexar issues abiertos por título exacto ---
r = sh(["gh", "issue", "list", "--state", "open", "--limit", "300", "--json", "number,title"])
existing = {x["title"]: x["number"] for x in json.loads(r.stdout)} if r.returncode == 0 and r.stdout.strip() else {}

def create_issue(title, body, labels):
    if title in existing:
        n = existing[title]
        print(f"skip: #{n} ya existe (título idéntico) — {title}")
        return n
    with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False) as f:
        f.write(body); path = f.name
    cmd = ["gh", "issue", "create", "--title", title, "--body-file", path]
    if labels:
        cmd += ["--label", ",".join(labels)]
    r = sh(cmd)
    os.unlink(path)
    if r.returncode != 0:
        sys.stderr.write(f"ERROR creando '{title}': {r.stderr}\n"); sys.exit(5)
    m = re.search(r"/issues/(\d+)", r.stdout)
    if not m:
        sys.stderr.write(f"ERROR: no pude parsear el número del issue creado: {r.stdout}\n"); sys.exit(5)
    n = int(m.group(1))
    existing[title] = n  # por si dos slices comparten título (no deberían)
    print(f"ok:   #{n} {title}")
    return n

# --- crear sub-issues en orden, materializando ## Blocked by ---
# Cada sub-issue lleva "ready" (dedup) además de sus labels de plan: b1 --auto lo
# reconoce como issue de b0 y reusa el veredicto sin fork de research. El epic queda
# afuera (se crea más abajo sin "ready").
num = {}
for it in issues:
    body = it["body"].rstrip()
    deps = it.get("blocked_by", [])
    if deps:
        body += "\n\n## Blocked by\n" + "\n".join(f"- #{num[d]}" for d in deps)
    labels = list(dict.fromkeys(it.get("labels", []) + ["ready"]))
    num[it["id"]] = create_issue(it["title"], body, labels)

# --- epic de tracking (opcional) ---
epic_n = None
if epic:
    body = epic.get("body")
    if not body:
        head = "Epic de seguimiento. Sub-issues:" if lang == "es" else "Tracking epic. Sub-issues:"
        rows = "\n".join(f"- [ ] #{num[it['id']]} {it['title']}" for it in issues)
        foot = ("\n\nProcesar con `/b-pipeline:b10-ship --epic=<N>` (reemplazar N por el número de este epic)."
                if lang == "es" else
                "\n\nDrain with `/b-pipeline:b10-ship --epic=<N>` (replace N with this epic's number).")
        body = f"{head}\n{rows}{foot}"
    if epic.get("closing_slice") == "epic":
        # El epic mismo es el slice de cierre: depende de TODOS los subs.
        # epic-graph.sh lo detecta (deps cubren >=80% del grafo) y b10 lo construye
        # último, tras el gate de epic-review.
        body += "\n\n## Blocked by\n" + "\n".join(f"- #{num[it['id']]}" for it in issues)
    labels = list(dict.fromkeys((epic.get("labels") or []) + ["epic"]))
    epic_n = create_issue(epic["title"], body, labels)

# --- vincular sub-issues nativos bajo el epic ---
link_ok = True
if epic_n is not None:
    sub_nums = [str(num[it["id"]]) for it in issues]
    r = sh(["bash", epic_link, str(epic_n)] + sub_nums)
    sys.stdout.write(r.stdout)
    if r.returncode != 0:
        sys.stderr.write(r.stderr)
        sys.stderr.write("WARN: epic-link fallo — b10 igual lee los #N del body del epic (fallback)\n")
        link_ok = False

csv = ",".join(str(num[it["id"]]) for it in issues)
print(f"B0_DONE epic={epic_n if epic_n is not None else 'none'} issues={csv} waves={n_waves} mode=created")
sys.exit(0 if link_ok else 6)
PY
