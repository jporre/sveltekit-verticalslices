---
name: b7-screen-review
description: 'Revisión visual de UNA pantalla del feature en construcción. Diseñado para ser invocado por b7-issue-to-pr vía Agent (sub-agente), una vez por pantalla y en paralelo. Abre la ruta en el browser via agent-browser / claude-in-chrome MCP, recorre los estados requeridos (golden/empty/error/loading), captura screenshots, evalúa contra los acceptance_criteria_visual del triage, y emite veredicto pass/warn/fail + script attach.sh que postea un comentario informativo en el PR con los nombres de los screenshots (GH REST no permite inline upload). Usa Sonnet (multimodal); no requiere Opus. Trigger: invocación explícita desde b7 o cuando el usuario pide "revisar visualmente la pantalla X" / "tomar screenshots de la ruta Y".'
allowed-tools: Bash, Read, Write, mcp__claude-in-chrome__navigate, mcp__claude-in-chrome__tabs_create_mcp, mcp__claude-in-chrome__tabs_close_mcp, mcp__claude-in-chrome__tabs_context_mcp, mcp__claude-in-chrome__read_page, mcp__claude-in-chrome__find, mcp__claude-in-chrome__form_input, mcp__claude-in-chrome__javascript_tool, mcp__claude-in-chrome__read_console_messages
context: fork
model: sonnet
effort: medium
---

# b7-screen-review — revisión visual de una pantalla

Skill **single-screen, single-call**. La paralelización se hace afuera (b7 lanza un Agent por pantalla en el mismo turno). Acá adentro: una pantalla, una sesión de browser, N capturas, un veredicto.

> En este proyecto "tarea" = issue de GitHub. Este skill no consume issues directo; recibe los criterios ya extraídos por el triage (`.b7/screens/<Name>.md`).

## Argumentos recibidos

```text
$ARGUMENTS
```

> Skill `context: fork`: el subagente solo ve este `SKILL.md`. Si se invoca via `Skill` con args, `$ARGUMENTS` es la UNICA via por la que llegan al fork. Cuando lo invoca b7 via la herramienta `Agent`, los params van en el prompt del Agent (tabla abajo). Parsear ambos: leer `$ARGUMENTS` primero; si esta vacio, usar lo del prompt del Agent.

## Argumentos esperados (en el prompt del Agent que lo invoca)

| Param | Ejemplo | Obligatorio |
|-------|---------|-------------|
| `screen` | `BandejaTareasPage` | sí |
| `route` | `/tareas` | sí |
| `port` | `6024` | sí (default proyecto) |
| `criteria_file` | `.b7/screens/BandejaTareasPage.md` | sí |
| `out_dir` | `.b7/review` | sí |
| `states` | `golden,empty,error` | no (default `golden`) |
| `worktree` | `/Users/x/worktrees/6-foo` | no — si viene, el pre-flight gatea con `verify-port` (server debe servir ESE worktree, no master); si falta, cae a `curl` (modo standalone) |
| `auth_cookie` | `auth-session=QZHi...` | no — si viene, se inyecta via `document.cookie` para pasar el muro OAuth sin login manual (la genera b7 con `mint-dev-session.sh`); si falta, se reusa la sesión del Chrome real |

## Output (contrato con b7)

Crear en `<out_dir>/`:

- `<Name>.json`:
  ```json
  {
    "screen": "BandejaTareasPage",
    "route": "/tareas",
    "verdict": "pass|warn|fail",
    "criteria_results": [
      {"criterion": "Tabla muestra columnas X,Y,Z", "passed": true, "evidence": "screenshots/golden.png"},
      {"criterion": "Botón nuevo crea tarea", "passed": false, "evidence": "...", "note": "el botón no existe"}
    ],
    "findings": [
      {"severity": "error|warn|info", "message": "...", "screenshot": "..."}
    ],
    "screenshots": [
      {"label": "golden", "path": ".b7/review/BandejaTareasPage-golden.png"},
      {"label": "empty",  "path": ".b7/review/BandejaTareasPage-empty.png"}
    ],
    "console_errors": ["..."],
    "duration_ms": 12340
  }
  ```
- Las PNG correspondientes.
- `<Name>-attach.sh` — script ejecutable que postea un comentario informativo en el PR con los nombres de los PNG + puntero al run-report. NO sube las imágenes inline (GH REST no lo permite). Lo llama `b7` solo en modo `--wet`.

## Workflow

### 0. Cargar las MCP tools de claude-in-chrome

Las tools `mcp__claude-in-chrome__*` son **deferred**: en un fork no llegan cargadas y llamarlas directo falla. **Primero** cargarlas via `ToolSearch`:

```
ToolSearch("select:mcp__claude-in-chrome__tabs_context_mcp,mcp__claude-in-chrome__tabs_create_mcp,mcp__claude-in-chrome__tabs_close_mcp,mcp__claude-in-chrome__read_page,mcp__claude-in-chrome__find,mcp__claude-in-chrome__javascript_tool,mcp__claude-in-chrome__read_console_messages")
```

Si `ToolSearch` no devuelve las tools (extensión no conectada), abortar con `verdict: fail` y `findings: [{severity:error, message:"claude-in-chrome no disponible"}]`.

### 1. Pre-flight rápido

- El dev server del worktree lo levanta **b7** (paso 5.0) en `$PORT`. Verificar que responde y que sirve el checkout correcto:
  - **Si vino `worktree`** (invocado por b7): gatear con `verify-port` — confirma que el proceso que escucha en `<port>` tiene su cwd EN ese worktree, no en master. Esto previene el incidente de revisar pantallas contra master cuando un dev server viejo ocupa el puerto:
    ```bash
    PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/skills/b-pipeline}"
    bash "$PLUGIN_ROOT/skills/b7-issue-to-pr/scripts/guardrails.sh" verify-port "<port>" "<worktree>"
    ```
    Exit 40 (nadie escucha) o 41 (lo sirve otro cwd) → abortar con `verdict: fail` y `findings: [{severity:error, message:"verify-port fallo: :<port> no sirve el worktree (¿b7 paso 5.0 lo levantó? ¿dev server viejo en el puerto?)"}]`.
  - **Si NO vino `worktree`** (modo standalone): `curl -fsS http://localhost:<port>/ >/dev/null` (3 reintentos, 2s entre c/u). Si no responde, abortar con `verdict: fail` y `findings: [{severity:error, message:"dev server no responde en port X"}]`.
- Crear `<out_dir>` si no existe.
- Leer `<criteria_file>` (markdown plano del triage). Extraer los `acceptance_criteria_visual` como lista checkable.

### 2. Sesión browser

Hay dos modos según venga o no `auth_cookie`.

#### 2a. CON `auth_cookie` (sesión scriptada — preferido cuando b7 la pasa)

b7 usa `mint-dev-session.sh` para insertar una sesión válida en la DB del worktree y te pasa `auth_cookie=auth-session=<token>`. Inyectarla en el **mismo origen** del dev server y navegar en la MISMA tab:

1. `mcp__claude-in-chrome__tabs_context_mcp` primero (regla del MCP server).
2. `tabs_create_mcp` con `http://localhost:<port>/login` (aterrizar en una ruta del **mismo origen** — `document.cookie` es host-scoped, hay que estar en el host antes de setearla).
3. Inyectar la cookie via `javascript_tool` en esa tab:
   ```js
   // auth_cookie ya viene como "auth-session=<token>"
   document.cookie = "<auth_cookie>; path=/; SameSite=Lax";
   ```
4. **Re-navegar en la misma tab** a `http://localhost:<port><route>` (la cookie ya viaja en el request). No abrir tab nueva — perdería la cookie recién seteada.
5. `read_page` y confirmar que NO redirige a login. Si aún redirige, la cookie no prendió (host equivocado / sesión expirada): marcar `verdict: warn`, criterios `not-evaluated`, finding `{severity: info, message: "auth_cookie no prendió — revisar mint-dev-session.sh / verify"}`, y terminar.

#### 2b. SIN `auth_cookie` (reusar el Chrome real logueado)

`claude-in-chrome` opera el **Chrome real** del usuario, donde ya hay (o debería haber) una sesión válida contra el dev server. **No** se hace login automatizado.

1. `mcp__claude-in-chrome__tabs_context_mcp` primero (regla del MCP server).
2. `tabs_create_mcp` con `http://localhost:<port><route>`.
3. `read_page` y detectar **redirección a login** (URL contiene `/login`/`/auth`, o aparece el formulario OAuth). Si redirige a login:
   - NO intentar loguearse.
   - Marcar `verdict: warn`, todos los criterios `not-evaluated`, y un finding `{severity: info, message: "auth-required: abrí http://localhost:<port>/ en tu Chrome y logueate, luego re-corré el review"}`.
   - Saltar a generar el JSON y terminar (no hay capturas útiles tras un login wall).

Esperar a que el DOM esté estable: `read_page` y verificar que no esté el spinner principal. Si tras 8s sigue cargando → `warn`, capturar igual.

### 3. Recorrer estados

Vocabulario de states alineado con `states_required` del triage schema. Mapeo de valores legacy: `success` ≡ `golden`; `permission-denied` → si no es simulable, marcar `not-evaluated` (no fallido).

Para cada state en `states`:

- **golden** — la pantalla con datos felices. Captura screenshot.
- **empty** — vaciar datos: o navegar a `<route>?_b7=empty` (convención del proyecto si existe), o usar `javascript_tool` para limpiar localStorage/state, o evaluar el texto que aparece cuando no hay datos.
- **error** — forzar error: bloquear network via DevTools, o llamar al endpoint que dispare `error(500)`. Si no se puede simular, marcar el criterio como `not-evaluated` (no como fallido).
- **loading** — opcional, suele ser flaky.
- **invalid-submit** — solo pantallas con form de crear/editar. Click en el botón submit SIN llenar los requeridos (no ingresar datos válidos). Criterio auto: los mensajes/bordes de error deben quedar visibles. Anti-patrón: si el botón submit está `disabled` y por eso NO aparece ningún error → `passed: false`, citando la regla dura de la receta de forms (`disabled={submitting}`, NUNCA `disabled={!isFormValid}` — ver `b2-build-feature/references/forms-recipe.md`). Si la pantalla no tiene form, `not-evaluated`.

Para cada state:
1. Tomar screenshot via `javascript_tool`:
   ```js
   // Página completa
   await new Promise(r => setTimeout(r, 200));
   ```
   Después usar `agent-browser screenshot` desde Bash (CLI más confiable que MCP para PNG). Comando:
   ```bash
   agent-browser screenshot --output "<out_dir>/<Name>-<state>.png" --full-page
   ```
2. Leer `read_console_messages` con `pattern: "(error|warn|Uncaught)"` y guardar en `console_errors`.

### 4. Evaluar criterios

Para cada `criterion` del archivo: marcar `passed` true/false comparando contra lo observado en los screenshots y el `read_page`. **Ser literal**: si el criterio dice "muestra columnas A, B, C" y solo hay A y B, `passed: false`.

Reglas de veredicto:

- `fail`: ≥1 criterio crítico no cumplido **con sesión válida** O console_errors con severity `error`
- `warn`: criterios cumplidos pero con observaciones (rendimiento, accesibilidad, console warnings), **o** `auth-required` (login pendiente en Chrome → criterios `not-evaluated`)
- `pass`: todos los criterios verdes, sin findings críticos

`not-evaluated` NO es `fail`: una pantalla que no se pudo cargar por falta de login no significa que el feature esté roto. b7 lo trata como nota, no como bloqueante.

### 5. Generar attach.sh

Escribir `<out_dir>/<Name>-attach.sh`:

```bash
#!/usr/bin/env bash
# Postea un comentario informativo en el PR con los screenshots de <Name>.
# b7-issue-to-pr lo invoca solo en modo --wet, pasándole el PR number.
set -euo pipefail
PR="${1:-}"
[ -z "$PR" ] && { echo "usage: $0 <pr-number>"; exit 2; }
REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"

# NOTA: GH REST no permite subir imágenes inline en comentarios de PR. Este script
# NO sube los PNG: postea un comentario con los nombres de archivo + puntero al
# run-report (donde sí se ven embebidos en el HTML local). Para inline real haría
# falta subir a un host estático o usar `gh release upload` (iteración futura).
BODY="### 🖼️ Screenshots — ${SCREEN_NAME:-pantalla}

$(for png in "$(dirname "$0")"/<Name>-*.png; do
  echo "- \`$(basename "$png")\` — disponible en el run-report y en el worktree"
done)
"
gh pr comment "$PR" --body "$BODY"
```

(Limitación conocida: la API de GH no acepta upload directo de imágenes en comentarios via REST. Workaround real para una iteración futura: subir a un host estático o usar `gh release upload`. Por ahora dejamos el comentario informativo + ruta al run-report donde las imágenes sí se ven embebidas en HTML local.)

### 6. Limpieza

Cerrar la tab via `tabs_close_mcp`. NO cerrar otras tabs del usuario.

## Anti-patrones (importante)

- **No** disparar dialogs (alert/confirm/prompt) — bloquean al MCP server.
- **No** hacer login interactivo (OAuth). Con `auth_cookie` se inyecta la sesión scriptada (paso 2a); sin ella se reusa la sesión del Chrome real (paso 2b). Si la ruta redirige a login sin cookie → `warn` + criterios `not-evaluated` + nota para que el usuario se loguee y re-corra.
- **No** intentar resolver bugs encontrados — solo reportar. La iteración la maneja b7.
- **No** abrir 5 tabs en paralelo desde acá — la paralelización es por sub-agente, no por tab.
- **No** asumir que el dev server está corriendo — verificar siempre.

## Manejo de errores

- Si MCP browser falla 2-3 veces consecutivas en una acción, abortar con `verdict: fail` y `findings: [{severity:error, message:"browser MCP no responde"}]`. No reintentar indefinidamente (lección de claude-in-chrome guidelines).
- Si la ruta da 404/401/403, capturar la página de error como evidencia y marcar `verdict: fail` con findings explicativos.
- Si una de las N capturas falla pero las otras OK, `verdict: warn` con la falla en findings.

## Performance / tokens

- Usar `read_page` máximo 2 veces por estado (después de cargar y después de interactuar). Más es ruido.
- Los `read_console_messages` con `pattern` filtran del lado del MCP — usar siempre.
- Screenshots se guardan a disco; **no** intentar leerlos como texto via Read (binario, quemaría tokens).
- El veredicto + criteria_results se escriben en JSON, nunca como prosa larga.

## Por qué este skill existe (separado de b7)

- **Toolset distinto**: browser MCP no es necesario en el resto del pipeline.
- **Aislamiento de contexto**: cada Agent tiene su propio contexto; los read_page verbosos no contaminan al orquestador.
- **Paralelización real**: 3 pantallas = 3 Agents en el mismo turno = revisión visual en wall-clock de una.
- **Modelo más barato**: Sonnet alcanza para juicio visual; Opus sería waste.
