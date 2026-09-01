---
name: b0-conversation-to-issues
description: 'Convierte la conversación actual (o un plan/PRD/doc, o un issue grande existente) en issues de GitHub sliceados en vertical (tracer-bullet), con dependencias y epic de tracking, listos para drenar con b10-ship --epic. Usar cuando el usuario pida convertir lo conversado o un plan en issues/tareas/tickets ("crea los issues de esto", "turn this into issues"), pida desglosar un issue/epic existente en sub-issues ("desglosa el issue #42"), pida partir trabajo en vertical slices, o cuando una sesión de diseño/brainstorm converge en trabajo por registrar. TAMBIÉN al INICIO: con una idea cruda ("quiero conversar una idea", "ayúdame a pensar X antes de codear") entra en modo diseño — entrevista 1x1 que madura la idea hasta un plan sliceable y recién ahí crea los issues. Paso génesis, antes de b1-triage: no implementa, no triagea, no abre PRs.'
allowed-tools: Bash, Read, Write, AskUserQuestion, Agent, Workflow
model: opus
---


# b0-conversation-to-issues — conversación → estructura de issues

> **Multi-harness (Claude Code / pi).** Los mecanismos del harness se mapean así: `AskUserQuestion` → en pi, pregunta en texto y espera la respuesta. `Agent(subagent_type=…)`/`Agent call` → en pi, tool `subagent` con `agent: "<nombre>"` y `model` opcional (este paquete define los agentes `b7-impl`, `b7-impl-s`, `b7-screen-review`). `Skill(bN-…)`/`Skill b-pipeline:bN-…` → en pi, carga el `SKILL.md` de ese skill con `read` y síguelo. `Workflow` → en pi, tool `subagent` con `workflowScript` (mismas primitivas `runs.run`/`runs.all`). `PushNotification` → en pi, omítelo y reporta el hito en tu respuesta. `CLAUDE_PLUGIN_ROOT` existe en ambos (pi la exporta su extensión de compatibilidad). En Claude Code, todo funciona como está escrito.

Paso **b0**: el génesis del pipeline. Toma lo discutido en la sesión y lo deja como **issues de GitHub bien formados**, **sliceados en vertical**, **ordenados por dependencia** y agrupados bajo un **epic** — exactamente la forma que `b10-ship --epic=<N>` sabe drenar. No construye nada: produce el input del resto del pipeline (b1 → … → b10).

> En este proyecto "tarea" = issue de GitHub. Trato ambos como sinónimos.

## SIN `context: fork` — a propósito

Fuente de verdad = historial de esta sesión; usuario presente para el gate (`AskUserQuestion`). Razonamiento (destilar, slicear, gate) en el main loop; delegar solo grounding read-only (Paso 2) y redacción de bodies aprobados (Paso 6). Ningún subagente decide el slicing.

## Argumentos

```
[--design]             forzar modo diseño (entrevista) aunque la conversación parezca madura
[--from=<archivo|issue>] leer ADEMÁS un plan/PRD/spec/doc (path) o un issue de GitHub (#N o URL) como fuente
[--scope=<area>]       hint de scope para labels y rama (ej. productos, ventas, auth)
[--epic-title="..."]   título explícito del epic; si falta, se deriva del tema
[--no-epic]            no crear epic de tracking (issues sueltos; usar solo con 1-2 issues independientes)
[--lang=es|en]         idioma de los issues; default autodetectado de la conversación
[--cluster-hint]       marcar slices secuenciales del mismo scope como cluster sugerido para b8-swarm
[--fast]               junto con --yes: estampar epic-auto-merge sin preguntar (modo rápido headless)
[--yes]                saltar el gate de confirmación (power users); por default el gate es OBLIGATORIO
[--dry-run]            llegar hasta el preview y NO crear nada en GitHub
```

**Argumentos recibidos en esta invocación:**

```text
$ARGUMENTS
```

> Si `$ARGUMENTS` aparece vacío, usar defaults (fuente = conversación, epic on, lang autodetectado).

## El principio: slices VERTICALES, no capas horizontales

Esta es la decisión de diseño central del skill — y donde más se equivoca un modelo. Cada issue debe ser una **rebanada vertical end-to-end**: algo que un usuario **puede usar** al mergearse, atravesando todo el stack (Drizzle → remote function → pantalla). NO una capa técnica.

| Slice VERTICAL (correcto) | Capa HORIZONTAL (incorrecto) |
| --- | --- |
| "Listar productos en `/productos`" (DB + `get_products` + `+page.svelte`) | "Crear el schema Drizzle de todo el módulo" |
| "Crear/editar producto con formulario upsert" | "Escribir todas las remote functions" |
| "Eliminar producto con confirmación" | "Maquetar todos los componentes UI" |
| "Filtrar y buscar en el listado" | "Conectar el front al back" |

Por qué vertical: cada slice = **un PR de b7** = entrega valor verificable en el browser por sí solo. Las capas horizontales no se pueden revisar visualmente, no cierran nada útil, y rompen el modelo screen-first del plugin (b2/b7 construyen y revisan **por pantalla**, no por capa).

### Tracer bullet primero

El **primer slice** es el *tracer bullet*: el camino más delgado que ejerce **todo el stack** de punta a punta (típicamente "listar X read-only" — una query, una pantalla, auth). Prueba que la arquitectura cierra. Los slices siguientes **agregan una capacidad** encima (crear, editar, borrar, filtrar, exportar…), cada uno dependiente del tracer.

### Tamaño de cada slice = b7

Cada slice debe caber en un PR de b7: **simple (3-5 archivos)** o **medium (5-8)**. Si un slice pinta **complex (8-15+)**, **partirlo en más slices** — el bot no construye complex sin gate, y un issue gigante no es un buen slice. Mejor 4 slices simples que 1 complex.

## GATE OBLIGATORIO: verificar lo que el usuario REALMENTE pide

Antes de crear **nada** en GitHub, confirmar con el usuario. Esto es ADN del plugin (igual que b1-triage entiende antes de construir, y b9 nunca mergea sin un humano): **registrar mal una conversación propaga el error por todo el pipeline**. Un issue mal scopeado se construye, se revisa y casi se mergea antes de que alguien note que no era lo pedido.

El gate ataca el objetivo real, no la solución literal (problema XY).

Mecánica del gate (Paso 5): presentar en texto el entendimiento + el breakdown propuesto (epic + slices + orden de olas), y recién ahí usar `AskUserQuestion` para confirmar / ajustar / corregir. **No** crear issues hasta tener el OK. Con `--yes` se omite (power users que confían en el breakdown), pero el default SIEMPRE confirma.

## Flujo

### Paso 0 — ¿Diseñar o slicear? (madurez de la conversación)

Evaluar si la conversación aguanta el slicing: objetivo claro, entidades y operaciones nombradas, pocas ambigüedades.

- **Madura** (o `--yes`): flujo clásico — seguir al Paso 1.
- **Cruda** — invocado al inicio con solo una idea, o dominan los supuestos sin resolver — o `--design` explícito: **modo diseño**. Leer `references/design-interview.md` y seguir su protocolo: resumen inteligente si hubo conversación previa, entrevista 1x1 con respuesta recomendada por pregunta, design doc en `docs/plans/<tema>.md` actualizado a medida que las decisiones cierran, convergencia propuesta cuando el checklist cierra. Al converger, volver acá y seguir al Paso 1 (la destilación sale casi gratis: ES el design doc).
- En la duda, proponer modo diseño vía `AskUserQuestion` — slicear supuestos sin madurar propaga el error por todo el pipeline (el mismo argumento del gate).

### Paso 1 — Sintetizar la necesidad (de la conversación)

Releer la conversación de esta sesión (y la fuente `--from` si se pasó) y destilar:

- **Objetivo real** — el "para qué", no la frase literal. 1-2 líneas.
- **Entidades / datos** — los sustantivos del dominio (productos, ventas, usuarios…).
- **Operaciones** — qué se hace con cada entidad (ver, crear, editar, borrar, filtrar, aprobar…).
- **Restricciones** — auth/permisos, reglas de negocio, deadlines, dependencias mencionadas.
- **Supuestos y ambigüedades** — lo que NO quedó claro; se explicita en el gate, no se inventa.

Regla dura: **no agregar requisitos que no estén en la conversación o el doc.** Si algo falta para slicear bien, es material del gate (preguntarlo), no para rellenar de oficio.

**`--from` = issue de GitHub** (`#N`, número o URL): leer body Y comentarios — `gh issue view <N> --comments` — los comentarios suelen corregir el scope del body. Ese issue pasa a ser el **epic padre**: `epic: { "number": N }` en el plan (Paso 6); no se crea epic nuevo, no se edita ni se cierra el origen.

### Paso 2 — Aterrizar en el codebase (acotado)

Para que los issues nombren rutas/entidades REALES (no inventadas), un grounding breve — mismo espíritu acotado que b1-triage (grounding, no exploración exhaustiva).

Incluye la doc viva del repo: `docs/ARCHITECTURE.md` (mapa de slices + Decisiones) y el `docs/readme.md` colocado de cada feature que un slice toque. Títulos y bodies usan el vocabulario real del dominio, y ningún slice re-propone algo rechazado en Decisiones.

**Primero, un probe FUNCIONAL de codegraph** (no confiar en "existe `.codegraph/`": la db puede estar rota o stale). Correr el probe compartido y, si dice `ok`, confirmar con una query real de la **entidad 1**:

```bash
bash "$CLAUDE_PLUGIN_ROOT/skills/b1-add-worktree/scripts/codegraph-probe.sh" .   # -> CODEGRAPH_STATUS=ok|stale|missing|broken db_age_days=<n>
codegraph query "<entidad-1>" -p .                                              # solo si status=ok: confirma que devuelve rutas usables
```

El probe SIEMPRE sale 0; el `CODEGRAPH_STATUS` elige la rama de grounding. `codegraph` es recomendación con fallback, **nunca gate**.

#### Rama A — status `ok`: codegraph en el main loop, CERO Explore agents

Con la db usable, hacer **una query de codegraph por entidad en el main loop** (no delegar a subagentes):

- `codegraph_search "<entidad>"` (o `codegraph query "<entidad>" -p .`) por cada entidad → rutas + tablas reales. Una sola consulta suele cubrir varias entidades relacionadas.
- **NO** lanzar `Agent(Explore)`: la query directa es más rápida y barata, y evita el fan-out.
- Confirmar nombres de scope reales para las labels (`scope:<area>`).

#### Rama B — status `stale`/`missing`/`broken`: fallback rg + Explore

Cuando el probe **no** da `ok`, usar `rg`/grep y Explore (y **NO** invocar tools `codegraph_*`: devolverían datos stale o fallarían):

- Por cada entidad, un grep dirigido: `rg -l "<entidad>" src/routes src/lib/server/db/schema`.
- Si ya existe la ruta/feature → el slice es enhancement de algo existente (afecta título y alcance), o puede ser **duplicate** (no crear).
- Confirmar nombres de scope reales para las labels (`scope:<area>`).

Para entidades múltiples o un codebase desconocido, delegar el grounding a `Agent(subagent_type=Explore)` para no gastar el contexto principal — y **paralelizar cuando hay varias entidades**:

- **1-3 entidades:** un solo `Agent(Explore)` acotado ("ubica las rutas y tablas de X, Y, Z; reporta paths exactos").
- **4+ entidades:** lanzar varios `Agent(Explore)` **en paralelo** (todos en un mismo mensaje, un agente por entidad o par de entidades cohesivas), cada uno con encargo cerrado: "¿existe `src/routes/<area>`? ¿qué tabla Drizzle la respalda? reporta paths exactos o 'no existe'". Read-only y disjuntos → seguro en paralelo, y corta el wall-clock de N búsquedas secuenciales. Cap razonable: ~6 agentes.

El grounding es read-only: no decide nada, solo devuelve paths reales para que el slicing nombre rutas/tablas que existen (o confirme que son nuevas). Consolidas los reportes en el main loop antes de slicear.

### Paso 3 — Slicear en vertical

Aplicar el principio de arriba. Para CADA slice definir:

- **id** estable de slice (ej. `s1-list`, `s2-upsert`) — interno, lo usa el plan para deps.
- **título** estilo conventional (`feat(scope): …`, `fix(scope): …`).
- **objetivo + pantalla(s)** con ruta, journey y criterios de aceptación visuales.
- **alcance**: qué entra en ESTE slice y qué queda explícitamente para otro.
- **labels**: `feature|bug|enhancement` + `scope:<area>` (+ `simple|medium` como hint; b1-triage reconfirma).

Dos excepciones al corte estándar (detalle en `references/slicing-guide.md`):

- **Prefactor**: si el grounding muestra código que pelea contra los slices, UN slice `refactor(scope)` chico antes del tracer — *make the change easy, then make the easy change*. Solo si desbloquea slices de ESTE epic; limpieza general del repo es b-setup-or-fix, no un issue acá.
- **Refactor ancho** (rename de columna / retipado de símbolo compartido, blast radius repo-wide): no forzarlo a tracer-bullet — cortarlo expand–contract (§ Refactor ancho de la guía).

### Paso 4 — Ordenar en olas (dependencias)

Asignar `blocked_by` (lista de slice-ids) a cada slice:

- El tracer bullet (ola 0) no depende de nada.
- **Deps SOLO reales, olas anchas:** `blocked_by` únicamente cuando el slice consume algo que otro CREA (schema, query, pantalla). Prohibido encadenar por orden estético o "flujo natural" — todo lo que solo depende del tracer va JUNTO en la ola 1, aunque sean 5 slices. Cada dep artificial es una ola extra de espera: las olas anchas son lo que b10 paraleliza (wave-build / cluster b8).
- Dentro de una ola, buscar `## Archivos previstos` disjuntos entre slices de scopes distintos (precondición de wave-build). Mismo scope compartiendo archivos → candidatos a cluster, no a deps.
- El **array final de issues debe quedar en orden topológico** (toda dep aparece antes que quien la usa) — el script lo exige.

Esto se materializa como la sección `## Blocked by` en cada body (el script la inyecta resolviendo ids → #números reales). Es la MISMA convención que `epic-graph.sh` de b10 parsea para calcular olas y el `closing_slice`.

**Cluster (opcional):** si ≥2 slices son secuenciales, del **mismo scope**, `simple|medium`, y conviene un PR combinado, marcarlo como cluster (con `--cluster-hint`) para sugerir luego `b10-ship --epic --cluster` (que invoca b8-swarm). Slices de scopes distintos NUNCA van al mismo cluster.

**Consolidación (vertical, pero inteligente):** con las olas asignadas, cruzar los `## Archivos previstos` de todos los slices (matriz archivo × slice) y aplicar `references/slicing-guide.md` § Consolidación: overlap en la misma ola → cluster o merge (wave-build exige disjuntos); overlap entre olas solo si es append-only (si un slice reescribe lo de otro, mergear); y la cola transversal — tests y docs que 3+ slices tocarían — se extrae a UN slice de cierre `blocked_by` todos: se escribe una vez contra el estado final, no N veces contra estados intermedios. Los criterios visuales se quedan en su slice (b7 los verifica por pantalla). El resultado se muestra en el gate.

### Paso 5 — GATE de verificación (humano)

Presentar el plan al usuario, en texto simple, pero claro:

1. **Entendimiento**: objetivo real + entidades + operaciones (1 párrafo).
2. **Supuestos/ambigüedades** detectados.
3. **Breakdown**: epic + lista de slices con su ola y deps (mostrar como árbol de olas). Si la fuente enumera user stories o requisitos (PRD, design doc, issue origen), mapear cuáles cubre cada slice y listar los NO cubiertos — se resuelven en el gate (scope out explícito o slice nuevo), no se pierden en silencio.
4. **Criterios de éxito por slice**: 1-3 criterios de aceptación por slice (qué se verá/podrá hacer cuando esté logrado — los mismos que b7-screen-review y el epic-review verificarán después). Esto es LO QUE el gate aprueba: los bodies del Paso 6 elaboran estos criterios, no inventan otros.
5. **Plan de ejecución**: que corre junto por ola (cluster mismo scope / wave-build scopes disjuntos / secuencial y por qué), dónde caerán los gates humanos (complex, waivers, epic-review).

**Regla dura del gate: la pregunta va DESPUÉS del plan, en el mismo mensaje.** Preguntar "¿de acuerdo?" sin haber mostrado los puntos 1-5 no es un gate, es un trámite — el usuario no puede aprobar lo que no vio.

Luego `AskUserQuestion` con DOS preguntas:

**Pregunta 1 — breakdown y criterios** (la aprobación versa sobre los CRITERIOS de éxito — qué determina que cada slice se logró — no sobre un "de acuerdo" genérico):

- "Crear tal cual: slices y criterios reflejan lo pedido" (recomendado si es así)
- "Ajustar criterios de aceptación" (falta o sobra un check de éxito)
- "Ajustar el slicing" (más/menos granular, scope)
- "No es lo que pedí"

**Pregunta 2 — modo de ejecución:**

- "Rápido (epic-auto-merge)" — recomendado si TODOS los slices son simple|medium: b0 estampa `epic-auto-merge` en el epic; b10 drena PRs con b6 blockers=0 sin gate por PR y activa paralelismo (wave-build, cluster, cap dinámico). Revisión humana concentrada en epic-review final + gates batcheados.
- "Supervisado" — sin label: cada merge espera `merge-approved` humano, builds secuenciales (comportamiento clásico).

Iterar hasta el OK. Con `--yes`, saltar este paso (modo de ejecución: supervisado, salvo `--fast` explícito en los argumentos). **Nunca** crear antes del OK.

### Paso 6 — Construir el plan + preview (dry-run)

Escribir el plan JSON a un scratch (ej. `"$(mktemp -t b0-plan.XXXX).json"`) con el schema que documenta `scripts/create-epic.sh`:

```json
{
  "lang": "es",
  "epic": { "title": "Epic: <tema>", "labels": ["scope:<area>"], "closing_slice": "epic" },
  "issues": [
    { "id": "s1-list", "title": "feat(<area>): …", "body": "<markdown SIN ## Blocked by>",
      "labels": ["feature", "scope:<area>", "simple"], "blocked_by": [] },
    { "id": "s2-upsert", "title": "feat(<area>): …", "body": "…",
      "labels": ["feature", "scope:<area>", "medium"], "blocked_by": ["s1-list"] }
  ]
}
```

> Las deps van SOLO en `blocked_by` (ids), **no** escribir `## Blocked by` ni `#numeros` en el `body` — esos issues aún no existen; el script inyecta la sección resolviendo ids → números reales.
> `closing_slice: "epic"` hace que el epic dependa de TODOS los subs y se vuelva el slice de cierre de b10 (build último, tras epic-review). Útil cuando el cierre del epic incluye limpieza/swap. Si no aplica, `null`.
> Con `--from=<issue>`: `"epic": { "number": <N>, "closing_slice": null }` — el script reusa ese issue como epic (linkea subs nativos) y NO toca su body ni labels; por eso `closing_slice` debe ser `null`.
> Con `--no-epic`: omitir la clave `epic` (issues sueltos, sin linkeo).

#### Redacción de bodies — inline o en paralelo

El cuerpo de cada slice es independiente: distinto archivo, distinta pantalla. El **slicing** (objetivo, deps, olas) es la parte difícil y ya quedó fijado y aprobado en el gate; redactar los markdown es trabajo mecánico que sigue el template de `references/slicing-guide.md`.

- **Breakdown chico (≤5 slices):** redactar los bodies inline. Es rápido y mantiene un solo tono.
- **Breakdown grande (≥6 slices):** **paralelizar la redacción** vía `Workflow` — un `agent()` (haiku/sonnet) por slice. Cada agente recibe lo MISMO para no divergir: (a) el template del slicing-guide, (b) la **lista completa de slices** (título + alcance de cada uno) para que su sección `## Alcance` referencie bien lo que queda para OTROS slices, (c) los grounding facts (rutas/tablas reales del Paso 2), (d) el idioma, (e) el path del design doc si existe (`docs/plans/<tema>.md`) — cada body lo linkea en vez de repetir las reglas globales. Devuelve `{id, body}`. El main loop ensambla los bodies devueltos en el array `issues` del plan JSON. Cap de paralelismo razonable: ~8.

Script del Workflow: cargar (Read) `scripts/draft-bodies.workflow.js` e invocar `Workflow({ script:<contenido>, args:{ slices:[{id,title,scope,criterios:[...]}], lang:'es', grounding:'<resumen Paso 2>' } })` — `criterios` son los aprobados en el gate del Paso 5; los agentes los elaboran, no inventan otros. Tras recibir `{bodies}`, mapear `id → body` y completar cada issue del plan. **El slicing NO se delega** — los agentes solo escriben prosa de slices que tú ya decidiste; no inventan slices nuevos ni cambian deps.

Correr el preview (no toca GitHub):

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cat "$HOME/.claude/b-pipeline.root" 2>/dev/null || ls -d "$HOME"/.claude/plugins/marketplaces/b-pipeline* 2>/dev/null | head -1)}"
B0="$PLUGIN_ROOT/skills/b0-conversation-to-issues/scripts/create-epic.sh"
bash "$B0" "$PLAN_JSON" --dry-run
```

Mostrar el árbol de olas. Si `--dry-run` global: parar acá, reportar el path del plan para inspección, emitir `B0_DONE … mode=dry-run`.

### Paso 7 — Crear la estructura

```bash
bash "$B0" "$PLAN_JSON"
```

El script: asegura labels, crea cada sub-issue resolviendo deps, crea el epic (rollup) y vincula los sub-issues nativos vía `epic-link.sh`. Es idempotente-lite (título idéntico abierto → reusa, no duplica). Parsear su última línea:

```
B0_DONE epic=<N|none> issues=<n1,n2,...> waves=<k> mode=created
```

**Post-creación (en este orden):**

1. **Design doc (si hubo modo diseño):** actualizar el estado del doc a `issues-creados (#<epic>)`, commitear docs-only a la rama default y pushear — `git add docs/plans/<tema>.md && git commit -m "docs(plans): diseño de <tema> (#<epic>)" && git push`. Riesgo cero (solo docs/), y deja el tree limpio para el preflight de b10 (exit 18) con el doc referenciable desde los bodies. NO mezclar nada más en ese commit.
2. **Modo rápido elegido en el gate:** `gh issue edit <EPIC> --add-label epic-auto-merge` — comando separado POST-creación, nunca en los labels del plan JSON: garantiza un evento `labeled` con tu token (actor humano) que `bp_label_event` valida en b10. El humano ya decidió en el gate; el label solo lo materializa. Quitarlo del epic en GitHub apaga el modo rápido en cualquier momento.

### Paso 8 — Reportar + handoff a b10

Resumen corto en terminal:

- Epic creado (#N) + cantidad de slices + olas + modo de ejecución (rápido/supervisado).
- Siguiente paso: `/b-pipeline:b10-ship --epic=<N>` — sin flags ni env vars: si el epic tiene `epic-auto-merge`, b10 activa solo el modo rápido completo (drenaje auto-merge + wave-build + cluster + cap dinámico).

Última línea SIEMPRE (machine-readable, por si otro orquestador la consume):

```
B0_DONE epic=<N|none> issues=<csv> waves=<k> mode=<created|dry-run>
```

## Contrato con b10 (por qué esto "encaja")

- **Dependencias** = sección `## Blocked by` con `#N` en el body → `epic-graph.sh` la parsea para las olas.
- **Sub-issues nativos** vía `epic-link.sh` → el epic muestra progreso nativo y `b10 --epic` los enumera (con fallback a los `#N` del rollup si el linkeo falla).
- **closing_slice** = el epic con `## Blocked by` sobre todos los subs (≥80% del grafo) → b10 lo construye último, tras el gate de epic-review.
- **Cluster** = slices del mismo `scope`, `simple|medium` → candidatos a `b8-swarm` (1 PR combinado).
- Cada issue trae lo que **b1-triage** espera (entidad, operación, scope, criterios) y lo que **b2/b7** necesitan (pantallas con ruta + journey + acceptance). `create-epic.sh` estampa los sub-issues con label `ready` (el epic no) — como el grounding y el gate humano ya se pagaron acá, **b1 `--auto` los reusa sin re-triagear** (deriva el veredicto de los labels + `## Blocked by`). Solo re-triagea si un humano comentó el issue después de crearlo. b0 no reemplaza el triage: lo pre-paga.

## Qué NO hacer

- **No usar `gh issue create` a mano** para esto — usar `create-epic.sh` (resuelve deps, linkea el epic, evita duplicados).
- **No cerrar ni editar el issue origen** (`--from=<issue>`): es el epic padre; solo recibe el linkeo nativo de sub-issues.

## Referencias

- `references/design-interview.md` — protocolo del modo diseño: entrevista 1x1, checklist de convergencia, template del design doc. Leer al entrar en modo diseño (Paso 0).
- `references/slicing-guide.md` — vertical vs horizontal, método tracer-bullet, excepciones (prefactor, refactor ancho expand–contract), ejemplo completo con grafo de deps y plan JSON, y el template de cuerpo de issue. Leer al redactar los bodies.
- `scripts/draft-bodies.workflow.js` — script Workflow para redacción paralela de bodies (breakdown >=6 slices).
- `scripts/create-epic.sh` — creación determinística: labels + sub-issues + deps + epic + linkeo nativo. Soporta `--dry-run`.
- `../b10-ship/scripts/epic-graph.sh` — lo que b10 usa para leer este grafo (referencia del contrato de deps/olas).
