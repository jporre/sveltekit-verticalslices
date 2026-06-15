---
name: b4-pull-request
description: Create a GitHub pull request following project conventions. Use when the user asks to create a PR, submit changes for review, or open a pull request. Handles commit analysis, branch management, PR template usage, and PR creation using the gh CLI tool.
context: fork
agent: Explore
model: haiku
---

# Create Pull Request

## Argumentos recibidos

```text
$ARGUMENTS
```

> Skill `context: fork`: el subagente solo ve este `SKILL.md`. El placeholder `$ARGUMENTS` es la UNICA via por la que los argumentos tipeados (branch, flags como `--draft`, `--body-file`, `--issue=N`) llegan al fork — el harness los sustituye. Si aparece vacio, derivar del estado de git actual.

Flags soportados:

- `--draft` — crear el PR en draft.
- `--body-file <path>` — usar ese archivo como body.
- `--issue=N` — el PR cierra el issue #N: el body DEBE incluir `Closes #N` real (nunca el placeholder `#XXXX`) y se salta la pregunta de issue relacionado.

This skill guides you through creating a well-structured GitHub pull request that follows project conventions and best practices.

## Prerequisites Check

Before proceeding, verify the following:

### 1. Check if `gh` CLI is installed

```bash
gh --version
```

If not installed, inform the user:

> The GitHub CLI (`gh`) is required but not installed. Please install it:
>
> - macOS: `brew install gh`
> - Other: https://cli.github.com/

### 2. Check if authenticated with GitHub

```bash
gh auth status
```

If not authenticated, guide the user to run `gh auth login`.

### 3. Verify clean working directory

```bash
git status
```

If there are uncommitted changes, ask the user whether to:

- Commit them as part of this PR
- Stash them temporarily
- Discard them (with caution)

## Gather Context

### 1. Identify the current branch

```bash
git branch --show-current
```

Ensure you're not on `main` or `master`. If so, ask the user to create or switch to a feature branch.

### 2. Find the base branch (NUNCA asumir `main`)

```bash
BASE=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)
# Fallback si gh falla: git remote show origin | grep "HEAD branch"
```

Este repo usa `master`; otros usan `main`. **Usar `$BASE` en TODOS los comandos siguientes** — nunca hardcodear `main`.

### 3. Analyze recent commits relevant to this PR

```bash
git log origin/${BASE}..HEAD --oneline --no-decorate
```

Review these commits to understand:

- What changes are being introduced
- The scope of the PR (single feature/fix or multiple changes)
- Whether commits should be squashed or reorganized

### 4. Review the diff

```bash
git diff origin/${BASE}..HEAD --stat
```

This shows which files changed and helps identify the type of change.

## Information Gathering

Before creating the PR, you need the following information. Check if it can be inferred from:

- Commit messages
- Branch name (e.g., `fix/issue-123`, `feature/new-login`)
- Changed files and their content

Si falta informacion critica y no vino `--issue=N`: derivarla de commits/branch; si el issue no se puede determinar, usar el placeholder `#XXXX` y dejarlo anotado en el resumen final (este skill corre en fork no-interactivo — no puede preguntar al usuario).

### Required Information

1. **Related Issue Number**: Si vino `--issue=N` en los argumentos, usarlo directo (sin preguntar). Si no, look for patterns like `#123`, `fixes #123`, or `closes #123` in commit messages
2. **Description**: What problem does this solve? Why were these changes made?
3. **Type of Change**: Bug fix, new feature, breaking change, refactor, cosmetic, documentation, or workflow
4. **Test Procedure**: How was this tested? What could break?

## Git Best Practices

Before creating the PR, consider these best practices:

### Commit Hygiene

1. **Atomic commits**: Each commit should represent a single logical change
2. **Clear commit messages**: Follow conventional commit format when possible
3. **No merge commits**: Prefer rebasing over merging to keep history clean

### Branch Management

1. **Rebase on latest base** (if needed):

   ```bash
   git fetch origin
   git rebase origin/${BASE}
   ```

2. **Squash if appropriate**: If there are many small "WIP" commits, consider interactive rebase:
   ```bash
   git rebase -i origin/${BASE}
   ```
   Only suggest this if commits appear messy and the user is comfortable with rebasing.

### Push Changes

Ensure all commits are pushed:

```bash
git push origin HEAD
```

If the branch was rebased, you may need:

```bash
git push origin HEAD --force-with-lease
```

## Create the Pull Request

**IMPORTANT**: Read and use the PR template at `.github/pull_request_template.md`. The PR body format must **strictly match** the template structure. Do not deviate from the template format.

**Si el template NO existe en el repo** (o ya vino `--body-file`): usar estructura minima — `## Resumen`, `Closes #N`, `## Tipo de cambio`, `## Como se probo` — y anotarlo en el resumen final.

When filling out the template:

- Replace `#XXXX` with the actual issue number, or keep as `#XXXX` if no issue exists (for small fixes)
- Fill in all sections with relevant information gathered from commits and context
- Mark the appropriate "Type of Change" checkbox(es)
- Complete the "Pre-flight Checklist" items that apply

### Create PR with gh CLI

**Use a temporary file for the PR body** to avoid shell escaping issues, newline problems, and other command-line flakiness:

1. Write the PR body to a temporary file:

   ```
   /tmp/pr-body.md
   ```

2. Create the PR using the file:

   ```bash
   gh pr create --title "PR_TITLE" --body-file /tmp/pr-body.md --base "${BASE}"
   ```

3. Clean up the temporary file:
   ```bash
   rm /tmp/pr-body.md
   ```

For draft PRs:

```bash
gh pr create --title "PR_TITLE" --body-file /tmp/pr-body.md --base "${BASE}" --draft
```

**Why use a file?** Passing complex markdown with newlines, special characters, and checkboxes directly via `--body` is error-prone. The `--body-file` flag handles all content reliably.

## Post-Creation

After creating the PR:

1. **Display the PR URL** so the user can review it
2. **Remind about CI checks**: Tests and linting will run automatically
3. **Suggest next steps**:
   - Add reviewers if needed: `gh pr edit --add-reviewer USERNAME`
   - Add labels if needed: `gh pr edit --add-label "bug"`

## Error Handling

### Common Issues

1. **No commits ahead of base (`${BASE}`)**: The branch has no changes to submit relative to `${BASE}`
   - Ask if the user meant to work on a different branch

2. **Branch not pushed**: Remote doesn't have the branch
   - Push the branch first: `git push -u origin HEAD`

3. **PR already exists**: A PR for this branch already exists
   - Show the existing PR: `gh pr view`
   - Ask if they want to update it instead

4. **Merge conflicts**: Branch conflicts with base
   - Guide user through resolving conflicts or rebasing

## Summary Checklist

Before finalizing, ensure:

- [ ] `gh` CLI is installed and authenticated
- [ ] Working directory is clean
- [ ] All commits are pushed
- [ ] Branch is up-to-date with base branch
- [ ] Related issue number is identified, or placeholder is used
- [ ] PR description follows the template exactly
- [ ] Appropriate type of change is selected
- [ ] Pre-flight checklist items are addressed
