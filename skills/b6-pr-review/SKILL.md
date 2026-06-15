---
name: b6-pr-review
description: |
  Review an existing GitHub pull request with deep SvelteKit expertise. Use ALWAYS when the user asks to review a PR, says "review PR", "revisar PR", "revisa el PR", "PR review", "code review", mentions reviewing pull request code, or provides a PR number/URL for review. This skill reads the full diff, analyzes code quality, checks security patterns, and detects SvelteKit anti-patterns. It requires the PR to already exist on GitHub.
---

## User Input

```text
$ARGUMENTS
```

**Flag `--auto`** (para orquestadores como b7/b10 — modo desatendido): no ofrecer acciones interactivas en el Paso 5; publicar el reporte directo como comentario del PR (con el marker de veredicto) y terminar con la linea `B6_VERDICT`.

# SvelteKit PR Review

Revisa un pull request existente en GitHub con foco en calidad, seguridad, y patrones correctos de SvelteKit/Svelte 5.

**Regla critica**: Ejecuta herramientas PRIMERO, analiza DESPUES. Cada paso empieza con un tool call.

## Paso 0: Identificar el PR

Determina el numero del PR desde los argumentos del usuario. Si proporcionaron una URL, extrae el numero. Si no proporcionaron numero, busca el PR del branch actual:

```bash
gh pr view --json number --jq '.number' 2>/dev/null
```

Si no hay PR, informa al usuario que necesitas un PR existente.

## Paso 1: Recolectar contexto (ejecutar INMEDIATAMENTE)

Ejecuta el script que recopila todo el contexto del PR:

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/skills/b-pipeline}"
bash "$PLUGIN_ROOT/skills/b6-pr-review/scripts/pr-context.sh" <PR_NUMBER>
```

Lee el output completo. El script entrega:

- **PR_META**: titulo, descripcion, autor, stats
- **PR_FILES**: archivos cambiados
- **PR_DIFF**: el diff completo
- **PR_COMMITS**: historial de commits
- **CLASSIFY_FILES**: archivos clasificados por tipo (LOAD_SERVER, REMOTE_FUNCTION, API_ENDPOINT, SVELTE_COMPONENT, etc.)

## Paso 2: Leer CLAUDE.md del proyecto

Lee el CLAUDE.md del proyecto para entender las convenciones especificas:

```bash
cat CLAUDE.md
```

Esto te da la arquitectura feature-first, convenciones de codigo, y patrones esperados.

## Paso 3: Revisar en 5 areas

Analiza el diff y los archivos cambiados en las cinco areas de revision. Para cada area, indica hallazgos con severidad:

- **BLOCKER**: Debe corregirse antes de merge. Problemas de seguridad, bugs claros, violaciones de arquitectura graves.
- **WARNING**: Deberia corregirse. Malas practicas, anti-patrones, deuda tecnica significativa.
- **SUGGESTION**: Mejora opcional. Estilo, simplificacion, oportunidades de refactor.
- **OK**: El area esta bien. Confirma brevemente por que.

---

### Area 1: Calidad del PR (redaccion y comprensibilidad)

Evalua el PR como documento, no el codigo:

1. **Titulo**: Es claro, conciso, y describe el cambio? Sigue algun patron (conventional commits, etc)?
2. **Descripcion/Body**: Explica el "por que" del cambio, no solo el "que"? Tiene contexto suficiente para que un reviewer entienda sin leer todo el diff?
3. **Referencia a issue**: Menciona el issue relacionado (#N)?
4. **Scope**: El PR tiene un scope razonable? (no mezcla multiples features o fixes inconexos)
5. **Commits**: Los mensajes de commit son informativos? Cada commit es atomico?

Si el body esta vacio o es un placeholder, es un BLOCKER.

---

### Area 2: Calidad del codigo

Lee los archivos cambiados con atencion. Para archivos `.svelte` y `.ts` relevantes, lee el archivo completo (no solo el diff) para entender el contexto.

Evalua:

1. **Simplicidad**: El codigo es directo o hay sobre-ingenieria? Hay abstracciones prematuras, helpers innecesarios, o indirecciones que no se justifican?
2. **Arquitectura colocada por feature**: Los archivos estan en la estructura correcta?
   - Todo el feature vive en su carpeta de ruta `src/routes/<feature>/` (pagina, remote, componentes, types)
   - `+page.svelte` ES la pantalla; componentes como hermanos PascalCase, sin subcarpeta `ui/` ni `src/lib/features/`
   - Remote functions en `<feature>.remote.ts` (fuera de `src/lib/server/`), no el generico `data.remote.ts`
   - Server-only code en `.server.ts` colocados; solo lo realmente compartido vive en `$lib`
3. **Convenciones**:
   - shadcn-svelte con namespace imports (`import * as Card from ...`)
   - Lucide con deep imports (`import Plus from '@lucide/svelte/icons/plus'`)
   - snake_case para remote functions, PascalCase para componentes
   - Drizzle: query builder tipado (`db.query.*` / `db.insert/update`); raw `sql` solo como ultimo recurso
4. **Tipos**: Los tipos son adecuados? Hay `any` injustificados? Los tipos de schema Drizzle se propagan (no re-declarar interfaces a mano)?
5. **Complejidad innecesaria**: Hay codigo que podria ser mas simple? Usar la tabla de CLAUDE.md como guia:
   - `goto()` donde bastaba un `href`
   - Filtrado server-side para pocos items (deberia ser `$derived`)
   - `$state` + `$effect` donde bastaba `$derived`

---

### Area 3: Seguridad

Lee `references/security-checklist.md` para los patrones detallados. Revisa CADA archivo segun su clasificacion:

**Para archivos LOAD_SERVER y LAYOUT_SERVER** (`+page.server.ts`, `+layout.server.ts`):

- Tiene verificacion de `locals.user`?
- Si devuelve datos protegidos sin auth check, es BLOCKER
- Excepcion: paginas explicitamente publicas

**Para archivos REMOTE_FUNCTION** (`*.remote.ts`):

- Cada `query`, `form`, y `command` llama a `requireUser()` o `requirePermission('verbo:sustantivo')`?
- Si una remote function no tiene verificacion, es BLOCKER
- Los permisos usan el formato correcto `verbo:sustantivo`?

**Para archivos API_ENDPOINT** (`+server.ts`):

- Verifican `locals.user` o API key?
- Si no hay verificacion, es BLOCKER

**Para TODO el diff**:

- Hay secrets, API keys, o passwords hardcodeados?
- Se usa `$env/static/private` o `$env/dynamic/private` para secretos?
- Los errores usan el formato estructurado `{ message, code }`?
- No hay `throw new Error()` donde deberia ser `error(status, { message, code })`?
- No hay variables mutables a nivel de modulo en `.server.ts` (data leak entre usuarios)?

---

### Area 4: Anti-patrones SvelteKit (React-isms)

Lee `references/sveltekit-antipatterns.md` para la lista completa. Busca estos patrones en el diff:

**En archivos SVELTE_COMPONENT** (`.svelte`):

1. `goto()` para navegacion simple (deberia ser `href`)
2. `onMount` + `fetch` (deberia ser remote function o load)
3. `$effect` para computar valores (deberia ser `$derived`)
4. Spread para actualizar estado (`{...obj, key: val}` en vez de mutacion directa)
5. `<slot />` o `<slot name="...">` (Svelte 4, deberia ser snippets)
6. `on:click` / `on:change` (Svelte 4, deberia ser `onclick` / `onchange`)
7. Named imports de shadcn (`import { Card }` en vez de `import * as Card`)
8. `Select.Value` (no existe)
9. Lucide imports incorrectos (`import { Plus } from 'lucide-svelte'`)

**En archivos REMOTE_FUNCTION** (`.remote.ts`): 10. Archivo dentro de `src/lib/server/` (prohibido) 11. Query sin `refresh()` despues de mutacion en el componente que la usa

**En archivos TYPESCRIPT** (`.ts`): 12. `try/catch` envolviendo `error()` o `redirect()` de SvelteKit 13. Errores sin estructura (`error(400, 'string')` en vez de `error(400, { message, code })`)

**En archivos LOAD_SERVER**: 14. Filtrado server-side para datasets pequenos (<1000 items)

Cada anti-patron encontrado es al menos WARNING (BLOCKER si causa bugs).

---

### Area 5: Funcionalidad duplicada

El PR puede introducir funciones que ya existen en el codebase con otro nombre o forma ligeramente distinta. Este problema es especialmente comun en proyectos donde multiples desarrolladores (o LLMs) agregan codigo sin conocer lo que ya existe.

**Zonas de alto riesgo** donde la duplicacion es mas frecuente:

- Utilidades y helpers (`src/lib/utils/`, `src/lib/helpers/`)
- Formateo de fechas, numeros, moneda
- Validacion y sanitizacion de datos
- Funciones de logging o tracking
- Verificacion de permisos y autenticacion (variantes de `requireUser`, `requirePermission`)
- Construccion de queries Drizzle o transformacion de datos
- Formateo de respuestas de API o errores

**Como detectar duplicados en el contexto del PR:**

1. Para cada funcion NUEVA que el PR introduce (no modificaciones), identifica su proposito semantico
2. Busca en el codebase existente funciones con proposito similar usando Grep:
   - Busca por nombre de funcion similar (ej: si el PR agrega `formatDate`, busca `format.*date`, `date.*format`, `toDateString`)
   - Busca por el patron de operacion (ej: si la funcion nueva hace `new Intl.DateTimeFormat`, busca otros usos de `Intl.DateTimeFormat`)
3. Si encuentras una funcion existente que hace lo mismo (o casi lo mismo), reporta ambas con sus ubicaciones

**Criterios de severidad:**

- **WARNING**: La funcion nueva duplica funcionalidad existente. El PR deberia reusar la funcion existente o consolidar ambas.
- **SUGGESTION**: Las funciones son similares pero con diferencias justificables (distintos contextos, server vs client, etc). Sugerir considerar unificar.

**Ejemplo de reporte:**

```
WARNING: `formatDateShort()` en src/routes/reportes/reportes-utils.ts duplica
`formatFecha()` en src/lib/utils/dates.ts. Ambas formatean una fecha como "DD/MM/YYYY"
usando Intl.DateTimeFormat. Reusar la existente.
```

Si el skill `finding-duplicate-functions` esta disponible, puede invocarse para un analisis mas profundo de las zonas de alto riesgo del proyecto.

## Paso 4: Generar el reporte

Presenta el reporte con este formato exacto:

```markdown
# PR Review: #<NUMBER> — <TITLE>

**Autor**: <author> | **Branch**: <head> → <base> | **Archivos**: <N> | **+<additions> / -<deletions>**

---

## 1. Calidad del PR

<hallazgos con severidad>

## 2. Calidad del Codigo

<hallazgos con severidad>

## 3. Seguridad

<hallazgos con severidad>

## 4. Anti-patrones SvelteKit

<hallazgos con severidad>

## 5. Funcionalidad Duplicada

<hallazgos con severidad>

---

## Resumen

| Area          | Resultado               |
| ------------- | ----------------------- |
| Calidad PR    | <BLOCKER/WARNING/OK>    |
| Codigo        | <BLOCKER/WARNING/OK>    |
| Seguridad     | <BLOCKER/WARNING/OK>    |
| Anti-patrones | <BLOCKER/WARNING/OK>    |
| Duplicacion   | <WARNING/SUGGESTION/OK> |

**Veredicto**: <APROBAR / APROBAR CON CAMBIOS / SOLICITAR CAMBIOS>

<si hay blockers, listar los cambios requeridos>
<si hay warnings, listar las mejoras recomendadas>

<!-- b6:verdict=approve|approve-with-changes|request-changes blockers=N warnings=M -->
```

El marker HTML de la ultima linea es el **canal durable del veredicto**: queda en el comentario del PR en GitHub, sobrevive crashes de sesion, y los orquestadores (b9-close, b10-ship) lo re-leen con `gh pr view --json comments,reviews` (cubre tambien reportes viejos publicados como review). Incluirlo SIEMPRE al publicar el reporte en GitHub.

Ademas, terminar el output de terminal SIEMPRE con la linea machine-readable:

```
B6_VERDICT verdict=approve|approve-with-changes|request-changes blockers=N warnings=M pr=<numero>
```

## Paso 5: Publicar / ofrecer acciones

**Con `--auto` (desatendido):** publicar el reporte directo y terminar:

```bash
gh pr comment <N> --body-file /tmp/pr-review.md
```

> IMPORTANTE: usar `gh pr comment`, NO `gh pr review --comment` — un review COMMENTED aparece en `--json reviews` y NO en `--json comments`, y los parsers del pipeline (b9-close PASO 2, b10 `b6_marker`) leen ambos pero el canal canonico es el comentario. Ademas `--approve`/`--request-changes` NO funcionan sobre PRs propios (GitHub bloquea self-review) y los PRs del flujo b se crean con el token del usuario. El veredicto viaja en el marker `<!-- b6:verdict=... -->`, no en el review state de GitHub.

**Modo interactivo:** despues del reporte, ofrece al usuario:

1. **Publicar en GitHub**: `gh pr comment <N> --body-file /tmp/pr-review.md` (incluye el marker de veredicto)
2. **Corregir los issues**: Si hay blockers o warnings, ofrecer crear un branch para corregirlos
3. **Revisar archivos especificos**: Si el usuario quiere profundizar en algun archivo

## Notas

- Si el diff es muy largo (>3000 lineas), enfoca la revision en archivos de alto riesgo: remote functions, server loads, endpoints, y componentes principales. Menciona que archivos fueron revisados superficialmente.
- Si encuentras un patron que no esta en las referencias pero es claramente problematico, reportalo igual con una explicacion.
- Adapta la profundidad de la revision al tamano del PR. Un PR de 3 archivos no necesita el mismo nivel de detalle que uno de 30.
