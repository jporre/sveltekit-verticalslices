---
name: b1-add-worktree
description: 'Create an isolated git worktree for feature development. Use when the user says /b-add-worktree, asks to create a worktree, wants to start working on a feature in isolation, or mentions needing a separate workspace for a branch. Requires the worktree name as an argument.'
allowed-tools: Bash, AskUserQuestion
context: fork
---

# Create Git Worktree

Create an isolated git worktree for feature development with symlinks to shared resources and a new terminal session.

## Usage

The user provides a worktree name as the argument: `/b-add-worktree my-feature`

## Argumentos recibidos

```text
$ARGUMENTS
```

> Skill `context: fork`: el subagente solo ve este `SKILL.md`. El placeholder `$ARGUMENTS` es la UNICA via por la que el nombre del worktree tipeado llega al fork — el harness lo sustituye. Si aparece vacio o sin sustituir, pedir el nombre.

## Workflow

1. **Parse the name**: Extract the worktree name from the argument. If no name was provided, ask the user for one.

   The name is used **as-is** for the branch (including any prefix like `feat/`, `fix/`, `chore/`). The folder under `worktrees/` uses only the segment after the final `/`, so the worktrees directory stays flat.

   Examples:
   - `feat/83-crm-fase-1-schema` → branch `feat/83-crm-fase-1-schema`, folder `worktrees/83-crm-fase-1-schema`
   - `fix/timezone-bug` → branch `fix/timezone-bug`, folder `worktrees/timezone-bug`
   - `mi-feature` → branch `mi-feature`, folder `worktrees/mi-feature`

2. **Confirm the branch name**: Show the user the exact branch name and folder path that will be created, and ask them to confirm (or suggest a prefix like `feat/`/`fix/` if the provided name has none and it seems appropriate).

3. **Ask the base branch**: Ask the user:

   > Create worktree from **current branch** (`<current-branch>`) or from **master**?

4. **Ensure clean working tree**: Before running the script, check `git status`. If there are uncommitted changes, commit them first (ask the user for confirmation). The script will abort if the tree is dirty, so this step prevents failures.

5. **Run the script — MANDATORY**: You MUST invoke `setup-worktree.sh` exactly as shown. Do NOT call `git worktree add` directly, do NOT recreate the steps inline, do NOT skip ahead by symlinking `.env` or running `pnpm install` yourself. The script handles worktree creation, symlinks every `.env*` file, picks a free dev port, generates a `dev.sh` shim, installs dependencies, and opens a terminal — all of those are required for the worktree to be "ready for dev/test".

   ```bash
   bash <skill-dir>/scripts/setup-worktree.sh "<worktree-name>" "<base-branch>"
   ```

   For automation (e.g. `b7-issue-to-pr`) that should not pop a Terminal window, append `--headless`:

   ```bash
   bash <skill-dir>/scripts/setup-worktree.sh "<worktree-name>" "<base-branch>" --headless
   ```

   In headless mode the final stdout line is machine-parseable: `WORKTREE_READY dir=<abs-path> branch=<name> port=<n>`. Consumers should grep that line rather than reparsing the human-friendly output.

   Where `<skill-dir>` is the directory containing this SKILL.md file. Resolve it portably as `"${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/skills/b-pipeline}/skills/b1-add-worktree"` — works whether the plugin is installed via the Claude Code marketplace or sitting in the dev location.

   If the script fails, report the failure to the user and stop. Do not work around it by running pieces manually — the failure usually points to real state that needs human attention (dirty tree, branch already exists, port detection failure).

6. **Report the result**: Tell the user the worktree is ready and a new terminal has been opened in it. Mention:
   - the path
   - the branch name
   - the **dev port** chosen by the script and that they should run `./dev.sh` (NOT `pnpm dev`, which is hardcoded to 6025 and would collide with the parent repo)

That's it. The bash script handles all the heavy lifting — do not reimplement its logic inline.
