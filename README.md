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

**Don't have the issues yet?** Start one step earlier with **`b0-conversation-to-issues`**: it turns the current conversation (a design chat, a brainstorm, a plan) into well-scoped GitHub issues, **sliced vertically** (tracer-bullet), ordered by dependency, and grouped under an epic — the exact shape `b10-ship --epic` drains. It verifies what you *really* want before creating anything.

---

## 2. How it works (mental model)

A few ideas explain the whole design:

- **Orchestrators chain atomic skills.** The big skills (`b10-ship`, `b7-issue-to-pr`, `b8-swarm`) do not implement anything themselves — they *decide* and *call* the small skills (`b1-triage-issue`, `b1-add-worktree`, `b2-build-feature`, `b3-git-commit`, `b4-pull-request`, `b6-pr-review`, `b9-close`). The value is the orchestration, the budgets, and the gates.
- **State lives in GitHub, not on disk.** Labels, sticky comments with hidden markers (e.g. `<!-- b7:status -->`), and PR review verdicts (`<!-- b6:verdict=... -->`) are the source of truth. This is why the pipeline is **idempotent**: re-running the same command reconciles state from GitHub and resumes where it left off (see [§13](#13-recovery-and-idempotency)).
- **Isolation by worktree.** Every feature is built in its own `git worktree` on its own branch, with its own dev-server port. Your main working tree is never edited.
- **Screen-first builds.** Features are decomposed into screens (Feature-Sliced Design). Each screen is built, then visually verified in your real Chrome before the PR is opened.
- **Budgets and backpressure.** Runs are bounded (max iterations, max changed files) and the pipeline refuses to pile up work (it will not start if too many bot PRs are already open).

---

## 3. Prerequisites

| Requirement | Why | Check |
| --- | --- | --- |
| **Claude Code** | The plugin runs inside Claude Code. | `claude --version` |
| **`gh` CLI, authenticated** | All GitHub state (issues, labels, PRs, comments) goes through `gh`. | `gh auth status` |
| **A git repo with a GitHub remote** | The pipeline reads issues and opens PRs against `origin`. | `gh repo view` |
| **A SvelteKit project** | `b2-build-feature` is SvelteKit-specific (Remote Functions, Svelte 5, Drizzle, shadcn-svelte). | — |
| **Node + a dev server** | The worktree runs `vite` so screens can be verified. | `npm run dev` works |
| **Google Chrome + the claude-in-chrome extension** | Visual screen review drives your **real** Chrome and reuses your logged-in session. | Extension connected |

> If you only want issue → draft PR and you do not need visual review, Chrome is optional — screens are skipped with a note when the dev server or browser is unavailable.

---

## 4. Installation, step by step

1. **Add the marketplace.** Point Claude Code at this repository (a URL or a local path both work):

   ```bash
   claude plugin marketplace add <url-or-path-to-this-repo>
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

That is it — there is no build step. The plugin auto-discovers its hooks from `hooks/hooks.json` and its skills from `skills/`.

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
| **b0-conversation-to-issues** | Genesis step (before triage). Turns the conversation (or a plan/PRD via `--from`) into vertically-sliced GitHub issues with dependencies and an epic, ready for `b10-ship --epic`. Verifies the real intent with a human gate before creating anything. |
| **b10-ship** | Top-level orchestrator. `<issue>` for one issue, or `--epic=<N>` to drain an epic's sub-issue graph. Chains triage → build → review → close with the human gates. |
| **b7-issue-to-pr** | Single-issue orchestrator: triage → worktree → build → screen review → commit → **draft PR** → auto-review. Stops at the draft PR (does not merge). |
| **b8-swarm** | Resolves a **cluster of related issues** in **one** combined PR (refactors, multi-step migrations, "Phase X.Y" series). One worktree, one branch, one PR. |
| **b1-triage-issue** | Evaluates and labels a GitHub issue (ready / needs-info / blocked / duplicate + simple / medium / complex) and emits a `TRIAGE_RESULT`. |
| **b1-add-worktree** | Creates an isolated worktree (`setup-worktree.sh`) and gates on a clean tree (`assert-clean.sh`). Installs a per-worktree pre-commit budget hook. |
| **b2-build-feature** | The actual SvelteKit implementation: Remote Functions, Svelte 5 runes, Drizzle, shadcn-svelte, with in-browser verification. |
| **b3-git-commit** | Conventional commits with intelligent staging; enforces a clean-tree gate. |
| **b3-security** | Reference for the `verb:noun` permission model and securing Remote Functions. |
| **b4-pull-request** | Creates the PR from the project template. |
| **b6-pr-review** | Reviews a PR across five areas and writes a durable verdict marker (`<!-- b6:verdict=... -->`). |
| **b7-screen-review** | Visual verification of one screen in your real Chrome against the triage's visual acceptance criteria. Invoked in parallel, one sub-agent per screen. |
| **b9-close** | Canonical close: merges the PR, closes the issue, and cleans the worktree — behind a human approval gate. |

---

## 7. The pipeline, step by step

This is exactly what happens when you run `/b-pipeline:b10-ship <issue>`.

### Step 0 — Preflight + lock

The orchestrator runs safety checks before anything else and acquires a lock so two runs cannot collide:

- Kill switch present? → refuse.
- `gh` authenticated? → required.
- Main working tree dirty? → stop (a build would abort halfway anyway).
- Too many open bot PRs (backpressure)? → offer to drain them first.

### Step 1 — Reconcile (idempotency)

It reads the issue's current state from GitHub (labels, PR, review verdict) and **jumps to the right phase**. A fresh issue starts at triage; an issue that already has an approved PR jumps straight to close. This is what makes re-running safe.

### Step 2 — Triage (conditional gate)

It calls `b1-triage-issue`:

- **ready + simple/medium** → proceed to build.
- **ready + complex** → **human gate.** It asks whether to force the autonomous build, build interactively, or skip. Complex work is not built unattended by default.
- **needs-info / blocked / duplicate** → the questions/reasons are posted on the issue; it notifies you and stops. When the reporter replies, the next run detects the new comment and re-triages automatically.

### Step 3 — Build (this is `b7-issue-to-pr`'s five mandatory steps)

Inside the build phase, `b7-issue-to-pr` runs five non-skippable steps:

1. **Create the worktree** (`b1-add-worktree`). Branch `feat/<issue>-<slug>` or `fix/<issue>-<slug>`. The main repo is never edited.
2. **Post a sticky status comment** on the issue (marker `<!-- b7:status -->`) so the reporter knows the bot picked it up.
3. **Commit** the work via `b3-git-commit` (conventional commits, grouped by theme).
4. **Open a draft PR** via `b4-pull-request` with `Closes #<issue>`, release notes, technical changes, and screenshots; sync the issue labels (`ready`/`auto-pr` → `in-progress` → `in-review`).
5. **Run `b6-pr-review`** on the fresh PR and attach the verdict. High-severity findings cause it to re-iterate (within budget) or ask for a human.

In between steps 2 and 3 the feature is built screen by screen: the worktree's dev server is started on its own port and each screen is verified in your real Chrome via `b7-screen-review` (one parallel sub-agent per screen).

### Step 4 — Verify

The orchestrator confirms the worktree is clean (committing anything left over) and reads the `b6` verdict from the PR:

- **blockers = 0** → proceed to close.
- **blockers > 0** → label the issue `needs-human-review`, summarize the blockers, notify, and stop.

### Step 5 — Close (human gate, always)

It calls `b9-close`, which **always** requires human approval — either the asynchronous `merge-approved` label or an in-session confirmation. On approval it merges the PR, closes the issue, and removes the worktree. If you are away and no label is set, it leaves the PR `awaiting-approval` and the next run resumes here.

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

There are exactly three points where a person must decide:

1. **Complex issues** are not built unattended. Triage flags `complex`; you choose force / interactive / skip.
2. **No PR ever merges** without (a) a green `b6` review (0 blockers) **and** (b) explicit human approval — the `merge-approved` label or an in-session yes.
3. **An epic's closing slice** requires an epic review and the `epic-approved` label before it merges.

---

## 10. Labels the pipeline uses

Triage reads and writes these labels; they are the pipeline's control plane. Create them in your repo so triage can apply them:

- **Readiness:** `ready`, `needs-info`, `blocked`, `duplicate`
- **Complexity:** `simple`, `medium`, `complex`
- **Progress:** `in-progress`, `in-review`
- **Bot / approval:** `auto-pr-bot`, `merge-approved`, `epic-approved`, `awaiting-approval`
- **Escalation:** `needs-human-review`, `pipeline-failed`

---

## 11. Artifacts it produces

- **Worktrees** — one per feature, on a `feat/…` or `fix/…` branch, removed on close.
- **`.b7/` state** inside the worktree — `state.json`, per-screen criteria (`.b7/screens/<Name>.md`), and visual review output (`.b7/review/<Name>.json` + PNGs).
- **Run reports** — a markdown report per run (kept under the plugin's state dir).
- **GitHub trail** — a sticky issue comment, a draft PR with release notes + technical changes, and a `b6` review comment with a durable verdict marker.

---

## 12. Safety features

- **Kill switch.** Create a `b7.STOP` file in the state dir and the pipeline refuses to start.
- **Single-flight lock.** Only one run at a time; stale locks expire after 6 hours, and a run never deletes another session's lock.
- **Budgets.** `--max-iterations` and `--budget-files` bound every run.
- **Backpressure.** With three or more open `auto-pr-bot` PRs, the pipeline offers to drain them before starting more.
- **Per-worktree pre-commit hook.** `b1-add-worktree` installs a budget hook scoped to the worktree (via `core.hooksPath --worktree`), chaining any existing hook (husky/lefthook) first. It blocks commits that blow the file budget or touch a secret denylist (`*.pem`, `*.key`, `secrets/`).
- **`git worktree add` guard (full disclosure of what runs on your machine).** Installing the plugin registers exactly one `PreToolUse` hook. It inspects every Bash command Claude is about to run and blocks a raw `git worktree add`, nudging you to `b1-add-worktree` (which sets up isolation correctly). The hook runs **locally only** — no network calls, no telemetry; it merely allows or blocks the command. Everything else in the plugin runs on demand, and GitHub access uses your own authenticated `gh` CLI.
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
