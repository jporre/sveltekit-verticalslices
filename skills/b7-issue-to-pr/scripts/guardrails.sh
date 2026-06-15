#!/usr/bin/env bash
# Guardrails for b7-issue-to-pr.
#
# Subcommands:
#   preflight <issue-number>           — run before anything else; exits non-zero if unsafe to proceed
#   check-budget <worktree-dir>        — verify files-changed / lines-added under cap; exits non-zero if exceeded
#   acquire-lock                       — flock the b7 lock file (writes PID); exits non-zero if already held
#   release-lock                       — remove the lock file
#   state-dir                          — print the b7 state dir (creates it if missing) and exit
#   cache-issue <issue-number> <out-dir> — cache `gh issue view` JSON to <out-dir>/issue.json (idempotent)
#   context-snapshot <out-dir>         — write <out-dir>/context.md with stack/aliases/colocated layout (no LLM)
#   init-state <issue-number> <out-dir> — write a minimal .b7/state.json scaffold for publish-docs.sh
#   verify-worktree <dir>              — verify the worktree was created by setup-worktree.sh (marker + symlinks + dev.sh + location)
#
# Env knobs:
#   B7_MAX_OPEN_PRS    (default 3)     — backpressure threshold for open auto-pr-bot PRs
#   B7_BUDGET_FILES    (default 25)
#   B7_BUDGET_LINES    (default 1500)
#   B7_BOT_LABEL       (default auto-pr-bot)

set -euo pipefail

B7_MAX_OPEN_PRS="${B7_MAX_OPEN_PRS:-3}"
B7_BUDGET_FILES="${B7_BUDGET_FILES:-25}"
B7_BUDGET_LINES="${B7_BUDGET_LINES:-1500}"
B7_BOT_LABEL="${B7_BOT_LABEL:-auto-pr-bot}"

# Plugin root derivado desde la ubicacion del script (.../skills/b7-issue-to-pr/scripts).
# Portable: no asume instalacion en ~/.claude/skills.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"

# State dir is per-project. Caller passes CLAUDE_PROJECT_DIR via env (Claude Code sets this);
# fall back to a hash of the current working directory's repo root for direct shell invocations.
state_dir() {
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
    local slug
    slug="$(printf '%s' "$CLAUDE_PROJECT_DIR" | sed 's|/|-|g')"
    printf '%s/.claude/projects/%s' "$HOME" "$slug"
  else
    local repo_root slug
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    slug="$(printf '%s' "$repo_root" | sed 's|/|-|g')"
    printf '%s/.claude/projects/%s' "$HOME" "$slug"
  fi
}

ensure_state_dir() {
  local d
  d="$(state_dir)"
  mkdir -p "$d/b7-runs"
  printf '%s' "$d"
}

cmd_state_dir() {
  ensure_state_dir
  echo
}

cmd_preflight() {
  local issue="${1:-}"
  if [ -z "$issue" ]; then
    echo "preflight: missing issue number" >&2
    return 2
  fi

  local sd
  sd="$(ensure_state_dir)"

  # Kill-switch file
  if [ -f "$sd/b7.STOP" ]; then
    echo "preflight: kill-switch present at $sd/b7.STOP — refusing to run" >&2
    return 10
  fi

  # Lock file
  if [ -f "$sd/b7.lock" ]; then
    local pid
    pid="$(cat "$sd/b7.lock" 2>/dev/null || echo)"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      echo "preflight: another b7 run is in progress (pid $pid)" >&2
      return 11
    else
      echo "preflight: stale lock file (pid $pid not running) — removing" >&2
      rm -f "$sd/b7.lock"
    fi
  fi

  # gh auth
  if ! gh auth status >/dev/null 2>&1; then
    echo "preflight: gh not authenticated" >&2
    return 12
  fi

  # Issue must be open and not opted-out
  local issue_json state body labels
  if ! issue_json="$(gh issue view "$issue" --json state,body,labels 2>/dev/null)"; then
    echo "preflight: cannot read issue #$issue" >&2
    return 13
  fi

  state="$(printf '%s' "$issue_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["state"])')"
  if [ "$state" != "OPEN" ]; then
    echo "preflight: issue #$issue is $state, not OPEN" >&2
    return 14
  fi

  body="$(printf '%s' "$issue_json" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("body",""))')"
  if printf '%s' "$body" | grep -q '<!-- no-auto-pr -->'; then
    echo "preflight: issue body contains <!-- no-auto-pr --> opt-out marker" >&2
    return 15
  fi

  labels="$(printf '%s' "$issue_json" | python3 -c 'import json,sys; print(",".join(l["name"] for l in json.load(sys.stdin).get("labels",[])))')"
  if printf '%s' ",$labels," | grep -q ',do-not-automate,'; then
    echo "preflight: issue has do-not-automate label" >&2
    return 16
  fi

  # Backpressure on open bot PRs
  local open_count
  open_count="$(gh pr list --state open --label "$B7_BOT_LABEL" --json number 2>/dev/null \
    | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))' 2>/dev/null || echo 0)"
  if [ "$open_count" -ge "$B7_MAX_OPEN_PRS" ]; then
    echo "preflight: $open_count open $B7_BOT_LABEL PRs — at or above B7_MAX_OPEN_PRS=$B7_MAX_OPEN_PRS" >&2
    return 17
  fi

  # Working tree must be clean (b1-add-worktree's script also checks, but failing fast here is friendlier)
  if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "preflight: working tree is dirty — commit or stash first" >&2
    return 18
  fi

  echo "preflight OK: issue #$issue eligible; open bot PRs=$open_count/$B7_MAX_OPEN_PRS"
  return 0
}

cmd_check_budget() {
  local worktree="${1:-}"
  if [ -z "$worktree" ] || [ ! -d "$worktree" ]; then
    echo "check-budget: missing or invalid worktree dir" >&2
    return 2
  fi

  # Count files changed (vs the worktree's branch base) and lines added/removed.
  # We use the merge-base with master so partial work isn't double-counted across iterations.
  local base files added removed
  base="$(cd "$worktree" && git merge-base HEAD master 2>/dev/null || echo)"
  if [ -z "$base" ]; then
    echo "check-budget: cannot find merge-base with master" >&2
    return 3
  fi

  files="$(cd "$worktree" && git diff --name-only "$base" -- | wc -l | tr -d ' ')"
  added="$(cd "$worktree" && git diff --shortstat "$base" -- | sed -n 's/.* \([0-9]*\) insertion.*/\1/p')"
  removed="$(cd "$worktree" && git diff --shortstat "$base" -- | sed -n 's/.* \([0-9]*\) deletion.*/\1/p')"
  added="${added:-0}"
  removed="${removed:-0}"
  local net=$((added - removed))

  echo "budget: files=$files added=$added removed=$removed net=$net (caps: files=$B7_BUDGET_FILES net=$B7_BUDGET_LINES)"

  if [ "$files" -gt "$B7_BUDGET_FILES" ]; then
    echo "check-budget: $files files changed exceeds cap $B7_BUDGET_FILES" >&2
    return 20
  fi
  if [ "$net" -gt "$B7_BUDGET_LINES" ]; then
    echo "check-budget: $net net lines exceeds cap $B7_BUDGET_LINES" >&2
    return 21
  fi

  return 0
}

cmd_acquire_lock() {
  local sd
  sd="$(ensure_state_dir)"
  if [ -f "$sd/b7.lock" ]; then
    local pid
    pid="$(cat "$sd/b7.lock" 2>/dev/null || echo)"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      echo "acquire-lock: held by pid $pid" >&2
      return 11
    fi
  fi
  echo "$$" > "$sd/b7.lock"
  echo "$sd/b7.lock"
}

cmd_release_lock() {
  local sd
  sd="$(ensure_state_dir)"
  rm -f "$sd/b7.lock"
}

cmd_cache_issue() {
  local issue="${1:-}" outdir="${2:-}"
  if [ -z "$issue" ] || [ -z "$outdir" ]; then
    echo "cache-issue: usage: cache-issue <issue> <out-dir>" >&2
    return 2
  fi
  mkdir -p "$outdir"
  local out="$outdir/issue.json"
  if [ -f "$out" ] && [ -s "$out" ]; then
    # idempotente: si ya existe y no está vacío, no re-pegarle a gh
    echo "cache-issue: $out already cached"
    return 0
  fi
  if ! gh issue view "$issue" --json number,title,body,labels,state,author,createdAt,url,comments > "$out" 2>/dev/null; then
    echo "cache-issue: gh issue view #$issue failed" >&2
    rm -f "$out"
    return 4
  fi
  echo "cache-issue: wrote $out"
}

cmd_context_snapshot() {
  local outdir="${1:-}"
  if [ -z "$outdir" ]; then
    echo "context-snapshot: usage: context-snapshot <out-dir>" >&2
    return 2
  fi
  mkdir -p "$outdir"
  local out="$outdir/context.md"
  if [ -f "$out" ]; then
    echo "context-snapshot: $out already exists"
    return 0
  fi

  # Detectar repo root (pwd o el del worktree pasado).
  local repo_root pkg_name
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  pkg_name="$(python3 -c "import json; print(json.load(open('$repo_root/package.json')).get('name','?'))" 2>/dev/null || echo '?')"

  cat > "$out" <<EOF
# Contexto de proyecto (snapshot para sub-skills)

> Generado por guardrails.sh context-snapshot. NO LLM. Sub-skills lo leen
> en vez de explorar el repo desde cero.

## Stack
- Paquete: \`$pkg_name\`
- SvelteKit 2 + Svelte 5 (runes, async components)
- Remote Functions (\`*.remote.ts\`) para todo acceso a datos + lógica de negocio simple
- TailwindCSS 4 + shadcn-svelte + @lucide/svelte
- Drizzle ORM + Postgres 18 (uuidv7 para IDs nuevos)
- Zod para validación
- svelte-sonner para notificaciones

## Aliases
- \`\$lib\` → \`src/lib\`
- \`\$src\` → \`src\`
- \`\$components\` → \`src/lib/components\`
- \`\$api\` → \`src/routes/api\`

## Layout colocado por feature (la carpeta de ruta ES la carpeta del feature)
\`\`\`
src/routes/<feature>/
  +page.svelte                     # la pantalla (UI aqui; importa componentes hermanos)
  +page.server.ts                  # load + guard de permiso
  <feature>.remote.ts              # query/form/command + reglas de negocio simples
  <feature>-types.ts               # tipos (o exportarlos desde <feature>.remote.ts)
  <Feature>Form.svelte             # componentes hermanos, planos, PascalCase (sin subcarpeta ui/)
  schemas.ts                       # solo si la validacion es compleja
  <feature>.server.ts              # logica compleja (solo si aplica)
  new/ , [id]/                     # sub-rutas con su propio +page.svelte (y *.remote.ts si aplica)
\`\`\`
Todo el feature vive en una carpeta bajo src/routes. Nada de src/lib/features ni thin wrappers.
Solo lo realmente compartido (shadcn, db, helpers cross-feature) vive en \$lib.

## Convenciones obligatorias
- Imports shadcn con namespace: \`import * as Card from '\$lib/components/ui/card'\`
- Lucide: \`import Plus from '@lucide/svelte/icons/plus'\`
- Remote functions snake_case: \`get_*\`, \`create_*\`, \`update_*\`, \`delete_*\`
- Archivo remote nombrado \`<feature>.remote.ts\` (nunca el generico \`data.remote.ts\`), fuera de \`src/lib/server/\`
- Componentes PascalCase
- Tablas DB \`ta_*\`, vistas \`vi_*\`
- Errores estructurados: \`error(STATUS, {message, code})\`
- Permisos formato \`verbo:sustantivo\` (ej \`leer:tarea\`)
- Rutas nuevas REQUIEREN registro en \`app.route_permissions\` o el guard del layout redirige a fallback
- UUID default en tablas nuevas: \`uuidv7()\` (NO \`gen_random_uuid()\` ni \`uuid_generate_v4()\`)

## Comandos rápidos
- \`pnpm dev\` (puerto 6024)
- \`pnpm check:machine -- --threshold error\`
- \`pnpm test:unit -- --run --reporter=dot\`
- \`pnpm lint -- --quiet\`
- \`pnpm format\`

## Anti-patrones a evitar (importante)
- \`onclick={() => goto('/x')}\` → usar \`href="/x"\` directo
- Filtrado server-side con goto+query → usar \`\$derived(data.filter(...))\` si <1000 items
- \`\$effect\` con Chart.js / similares (loop infinito)
- Wrapping de \`error()\`/\`redirect()\` en try/catch
- Re-exportar tipos por compat sin uso real
EOF

  echo "context-snapshot: wrote $out"
}

cmd_init_state() {
  local issue="${1:-}" outdir="${2:-}"
  if [ -z "$issue" ] || [ -z "$outdir" ]; then
    echo "init-state: usage: init-state <issue> <out-dir>" >&2
    return 2
  fi
  mkdir -p "$outdir"
  local out="$outdir/state.json"
  if [ -f "$out" ]; then
    echo "init-state: $out already exists"
    return 0
  fi

  # Si hay issue.json cacheado, hidratar título/url desde ahí.
  local title="" url=""
  if [ -f "$outdir/issue.json" ]; then
    title="$(python3 -c "import json; print(json.load(open('$outdir/issue.json')).get('title',''))" 2>/dev/null || echo)"
    url="$(python3 -c "import json; print(json.load(open('$outdir/issue.json')).get('url',''))" 2>/dev/null || echo)"
  fi

  python3 - "$out" "$issue" "$title" "$url" <<'PY'
import json, sys, datetime
out, issue, title, url = sys.argv[1:5]
state = {
  "issue_number": issue,
  "issue_title": title,
  "issue_url": url,
  "status": "started",
  "status_emoji": "🚧",
  "status_label": "En curso",
  "mode": "dry-run",
  "started_utc": datetime.datetime.now(datetime.UTC).strftime("%Y-%m-%dT%H:%M:%SZ"),
  "milestone_triage": "⏳",
  "milestone_worktree": "⏳",
  "milestone_impl": "⏳",
  "milestone_screens": "⏳",
  "milestone_commit": "⏳",
  "milestone_pr": "⏳",
  "screens_block": "_Pendiente de triage._",
  "screens_table": "_Pendiente._",
  "screens_gallery": "_Pendiente._",
  "screens_list": "—",
  "next_steps_block": "El bot continúa trabajando. Volverá a comentar al avanzar.",
  "iteration_rows": "",
  "iter_count": 0,
  "max_iter": 6,
  "files_changed": 0,
  "net_lines": 0,
  "budget_files": 25,
  "budget_lines": 1500,
  "wall_clock": "—",
  "last_log_tail": "(sin errores aún)",
  "pr_block": "(dry-run — sin PR)",
  "pr_link": "—",
  "pr_number": "—",
  "pr_url": "—",
  "abort_reason": "",
  "changelog_link": "[CHANGELOG.md](../blob/master/CHANGELOG.md)",
  "changelog_line_link": "—",
  "issue_comment_url": "—",
  "pr_body_inlined_or_link": "—",
  "run_report_path": "—",
  "branch": "—",
  "worktree_dir": "—",
  "triage_verdict": "—",
  "triage_type": "—",
  "triage_scope": "—",
  "triage_complexity": "—",
  "triage_security": "—",
  "triage_summary": "—",
  "summary_line": "Inicializando run.",
  "summary_commercial": "—",
  "summary_technical": "—",
  "user_facing_changes": "—",
  "test_plan": "—",
  "tech_summary": "—",
  "perms_required": "—",
  "security_review_flag": "—",
  "check_status": "—",
  "test_status": "—",
  "lint_status": "—",
  "files_key_list": "—",
  "risks_block": "—",
  "type_label": "—",
  "updated_at": datetime.datetime.now(datetime.UTC).strftime("%Y-%m-%dT%H:%M:%SZ"),
  "started_utc": datetime.datetime.now(datetime.UTC).strftime("%Y-%m-%dT%H:%M:%SZ"),
  "finished_utc": "—",
  "run_id": "—",
  "remote_fns": "—",
  "migrations": "—",
  "iter_status": "—",
  "final_iter_status": "—",
  "pr_title": title or f"b7: issue #{issue}",
}
with open(out, "w") as f:
  json.dump(state, f, ensure_ascii=False, indent=2)
print(f"init-state: wrote {out}")
PY
}

cmd_verify_worktree() {
  local dir="${1:-}"
  if [ -z "$dir" ]; then
    echo "verify-worktree: usage: verify-worktree <dir>" >&2
    return 2
  fi
  if [ ! -d "$dir" ]; then
    echo "verify-worktree: not a directory: $dir" >&2
    return 30
  fi

  local fail=0

  # 1. Marker file from setup-worktree.sh
  if [ ! -f "$dir/.b7/worktree-ready.json" ]; then
    echo "verify-worktree: FAIL missing $dir/.b7/worktree-ready.json (worktree NOT created via b1-add-worktree)" >&2
    fail=1
  fi

  # 2. dev.sh shim
  if [ ! -x "$dir/dev.sh" ]; then
    echo "verify-worktree: FAIL missing or non-executable $dir/dev.sh" >&2
    fail=1
  fi

  # 3. At least one .env* symlink (the parent repo must have at least one, or there'd be nothing to link)
  local repo_root
  repo_root="$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | xargs dirname 2>/dev/null || echo)"
  local link_count
  link_count=$(find "$dir" -maxdepth 1 -name '.env*' -type l 2>/dev/null | wc -l | tr -d ' ')
  if [ -n "$repo_root" ] && [ -d "$repo_root" ]; then
    local src_env_count
    src_env_count=$(find "$repo_root" -maxdepth 1 -name '.env*' -type f 2>/dev/null | wc -l | tr -d ' ')
    if [ "$src_env_count" -gt 0 ] && [ "$link_count" -eq 0 ]; then
      echo "verify-worktree: FAIL parent has $src_env_count .env* file(s) but worktree has 0 symlinks" >&2
      fail=1
    fi
  fi

  # 4. node_modules present (pnpm install must have run)
  if [ ! -d "$dir/node_modules" ]; then
    echo "verify-worktree: FAIL missing $dir/node_modules (pnpm install did not run)" >&2
    fail=1
  fi

  # 5. Location must be under <parent>/worktrees/ — sibling-of-repo layout is the bug we're preventing
  case "$dir" in
    */worktrees/*) ;;
    *)
      echo "verify-worktree: FAIL $dir not under a worktrees/ directory (expected <parent>/worktrees/<slug>)" >&2
      fail=1
      ;;
  esac

  if [ "$fail" -ne 0 ]; then
    cat >&2 <<HINT
verify-worktree: this worktree was NOT created by b1-add-worktree/setup-worktree.sh.
Recreate it with:
  bash $PLUGIN_ROOT/skills/b1-add-worktree/scripts/setup-worktree.sh "<branch>" master --headless
Then re-run b7. Do not patch the broken worktree in place.
HINT
    return 31
  fi

  echo "verify-worktree OK: $dir"
  return 0
}

case "${1:-}" in
  preflight)        shift; cmd_preflight "$@" ;;
  check-budget)     shift; cmd_check_budget "$@" ;;
  acquire-lock)     shift; cmd_acquire_lock "$@" ;;
  release-lock)     shift; cmd_release_lock "$@" ;;
  state-dir)        shift; cmd_state_dir "$@" ;;
  cache-issue)      shift; cmd_cache_issue "$@" ;;
  context-snapshot) shift; cmd_context_snapshot "$@" ;;
  init-state)       shift; cmd_init_state "$@" ;;
  verify-worktree)  shift; cmd_verify_worktree "$@" ;;
  *)
    echo "Usage: $0 {preflight <issue>|check-budget <worktree>|acquire-lock|release-lock|state-dir|cache-issue <issue> <out>|context-snapshot <out>|init-state <issue> <out>|verify-worktree <dir>}" >&2
    exit 2
    ;;
esac
