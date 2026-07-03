#!/usr/bin/env bash
# Guardrails for b7-issue-to-pr.
#
# Subcommands:
#   env-check                          — validate runtimes/MCP/gh-token/DB before any phase; exit 19 on fail
#   preflight <issue-number>           — run before anything else; exits non-zero if unsafe to proceed
#   check-budget <worktree-dir>        — verify files-changed / lines-added under cap; exits non-zero if exceeded
#   acquire-lock [owner-pid]           — take the b7 lock (writes owner pid, default $PPID); exits non-zero if held
#   release-lock                       — remove the lock file
#   heartbeat <worktree-dir>           — write .b7/heartbeat (UTC) and touch the lock (keeps it fresh)
#   state-dir                          — print the b7 state dir (creates it if missing) and exit
#   cache-issue <issue-number> <out-dir> — cache `gh issue view` JSON to <out-dir>/issue.json (idempotent)
#   context-snapshot <out-dir>         — write <out-dir>/context.md with stack/aliases/colocated layout (no LLM)
#   init-state <issue-number> <out-dir> — write a minimal .b7/state.json scaffold for publish-docs.sh
#   verify-worktree <dir>              — verify the worktree was created by setup-worktree.sh (marker + symlinks + dev.sh + location)
#   verify-port <port> <worktree-dir>  — verify the dev server on <port> is serving <worktree> (cwd match); exit 40 nadie escucha, 41 intruso
#   validate-triage <triage.json>      — validate .b7/triage.json against triage-output.schema.json (required/enums/additionalProperties); exit 4 on invalid
#
# Env knobs:
#   B7_MAX_OPEN_PRS    (default 3)     — backpressure threshold for open auto-pr-bot PRs
#   B7_BUDGET_FILES    (default 25)
#   B7_BUDGET_LINES    (default 1500)
#   B7_BOT_LABEL       (default auto-pr-bot)
#   B7_LOCK_STALE_SECS (default 7200)  — lock older than this (mtime) is stale; matches b10's 2h zombie threshold
#
# env-check knobs:
#   B_ENV_CHECKS          (default "bin,mcp,gh,db,codegraph") — subset de checks a correr (coma-separado)
#   B_ENV_SKIP_MCP        (1 = saltar el check MCP; NUNCA setear dentro del loop por-issue de b8)
#   B_ENV_REQUIRED_MCP    (default "svelte") — servers MCP cuyo estado Failed/Needs-auth es FAIL (resto warn)
#   B_ENV_MCP_CACHE_SECS  (default 300) — TTL del cache de `claude mcp list` en <state-dir>/env-mcp.txt
#   B_ENV_CODEGRAPH_STALE_DAYS (default 7) — dias tras los cuales la db de codegraph se reporta stale (warn)

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

# Edad del lock en segundos (mtime). La staleness NO puede depender de kill -0:
# el lock sobrevive a run.sh a proposito (lo retiene la fase LLM), asi que el PID
# escritor muerto no significa run muerto. SKILL.md toca el lock en cada heartbeat.
lock_age_secs() {
  local f="$1" mtime
  mtime="$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo 0)"
  echo $(( $(date +%s) - mtime ))
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

  # Env-check PRIMERO: runtimes/MCP/gh-token/DB antes de cualquier fase (issue #7).
  # Detecta en segundos los blockers de entorno que hoy matan sesiones completas.
  cmd_env_check || return $?

  # Kill-switch file
  if [ -f "$sd/b7.STOP" ]; then
    echo "preflight: kill-switch present at $sd/b7.STOP — refusing to run" >&2
    return 10
  fi

  # Lock file — staleness por mtime, no por PID vivo (ver lock_age_secs).
  if [ -f "$sd/b7.lock" ]; then
    local pid age
    pid="$(cat "$sd/b7.lock" 2>/dev/null || echo '?')"
    age="$(lock_age_secs "$sd/b7.lock")"
    if [ "$age" -lt "${B7_LOCK_STALE_SECS:-7200}" ]; then
      echo "preflight: another b7 run is in progress (owner pid $pid, lock age ${age}s)" >&2
      return 11
    else
      echo "preflight: stale lock (age ${age}s > ${B7_LOCK_STALE_SECS:-7200}s) — removing" >&2
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

  # Codegraph: probe INFORMATIVO (nunca gate — decision del owner). Emite la linea
  # CODEGRAPH_STATUS=...; los sub-skills eligen codegraph_* vs rg segun el status.
  local cg_probe="$PLUGIN_ROOT/skills/b1-add-worktree/scripts/codegraph-probe.sh"
  if [ -x "$cg_probe" ]; then
    bash "$cg_probe" "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || true
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
  # Owner default: $PPID — el proceso invocador (cron/launchd/orquestador/sesion)
  # que sobrevive al handoff hacia la fase LLM. NO $$: ese PID muere con este script
  # y dejaba un lock instantaneamente "stale" para el janitor de b10.
  local owner="${1:-$PPID}" sd
  sd="$(ensure_state_dir)"
  if [ -f "$sd/b7.lock" ]; then
    local pid age
    pid="$(cat "$sd/b7.lock" 2>/dev/null || echo '?')"
    age="$(lock_age_secs "$sd/b7.lock")"
    if [ "$age" -lt "${B7_LOCK_STALE_SECS:-7200}" ]; then
      echo "acquire-lock: held by pid $pid (lock age ${age}s)" >&2
      return 11
    fi
    echo "acquire-lock: stale lock (age ${age}s) — taking over" >&2
  fi
  echo "$owner" > "$sd/b7.lock"
  echo "$sd/b7.lock"
}

cmd_release_lock() {
  local sd
  sd="$(ensure_state_dir)"
  rm -f "$sd/b7.lock"
}

cmd_heartbeat() {
  # Un solo lugar para el latido: heartbeat del worktree (b10 lo parsea con
  # `date -j -u -f '%Y-%m-%dT%H:%M:%SZ'` — NO cambiar el formato) + touch del lock
  # (la staleness del lock es por mtime; un build vivo lo mantiene fresco).
  local wt="${1:-}"
  if [ -z "$wt" ] || [ ! -d "$wt" ]; then
    echo "heartbeat: usage: heartbeat <worktree-dir>" >&2
    return 2
  fi
  mkdir -p "$wt/.b7"
  date -u +%Y-%m-%dT%H:%M:%SZ > "$wt/.b7/heartbeat"
  local sd
  sd="$(ensure_state_dir)"
  [ -f "$sd/b7.lock" ] && touch "$sd/b7.lock"
  return 0
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
  <feature>.md                     # doc del feature: proposito, pantallas, remote fns, datos, decisiones
  new/ , [id]/                     # sub-rutas con su propio +page.svelte (y *.remote.ts si aplica)
\`\`\`
Todo el feature vive en una carpeta bajo src/routes (regla 99%). Nada NUEVO en src/lib/features
ni thin wrappers. En \$lib solo: shadcn (\$lib/components/ui), css global, db (\$lib/server/db),
transversales genuinos (logger/auth/format usados por 3+ features sin logica de un feature).
Tolerancia legacy: EDITAR un feature existente bajo src/lib/features sigue SU patron interno;
CREAR un feature nuevo ahi esta prohibido. Al debuggear: leer primero el <feature>.md si existe.
Spec completa: skills/b2-build-feature/references/slice-spec.md (en el plugin).

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
- NUNCA imprimir valores de .env (cat/grep/head/printenv/env, etc.); usar \`hooks/env-probe.sh\` (fingerprints, no valores). El hook block-env-dump.sh lo bloquea.

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

  # Codegraph: probe informativo (nunca gate). El status decide la herramienta de
  # exploracion que usan los sub-skills; se deja escrito en el snapshot.
  local cg_probe cg_line
  cg_probe="$PLUGIN_ROOT/skills/b1-add-worktree/scripts/codegraph-probe.sh"
  if [ -x "$cg_probe" ]; then
    cg_line="$(bash "$cg_probe" "$repo_root" 2>/dev/null | tail -1)"
  fi
  cg_line="${cg_line:-CODEGRAPH_STATUS=missing db_age_days=-1}"
  cat >> "$out" <<EOF

## Codegraph
Estado (probe informativo, nunca gate): \`$cg_line\`

Regla: si el status **no es \`ok\`** (\`stale\`/\`missing\`/\`broken\`), usar \`rg\`/grep para
ubicar simbolos/rutas y **NO** invocar las tools \`codegraph_*\` (devolverian datos
stale o fallarian). Solo con status \`ok\` preferir \`codegraph_search\`/\`codegraph_context\`
(mas rapido que grep; suele evitar el fan-out de Explore). El probe SIEMPRE sale 0:
el status es recomendacion, no error.
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

cmd_verify_port() {
  # verify-port <port> <worktree-dir>
  # Confirma que quien escucha en <port> es un proceso cuyo cwd ES el worktree.
  # Evita revisar/servir master cuando otro dev server viejo ocupa el puerto
  # (dev.sh sin --strictPort derivaba a PORT+1 en silencio). Ver issue #6.
  local port="${1:-}" dir="${2:-}"
  if [ -z "$port" ] || [ -z "$dir" ]; then
    echo "verify-port: usage: verify-port <port> <worktree-dir>" >&2
    return 2
  fi

  # pid(s) escuchando en el puerto. Puede haber varios (worker + master de vite).
  local pids
  pids="$(lsof -nP -iTCP:"$port" -sTCP:LISTEN -t 2>/dev/null || true)"
  if [ -z "$pids" ]; then
    echo "verify-port: FAIL nadie escucha en :$port (dev server no levanto)" >&2
    return 40
  fi

  local want
  want="$(cd "$dir" 2>/dev/null && pwd -P || realpath "$dir" 2>/dev/null || echo "$dir")"

  local pid cwd got
  for pid in $pids; do
    # cwd del pid: lsof -Fn imprime lineas 'n<path>' para el fd cwd.
    cwd="$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1)"
    [ -z "$cwd" ] && continue
    got="$(realpath "$cwd" 2>/dev/null || echo "$cwd")"
    if [ "$got" = "$want" ]; then
      echo "B7_PORT_OK port=$port pid=$pid cwd=$got"
      return 0
    fi
  done

  # Ninguno de los listeners tiene cwd == worktree: intruso.
  pid="$(printf '%s\n' $pids | head -1)"
  cwd="$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1)"
  echo "verify-port: FAIL :$port lo sirve un proceso ajeno al worktree" >&2
  echo "  esperado cwd: $want" >&2
  echo "  intruso pid=$pid cwd=${cwd:-desconocido}" >&2
  echo "  hint: mata ese proceso (kill $pid) o revisa que dev.sh use --strictPort" >&2
  return 41
}

cmd_validate_triage() {
  local file="${1:-}"
  if [ -z "$file" ]; then
    echo "validate-triage: usage: validate-triage <triage.json>" >&2
    return 2
  fi
  if [ ! -f "$file" ]; then
    echo "VALIDATE_TRIAGE_FAIL file=$file reason=not-found" >&2
    return 4
  fi
  local schema="$SCRIPT_DIR/../templates/triage-output.schema.json"
  if [ ! -f "$schema" ]; then
    echo "validate-triage: schema not found at $schema" >&2
    return 3
  fi

  # Validacion mecanica contra el schema (draft 2020-12, subset): required, enums
  # de propiedades de primer nivel, y additionalProperties:false. No depende de la
  # libreria jsonschema (no siempre instalada); implementa el subset que importa.
  python3 - "$file" "$schema" <<'PY'
import json, sys

triage_path, schema_path = sys.argv[1], sys.argv[2]

def fail(reason):
    print(f"VALIDATE_TRIAGE_FAIL file={triage_path} reason={reason}", file=sys.stderr)
    sys.exit(4)

try:
    with open(triage_path) as f:
        data = json.load(f)
except json.JSONDecodeError as e:
    fail(f"invalid-json:{e}")

with open(schema_path) as f:
    schema = json.load(f)

if not isinstance(data, dict):
    fail("root-not-object")

props = schema.get("properties", {})

# required
for key in schema.get("required", []):
    if key not in data:
        fail(f"missing-required:{key}")

# additionalProperties:false → sin claves desconocidas de primer nivel
if schema.get("additionalProperties") is False:
    unknown = [k for k in data if k not in props]
    if unknown:
        fail(f"unknown-keys:{','.join(sorted(unknown))}")

# enums de propiedades de primer nivel presentes
for key, spec in props.items():
    if key in data and isinstance(spec, dict) and "enum" in spec:
        if data[key] not in spec["enum"]:
            fail(f"bad-enum:{key}={data[key]}:allowed={'|'.join(map(str, spec['enum']))}")

print(f"validate-triage OK: {triage_path}")
PY
}

# env-check: dueño unico de la validacion de entorno. Emite una linea por check
#   B_ENV name=<check> status=ok|fail|warn hint=<accion>
# y sale 19 SOLO si algun check es fail. Nunca imprime valores de .env (solo host/port
# del DB, explicitamente permitido por el AC del issue #7). Diseñado para correr como
# primer paso de los preflights de b7/b10/b8 y (subset bin+db) antes del worktree en b1.
#
# Checks (seleccionables via B_ENV_CHECKS): bin, mcp, gh, db, codegraph.
cmd_env_check() {
  local fail=0
  local checks="${B_ENV_CHECKS:-bin,mcp,gh,db,codegraph}"
  _want() { case ",$checks," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }

  # (1) Runtimes: fail si falta un binario duro; warn para los opcionales.
  if _want bin; then
    local b
    for b in node pnpm git gh jq python3 lsof; do
      if command -v "$b" >/dev/null 2>&1; then
        echo "B_ENV name=bin:$b status=ok hint=-"
      else
        echo "B_ENV name=bin:$b status=fail hint=falta en PATH; instalar $b"
        fail=1
      fi
    done
    for b in agent-browser nc; do
      if command -v "$b" >/dev/null 2>&1; then
        echo "B_ENV name=bin:$b status=ok hint=-"
      else
        echo "B_ENV name=bin:$b status=warn hint=opcional; instalar $b si se usa"
      fi
    done
  fi

  # (2) MCP: cache de `claude mcp list`; fail solo si un server REQUERIDO esta caido
  # o pide auth. Skippable con B_ENV_SKIP_MCP=1 (NUNCA dentro del loop por-issue).
  if _want mcp; then
    if [ "${B_ENV_SKIP_MCP:-0}" = "1" ]; then
      echo "B_ENV name=mcp status=warn hint=skip (B_ENV_SKIP_MCP=1)"
    elif ! command -v claude >/dev/null 2>&1; then
      echo "B_ENV name=mcp status=warn hint=claude CLI ausente; no se pudo listar MCP"
    else
      local sd cache ttl
      sd="$(ensure_state_dir)"
      cache="$sd/env-mcp.txt"
      ttl="${B_ENV_MCP_CACHE_SECS:-300}"
      if [ ! -f "$cache" ] || [ "$(lock_age_secs "$cache")" -gt "$ttl" ]; then
        claude mcp list > "$cache" 2>&1 || true
      fi
      local required="${B_ENV_REQUIRED_MCP:-svelte}" srv line
      for srv in $required; do
        line="$(grep -iE "(^|[[:space:]])${srv}[: ]" "$cache" 2>/dev/null | head -1 || true)"
        if [ -z "$line" ]; then
          echo "B_ENV name=mcp:$srv status=warn hint=server requerido no aparece en 'claude mcp list'"
        elif printf '%s' "$line" | grep -qiE 'fail|not connected|needs? auth|authenticat|✗|✘'; then
          echo "B_ENV name=mcp:$srv status=fail hint=reconectar/autenticar server MCP '$srv'"
          fail=1
        else
          echo "B_ENV name=mcp:$srv status=ok hint=-"
        fi
      done
      # Otros servers con problema: warn informativo (no bloquean).
      local other
      other="$(grep -iE 'fail|not connected|needs? auth|✗|✘' "$cache" 2>/dev/null \
        | grep -viE "($(printf '%s' "$required" | tr ' ' '|'))" | head -3 || true)"
      if [ -n "$other" ]; then
        echo "B_ENV name=mcp:otros status=warn hint=servers no-requeridos con problemas (informativo)"
      fi
    fi
  fi

  # (3) gh token: exige un login resoluble.
  if _want gh; then
    local login
    if login="$(gh api user -q .login 2>/dev/null)" && [ -n "$login" ]; then
      echo "B_ENV name=gh-token status=ok hint=autenticado como $login"
    else
      echo "B_ENV name=gh-token status=fail hint=gh auth login (token invalido/ausente)"
      fail=1
    fi
  fi

  # (4) DB: host/port de DATABASE_URL via python3 SIN imprimir el valor crudo
  # (stderr suprimido; el script atrapa toda excepcion y no emite el URL). nc -z -w3.
  if _want db; then
    if [ -z "${DATABASE_URL:-}" ]; then
      echo "B_ENV name=db status=warn hint=DATABASE_URL no seteada; skip check DB"
    else
      local hp
      hp="$(python3 -c 'import os
from urllib.parse import urlparse
try:
    u = urlparse(os.environ["DATABASE_URL"])
    h = u.hostname or ""
    p = u.port or 5432
    if h:
        print(h, p)
except Exception:
    pass' 2>/dev/null || true)"
      if [ -z "$hp" ]; then
        echo "B_ENV name=db status=warn hint=DATABASE_URL sin host parseable; skip"
      elif ! command -v nc >/dev/null 2>&1; then
        echo "B_ENV name=db status=warn hint=nc ausente; no se pudo probar ${hp% *}:${hp#* }"
      else
        local dbhost="${hp% *}" dbport="${hp#* }"
        if nc -z -w3 "$dbhost" "$dbport" >/dev/null 2>&1; then
          echo "B_ENV name=db status=ok hint=tcp $dbhost:$dbport alcanzable"
        else
          echo "B_ENV name=db status=fail hint=sin TCP a $dbhost:$dbport (DB caida/red)"
          fail=1
        fi
      fi
    fi
  fi

  # (5) codegraph: SOLO warn informativo si la db esta stale. NUNCA gate (decision del owner).
  if _want codegraph; then
    local repo_root cg dbf
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    cg="$repo_root/.codegraph"
    if [ ! -d "$cg" ]; then
      echo "B_ENV name=codegraph status=ok hint=sin .codegraph (opcional)"
    else
      dbf="$(find "$cg" -maxdepth 2 -name '*.db' -type f 2>/dev/null | head -1 || true)"
      if [ -z "$dbf" ]; then
        echo "B_ENV name=codegraph status=warn hint=.codegraph sin db; init pendiente (informativo)"
      else
        local age_days=$(( $(lock_age_secs "$dbf") / 86400 ))
        if [ "$age_days" -gt "${B_ENV_CODEGRAPH_STALE_DAYS:-7}" ]; then
          echo "B_ENV name=codegraph status=warn hint=db stale (${age_days}d); correr codegraph update (informativo)"
        else
          echo "B_ENV name=codegraph status=ok hint=db fresca (${age_days}d)"
        fi
      fi
    fi
  fi

  if [ "$fail" -ne 0 ]; then
    echo "env-check: uno o mas checks FAIL — abortando antes de gastar la sesion" >&2
    return 19
  fi
  return 0
}

case "${1:-}" in
  env-check)        shift; cmd_env_check "$@" ;;
  preflight)        shift; cmd_preflight "$@" ;;
  validate-triage)  shift; cmd_validate_triage "$@" ;;
  check-budget)     shift; cmd_check_budget "$@" ;;
  acquire-lock)     shift; cmd_acquire_lock "$@" ;;
  release-lock)     shift; cmd_release_lock "$@" ;;
  heartbeat)        shift; cmd_heartbeat "$@" ;;
  state-dir)        shift; cmd_state_dir "$@" ;;
  cache-issue)      shift; cmd_cache_issue "$@" ;;
  context-snapshot) shift; cmd_context_snapshot "$@" ;;
  init-state)       shift; cmd_init_state "$@" ;;
  verify-worktree)  shift; cmd_verify_worktree "$@" ;;
  verify-port)      shift; cmd_verify_port "$@" ;;
  *)
    echo "Usage: $0 {env-check|preflight <issue>|check-budget <worktree>|acquire-lock [owner-pid]|release-lock|heartbeat <worktree>|state-dir|cache-issue <issue> <out>|context-snapshot <out>|init-state <issue> <out>|verify-worktree <dir>|verify-port <port> <worktree>|validate-triage <triage.json>}" >&2
    exit 2
    ;;
esac
