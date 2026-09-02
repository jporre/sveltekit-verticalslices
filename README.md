# b-pipeline

A [Claude Code](https://claude.com/claude-code) plugin that drives a GitHub issue all the way to a merged pull request — **triage → isolated worktree → build → screenshots → commit → draft PR → code review → gated merge** — by chaining a set of small, focused skills.

It is built for **SvelteKit** projects (Remote Functions, Svelte 5 runes, Drizzle, shadcn-svelte) and keeps a **human in the loop** at the points that matter: nothing complex gets built, and nothing ever merges, without a person saying yes.

> Throughout this plugin, **"task" = GitHub issue**. The two terms are used interchangeably.

---

## Table of contents

1. [What it does](#1-what-it-does)
2. [How it works (mental model)](#2-how-it-works-mental-model)
3. [Prerequisites](#3-prerequisites)
4. [Installation, step by step](#4-installation-step-by-step)
5. [Quick start](#5-quick-start)
6. [The skills at a glance](#6-the-skills-at-a-glance)
7. [The pipeline, step by step](#7-the-pipeline-step-by-step)
8. [Orchestrators and their flags](#8-orchestrators-and-their-flags)
9. [Human gates](#9-human-gates)
10. [Labels the pipeline uses](#10-labels-the-pipeline-uses)
11. [Artifacts it produces](#11-artifacts-it-produces)
12. [Safety features](#12-safety-features)
13. [Recovery and idempotency](#13-recovery-and-idempotency)
14. [Using individual skills](#14-using-individual-skills)
15. [Troubleshooting](#15-troubleshooting)

---

## 1. What it does

You give it an issue number. It:

1. **Triages** the issue (labels it, evaluates complexity, asks for missing info).
2. Creates an **isolated git worktree** so your main checkout is never touched.
3. **Builds** the feature screen by screen, verifying each one in a real browser.
4. **Commits** with conventional-commit messages.
5. Opens a **draft PR** with release notes, technical changes, and screenshots.
6. Runs an automated **code review** across five areas.
7. Waits for a **human approval**, then **merges**, closes the issue, and cleans up the worktree.

It runs unattended where it is safe to do so, and **stops and asks** where judgement is required (complex builds, every merge).

**Don't have the issues yet?** Start one step earlier with **`b0-conversation-to-issues`**: it turns the current conversation (a design chat, a brainstorm, a plan) into well-scoped GitHub issues, **sliced vertically** (tracer-bullet), ordered by dependency, and grouped under an epic — the exact shape `b10-ship --epic` drains. It verifies what you *really* want before creating anything. You can even invoke it with nothing but a raw idea: **design mode** interviews you one question at a time (recommended answer included, codebase facts looked up instead of asked), keeps a living design doc in `docs/plans/`, and only converts to issues once the plan converges.

---

## 2. How it works (mental model)

A few ideas explain the whole design:

- **Orchestrators chain atomic skills.** The big skills (`b10-ship`, `b7-issue-to-pr`, `b8-swarm`) do not implement anything themselves — they *decide* and *call* the small skills (`b1-triage-issue`, `b1-add-worktree`, `b2-build-feature`, `b3-git-commit`, `b4-pull-request`, `b6-pr-review`, `b9-close`). The value is the orchestration, the budgets, and the gates.
- **State lives in GitHub, not on disk.** Labels, sticky comments with hidden markers (e.g. `<!-- b7:status -->`), and PR review verdicts (`<!-- b6:verdict=... -->`) are the source of truth. This is why the pipeline is **idempotent**: re-running the same command reconciles state from GitHub and resumes where it left off (see [§13](#13-recovery-and-idempotency)).
- **Isolation by worktree.** Every feature is built in its own `git worktree` on its own branch, with its own dev-server port. Your main working tree is never edited.
- **Screen-first builds.** Features are decomposed into screens (Feature-Sliced Design). Each screen is built, then visually verified in your real Chrome before the PR is opened. The outcome is never silent: a `b7:screen-review=` marker on the PR and a `screens=` token on the run's status line always say whether it ran, passed, or was skipped (and why) — see [§7](#7-the-pipeline-step-by-step) and [§11](#11-artifacts-it-produces).
- **Budgets and backpressure.** Runs are bounded (max iterations, max changed files) and the pipeline refuses to pile up work (it will not start if too many bot PRs are already open).
- **Delegation, not bypass, at scale.** Every automated shortcut (epic auto-merge, batched approvals, parallel builds) re-derives its own evidence at the moment it acts instead of trusting a flag — see [§9](#9-human-gates).

---

## 3. Prerequisites

| Requirement | Why | Check |
| --- | --- | --- |
| **Claude Code** | The plugin runs inside Claude Code. | `claude --version` |
| **`gh` CLI, authenticated** | All GitHub state (issues, labels, PRs, comments) goes through `gh`. | `gh auth status` |
| **A git repo with a GitHub remote** | The pipeline reads issues and opens PRs against `origin`. | `gh repo view` |
| **A SvelteKit project** | `b2-build-feature` is SvelteKit-specific (Remote Functions, Svelte 5, Drizzle, shadcn-svelte). | — |
| **Node + a dev server** | The worktree runs `vite` so screens can be verified. | `npm run dev` works |
| **`agent-browser` CLI** | Visual screen review drives its own browser (navigation, auth cookie, screenshots, console). | `agent-browser --help` |

> If you only want issue → draft PR and you do not need visual review, `agent-browser` is optional — screens are skipped with a note when the dev server or browser is unavailable.

> The default branch name is detected, never assumed — `main`, `master`, or anything else works with zero configuration.

---

## 4. Installation, step by step

1. **Add the marketplace.** Point Claude Code at this repository (a URL or a local path both work):

   ```bash
   claude plugin marketplace add https://github.com/jporre/sveltekit-verticalslices
   ```

2. **Install the plugin:**

   ```bash
   claude plugin install b-pipeline
   ```

3. **Verify the skills are available.** Inside Claude Code, the skills are namespaced as `b-pipeline:<skill>`. Type `/` and you should see entries like `/b-pipeline:b10-ship`.

4. **Confirm `gh` is authenticated** (the pipeline will refuse to start otherwise):

   ```bash
   gh auth status
   ```

That is it — there is no build step. The plugin auto-discovers its hooks from `hooks/hooks.json`, its skills from `skills/`, and its agents from `agents/`.

### Instalación alternativa: pi

El mismo repo funciona como [paquete pi](https://pi.dev/packages) — sin paso extra de empaquetado:

```bash
pi install /ruta/a/b-pipeline-market        # checkout local
pi install git:github.com/jporre/sveltekit-verticalslices@v1.10.0   # git
```

pi descubre los skills de `skills/` (invocables como `/skill:b10-ship 42`) y carga la extensión `pi/b-pipeline-compat.ts`, que activa los mismos guardrails que los hooks de Claude Code (bloqueo de `git worktree add` directo, bloqueo de dumps de `.env`, symlinks de `.env*` a los worktrees) y exporta `CLAUDE_PLUGIN_ROOT` para que los scripts del plugin resuelvan su raíz igual que en Claude Code.

> **Nota de compatibilidad**: skills, guardrails y agentes (`b7-impl`, `b7-impl-s`, `b7-screen-review` — portados a `pi-agents/`) están verificados en pi. Los orquestadores llevan una nota **Multi-harness** que mapea las tools de Claude Code (`AskUserQuestion`, `Agent`, `Skill`, `Workflow`) a sus equivalentes en pi (pregunta en texto, tool `subagent`, carga del SKILL.md con `read`, `subagent` con `workflowScript`).

---

## 5. Quick start

The simplest end-to-end run — take issue **42** all the way to a merged PR:

```text
/b-pipeline:b10-ship 42
```

What you will see:

1. The pipeline triages #42 and (if it is `simple` or `medium`) starts building immediately.
2. It builds in a worktree, commits, opens a **draft PR**, and runs the auto-review.
3. It **pauses at the merge gate** and asks you to approve.
4. On approval it merges, closes #42, and removes the worktree.

Want to see what it *would* do without touching anything?

```text
/b-pipeline:b10-ship 42 --dry-run
```

Only need the draft PR (stop before merge)?

```text
/b-pipeline:b7-issue-to-pr 42
```

Don't have the issues yet — just a conversation? Generate them first, then ship the epic:

```text
/b-pipeline:b0-conversation-to-issues        # turns this chat into sliced issues + epic
/b-pipeline:b10-ship --epic=<N>              # drains the epic it just created
```

---

## 6. The skills at a glance

Skills are namespaced `b-pipeline:<skill>`.

| Skill | Role |
| --- | --- |
| **b0-conversation-to-issues** | Genesis step (before triage). Turns the conversation (or a plan/PRD via `--from`) into vertically-sliced GitHub issues with dependencies and an epic, ready for `b10-ship --epic`. With a raw idea it enters design mode first (`--design` to force): a 1-question-at-a-time interview that matures the idea into a `docs/plans/` design doc before slicing. Verifies the real intent with a human gate — including the execution mode (fast/supervised) — before creating anything. |
| **b10-ship** | Top-level orchestrator. `<issue>` for one issue, or `--epic=<N>` to drain an epic's sub-issue graph. Chains triage → build → review → close with the human gates. |
| **b7-issue-to-pr** | Single-issue orchestrator: triage → worktree → build → screen review → commit → **draft PR** → auto-review. Stops at the draft PR (does not merge). |
| **b8-swarm** | Resolves a **cluster of related issues** in **one** combined PR (refactors, multi-step migrations, "Phase X.Y" series). One worktree, one branch, one PR. |
| **b1-triage-issue** | Evaluates and labels a GitHub issue (ready / needs-info / blocked / duplicate + simple / medium / complex) and emits a `TRIAGE_RESULT`. |
| **b1-add-worktree** | Creates an isolated worktree (`setup-worktree.sh`) and gates on a clean tree (`assert-clean.sh`). Installs a per-worktree pre-commit budget hook. |
| **b2-build-feature** | The actual SvelteKit implementation: Remote Functions, Svelte 5 runes, Drizzle, shadcn-svelte, with in-browser verification. |
| **b3-git-commit** | Conventional commits with intelligent staging; enforces a clean-tree gate. |
| **b4-pull-request** | Creates the PR from the project template. |
| **b6-pr-review** | Reviews a PR across five areas and writes a durable verdict marker (`<!-- b6:verdict=... -->`). |
| **b9-close** | Canonical close: merges the PR, closes the issue, and cleans the worktree — behind a human approval gate. |
| **b-setup-or-fix** | Standalone "genie in a bottle" — **user-invoked only, never chained by the pipeline**. Audits an entire degraded SvelteKit repo (load functions / manual fetch instead of Remote Functions, Svelte 4 syntax, over-engineering, duplicates, comment noise) and migrates it rung by rung (E1 security → E6 docs) toward the same doctrine b2 builds with and b6 reviews against — or installs that base in a fresh project (`--init`). Every rung is verified against a baseline and human-gated before any edit. |

The visual reviewer `b7-screen-review` is a plugin **agent**, not a skill: it is defined in `agents/b7-screen-review.md` and spawned by `b7-issue-to-pr` / `b8-swarm` via `subagent_type: "b-pipeline:b7-screen-review"`, one per screen in parallel. It verifies each screen against the triage's visual acceptance criteria using the `agent-browser` CLI.

---

## 7. The pipeline, step by step

This is exactly what happens when you run `/b-pipeline:b10-ship <issue>` — each stage, the skill that does the work, and who invokes it:

| Stage | Skill | Invoked by | Gate / stop condition |
| --- | --- | --- | --- |
| Preflight + lock (kill switch, `gh` auth, clean tree, backpressure) | `b10-ship` | you | Refuses to start if any check fails |
| Reconcile state from GitHub (labels, PR, verdict) and jump to the pending phase | `b10-ship` | `b10-ship` | — (this is what makes re-running safe) |
| Triage: readiness + complexity labels | `b1-triage-issue` | `b10-ship` | `complex` → human chooses force / interactive / skip; `needs-info` / `blocked` / `duplicate` → posts questions and stops |
| Create isolated worktree, branch `feat/…` or `fix/…` | `b1-add-worktree` | `b7-issue-to-pr` (step 1) | Aborts if the worktree cannot be created |
| Sticky status comment on the issue (`<!-- b7:status -->`) | `b7-issue-to-pr` | `b7-issue-to-pr` (step 2) | — |
| Build the feature screen by screen | `b2-build-feature` | `b7-issue-to-pr` | — |
| Visual verification of each screen | `b7-screen-review` (plugin agent) | `b7-issue-to-pr` (parallel, one agent per screen) | Skipped with a note if dev server or `agent-browser` is unavailable |
| Conventional commits, grouped by theme | `b3-git-commit` | `b7-issue-to-pr` (step 3) | — |
| Draft PR with `Closes #<issue>` + label sync (`ready` → `in-progress` → `in-review`) | `b4-pull-request` | `b7-issue-to-pr` (step 4) | — |
| Auto-review across five areas, durable verdict marker (`<!-- b6:verdict=... -->`) | `b6-pr-review` | `b7-issue-to-pr` (step 5) | blockers > 0 → label `needs-human-review`, summarize, stop |
| Merge the PR, close the issue, remove the worktree | `b9-close` | `b10-ship` | **Always** a human gate: `merge-approved` label or in-session yes; otherwise leaves `awaiting-approval` |

`b7-issue-to-pr`'s five mandatory, non-skippable steps are the rows marked step 1–5 (worktree, sticky comment, commit, draft PR, review); the build and the visual verification happen between steps 2 and 3.

### A note on skill numbering

The `bN-` prefixes reflect the order the skills were created, not the execution order, and directories are never renamed (links and history stay stable). That is why there are two `b1` skills (`b1-triage-issue`, `b1-add-worktree`), one `b7` skill (`b7-issue-to-pr`) plus the `b7-screen-review` agent, a single `b3` (`b3-git-commit`), and no `b5`.

---

## 8. Orchestrators and their flags

### `b10-ship` — full pipeline through merge

```text
/b-pipeline:b10-ship <issue>          # one issue, triage → merge
/b-pipeline:b10-ship --epic=<N>       # drain an epic's sub-issue graph
/b-pipeline:b10-ship <issue> --dry-run # report the plan only, change nothing
/b-pipeline:b10-ship --epic=<N> --cluster  # independent waves via b8-swarm (combined PRs)
/b-pipeline:b10-ship <issue> --informe # on close, also generate a weekly report entry
```

Epic mode adds three opt-in behaviors, all off by default and all still gated:

- **Auto-merge drain.** Label the epic `epic-auto-merge` and sub-issue PRs merge without a per-PR approval as they clear review — `b9-close` independently re-checks epic membership, a fresh 0-blocker `b6` verdict, and green CI before every single merge (still one at a time). The epic's own closing slice is never auto-merged; it always waits for the `epic-approved` gate below.
- **Batch approvals.** Instead of one prompt per issue, complex-issue decisions and regression waivers are grouped into a single `AskUserQuestion` per wave, each option showing its own evidence.
- **Parallel builds (opt-in).** Set `B7_PARALLEL=1` in the environment to let an epic wave build a few independent, non-`complex` issues concurrently (capped, distinct scopes only). Omit it and builds stay sequential, which is the default and the safer choice for most repos.

**Fast mode is one switch.** A live `epic-auto-merge` label (human actor) turns on the whole package at once — auto-merge drain, parallel wave builds (`B7_PARALLEL=1` implied), automatic same-scope clustering via `b8-swarm`, and the dynamic backpressure cap — no flags or env vars needed; `b0`'s gate can stamp the label at creation when you pick fast execution. Removing the label reverts everything to sequential + per-PR gates. The four human gates (complex batch, waiver batch, `epic-approved`, CI-failure stop) never turn off.

See `skills/b10-ship/references/epic-mode.md` for the full mechanics if you are auditing or extending the pipeline.

### `b7-issue-to-pr` — issue → draft PR (stops before merge)

```text
/b-pipeline:b7-issue-to-pr <issue>
        --lang=es              # language for issue comments / PR body
        --dry-run | --wet      # --wet (default) opens the PR; --dry-run builds but opens nothing
        --no-pr                # build + commit, skip PR creation
        --max-iterations=N     # cap build/review iterations (default 6)
        --budget-files=N       # cap changed files (default 25)
        --force-complex        # build a complex issue without the gate
```

### `b8-swarm` — cluster of related issues → one combined PR

Use when several issues touch the same area and belong in a single PR (a multi-step migration, a "Phase X.Y" series). It produces one worktree, one branch, and one combined PR — not one PR per issue.

---

## 9. Human gates

There are three points where a person must decide:

1. **Complex issues** are not built unattended. Triage flags `complex`; you choose force / interactive / skip.
2. **No PR ever merges** without (a) a green `b6` review (0 blockers) **and** (b) explicit human approval — the `merge-approved` label, an in-session yes, or the delegated epic channel below.
3. **An epic's closing slice** requires an epic review and the `epic-approved` label before it merges — this gate is never delegated or auto-approved.

**Delegating gate 2 at epic scale.** The `epic-auto-merge` label on an epic lets its sub-issue PRs merge unattended as each clears review, but it is a scoped delegation, not a bypass: `b9-close` re-verifies, on every single merge, that the PR belongs to that epic, that its `b6` review is fresh with 0 blockers, and that CI is green — a stale label, a foreign PR, or a `needs-human-review` sub-issue disqualifies it back to a human channel. Any sub-issue can veto the whole channel by carrying `needs-human-review`. To keep gate 1 and the regression-test judgment call from turning into one prompt per issue, epic runs batch those decisions into a single multi-select question per wave instead — see [§8](#8-orchestrators-and-their-flags).

---

## 10. Labels the pipeline uses

Triage reads and writes these labels; they are the pipeline's control plane. Create them in your repo so triage can apply them:

- **Readiness:** `ready`, `needs-info`, `blocked`, `duplicate`
- **Complexity:** `simple`, `medium`, `complex`
- **Progress:** `in-progress`, `in-review`
- **Bot / approval:** `auto-pr-bot`, `merge-approved`, `epic-approved`, `epic-auto-merge`, `awaiting-approval`, `awaiting-walkthrough`
- **Batch-decision (epic mode):** `force-complex-ok`, `regression-waiver-ok`
- **Escalation:** `needs-human-review`, `pipeline-failed`

---

## 11. Artifacts it produces

- **Worktrees** — one per feature, on a `feat/…` or `fix/…` branch, removed on close.
- **`.b7/` state** inside the worktree — `state.json`, per-screen criteria (`.b7/screens/<Name>.md`), and visual review output (`.b7/review/<Name>.json` + PNGs).
- **Run reports** — a markdown report per run (kept under the plugin's state dir).
- **GitHub trail** — a sticky issue comment, a draft PR with release notes + technical changes, a `<!-- b7:screen-review=... -->` marker recording whether visual verification ran (and why not, if it didn't), and a `b6` review comment with a durable verdict marker. A bot PR that touches UI with no screen evidence and no declared skip is a `b6` **blocker**, not a silent gap.

---

## 12. Safety features

- **Kill switch.** Create a `b7.STOP` file in the state dir and the pipeline refuses to start.
- **Single-flight lock.** Only one run at a time; stale locks expire after 6 hours, and a run never deletes another session's lock.
- **Budgets.** `--max-iterations` and `--budget-files` bound every run.
- **Backpressure.** With three or more open `auto-pr-bot` PRs, the pipeline offers to drain them before starting more.
- **Per-worktree pre-commit hook.** `b1-add-worktree` installs a budget hook scoped to the worktree (via `core.hooksPath --worktree`), chaining any existing hook (husky/lefthook) first. It blocks commits that blow the file budget or touch a secret denylist (`*.pem`, `*.key`, `secrets/`).
- **Hooks (full disclosure of what runs on your machine).** Installing the plugin registers the hooks declared in `hooks/hooks.json` — four scripts, five registrations:
  - `PreToolUse` on **Bash** → `block-git-worktree-add.sh`: blocks a raw `git worktree add`, nudging you to `b1-add-worktree` (which sets up isolation correctly).
  - `PreToolUse` on **Bash** → `block-env-dump.sh`: blocks commands that would dump secret-bearing env files (e.g. `.env`).
  - `PreToolUse` on **Read** → `block-env-dump.sh`: same guard when Claude tries to read those files directly.
  - `PostToolUse` on **Bash** → `link-worktree-env.sh`: after `setup-worktree.sh` runs, symlinks the parent repo's untracked `.env*` files into each worktree. Non-fatal and idempotent; lives in a hook so the setup script itself stays free of secret-touching patterns that trip the harness safety classifier in headless runs.
  - `SessionStart` → `write-root-marker.sh`: writes the plugin's install path to `~/.claude/b-pipeline.root` so the pipeline's scripts can find it (skill snippets do not receive `CLAUDE_PLUGIN_ROOT`).

  All hooks run **locally only** — no network calls, no telemetry; they merely allow or block an action (or write a local marker). Everything else in the plugin runs on demand, and GitHub access uses your own authenticated `gh` CLI.
- **Worktree isolation.** The main checkout is never edited; all writes go to the worktree.

---

## 13. Recovery and idempotency

**The universal recovery action is to re-run the same command.** Because state lives in GitHub, a re-run reconciles and jumps to the pending phase:

```text
/b-pipeline:b10-ship 42      # interrupted? just run it again — it resumes
```

- Build crashed after the worktree was created → the next run resumes the build.
- PR opened but review missing → the next run runs the review.
- PR approved but not merged → the next run merges and closes.

You almost never need to clean up by hand.

---

## 14. Using individual skills

The orchestrators are the happy path, but every skill works standalone:

```text
/b-pipeline:b1-triage-issue 42      # just triage and label issue #42
/b-pipeline:b1-add-worktree my-feature   # just create an isolated worktree
/b-pipeline:b6-pr-review 128        # just review PR #128
/b-pipeline:b9-close 128            # just merge PR #128 and clean up (with the gate)
/b-pipeline:b-setup-or-fix --audit       # diagnose the whole repo, touch nothing
/b-pipeline:b-setup-or-fix               # full rescue: audit -> human gate -> verified rungs
```

---

## 15. Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| Pipeline refuses to start | `gh` not authenticated | `gh auth login` |
| Refuses to start, mentions dirty tree | Main working tree has uncommitted changes | Commit or stash, then re-run |
| Refuses to start, mentions backpressure | Three or more open `auto-pr-bot` PRs | Merge/close some, or accept the offer to drain them |
| Refuses to start, mentions `b7.STOP` | Kill switch file present | Delete the `b7.STOP` file in the state dir |
| Screens skipped / "auth-required" | Dev server not up, or Chrome not logged in | Start the dev server; open the app in your real Chrome and log in, then re-run |
| Build stops at "complex" | Complexity gate | Re-run and choose to force, or pass `--force-complex` to `b7-issue-to-pr` |
| PR opened but won't merge | Missing approval or open `b6` blockers | Add the `merge-approved` label (or approve in session) and resolve blockers |

---

*Battle-tested end to end on a real 10-sub-issue epic (PRs opened, reviewed, and merged through the gates).*
