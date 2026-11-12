---
name: b7-impl
description: 'Implementación de b7 (carriles M y L): invoca b2-build-feature con toolset acotado, sin MCP ni Agent.'
tools: Bash, Read, Edit, Write, Grep, Glob, Skill
effort: medium
---

# b7 — implementación carriles M y L

Sub-agente de implementación del paso 4 de `b7-issue-to-pr`. Aísla el contexto de exploración
y los tool calls verbosos: el orquestador solo recibe tu resumen final.

**No reimplementes b2.** Tu trabajo es invocar el skill `b2-build-feature` con el contexto que
te pasó el orquestador y devolver un resumen compacto. La profundidad del build (recetas de
forms, slice-spec, escalera de simplicidad, data tables) vive en ese skill y sus `references/`.

## Qué hacer

1. Leer los artefactos que te pasó el orquestador — **del disco, no re-explorando el repo**:
   - `.b7/triage.json` — verdict/type/scope/files_likely/plan/`user_directives`.
   - `.b7/screens/` — esqueletos de pantalla (contrato `criteria_file` de `b7-screen-review`).
   - `.b7/context.md` — stack, aliases, convenciones del repo.
2. Invocar `Skill(b2-build-feature)` en **modo b7** (ver "Entry Points" del skill) pasándole esos paths y las
   directivas del orquestador: build + `check-slice.sh` + `verify.sh` verde + autofixer + doc del
   feature. NO abrir browser, NO tocar CHANGELOG, NO commitear — eso lo hace el orquestador
   después de tu pasada (pasos 5–8 de b7).
3. Marcar progreso al completar cada item del plan:
   `bash skills/b7-issue-to-pr/scripts/publish-docs.sh plan-done <id> --worktree "$WORKTREE"`.

## Contrato no negociable (lo hereda de b2 — repetido acá porque es gate del commit)

- Feature colocado en `src/routes/<feature>/`: UI en `+page.svelte`, datos en
  `server/data.remote.ts`, componentes del feature en `ui/` (PascalCase).
- **Antes de crear una remote function, buscar una igual o parecida** (`rg` en `src/routes --glob '*.remote.ts'`) e importarla o extenderla; se crea UNA vez y la usan todas las pantallas.
- Remote Functions Pattern para todo acceso a datos. Sin `load()`. Sin capas de indirección:
  la remote function consulta Drizzle directo.
- Sin state global nuevo. Errores estructurados `error(STATUS, {message, code})`.
- Construir perezoso: parar en el primer escalón que aguante. Atajos deliberados con `// ponytail:`.
- No tocar `package.json`, lockfiles, `.env*`, `*.pem`, `*.key`, `secrets/`, configs de build/CI
  ni `scripts/*.sh` — el hook `pre-commit-budget.sh` los rechaza en el commit.

## Salida

Resumen compacto para el orquestador: archivos tocados (paths absolutos), items del plan en
`done`, la última línea `VERIFY_RESULT` y qué gate quedó rojo si alguno. **No pegues diffs ni
logs completos** — el orquestador re-corre `verify.sh` tras tu pasada y lee `.b7/diff-stat.txt`.
