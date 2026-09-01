---
name: b6-pr-review
description: 'Review de un PR existente en GitHub: calidad, seguridad y anti-patrones SvelteKit; publica el veredicto (marker b6). Usar cuando pidan revisar un PR ("revisar PR", "review PR", número/URL de PR) o cuando b7/b8/b9/b10 encadenen la fase review (--auto, --light).'
context: fork
---

## User Input

```text
$ARGUMENTS
```

> Skill `context: fork`: el subagente solo ve el cuerpo de este `SKILL.md`. El placeholder `$ARGUMENTS` de arriba es la ÚNICA vía por la que el número/URL de PR y los flags (`--auto`, `--light`) llegan al fork — el harness lo sustituye. Si aparece vacío o sin sustituir, derivar el PR de la branch actual (Paso 0).
>
> **Por qué fork:** el diff completo, los archivos leídos enteros y el contexto de `pr-context.sh` son 10-40 KB que, sin fork, se quedan en el contexto de la sesión y se re-leen en cada request hasta el final. El fork los quema al terminar y devuelve solo el handoff del Paso 5. El contrato con los orquestadores no cambia: viaja por el marker `<!-- b6:verdict -->` en el PR y la línea `B6_VERDICT`, no por el contexto.

**Flag `--auto`** (para orquestadores como b7/b10 — modo desatendido): no ofrecer acciones interactivas en el Paso 5; publicar el reporte directo como comentario del PR (con el marker de veredicto) y terminar con la línea `B6_VERDICT`.

**Flag `--light`** (revisión acotada para PRs chicos): reduce la profundidad de lectura sin cambiar el reporte ni el veredicto. **Modo efectivo = flag O size-gate**: el `pr-context.sh` emite la sección `=== REVIEW_MODE ===` con `light` o `full` según su size-gate (los umbrales viven en el script); si se pasa `--light`, se fuerza `light` aunque el gate diga `full`. Las reglas por área del modo `light` están en los callouts `> Modo light:` de las Áreas 2–5.

El reporte, el marker `<!-- b6:verdict -->` y la línea `B6_VERDICT` son **idénticos en ambos modos** (los parsers de b7/b9/b10 no cambian); en `light` la cabecera del reporte agrega `modo: light`.


# SvelteKit PR Review

> **Multi-harness (Claude Code / pi).** Los mecanismos del harness se mapean así: `AskUserQuestion` → en pi, pregunta en texto y espera la respuesta. `Agent(subagent_type=…)`/`Agent call` → en pi, tool `subagent` con `agent: "<nombre>"` y `model` opcional (este paquete define los agentes `b7-impl`, `b7-impl-s`, `b7-screen-review`). `Skill(bN-…)`/`Skill b-pipeline:bN-…` → en pi, carga el `SKILL.md` de ese skill con `read` y síguelo. `Workflow` → en pi, tool `subagent` con `workflowScript` (mismas primitivas `runs.run`/`runs.all`). `PushNotification` → en pi, omítelo y reporta el hito en tu respuesta. `CLAUDE_PLUGIN_ROOT` existe en ambos (pi la exporta su extensión de compatibilidad). En Claude Code, todo funciona como está escrito.

Revisa un pull request existente en GitHub con foco en calidad, seguridad, y patrones correctos de SvelteKit/Svelte 5.

**Regla crítica**: Ejecuta herramientas PRIMERO, analiza DESPUÉS. Cada paso empieza con un tool call.

## Paso 0: Identificar el PR

Determina el número del PR desde los argumentos del usuario. Si proporcionaron una URL, extrae el número. Si no proporcionaron número, busca el PR del branch actual:

```bash
gh pr view --json number --jq '.number' 2>/dev/null
```

Si no hay PR, informa al usuario que necesitas un PR existente.

## Paso 1: Recolectar contexto (ejecutar INMEDIATAMENTE)

Ejecuta el script que recopila todo el contexto del PR:

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cat "$HOME/.claude/b-pipeline.root" 2>/dev/null || ls -d "$HOME"/.claude/plugins/marketplaces/b-pipeline* 2>/dev/null | head -1)}"
# Agregar `--light` como segundo arg si el usuario/orquestador pasó ese flag (fuerza modo light).
bash "$PLUGIN_ROOT/skills/b6-pr-review/scripts/pr-context.sh" <PR_NUMBER> [--light]
```

Lee el output completo. El script entrega:

- **REVIEW_MODE**: `light` o `full` (size-gate + flag). Determina la profundidad de las Áreas 2–5 (ver flag `--light` arriba).
- **PR_META**: título, descripción, autor, stats
- **PR_FILES**: archivos cambiados
- **PR_DIFF_STAT**: diffstat per-archivo (solo en modo `full`)
- **PR_DIFF**: el diff completo
- **PR_COMMITS**: historial de commits
- **PR_CHECKS**: estado de los checks de CI (`gh pr checks`). Alimenta el punto 6 del Área 1.
- **CLASSIFY_FILES**: archivos clasificados por tipo (LOAD_SERVER, REMOTE_FUNCTION, API_ENDPOINT, SVELTE_COMPONENT, etc.)
- **FIX_REGRESSION_GATE**: `FIX_WITHOUT_TEST=true|false` — true cuando el PR es `fix/*` y el diff no toca ningún archivo `.(test|spec).` (gate de regresión; ver Área 2)
- **SCREEN_EVIDENCE**: `UI_TOUCHED=true|false` + `BOT_PR=true|false` + `EVIDENCE=screenshots|skipped|none` (con skip la línea trae `EVIDENCE=skipped reason=<r>`; reason ausente = marker viejo) — gate de evidencia visual para PRs de bot que tocan UI (ver Área 2)
- **CHANGED_SYMBOLS**: símbolos exportados del diff (líneas `NEW:` / `MODIFIED:` / `REMOVED:`, best-effort) + línea `CODEGRAPH: ok|absent` (probe informativo). Alimenta el punto 6 del Área 2 y el paso 2 del Área 5.

## Paso 2: Leer CLAUDE.md del proyecto

Lee el CLAUDE.md del proyecto para entender las convenciones específicas:

```bash
cat CLAUDE.md
```

Esto te da la arquitectura feature-first, convenciones de código, y patrones esperados.

## Paso 3: Revisar en 5 áreas

Analiza el diff y los archivos cambiados en las cinco áreas de revisión. Para cada área, indica hallazgos con severidad:

- **BLOCKER**: Debe corregirse antes de merge. Problemas de seguridad, bugs claros, violaciones de arquitectura graves.
- **WARNING**: Debería corregirse. Malas prácticas, anti-patrones, deuda técnica significativa.
- **SUGGESTION**: Mejora opcional. Estilo, simplificación, oportunidades de refactor.
- **OK**: El área está bien. Confirma brevemente por qué.

**Formato de finding — OBLIGATORIO (una línea, al principio de línea):** cada
BLOCKER, WARNING y SUGGESTION se escribe como una línea que arranca con `- **SEVERIDAD**:`

```
- **BLOCKER**: <archivo:linea> <descripcion en una linea>
- **WARNING**: <archivo:linea> <descripcion en una linea>
- **SUGGESTION**: <archivo:linea> <descripcion en una linea>
```

`verdict.sh` **computa el veredicto contando estas líneas** (`grep -cE '^- \*\*BLOCKER\*\*:'`),
no interpreta prosa. Por eso: un hallazgo por línea, sin la severidad suelta en
medio de un párrafo, y la tabla resumen usa celdas (`| Código | BLOCKER |`) que NO
empiezan con `- **` — así no se doble-cuentan. El veredicto NO es juicio libre del
modelo: sale de la regla `blockers>0 -> request-changes; warnings>0 -> approve-with-changes; sino approve`.

---

### Área 1: Calidad del PR (redacción y comprensibilidad)

**PRs de bot (`BOT_PR=true`): solo 3 checks mecánicos** — el body lo genera `publish-docs.sh` por plantilla determinística; revisar la redacción de tu propia plantilla en cada PR es ceremonia. (1) `Closes #N` presente, (2) body no vacío ni placeholder (BLOCKER si lo es), (3) checks de CI (punto 6 de abajo). Sin findings de redacción/scope/commits — el scope-growth ya lo expone IMPACT_DRIFT de b7 y los commits los formatea b3.

**PRs humanos:** evalúa el PR como documento, no el código:

1. **Título**: ¿Es claro, conciso, y describe el cambio? ¿Sigue algún patrón (conventional commits, etc)?
2. **Descripción/Body**: ¿Explica el "por qué" del cambio, no solo el "qué"? ¿Tiene contexto suficiente para que un reviewer entienda sin leer todo el diff?
3. **Referencia a issue**: ¿Menciona el issue relacionado (#N)?
4. **Scope**: ¿El PR tiene un scope razonable? (no mezcla múltiples features o fixes inconexos)
5. **Commits**: ¿Los mensajes de commit son informativos? ¿Cada commit es atómico?
6. **Checks de CI** (sección `PR_CHECKS`): checks en fail son WARNING (BLOCKER si el fallo viene claramente del cambio del PR).

Si el body está vacío o es un placeholder, es un BLOCKER.

---

### Área 2: Calidad del código

Lee los archivos cambiados con atención. Para archivos `.svelte` y `.ts` relevantes, lee el archivo completo (no solo el diff) para entender el contexto.

> **Modo `light`:** revisar solo los hunks del diff; NO leer los archivos completos.

**Paso mecánico primero (antes del juicio LLM):** correr `check-slice.sh` sobre la rama del PR.
Valida la conformidad estructural del slice-spec que no requiere criterio (feature nuevo
bajo `src/lib/features/`, `*.remote.ts` fuera de `server/`, `*.remote.ts` bajo `src/lib/server/`, slice
nuevo sin `docs/readme.md`):

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cat "$HOME/.claude/b-pipeline.root" 2>/dev/null || ls -d "$HOME"/.claude/plugins/marketplaces/b-pipeline* 2>/dev/null | head -1)}"
bash "$PLUGIN_ROOT/skills/b2-build-feature/scripts/check-slice.sh" "$(gh pr view "$PR" --json baseRefName -q .baseRefName)"
# → SLICE_CHECK ok | SLICE_CHECK violations=<n>
```

Cada `VIOLATION` es un finding de arquitectura (BLOCKER/WARNING según el punto 2 de abajo).
El juicio LLM cubre lo que el script no ve (duplicación, indirección, código muerto).

**Gate de regresión (mecánico, del contexto):** si `FIX_REGRESSION_GATE` trae
`FIX_WITHOUT_TEST=true`, el PR es un `fix/*` que no toca ningún test. Emitir un
WARNING pidiendo el test de regresión (el que falla sin el fix y pasa con el) o una
justificación explícita de por qué no aplica:

```
- **WARNING**: <PR> fix sin test de regresión — agregar un test que falle sin el fix, o justificar por qué no aplica
```

Con `FIX_WITHOUT_TEST=false` (o PR no-`fix/*`) no hay finding por este gate.

**Gate de evidencia visual (mecánico, del contexto):** la sección `SCREEN_EVIDENCE`
trae `UI_TOUCHED`, `BOT_PR` y `EVIDENCE`. El gate aplica SOLO con `BOT_PR=true` (label
`auto-pr-bot`) Y `UI_TOUCHED=true`. A PRs humanos (`BOT_PR=false`) el gate NO aplica;
con `UI_TOUCHED=false` tampoco hay finding.

Con el gate activo y `EVIDENCE=none`, emitir este BLOCKER:

```
- **BLOCKER**: <PR> PR de bot toca UI sin evidencia visual ni skip declarado — correr b7 paso 5 o declarar skip válido
```

Con el gate activo y `EVIDENCE=skipped`, emitir este WARNING (skip declarado no bloquea)
citando el reason de la línea (`EVIDENCE=skipped reason=<r>`); si la línea no trae reason
(marker viejo), omitir el paréntesis:

```
- **WARNING**: <PR> screen-review omitido (<r>) — evaluar si el PR necesita evidencia visual antes del merge
```

Con `EVIDENCE=screenshots` no hay finding por este gate. El BLOCKER se resuelve dentro
del loop de b7: re-correr el paso 5 (screen-review + attach.sh) o postear el marker de
skip válido en el PR — nunca requiere intervención fuera del loop.

Evalúa:

1. **Simplicidad (lente de la escalera perezosa)**: ¿El código es directo o hay sobre-ingeniería? Lente — ¿pasaron de largo un peldaño que aguantaba? (¿una abstracción nueva donde la stdlib/SvelteKit/una dep ya instalada bastaba? ¿un service layer para CRUD simple? ¿una dependencia nueva para lo que son unas líneas?). Banderas concretas:
   - **Indirección innecesaria** (el antipatrón que más molesta): `query → función → abstracción Drizzle → otra función → query`. La remote function debe hacer la query Drizzle directo; cada salto intermedio sin lógica real es WARNING.
   - **Abstracción de una sola implementación**: interfaz/factory/wrapper con un solo uso → WARNING (borrarlo simplifica).
   - **Helpers que envuelven una llamada**: una función que solo reenvía a otra → inline.
   - **Marcador `// ponytail:`**: si un atajo está marcado así, es una simplificación **deliberada** — NO la reportes como ignorancia. Valida que el techo nombrado (ej. "client-side <1000 items", "lock global") sea razonable para el caso; solo es finding si el techo ya se superó (ej. ponytail dice "<1000 items" pero la query trae 50k). Un atajo sano marcado con ponytail es **OK**, no WARNING.
   - **Prosa de más**: comentarios que explican el QUÉ (el código ya lo dice), docstrings de párrafos, comentarios que referencian el task/PR. SUGGESTION para borrarlos. (Excepción: `// ponytail:` es la prosa válida — marca intención.)
2. **Arquitectura colocada por feature**: ¿Los archivos están en la estructura correcta? Spec canónica (regla 99%, tabla de excepciones `$lib`, tolerancia legacy, checklist): `../b2-build-feature/references/slice-spec.md`.
   - Todo el feature vive en su carpeta de ruta `src/routes/<feature>/` (página, remote, componentes, types)
   - `+page.svelte` ES la pantalla; componentes del feature en `ui/<Componente>.svelte` (PascalCase), nunca en `src/lib/features/`
   - Remote functions en `server/data.remote.ts` — ningún `*.remote.ts` fuera de `server/` (patrón viejo `<feature>.remote.ts` suelto en la raíz) ni bajo `src/lib/server/`
   - Server-only code en `.server.ts` colocados; solo lo realmente compartido vive en `$lib` (excepciones taxativas del spec: shadcn, css, db, transversales 3+ features)
   - **Tolerancia legacy**: editar un feature existente bajo `src/lib/features/` siguiendo su patrón interno NO es finding; crear un feature NUEVO ahí es BLOCKER.
   - Feature nuevo sin su `docs/readme.md` (doc del slice) → WARNING
3. **Convenciones**:
   - shadcn-svelte con namespace imports (`import * as Card from ...`)
   - Lucide con deep imports (`import Plus from '@lucide/svelte/icons/plus'`)
   - snake_case para remote functions, PascalCase para componentes
   - Drizzle: query builder tipado (`db.query.*` / `db.insert/update`); raw `sql` solo como último recurso
4. **Tipos**: ¿Los tipos son adecuados? ¿Hay `any` injustificados? ¿Los tipos de schema Drizzle se propagan (no re-declarar interfaces a mano)?
5. **Complejidad innecesaria**: ¿Hay código que podría ser más simple? Usar la tabla de CLAUDE.md y `../b2-build-feature/references/simplicity-ladder.md` como guía:
   - `goto()` donde bastaba un `href`
   - Filtrado server-side para pocos items (debería ser `$derived`)
   - `$state` + `$effect` donde bastaba `$derived`
6. **Callers de símbolos MODIFICADOS o ELIMINADOS** (así se escapó la regresión D5): si `CHANGED_SYMBOLS` trae líneas `MODIFIED:` o `REMOVED:`, trazar los call sites de cada símbolo FUERA del diff. Con `CODEGRAPH: ok` usar `codegraph_callers`; sino fallback `rg -n '\b<simbolo>\('` (codegraph nunca es obligatorio). Un call site fuera del diff que la firma nueva rompe (argumentos, retorno, contrato) es **BLOCKER** citando `archivo:linea`; para un símbolo `REMOVED:`, cualquier call site que sobrevive es **BLOCKER**. Sin líneas `MODIFIED:` ni `REMOVED:`, saltar este punto. Los hallazgos van dentro de '## 2. Calidad del Código' (sin secciones nuevas: cero impacto en parsers).

---

### Área 3: Seguridad

La tabla y la lista inline de esta área son la fuente canónica de las reglas; `references/security-checklist.md` trae ejemplos de código, el mapeo operación → permiso y el apéndice `requireAnyPermission`. Revisa CADA archivo según su clasificación (CLASSIFY_FILES) con esta tabla:

> **Modo `light`:** usar solo la tabla y la lista inline de esta área; NO leer `references/security-checklist.md`.

| Clasificación | Verificación requerida | Si falta |
| --- | --- | --- |
| LOAD_SERVER / LAYOUT_SERVER (`+page.server.ts`, `+layout.server.ts`) | check de `locals.user` antes de devolver datos protegidos (excepción: páginas explícitamente públicas) | BLOCKER |
| REMOTE_FUNCTION (`*.remote.ts`) | cada `query`/`form`/`command` llama `requireUser()` o `requirePermission('verbo:sustantivo')` como primera operación (formato `verbo:sustantivo`, sin roles hardcodeados) | BLOCKER |
| API_ENDPOINT (`+server.ts`) | `locals.user` o API key | BLOCKER |

**Para TODO el diff**: sin secrets/API keys/passwords hardcodeados (usar `$env/static/private` o `$env/dynamic/private`); errores con formato estructurado `{ message, code }` (no `throw new Error()` donde debería ser `error(status, { message, code })`); sin variables mutables a nivel de módulo en `.server.ts` (data leak entre usuarios).

---

### Área 4: Anti-patrones SvelteKit (React-isms)

La lista inline de abajo es la fuente canónica; `references/sveltekit-antipatterns.md` trae ejemplos de código de cada patrón (misma numeración). Busca estos patrones en el diff:

> **Modo `light`:** usar solo la lista inline de esta área; NO leer `references/sveltekit-antipatterns.md`.

**En archivos SVELTE_COMPONENT** (`.svelte`):

1. `goto()` para navegación simple (debería ser `href`)
2. `onMount` + `fetch` (debería ser remote function o load)
3. `$effect` para computar valores (debería ser `$derived`)
4. Spread para actualizar estado (`{...obj, key: val}` en vez de mutación directa)
5. `<slot />` o `<slot name="...">` (Svelte 4, debería ser snippets)
6. `on:click` / `on:change` (Svelte 4, debería ser `onclick` / `onchange`)
7. Named imports de shadcn (`import { Card }` en vez de `import * as Card`)
8. `Select.Value` (no existe)
9. Lucide imports incorrectos (`import { Plus } from 'lucide-svelte'`)
   9b. UI nativa: `confirm()`/`alert()`, spinner o texto de carga en vez de `Skeleton`, colores crudos (`text-red-500`, hex) en vez de tokens semánticos (`text-destructive`, `text-muted-foreground`) — ver `b2-build-feature/references/shadcn-ui.md`

**En archivos REMOTE_FUNCTION** (`.remote.ts`): 10. Archivo dentro de `src/lib/server/` o fuera de `server/` del feature (prohibido) 11. Query sin `refresh()` después de mutación en el componente que la usa

**En archivos TYPESCRIPT** (`.ts`): 12. `try/catch` envolviendo `error()` o `redirect()` de SvelteKit 13. Errores sin estructura (`error(400, 'string')` en vez de `error(400, { message, code })`)

**En archivos LOAD_SERVER**: 14. Filtrado server-side para datasets pequeños (<1000 items)

Cada anti-patrón encontrado es al menos WARNING (BLOCKER si causa bugs).

---

### Área 5: Funcionalidad duplicada

El PR puede introducir funciones que ya existen en el codebase con otro nombre o forma ligeramente distinta.

> **Modo `light`:** revisar solo funciones NUEVAS exportadas; saltar el barrido completo de zonas de alto riesgo.

**Zonas de alto riesgo** donde la duplicación es más frecuente:

- Utilidades y helpers (`src/lib/utils/`, `src/lib/helpers/`)
- Formateo de fechas, números, moneda
- Validación y sanitización de datos
- Funciones de logging o tracking
- Verificación de permisos y autenticación (variantes de `requireUser`, `requirePermission`)
- Construcción de queries Drizzle o transformación de datos
- Formateo de respuestas de API o errores

**Cómo detectar duplicados en el contexto del PR:**

1. Para cada función NUEVA que el PR introduce (líneas `NEW:` de `CHANGED_SYMBOLS`; las modificaciones se cubren en Área 2 punto 6), identifica su propósito semántico
2. Busca en el codebase existente funciones con propósito similar:
   - **Primario (si `CODEGRAPH: ok`)**: una query `codegraph_search` por símbolo NEW (nombre + sinónimos del propósito); el grafo trae candidatos en una sola pasada
   - **Fallback (`CODEGRAPH: absent`)**: recetas Grep:
     - Busca por nombre de función similar (ej: si el PR agrega `formatDate`, busca `format.*date`, `date.*format`, `toDateString`)
     - Busca por el patrón de operación (ej: si la función nueva hace `new Intl.DateTimeFormat`, busca otros usos de `Intl.DateTimeFormat`)
3. Si encuentras una función existente que hace lo mismo (o casi lo mismo), reporta ambas con sus ubicaciones

**Criterios de severidad:**

- **WARNING**: La función nueva duplica funcionalidad existente. El PR debería reusar la función existente o consolidar ambas.
- **SUGGESTION**: Las funciones son similares pero con diferencias justificables (distintos contextos, server vs client, etc). Sugerir considerar unificar.

**Ejemplo de reporte:**

```
WARNING: `formatDateShort()` en src/routes/reportes/reportes-utils.ts duplica
`formatFecha()` en src/lib/utils/dates.ts. Ambas formatean una fecha como "DD/MM/YYYY"
usando Intl.DateTimeFormat. Reusar la existente.
```

Si el skill `finding-duplicate-functions` está disponible, puede invocarse para un análisis más profundo de las zonas de alto riesgo del proyecto.

## Paso 4: Generar el reporte

Presenta el reporte con este formato exacto:

```markdown
# PR Review: #<NUMBER> — <TITLE>

**Autor**: <author> | **Branch**: <head> → <base> | **Archivos**: <N> | **+<additions> / -<deletions>**<!-- si REVIEW_MODE=light, agregar: --> | **modo: light**

---

## 1. Calidad del PR

<hallazgos con severidad>

## 2. Calidad del Código

<hallazgos con severidad>

## 3. Seguridad

<hallazgos con severidad>

## 4. Anti-patrones SvelteKit

<hallazgos con severidad>

## 5. Funcionalidad Duplicada

<hallazgos con severidad>

---

## Resumen

| Área          | Resultado               |
| ------------- | ----------------------- |
| Calidad PR    | <BLOCKER/WARNING/OK>    |
| Código        | <BLOCKER/WARNING/OK>    |
| Seguridad     | <BLOCKER/WARNING/OK>    |
| Anti-patrones | <BLOCKER/WARNING/OK>    |
| Duplicación   | <WARNING/SUGGESTION/OK> |

**Veredicto**: <APROBAR / APROBAR CON CAMBIOS / SOLICITAR CAMBIOS>

<si hay blockers, listar los cambios requeridos>
<si hay warnings, listar las mejoras recomendadas>

<!-- b6:verdict=approve|approve-with-changes|request-changes blockers=N warnings=M -->
```

(Con líneas `- **HUMAN**:` en el reporte, el marker lleva además el token ` human=required` — lo anexa `verdict.sh stamp`, nunca a mano.)

El marker HTML de la última línea es el **canal durable del veredicto**: queda en el comentario del PR en GitHub, sobrevive crashes de sesión, y los orquestadores (b9-close, b10-ship, b7) lo re-leen con `verdict.sh read <pr>` (lector único; cubre comentarios y reviews). Incluirlo SIEMPRE al publicar el reporte en GitHub.

**Condición humana explícita (`- **HUMAN**:`).** Cuando el review concluye que algo solo se valida manualmente (flujo que el review no pudo ejercitar: pagos reales, hardware, migración destructiva, "el detalle debe recorrerse a mano"), NO dejarlo solo en prosa — emitir una línea contable:

```
- **HUMAN**: <qué recorrer manualmente y por qué el review no pudo validarlo>
```

No altera el verdict (no es blocker ni warning), pero `verdict.sh stamp` la detecta y anexa ` human=required` al marker; el canal auto-merge de b9 (condición 4) lo trata como veto — el PR cae a los canales humanos, donde la aprobación del humano ES la validación pedida. Prosa sin la línea contable = invisible para el pipeline (la causa del caso Snuuper#219, issue #50).

**No escribir el marker a mano.** Escribir el cuerpo del reporte con findings de una
línea, guardarlo en `/tmp/pr-review-<repo>-<PR>.md` (repo = nombre del directorio del
repo, PR = número; así corridas concurrentes no se pisan), y dejar que `verdict.sh`
compute y estampe el marker desde los counts:

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cat "$HOME/.claude/b-pipeline.root" 2>/dev/null || ls -d "$HOME"/.claude/plugins/marketplaces/b-pipeline* 2>/dev/null | head -1)}"
VERDICT="$PLUGIN_ROOT/skills/b6-pr-review/scripts/verdict.sh"
# 1) estampar el marker computado
bash "$VERDICT" stamp /tmp/pr-review-<repo>-<PR>.md      # imprime B6_VERDICT ... y anexa el marker
# 2) verificar coherencia marker<->counts<->regla (exit 4 = mismatch; corregir el reporte, no el marker)
bash "$VERDICT" check /tmp/pr-review-<repo>-<PR>.md
```

`stamp` emite la línea machine-readable `B6_VERDICT verdict=... blockers=N warnings=M`; terminar el output de terminal con ella (agregando `pr=<numero>`).

## Paso 5: Publicar / ofrecer acciones

**Con `--auto` (desatendido):** publicar directo — el archivo ya viene estampado y
verificado del Paso 4:

```bash
gh pr comment <N> --body-file /tmp/pr-review-<repo>-<PR>.md
```

Ningún otro paso escribe `/tmp/pr-review-<repo>-<PR>.md`: este skill es el único productor, y el nombre lleva repo+PR para que sesiones o repos concurrentes no se pisen el reporte.

> IMPORTANTE: usar `gh pr comment`, NO `gh pr review --comment` — un review COMMENTED aparece en `--json reviews` y NO en `--json comments`, y los parsers del pipeline (b9-close PASO 2, b10 `b6_marker`) leen ambos pero el canal canónico es el comentario. Además `--approve`/`--request-changes` NO funcionan sobre PRs propios (GitHub bloquea self-review) y los PRs del flujo b se crean con el token del usuario. El veredicto viaja en el marker `<!-- b6:verdict=... -->`, no en el review state de GitHub.

**Modo interactivo:** `AskUserQuestion` con dos opciones — publicar el reporte en el PR (`gh pr comment <N> --body-file /tmp/pr-review-<repo>-<PR>.md`, incluye el marker) o dejarlo solo local. Resuelta esa, terminar.

**Handoff obligatorio al cerrar (ambos modos).** Este skill corre en fork: su contexto muere acá, así que el retorno tiene que bastarse solo. Devolver, y nada más que esto:

```
B6_VERDICT ...            (la línea del Paso 4, verbatim)
reporte: /tmp/pr-review-<repo>-<PR>.md
blockers: <n> · warnings: <n>   + una línea por blocker: <archivo>:<línea> — <qué>
```

**NO pegar el reporte completo ni el diff en el retorno** — eso reintroduce en la sesión principal justo lo que el fork existe para aislar. Quien quiera profundizar lee el archivo del reporte, que ya tiene todo.

Los follow-ups NO van acá, son invocaciones nuevas desde la sesión principal (y arrancan con el contexto limpio, que es lo que se quiere para corregir): arreglar blockers → `b7-issue-to-pr` o edición directa sobre el worktree; mergear → `b9-close`.

## Notas

- Si el diff es muy largo (>3000 líneas), enfoca la revisión en archivos de alto riesgo: remote functions, server loads, endpoints, y componentes principales. Menciona que archivos fueron revisados superficialmente.
- Si encuentras un patrón que no está en las referencias pero es claramente problemático, repórtalo igual con una explicación.
