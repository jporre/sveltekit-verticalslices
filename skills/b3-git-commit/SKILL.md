---
name: b3-git-commit
description: 'Commits en formato conventional commits: analiza el diff, agrupa cambios en commits logicos y garantiza working tree limpio al terminar. Usar cuando el usuario pida commitear, o cuando otro skill del pipeline b (b2/b7/b8/b9/b10) necesite crear commits.'
model: haiku
allowed-tools: Bash
---

# Git Commit with Conventional Commits

## Argumentos recibidos

```text
$ARGUMENTS
```

Opcional: numero de issue (ej `262` o `#262`). Si viene, agregar footer `Refs #N` al commit principal (o `Closes #N` si el usuario lo pide explicitamente — en el flujo b el `Closes` vive en el PR, no en el commit).

Tipos: feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert

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

If nothing is staged or you want to group changes differently, stage the files for each logical commit.

**Never commit secrets** (.env, credentials.json, private keys).

### 3. Generate Commit Message

Analyze the diff to determine:

- **Type**: What kind of change is this?
- **Scope**: What area/module is affected?
- **Description**: One-line summary of what changed (present tense, imperative mood, <72 chars)

Update CHANGELOG.md with user-facing changes (incluirlo en el commit que corresponda).

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

If commit fails due to hooks, fix and create NEW commit (don't amend).

### 5. Verificacion final (OBLIGATORIO — no saltar)

El skill NUNCA termina con working tree sucio. Como ultimo paso, SIEMPRE correr:

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cat "$HOME/.claude/b-pipeline.root" 2>/dev/null || ls -d "$HOME"/.claude/plugins/marketplaces/b-pipeline* 2>/dev/null | head -1)}"
bash "$PLUGIN_ROOT/skills/b1-add-worktree/scripts/assert-clean.sh" . --fix
```

Segun exit code:

- **0** → limpio, terminado. Mostrar el commit graph.
- **6** (codigo sin commitear) → los archivos listados bajo `--- CODIGO ---` pertenecen al cambio: stagearlos y commitearlos (en el commit logico que corresponda, o un commit extra `chore: incluir archivos restantes del cambio`). Re-correr la verificacion. Repetir hasta exit 0. PROHIBIDO terminar reportando exito con exit 6.
- **7** (artefactos que `--fix` no pudo excluir, ej. tracked/staged) → reportarlos al usuario con el listado; no descartarlos.
- **2** (invocacion invalida / el directorio no es repo git) → abortar reportando el error textual; no reintentar ni dar el commit por verificado.

Este gate existe porque cambios fuera del commit bloquean el worktree y detienen el flujo b completo (b9-close no puede cerrar). El productor de commits garantiza el tree limpio, no el consumidor.
