---
name: b3-git-commit
description: 'Execute git commit with conventional commit message analysis, intelligent staging, and message generation. Use when user asks to commit changes, create a git commit, or mentions "/commit". Supports: (1) Auto-detecting type and scope from changes, (2) Generating conventional commit messages from diff, (3) Interactive commit with optional type/scope/description overrides, (4) Intelligent file staging for logical grouping'
license: MIT
model: haiku
allowed-tools: Bash
---

# Git Commit with Conventional Commits

## Argumentos recibidos

```text
$ARGUMENTS
```

Opcional: numero de issue (ej `262` o `#262`). Si viene, agregar footer `Refs #N` al commit principal (o `Closes #N` si el usuario lo pide explicitamente — en el flujo b el `Closes` vive en el PR, no en el commit).

## Overview

Create standardized, semantic git commits using the Conventional Commits specification. Analyze the actual diff to determine appropriate type, scope, and message. Group pending changes in logical groups and commit them accordingly. Ensure best practices for commit messages and workflow are followed.

## Conventional Commit Format

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

## Commit Types

| Type       | Purpose                        |
| ---------- | ------------------------------ |
| `feat`     | New feature                    |
| `fix`      | Bug fix                        |
| `docs`     | Documentation only             |
| `style`    | Formatting/style (no logic)    |
| `refactor` | Code refactor (no feature/fix) |
| `perf`     | Performance improvement        |
| `test`     | Add/update tests               |
| `build`    | Build system/dependencies      |
| `ci`       | CI/config changes              |
| `chore`    | Maintenance/misc               |
| `revert`   | Revert commit                  |

## Breaking Changes

```
# Exclamation mark after type/scope
feat!: remove deprecated endpoint

# BREAKING CHANGE footer
feat: allow config to extend other configs

BREAKING CHANGE: `extends` key behavior changed
```

## Workflow

### 1. Analyze Diff

```bash
# If files are staged, use staged diff
git diff --staged

# If nothing staged, use working tree diff
git diff

# Also check status
git status --porcelain
```

### 2. Stage Files (if needed)

If nothing is staged or you want to group changes differently:

```bash
# Stage specific files
git add path/to/file1 path/to/file2

# Stage by pattern
git add *.test.*
git add src/components/*

# Interactive staging
git add -p
```

**Never commit secrets** (.env, credentials.json, private keys).

### 3. Generate Commit Message

Analyze the diff to determine:

- **Type**: What kind of change is this?
- **Scope**: What area/module is affected?
- **Description**: One-line summary of what changed (present tense, imperative mood, <72 chars)

### 4. Execute Commit

```bash
# Single line
git commit -m "<type>[scope]: <description>"

# Multi-line with body/footer
git commit -m "$(cat <<'EOF'
<type>[scope]: <description>

<optional body>

<optional footer>
EOF
)"
```

### 5. Verificacion final (OBLIGATORIO — no saltar)

El skill NUNCA termina con working tree sucio. Como ultimo paso, SIEMPRE correr:

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/skills/b-pipeline}"
bash "$PLUGIN_ROOT/skills/b1-add-worktree/scripts/assert-clean.sh" . --fix
```

Segun exit code:

- **0** → limpio, terminado. Mostrar el commit graph.
- **6** (codigo sin commitear) → los archivos listados bajo `--- CODIGO ---` pertenecen al cambio: stagearlos y commitearlos (en el commit logico que corresponda, o un commit extra `chore: incluir archivos restantes del cambio`). Re-correr la verificacion. Repetir hasta exit 0. PROHIBIDO terminar reportando exito con exit 6.
- **7** (artefactos que `--fix` no pudo excluir, ej. tracked/staged) → reportarlos al usuario con el listado; no descartarlos.
- **2** (invocacion invalida / el directorio no es repo git) → abortar reportando el error textual; no reintentar ni dar el commit por verificado.

Este gate existe porque cambios fuera del commit bloquean el worktree y detienen el flujo b completo (b9-close no puede cerrar). El productor de commits garantiza el tree limpio, no el consumidor.

## Best Practices
1. Run `git status` and `git diff` to review changes
2. Group changes into logical thematic commits (feat/fix/chore/docs)
3. Use conventional commit format with scope when applicable
4. Update CHANGELOG.md with user-facing changes
5. Show the commit graph for confirmation
- One logical change per commit
- Present tense: "add" not "added"
- Imperative mood: "fix bug" not "fixes bug"
- Reference issues: `Closes #123`, `Refs #456`
- Keep description under 72 characters

## Git Safety Protocol

- NEVER update git config
- NEVER run destructive commands (--force, hard reset) without explicit request
- NEVER skip hooks (--no-verify) unless user asks
- NEVER force push to main/master
- If commit fails due to hooks, fix and create NEW commit (don't amend)
