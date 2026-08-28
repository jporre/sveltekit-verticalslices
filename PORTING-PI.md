# Port a pi package (rama `pi-package`)

El mismo repo se distribuye como **plugin de Claude Code** (rama main, `.claude-plugin/`) y como
**package de pi** (esta rama). El código de skills y hooks es compartido; solo cambia el mecanismo
de carga.

## Instalación

```bash
pi install git:github.com/jporre/sveltekit-verticalslices@pi-package
# o, sin push, directo del checkout local:
pi install /Users/jporre/www/sveltekit-verticalslices
```

El manifest vive en `package.json` bajo la clave `pi`:

| Recurso pi | Directorio | Notas |
|------------|-----------|-------|
| `skills`   | `skills/` | 13 skills, sin cambios. |
| `subagents.agents` | `agents/` | Convertidos al formato de pi-subagents (frontmatter `tools` con nombres de tool de pi). |
| `extensions` | `extensions/b-pipeline.ts` | Port de los hooks (ver abajo). |

## Port de hooks (Claude Code → pi)

Los scripts de `hooks/` se reutilizan tal cual: reciben el JSON de hook de Claude por stdin
(`tool_name` + `tool_input`) y bloquean con `exit 2`. La extensión arma ese JSON y mapea:

| Hook de Claude Code | Evento de pi | Comportamiento |
|---------------------|--------------|----------------|
| `SessionStart` → `write-root-marker.sh` | `session_start` | Persiste la raíz del plugin en `~/.claude/b-pipeline.root` (los snippets de los SKILL.md resuelven `PLUGIN_ROOT` desde ahí). |
| `PreToolUse: Bash` → `block-git-worktree-add.sh` | `tool_call` (bash) | Bloquea `git worktree add` directo; obliga a usar `b1-add-worktree`. |
| `PreToolUse: Bash/Read` → `block-env-dump.sh` | `tool_call` (bash/read) | Bloquea dumps de `.env*` y `printenv`/`env`. |
| `PostToolUse: Bash` → `link-worktree-env.sh` | `tool_execution_end` (con flag del `tool_call` previo) | Symlink `.env*` al worktree tras `setup-worktree.sh`. Non-fatal, igual que en Claude. |

## Cambios en `agents/`

- `b7-impl.md`: `tools: Bash, Read, Edit, Write, Grep, Glob, Skill` → `bash, read, edit, write, grep, find, ls`
  + `skills: b2-build-feature` (pi-subagents no tiene tool `Skill`; el skill se entrega por contexto).
- `b7-screen-review.md`: `tools: Bash, Read, Write` → `bash, read, write`; `model: sonnet` se movió a la
  descripción (en pi el orquestador fija el modelo con el parámetro `model` del subagent call).

## Adaptación pendiente (skills)

Los skills se cargan sin cambios, pero algunos pasos de orquestación referencian mecanismos de
Claude Code que conviene ajustar cuando corran en pi:

- Llamadas tipo `Agent(...)` con `model: sonnet/opus` (b7/b8/b10) → equivalen a
  `subagent({ agent: "b7-impl" | "b7-screen-review", model: ... })` vía pi-subagents.
- `Skill(b2-build-feature)` dentro de agentes → en pi el skill se entrega por contexto (ya
  configurado en `agents/b7-impl.md` con `skills:`).
- `$CLAUDE_PLUGIN_ROOT` → en pi no existe; todos los snippets ya resuelven portable vía
  `$HOME/.claude/b-pipeline.root`, que la extensión de pi escribe en cada `session_start`.
