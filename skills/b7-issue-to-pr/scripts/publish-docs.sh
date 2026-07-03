#!/usr/bin/env bash
# publish-docs.sh — escritura triple coordinada (CHANGELOG + issue comment + PR body).
#
# Lee .b7/state.json (la verdad central del run) y escribe los tres artefactos
# documentales en una sola pasada determinística. Sin tokens del LLM.
#
# Subcomandos:
#   changelog          — appendea/edita entry en CHANGELOG.md bajo [Unreleased]
#   issue-comment      — sticky comment en el issue (gh; edita si existe, crea si no)
#   pr-body            — escribe .b7/pr-body.md (consumido por b4-pull-request)
#   all                — todos los anteriores
#   aborted            — variante para cierre de aborto (marca el sticky con ⛔)
#   bailed [reason]    — variante para bail (verdict != ready); setea bail_reason
#   state-set k=v ...  — setea claves (whitelist=claves del state; auto-toca updated_at)
#   milestone <n> [N]  — avanza milestone_*/status/status_emoji/iter_count
#   plan-render        — renderiza .b7/triage.json plan[] → state.plan_block (idempotente)
#   plan-done <id>     — marca plan item por id como done=true en .b7/triage.json
#   plan-check         — exit 0 si plan.every(done) o plan=[]; exit 5 si quedan pendientes
#
# Marker sticky en issue: <!-- b7:status -->  (primera línea del comentario)
#
# Usage: publish-docs.sh <subcommand> [--state .b7/state.json] [--worktree DIR]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
TEMPLATES="$SKILL_DIR/templates"

SUB=""
STATE_PATH=""
WORKTREE="${PWD}"
POSARGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --state)    STATE_PATH="$2"; shift 2 ;;
    --worktree) WORKTREE="$2"; shift 2 ;;
    -*)         echo "publish-docs.sh: unknown flag: $1" >&2; exit 2 ;;
    *)
      if [ -z "$SUB" ]; then SUB="$1"; else POSARGS+=("$1"); fi
      shift ;;
  esac
done
# Compat: primer arg posicional (usado por plan-done <id>, bailed <reason>).
SUB_ARG="${POSARGS[0]:-}"

[ -z "$SUB" ]        && { echo "Usage: $0 {changelog|issue-comment|pr-body|all|aborted|bailed|state-set|milestone|plan-render|plan-done|plan-check} [--state PATH] [--worktree DIR]" >&2; exit 2; }
[ -z "$STATE_PATH" ] && STATE_PATH="$WORKTREE/.b7/state.json"
[ ! -f "$STATE_PATH" ] && { echo "publish-docs.sh: state json not found: $STATE_PATH" >&2; exit 3; }

# Helper: extraer valor de state.json (key path estilo jq pero con python3).
state_get() {
  python3 -c "
import json, sys
with open('$STATE_PATH') as f:
    d = json.load(f)
keys = '$1'.split('.')
v = d
for k in keys:
    if isinstance(v, dict):
        v = v.get(k, '')
    else:
        v = ''
        break
if isinstance(v, (dict, list)):
    print(json.dumps(v, ensure_ascii=False))
elif v is None:
    print('')
else:
    print(v)
"
}

# Helper: render template via render-report.sh (mismo motor envsubst).
render_template() {
  local tpl="$1"
  local out="$2"
  "$SCRIPT_DIR/render-report.sh" "$STATE_PATH" "$tpl" "$out"
}

# ---- subcomandos ----

cmd_changelog() {
  local repo_root issue_number scope
  repo_root="$(git -C "$WORKTREE" rev-parse --show-toplevel)"
  issue_number="$(state_get issue_number)"
  scope="$(state_get triage_scope)"

  local cl="$repo_root/CHANGELOG.md"
  [ -f "$cl" ] || { echo "# Changelog" > "$cl"; echo >> "$cl"; echo "## [Unreleased]" >> "$cl"; echo >> "$cl"; }

  local entry="$WORKTREE/.b7/changelog-entry.md"
  render_template "$TEMPLATES/changelog-entry.md" "$entry"

  # Insertar bajo "## [Unreleased]" si no hay entrada idempotente para este issue.
  if grep -qE "^### .*\(#${issue_number}\)" "$cl"; then
    echo "publish-docs/changelog: entry for #$issue_number already present (idempotent skip)"
    return 0
  fi

  python3 - "$cl" "$entry" <<'PY'
import sys, pathlib
cl_path, entry_path = sys.argv[1], sys.argv[2]
cl = pathlib.Path(cl_path).read_text()
entry = pathlib.Path(entry_path).read_text().rstrip() + "\n\n"
marker = "## [Unreleased]"
if marker in cl:
    cl = cl.replace(marker, marker + "\n\n" + entry, 1)
else:
    cl = "## [Unreleased]\n\n" + entry + "\n" + cl
pathlib.Path(cl_path).write_text(cl)
PY
  echo "publish-docs/changelog: appended entry for #$issue_number"
}

cmd_issue_comment() {
  local issue_number rendered marker repo
  issue_number="$(state_get issue_number)"
  [ -z "$issue_number" ] && { echo "publish-docs/issue-comment: missing issue_number in state" >&2; return 4; }

  rendered="$WORKTREE/.b7/issue-comment.md"
  render_template "$TEMPLATES/issue-comment.md" "$rendered"

  marker="<!-- b7:status -->"
  repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"

  # Buscar comentario existente con el marker (id numerico REST, no node id GraphQL).
  local existing_id
  existing_id="$(gh api "repos/$repo/issues/$issue_number/comments" --paginate \
    --jq ".[] | select(.body | startswith(\"$marker\")) | .id" 2>/dev/null | head -n 1 || true)"

  if [ -n "$existing_id" ]; then
    # Editar via gh api (PATCH /repos/:owner/:repo/issues/comments/:id)
    gh api --method PATCH "repos/$repo/issues/comments/$existing_id" \
      -f body="$(cat "$rendered")" >/dev/null
    echo "publish-docs/issue-comment: edited sticky comment $existing_id on issue #$issue_number"
  else
    gh issue comment "$issue_number" --body-file "$rendered" >/dev/null
    echo "publish-docs/issue-comment: created sticky comment on issue #$issue_number"
  fi
}

cmd_pr_body() {
  local out="$WORKTREE/.b7/pr-body.md"
  render_template "$TEMPLATES/pr-release-notes.md" "$out"
  echo "publish-docs/pr-body: wrote $out"
}

# Renderiza .b7/triage.json plan[] como checklist markdown y lo escribe en
# .b7/state.json bajo la clave plan_block. Idempotente.
cmd_plan_render() {
  local triage="$WORKTREE/.b7/triage.json"
  [ ! -f "$triage" ] && { echo "publish-docs/plan-render: missing $triage" >&2; return 4; }
  python3 - "$triage" "$STATE_PATH" <<'PY'
import json, sys, pathlib
triage_p, state_p = sys.argv[1], sys.argv[2]
triage = json.loads(pathlib.Path(triage_p).read_text())
plan = triage.get("plan") or []
if not plan:
    block = "_Sin plan estructurado (tarea trivial)._"
else:
    lines = []
    for it in plan:
        box = "[x]" if it.get("done") else "[ ]"
        note = f" _(`{it['note']}`)_" if it.get("note") else ""
        lines.append(f"- {box} `{it['id']}` — {it['desc']}{note}")
    block = "\n".join(lines)
state = json.loads(pathlib.Path(state_p).read_text()) if pathlib.Path(state_p).exists() else {}
state["plan_block"] = block
pathlib.Path(state_p).write_text(json.dumps(state, ensure_ascii=False, indent=2))
print(f"publish-docs/plan-render: {len(plan)} items → state.plan_block")
PY
}

# Marca un plan item como done=true por id. Si no existe, exit 6.
cmd_plan_done() {
  local id="${1:-}"
  [ -z "$id" ] && { echo "publish-docs/plan-done: usage: plan-done <id>" >&2; return 2; }
  local triage="$WORKTREE/.b7/triage.json"
  [ ! -f "$triage" ] && { echo "publish-docs/plan-done: missing $triage" >&2; return 4; }
  python3 - "$triage" "$id" <<'PY'
import json, sys, pathlib
p, target = sys.argv[1], sys.argv[2]
data = json.loads(pathlib.Path(p).read_text())
plan = data.get("plan") or []
hit = False
for it in plan:
    if it.get("id") == target:
        it["done"] = True
        hit = True
        break
if not hit:
    print(f"publish-docs/plan-done: id '{target}' not found in plan", file=sys.stderr)
    sys.exit(6)
pathlib.Path(p).write_text(json.dumps(data, ensure_ascii=False, indent=2))
print(f"publish-docs/plan-done: marked '{target}' done")
PY
  cmd_plan_render >/dev/null || true
}

# Gate DoD: exit 0 si plan vacío o plan.every(done); exit 5 si quedan pendientes
# (imprime los ids pendientes a stderr).
cmd_plan_check() {
  local triage="$WORKTREE/.b7/triage.json"
  [ ! -f "$triage" ] && { echo "publish-docs/plan-check: missing $triage" >&2; return 4; }
  python3 - "$triage" <<'PY'
import json, sys, pathlib
data = json.loads(pathlib.Path(sys.argv[1]).read_text())
plan = data.get("plan") or []
pending = [it["id"] for it in plan if not it.get("done")]
if pending:
    print("publish-docs/plan-check: pending items: " + ", ".join(pending), file=sys.stderr)
    sys.exit(5)
print(f"publish-docs/plan-check: ok ({len(plan)} items, all done or empty)")
PY
}

# Setea claves en state.json. Whitelist = claves ya existentes en el state del
# run (rechaza claves desconocidas para atrapar typos que renderizarian vacio).
# Auto-actualiza updated_at. Uso: state-set key=value [key=value ...]
cmd_state_set() {
  [ $# -eq 0 ] && { echo "publish-docs/state-set: usage: state-set key=value [key=value ...]" >&2; return 2; }
  python3 - "$STATE_PATH" "$@" <<'PY'
import json, sys, datetime, pathlib
state_p = sys.argv[1]
pairs = sys.argv[2:]
d = json.loads(pathlib.Path(state_p).read_text())
allowed = set(d.keys())
unknown, updates = [], {}
for p in pairs:
    if "=" not in p:
        print(f"publish-docs/state-set: bad pair (need key=value): {p}", file=sys.stderr)
        sys.exit(2)
    k, v = p.split("=", 1)
    if k not in allowed:
        unknown.append(k)
    else:
        updates[k] = v
if unknown:
    print("publish-docs/state-set: unknown key(s) not in state.json: " + ", ".join(unknown), file=sys.stderr)
    sys.exit(6)
d.update(updates)
d["updated_at"] = datetime.datetime.now(datetime.UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
pathlib.Path(state_p).write_text(json.dumps(d, ensure_ascii=False, indent=2))
print("publish-docs/state-set: set " + ", ".join(updates.keys()))
PY
}

# Avanza un milestone del run. Mapea el nombre a las claves milestone_*/status/
# status_emoji/status_label/iter_count. Uso: milestone <name> [N]
#   started | triage-done | worktree-ready | iter-green <N> |
#   screens-reviewed | committed | pr-opened
cmd_milestone() {
  local name="${1:-}" n="${2:-}"
  [ -z "$name" ] && { echo "publish-docs/milestone: usage: milestone <name> [N]" >&2; return 2; }
  python3 - "$STATE_PATH" "$name" "$n" <<'PY'
import json, sys, datetime, pathlib
state_p, name, n = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.loads(pathlib.Path(state_p).read_text())
DONE = "✅"
def running(label):
    d["status"] = "running"; d["status_emoji"] = "🚧"; d["status_label"] = label
if name == "started":
    d["status"] = "started"; d["status_emoji"] = "🚧"; d["status_label"] = "En curso"
elif name == "triage-done":
    d["milestone_triage"] = DONE; running("Triage listo")
elif name == "worktree-ready":
    d["milestone_worktree"] = DONE; running("Worktree listo")
elif name == "iter-green":
    d["milestone_impl"] = DONE; running("Implementacion verde")
    if n:
        if not n.isdigit():
            print(f"publish-docs/milestone: iter-green needs numeric N, got '{n}'", file=sys.stderr); sys.exit(2)
        d["iter_count"] = int(n)
elif name == "screens-reviewed":
    d["milestone_screens"] = DONE; running("Pantallas revisadas")
elif name == "committed":
    d["milestone_commit"] = DONE; running("Commit hecho")
elif name == "pr-opened":
    d["milestone_pr"] = DONE
    d["status"] = "pr-open"; d["status_emoji"] = "✅"; d["status_label"] = "PR abierto"
else:
    print(f"publish-docs/milestone: unknown milestone '{name}'", file=sys.stderr); sys.exit(2)
d["updated_at"] = datetime.datetime.now(datetime.UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
pathlib.Path(state_p).write_text(json.dumps(d, ensure_ascii=False, indent=2))
print(f"publish-docs/milestone: {name}" + (f" (N={n})" if n else ""))
PY
}

cmd_all() {
  cmd_plan_render || true
  cmd_changelog || true
  cmd_pr_body   || true
  cmd_issue_comment || true
}

cmd_aborted() {
  python3 - "$STATE_PATH" <<'PY'
import json, sys
p = sys.argv[1]
with open(p) as f: d = json.load(f)
d["status"] = "aborted"
d["status_emoji"] = "⛔"
d["status_label"] = "Detenido"
with open(p, "w") as f: json.dump(d, f, ensure_ascii=False, indent=2)
PY
  cmd_issue_comment || true
  cmd_changelog || true
}

cmd_bailed() {
  local reason="${1:-}"
  python3 - "$STATE_PATH" "$reason" <<'PY'
import json, sys
p, reason = sys.argv[1], sys.argv[2]
with open(p) as f: d = json.load(f)
d["status"] = "bailed"
d["status_emoji"] = "🚪"
d["status_label"] = "El bot baileó"
if reason:
    d["bail_reason"] = reason
with open(p, "w") as f: json.dump(d, f, ensure_ascii=False, indent=2)
PY
  cmd_issue_comment || true
}

case "$SUB" in
  changelog)     cmd_changelog ;;
  issue-comment) cmd_issue_comment ;;
  pr-body)       cmd_pr_body ;;
  all)           cmd_all ;;
  aborted)       cmd_aborted ;;
  bailed)        cmd_bailed "$SUB_ARG" ;;
  state-set)     cmd_state_set ${POSARGS[@]+"${POSARGS[@]}"} ;;
  milestone)     cmd_milestone ${POSARGS[@]+"${POSARGS[@]}"} ;;
  plan-render)   cmd_plan_render ;;
  plan-done)     cmd_plan_done "$SUB_ARG" ;;
  plan-check)    cmd_plan_check ;;
  *) echo "publish-docs.sh: unknown subcommand: $SUB" >&2; exit 2 ;;
esac
