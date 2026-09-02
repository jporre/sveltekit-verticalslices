---
name: b1-add-worktree
description: 'Crea un git worktree aislado para una branch. Usar cuando el usuario pida un worktree o un workspace aislado para trabajar. Requiere el nombre del worktree como argumento.'
allowed-tools: Bash, AskUserQuestion
context: fork
---


# Create Git Worktree

> **Multi-harness:** en pi, los mecanismos de Claude Code se mapean a equivalentes (`AskUserQuestion`→pregunta en texto, `Agent(subagent_type=…)`→tool `subagent`, `Skill(bN-…)`→`read` del SKILL.md de ese skill, `Workflow`→tool `subagent` con `workflowScript`, `PushNotification`→omitir). Tabla completa: README § *Instalación alternativa: pi*. En Claude Code todo funciona como está escrito.

Create an isolated git worktree for feature development with symlinks to shared resources and a new terminal session.

## Argumentos recibidos

```text
$ARGUMENTS
```

> Skill `context: fork`: el subagente solo ve este `SKILL.md`. El placeholder `$ARGUMENTS` es la ÚNICA vía por la que el nombre del worktree tipeado llega al fork — el harness lo sustituye.

## Workflow

1. **Parse the name**: Extract the worktree name from the argument. Si `$ARGUMENTS` llega vacío o sin sustituir (el placeholder literal no cuenta como nombre), pedir el nombre al usuario.

   The name is used **as-is** for the branch (including any prefix like `feat/`, `fix/`, `chore/`). The folder under `worktrees/` uses only the segment after the final `/`, so the worktrees directory stays flat.

   Examples:
   - `feat/83-crm-fase-1-schema` → branch `feat/83-crm-fase-1-schema`, folder `worktrees/83-crm-fase-1-schema`
   - `fix/timezone-bug` → branch `fix/timezone-bug`, folder `worktrees/timezone-bug`
   - `mi-feature` → branch `mi-feature`, folder `worktrees/mi-feature`

2. **Confirm the branch name**: Show the user the exact branch name and folder path that will be created, and ask them to confirm (or suggest a prefix like `feat/`/`fix/` if the provided name has none and it seems appropriate).

3. **Ask the base branch**: Ask the user:

   > Create worktree from **current branch** (`<current-branch>`) or from **la rama default**? (la resuelve el script vía `bp_default_branch`)

   En los pasos siguientes, `<plugin-root>` es la raíz del plugin. Resolverla portable como `"${CLAUDE_PLUGIN_ROOT:-$(cat "$HOME/.claude/b-pipeline.root" 2>/dev/null || ls -d "$HOME"/.claude/plugins/marketplaces/b-pipeline* 2>/dev/null | head -1)}"` — funciona con el plugin instalado vía Claude Code marketplace o en el dev location. `<skill-dir>` es `<plugin-root>/skills/b1-add-worktree`.

4. **Ensure clean working tree**: Before running the script, run `bash <skill-dir>/scripts/assert-clean.sh . --fix` en el repo padre y actuar según exit code: `0` = continuar; `6` = código sin commitear — commitear primero (pedir confirmación al usuario); `7` = artefactos persistentes — revisarlos a mano con el usuario antes de seguir.

5. **Env-check runtimes + DB — MANDATORY**: Before creating the worktree, verify the environment blockers that make `setup-worktree.sh` fail late (missing `pnpm`/`node`, DB unreachable). Run only the runtime and DB checks of b7's `env-check` (via `B_ENV_CHECKS=bin,db`); it emits one `B_ENV name=<check> status=ok|fail|warn hint=<action>` line per check and exits `19` if any hard check fails. If it exits non-zero, stop and report — do not attempt the worktree.

   ```bash
   B_ENV_CHECKS=bin,db bash "<plugin-root>/skills/b7-issue-to-pr/scripts/guardrails.sh" env-check
   ```

6. **Run the script — MANDATORY**: You MUST invoke `setup-worktree.sh` exactly as shown. Do NOT call `git worktree add` directly, do NOT recreate the steps inline, do NOT skip ahead by symlinking `.env` or running `pnpm install` yourself. El script aprovisiona todo lo que el worktree necesita para quedar "ready for dev/test"; el detalle vive solo en el script.

   ```bash
   bash <skill-dir>/scripts/setup-worktree.sh "<worktree-name>"
   ```

   Sin `base-branch`, el script resuelve la rama default vía `bp_default_branch`. Si el usuario eligió otra base (ej. la rama actual), pasarla como segundo argumento: `bash <skill-dir>/scripts/setup-worktree.sh "<worktree-name>" "<base-branch>"`.

   Si el usuario pide no abrir una ventana de Terminal, agregar `--headless` al comando.

   If the script fails, report the failure to the user and stop. Do not work around it by running pieces manually — the failure usually points to real state that needs human attention (dirty tree, branch already exists, port detection failure).

7. **Report the result**: Relatar al usuario el resumen final que imprime el script: path, branch, puerto dev y la instrucción de correr `./dev.sh`.
