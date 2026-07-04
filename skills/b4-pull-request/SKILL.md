---
name: b4-pull-request
description: 'Crea un GitHub PR desde la branch actual con el template del repo. Usar cuando pidan abrir un PR; es el paso PR que invocan b7-issue-to-pr y b8-swarm.'
context: fork
model: haiku
---

# Create Pull Request

## Argumentos recibidos

```text
$ARGUMENTS
```

> Skill `context: fork`: el subagente solo ve este `SKILL.md`. El placeholder `$ARGUMENTS` es la UNICA via por la que los argumentos tipeados (branch, flags como `--draft`, `--body-file`, `--issue=N`, `--label`) llegan al fork — el harness los sustituye. Si aparece vacio, derivar del estado de git actual.
>
> Corre headless: nunca preguntar al usuario. Derivar cada decision del estado git/GitHub, proceder con el default seguro y anotar cada decision en el resumen final.

Flags soportados:

- `--draft` — crear el PR en draft.
- `--body-file <path>` — usar ese archivo como body.
- `--issue=N` — el PR cierra el issue #N: el body DEBE incluir `Closes #N` real (nunca el placeholder `#XXXX`).
- `--label <name>` — agregar ese label al PR via `gh pr create --label`.

## Gather Context

### 1. Identify the current branch

```bash
git branch --show-current
```

### 2. Find the base branch (NUNCA asumir `main`)

```bash
BASE=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)
# Fallback si gh falla: git remote show origin | grep "HEAD branch"
```

**Usar `$BASE` en TODOS los comandos siguientes** — nunca hardcodear `main`. Si la branch actual ES `${BASE}`, abortar y reportarlo en el resumen final (headless: no crear PR desde el default branch).

### 3. Analyze commits and diff relevant to this PR

```bash
git log origin/${BASE}..HEAD --oneline --no-decorate
git diff origin/${BASE}..HEAD --stat
```

## Information Gathering

Derivar de commit messages, nombre de branch (e.g., `fix/issue-123`) y archivos cambiados:

1. **Related Issue Number**: Si vino `--issue=N` en los argumentos, usarlo directo. Si no, look for patterns like `#123`, `fixes #123`, or `closes #123` in commit messages. Si no se puede determinar, usar el placeholder `#XXXX` y dejarlo anotado en el resumen final.
2. **Description**: What problem does this solve? Why were these changes made?
3. **Type of Change**: Bug fix, new feature, breaking change, refactor, cosmetic, documentation, or workflow
4. **Test Procedure**: How was this tested? What could break?

## Push Changes

Ensure all commits are pushed:

```bash
git push origin HEAD
```

Si el remoto rechaza por divergencia:

```bash
git push origin HEAD --force-with-lease
```

## Create the Pull Request

**IMPORTANT**: Read and use the PR template at `.github/pull_request_template.md`. The PR body format must **strictly match** the template structure.

**Si el template NO existe en el repo** (o ya vino `--body-file`): usar estructura minima — `## Resumen`, `Closes #N`, `## Tipo de cambio`, `## Como se probo` — y anotarlo en el resumen final.

When filling out the template:

- Replace `#XXXX` with the actual issue number, or keep as `#XXXX` if no issue exists (for small fixes)
- Fill in all sections with relevant information gathered from commits and context
- Mark the appropriate "Type of Change" checkbox(es)
- Complete the "Pre-flight Checklist" items that apply

### Create PR with gh CLI

Si vino `--body-file`, usar ese archivo directo; si no, escribir el body a un archivo temporal unico (`mktemp`) y borrarlo despues de crear el PR.

```bash
gh pr create --title "PR_TITLE" --body-file "${BODY_FILE}" --base "${BASE}" --draft --label auto-pr-bot
```

Incluir `--draft` y `--label` solo si vinieron en los argumentos.

## Error Handling

1. **No commits ahead of base (`${BASE}`)**: abortar y reportarlo en el resumen final.
2. **Branch not pushed**: push the branch first: `git push -u origin HEAD`.
3. **PR already exists**: obtener la URL con `gh pr view`, no crear otro; reportar la URL existente y anotar la decision.
4. **Merge conflicts**: abortar y reportar el conflicto en el resumen final.

## Summary Checklist

Before finalizing, ensure:

- [ ] All commits are pushed
- [ ] Related issue number is identified, or placeholder is used
- [ ] PR description follows the template exactly (or minimal structure, noted)
- [ ] Appropriate type of change is selected
- [ ] PR URL reported como valor de retorno del fork, junto con placeholders y decisiones anotadas
