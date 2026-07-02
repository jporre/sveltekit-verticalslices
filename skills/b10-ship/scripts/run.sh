#!/usr/bin/env bash
set -euo pipefail

# b10-ship run.sh — preflight + reconciliacion de estado. NO toma decisiones de
# negocio: observa GitHub + worktrees locales y emite lineas B10_* parseables
# para que el skill salte a la fase correcta. El estado canonico vive en GitHub.
#
# Subcommands:
#   preflight                 killswitch + gh auth + tree limpio + backpressure + smoke de scripts
#   acquire-lock              lock atomico b10.lock (stale tras 6h); emite B10_LOCK_TOKEN; exit 21 si otro corre
#   release-lock [token]      con token: borra solo si coincide (no pisa el lock de otra sesion)
#   reconcile <issue>         emite B10_PHASE=triage|build|verify|close|done|blocked + contexto
#   needs-info-check <issue>  emite B10_NEEDS_INFO_ANSWERED=true|false|unknown
#   janitor                   worktrees b7 con heartbeat >2h y sin b7.lock vivo (candidatos a zombie)
#
# Exit codes: 0 ok | 2 uso | 12 gh auth | 17 backpressure | 18 tree sucio | 19 env-check | 20 killswitch | 21 lock

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Plugin root derivado desde la ubicacion del script (.../skills/b10-ship/scripts).
# Portable: funciona en cualquier instalacion del plugin, no solo ~/.claude/skills.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"
B8_GUARD="$PLUGIN_ROOT/skills/b8-swarm/scripts/guardrails.sh"
B7_GUARD="$PLUGIN_ROOT/skills/b7-issue-to-pr/scripts/guardrails.sh"
ASSERT_CLEAN="$PLUGIN_ROOT/skills/b1-add-worktree/scripts/assert-clean.sh"
SETUP_WT="$PLUGIN_ROOT/skills/b1-add-worktree/scripts/setup-worktree.sh"
PUBLISH_DOCS="$PLUGIN_ROOT/skills/b7-issue-to-pr/scripts/publish-docs.sh"
VERDICT_SH="$PLUGIN_ROOT/skills/b6-pr-review/scripts/verdict.sh"
LOCK_STALE_SECS="${B10_LOCK_STALE_SECS:-21600}"
HEARTBEAT_STALE_SECS="${B10_HEARTBEAT_STALE_SECS:-7200}"

state_dir() { bash "$B8_GUARD" state-dir; }

cmd_preflight() {
  local sd; sd="$(state_dir)"
  if [ -f "$sd/b10.STOP" ] || [ -f "$sd/b7.STOP" ]; then
    echo "b10: kill-switch activo en $sd" >&2; return 20
  fi
  gh auth status >/dev/null 2>&1 || { echo "b10: gh auth fallo" >&2; return 12; }
  # Env-check: runtimes/MCP/gh-token/DB antes de cualquier fase (issue #7; exit 19 si falla).
  bash "$B7_GUARD" env-check || return $?
  # b7/b8 abortan con tree sucio en el repo principal: detectarlo ACA, no a mitad de build.
  if [ -n "$(git status --porcelain 2>/dev/null || true)" ]; then
    echo "b10: working tree del repo principal sucio — commitear/stashear antes de correr el pipeline" >&2
    return 18
  fi
  # Smoke test del contrato de scripts compartidos (rotura silenciosa por refactor).
  local missing=0
  for f in "$B8_GUARD" "$ASSERT_CLEAN" "$SETUP_WT" "$PUBLISH_DOCS" "$VERDICT_SH"; do
    [ -f "$f" ] || { echo "b10: FALTA script compartido: $f" >&2; missing=1; }
  done
  grep -q 'issue-comment' "$PUBLISH_DOCS" || { echo "b10: publish-docs.sh perdio el subcomando issue-comment" >&2; missing=1; }
  grep -q 'cmd_read' "$VERDICT_SH" || { echo "b10: verdict.sh perdio el subcomando read" >&2; missing=1; }
  grep -q 'backpressure' "$B8_GUARD" || { echo "b10: guardrails.sh perdio el subcomando backpressure" >&2; missing=1; }
  [ "$missing" -eq 0 ] || return 2
  bash "$B8_GUARD" backpressure || return $?
  echo "B10_PREFLIGHT=ok"
}

cmd_acquire_lock() {
  local sd lock now ts age token
  sd="$(state_dir)"; lock="$sd/b10.lock"; now="$(date +%s)"
  token="b10-$$-$now"
  # Creacion atomica via noclobber (bash 3.2 safe) — sin TOCTOU.
  if ( set -C; echo "$now $token" > "$lock" ) 2>/dev/null; then
    echo "B10_LOCK=$lock"; echo "B10_LOCK_TOKEN=$token"; return 0
  fi
  ts="$(awk '{print $1}' "$lock" 2>/dev/null | tr -cd '0-9')"; ts="${ts:-0}"
  age=$((now - ts))
  if [ "$age" -lt "$LOCK_STALE_SECS" ]; then
    echo "b10: otro run activo (lock de hace ${age}s; stale a los ${LOCK_STALE_SECS}s). Si es un gate humano legitimo de otra sesion, NO forzar." >&2
    return 21
  fi
  echo "b10: lock stale (${age}s) — lo tomo" >&2
  rm -f "$lock"
  if ( set -C; echo "$now $token" > "$lock" ) 2>/dev/null; then
    echo "B10_LOCK=$lock"; echo "B10_LOCK_TOKEN=$token"; return 0
  fi
  return 21
}

cmd_release_lock() {
  local sd lock token="${1:-}"
  sd="$(state_dir)"; lock="$sd/b10.lock"
  if [ -n "$token" ] && [ -f "$lock" ] && ! grep -q "$token" "$lock" 2>/dev/null; then
    echo "b10: el lock pertenece a otra sesion — no lo borro" >&2; return 0
  fi
  rm -f "$lock"; echo "B10_LOCK=released"
}

# PR cuyo body cierra el issue N (sin falsos positivos #2610 vs #261).
find_pr() {
  local n="$1" state="$2"
  gh pr list --state "$state" --limit 100 --json number,body \
    --jq "[.[] | select(.body | test(\"[Cc]loses #${n}([^0-9]|$)\"))] | (.[0].number // empty)"
}

find_worktree() {
  local n="$1" wt
  # 1) Branch propio del issue: (feat|fix|chore|refactor|docs)/<issue>-<slug>
  wt="$(git worktree list --porcelain | awk -v n="$n" '
    /^worktree /{wt=substr($0,10)}
    /^branch refs\/heads\/(feat|fix|chore|refactor|docs)\//{
      sub(/^branch refs\/heads\/(feat|fix|chore|refactor|docs)\//, "", $0);
      if ($0 ~ "^"n"-") { print wt; exit }
    }')"
  if [ -n "$wt" ]; then echo "$wt"; return 0; fi
  # 2) Worktrees cluster de b8 (rama swarm/<ids> o tematica): buscar artefacto por-issue.
  git worktree list --porcelain | awk '/^worktree /{print substr($0,10)}' | while IFS= read -r wt; do
    if [ -f "$wt/.b7/triage-${n}.json" ] || [ -f "$wt/.b7/issue-${n}.json" ]; then
      echo "$wt"; break
    fi
  done
}

# Veredicto b6: delega en el lector unico verdict.sh (cubre comentarios Y reviews).
# Reformatea la linea B6_VERDICT al mismo formato B10_B6 de antes, ahora con warnings=M.
b6_marker() {
  local pr="$1" line v b w
  line="$(bash "$VERDICT_SH" read "$pr" 2>/dev/null || true)"   # exit 3 (sin marker) -> line vacia
  [ -n "$line" ] || return 0
  v="$(echo "$line" | grep -oE 'verdict=[a-z-]+' | cut -d= -f2)"
  b="$(echo "$line" | grep -oE 'blockers=[0-9]+' | cut -d= -f2)"
  w="$(echo "$line" | grep -oE 'warnings=[0-9]+' | cut -d= -f2)"
  [ -n "$v" ] && echo "b6:verdict=$v blockers=$b warnings=$w"
}

cmd_needs_info_check() {
  local n="$1" comments marker_created last_answer
  comments="$(gh issue view "$n" --json comments)"
  marker_created="$(echo "$comments" | jq -r \
    '[.comments[] | select(.body | contains("<!-- b10:questions"))] | (last.createdAt // empty)')"
  if [ -z "$marker_created" ]; then
    echo "B10_NEEDS_INFO_ANSWERED=unknown"; return 0
  fi
  # Respuesta = comentario posterior al marker que NO sea del propio pipeline
  # (excluye todo lo que lleve markers/encabezados del flujo b — se postean con el token del usuario).
  last_answer="$(echo "$comments" | jq -r '
    [.comments[]
      | select(.body | test("<!-- b7:status -->|<!-- b10:|<!-- b6:|## Evaluacion de Issue|## Issue Evaluation|## Revision de feature completo") | not)
    ] | (last.createdAt // empty)')"
  if [ -n "$last_answer" ] && [[ "$last_answer" > "$marker_created" ]]; then
    echo "B10_NEEDS_INFO_ANSWERED=true"
  else
    echo "B10_NEEDS_INFO_ANSWERED=false"
  fi
}

cmd_reconcile() {
  local n="$1"
  local ijson state labels pr wt marker blockers hb age now
  ijson="$(gh issue view "$n" --json state,labels,title,body)"
  state="$(echo "$ijson" | jq -r .state)"
  labels="$(echo "$ijson" | jq -r '[.labels[].name] | join(",")')"
  echo "B10_ISSUE=$n"
  echo "B10_ISSUE_STATE=$state"
  echo "B10_LABELS=$labels"

  if [ "$state" = "CLOSED" ]; then
    pr="$(find_pr "$n" open)"
    [ -n "$pr" ] && echo "B10_PR_ORPHAN=$pr (issue cerrado con PR abierto — revisar/cerrar a mano o via b9)"
    wt="$(find_worktree "$n")"
    [ -n "$wt" ] && echo "B10_WORKTREE=$wt (issue cerrado — limpieza pendiente via b9 PASO 6)"
    echo "B10_PHASE=done"; return 0
  fi

  pr="$(find_pr "$n" open)"
  if [ -n "$pr" ]; then
    echo "B10_PR=$pr"
    echo "B10_PR_STATE=$(gh pr view "$pr" --json isDraft,mergeable,reviewDecision \
      --jq '"draft=\(.isDraft) mergeable=\(.mergeable) review=\(.reviewDecision // "none")"')"
    wt="$(find_worktree "$n")"; [ -n "$wt" ] && echo "B10_WORKTREE=$wt"
    marker="$(b6_marker "$pr")"
    if [ -n "$marker" ]; then
      echo "B10_B6=$marker"
      blockers="$(echo "$marker" | grep -oE 'blockers=[0-9]+' | cut -d= -f2)"
      if [ "${blockers:-1}" -gt 0 ]; then
        echo "B10_PHASE=verify"   # review presente pero con blockers: NO saltar a close
      else
        echo "B10_PHASE=close"
      fi
    else
      echo "B10_B6=absent"
      echo "B10_PHASE=verify"
    fi
    return 0
  fi

  # PR mergeado con issue aun abierto (Closes mal formateado o base equivocada).
  pr="$(find_pr "$n" merged)"
  if [ -n "$pr" ]; then
    echo "B10_PR_MERGED=$pr (mergeado pero el issue sigue abierto — cerrar issue + limpiar via b9)"
    echo "B10_PHASE=close"; return 0
  fi

  wt="$(find_worktree "$n")"
  if [ -n "$wt" ]; then
    echo "B10_WORKTREE=$wt"
    echo "B10_RESUME=true"
    if [ -f "$wt/.b7/heartbeat" ]; then
      now="$(date +%s)"
      hb="$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$(cat "$wt/.b7/heartbeat")" +%s 2>/dev/null || echo 0)"
      age=$((now - hb))
      [ "$age" -gt "$HEARTBEAT_STALE_SECS" ] && echo "B10_ZOMBIE=true (heartbeat hace ${age}s — verificar b7.lock antes de barrer)"
    fi
    echo "B10_PHASE=build"; return 0
  fi

  case ",$labels," in
    *,needs-info,*)
      cmd_needs_info_check "$n"
      echo "B10_PHASE=triage"   # con answered=false el skill frena; unknown/true re-triagea
      return 0 ;;
  esac

  # Dependencias declaradas bajo el heading "## Blocked by" (misma convencion que epic-graph.sh).
  local deps dep open_deps=""
  deps="$(echo "$ijson" | jq -r .body | sed -n '/^##* *[Bb]locked *[Bb]y/,/^##[^#]/p' | grep -oE '#[0-9]+' | tr -d '#' | sort -un || true)"
  for dep in $deps; do
    [ "$(gh issue view "$dep" --json state --jq .state 2>/dev/null)" = "OPEN" ] && open_deps="${open_deps}${dep},"
  done
  if [ -n "$open_deps" ]; then
    echo "B10_BLOCKED_BY=${open_deps%,}"
    echo "B10_PHASE=blocked"; return 0
  fi

  echo "B10_PHASE=triage"
}

cmd_janitor() {
  local now wt hb age branch sd b7lock
  now="$(date +%s)"
  sd="$(state_dir)"; b7lock="$sd/b7.lock"
  if [ -f "$b7lock" ] && kill -0 "$(cat "$b7lock" 2>/dev/null)" 2>/dev/null; then
    echo "B10_JANITOR=skip (b7.lock vivo — hay un build corriendo, no barrer)"
    return 0
  fi
  git worktree list --porcelain | awk '/^worktree /{print substr($0,10)}' | while IFS= read -r wt; do
    [ -f "$wt/.b7/worktree-ready.json" ] || continue
    [ -f "$wt/.b7/heartbeat" ] || continue
    hb="$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$(cat "$wt/.b7/heartbeat")" +%s 2>/dev/null || echo 0)"
    age=$((now - hb))
    if [ "$age" -gt "$HEARTBEAT_STALE_SECS" ]; then
      branch="$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
      echo "B10_ZOMBIE dir=$wt branch=$branch heartbeat_age_s=$age"
    fi
  done
  return 0
}

case "${1:-}" in
  preflight)        cmd_preflight ;;
  acquire-lock)     cmd_acquire_lock ;;
  release-lock)     cmd_release_lock "${2:-}" ;;
  reconcile)        [ -n "${2:-}" ] || { echo "Usage: $0 reconcile <issue>" >&2; exit 2; }; cmd_reconcile "$2" ;;
  needs-info-check) [ -n "${2:-}" ] || { echo "Usage: $0 needs-info-check <issue>" >&2; exit 2; }; cmd_needs_info_check "$2" ;;
  janitor)          cmd_janitor ;;
  *) echo "Usage: $0 {preflight|acquire-lock|release-lock [token]|reconcile <issue>|needs-info-check <issue>|janitor}" >&2; exit 2 ;;
esac
