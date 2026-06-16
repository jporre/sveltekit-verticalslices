---
name: b0-conversation-to-issues
description: 'Convierte el HISTORIAL de la conversacion (o un plan/PRD/doc) en uno o varios GitHub issues bien scopeados, sliceados en VERTICAL (tracer-bullet), con dependencias y un epic de tracking — listos para drenar con b10-ship --epic. Es el paso GENESIS del pipeline, antes de b1-triage. Usar cuando el usuario diga "crea el/los issue(s) de esto", "convierte esto en issues/tareas", "arma las tareas en github", "saca los issues de lo que hablamos", "abre los tickets de esta conversacion", "turn this into issues", "create issues from this conversation/plan", "break this into tickets", "split this into vertical slices". Tambien cuando una sesion de diseño/brainstorm/planificacion converge en trabajo concreto que hay que registrar. Antes de crear NADA verifica con el usuario lo que REALMENTE pide (gate humano). NO implementa codigo, NO triagea, NO abre PRs — solo produce la estructura de issues que el resto del pipeline procesa.'
allowed-tools: Bash, Read, Write, AskUserQuestion, Agent, Skill
model: opus
---

# b0-conversation-to-issues — conversacion → estructura de issues

Paso **b0**: el genesis del pipeline. Toma lo discutido en la sesion y lo deja como **issues de GitHub bien formados**, **sliceados en vertical**, **ordenados por dependencia** y agrupados bajo un **epic** — exactamente la forma que `b10-ship --epic=<N>` sabe drenar. No construye nada: produce el input del resto del pipeline (b1 → … → b10).

> En este proyecto "tarea" = issue de GitHub. Trato ambos como sinonimos.

## SIN `context: fork` — a proposito

Este skill corre en el **main loop**, NO en fork. Es deliberado y critico: la fuente de verdad es **el historial de la conversacion actual**, y un fork solo ve el cuerpo de este `SKILL.md` (no la sesion). Forkear este skill lo dejaria ciego a lo unico que necesita leer. Tambien necesita `AskUserQuestion` con el usuario presente para el gate de verificacion. La unica via de aislamiento aqui es el `Agent` opcional del Paso 2 (grounding en el codebase).

## Argumentos

```
[--from=<archivo>]     leer ADEMAS un plan/PRD/spec/doc como fuente (se combina con la conversacion)
[--scope=<area>]       hint de scope para labels y rama (ej. productos, ventas, auth)
[--epic-title="..."]   titulo explicito del epic; si falta, se deriva del tema
[--no-epic]            no crear epic de tracking (issues sueltos; usar solo con 1-2 issues independientes)
[--lang=es|en]         idioma de los issues; default autodetectado de la conversacion
[--cluster-hint]       marcar slices secuenciales del mismo scope como cluster sugerido para b8-swarm
[--yes]                saltar el gate de confirmacion (power users); por default el gate es OBLIGATORIO
[--dry-run]            llegar hasta el preview y NO crear nada en GitHub
```

**Argumentos recibidos en esta invocacion:**

```text
$ARGUMENTS
```

> El placeholder `$ARGUMENTS` es la via por la que llegan los flags tipeados — el harness lo sustituye. Si aparece vacio, usar defaults (fuente = conversacion, epic on, lang autodetectado).

## El principio: slices VERTICALES, no capas horizontales

Esta es la decision de diseño central del skill — y donde mas se equivoca un modelo. Cada issue debe ser una **rebanada vertical end-to-end**: algo que un usuario **puede usar** al mergearse, atravesando todo el stack (Drizzle → remote function → pantalla). NO una capa tecnica.

| Slice VERTICAL (correcto) | Capa HORIZONTAL (incorrecto) |
| --- | --- |
| "Listar productos en `/productos`" (DB + `get_products` + `+page.svelte`) | "Crear el schema Drizzle de todo el modulo" |
| "Crear/editar producto con formulario upsert" | "Escribir todas las remote functions" |
| "Eliminar producto con confirmacion" | "Maquetar todos los componentes UI" |
| "Filtrar y buscar en el listado" | "Conectar el front al back" |

Por que vertical: cada slice = **un PR de b7** = entrega valor verificable en el browser por si solo. Las capas horizontales no se pueden revisar visualmente, no cierran nada util, y rompen el modelo screen-first del plugin (b2/b7 construyen y revisan **por pantalla**, no por capa).

### Tracer bullet primero

El **primer slice** es el *tracer bullet*: el camino mas delgado que ejerce **todo el stack** de punta a punta (tipicamente "listar X read-only" — una query, una pantalla, auth). Prueba que la arquitectura cierra. Los slices siguientes **agregan una capacidad** encima (crear, editar, borrar, filtrar, exportar…), cada uno dependiente del tracer.

### Tamaño de cada slice = b7

Cada slice debe caber en un PR de b7: **simple (3-5 archivos)** o **medium (5-8)**. Si un slice pinta **complex (8-15+)**, **partirlo en mas slices** — el bot no construye complex sin gate, y un issue gigante no es un buen slice. Mejor 4 slices simples que 1 complex.

## GATE OBLIGATORIO: verificar lo que el usuario REALMENTE pide

Antes de crear **nada** en GitHub, confirmar con el usuario. Esto es ADN del plugin (igual que b1-triage entiende antes de construir, y b9 nunca mergea sin un humano): **registrar mal una conversacion propaga el error por todo el pipeline**. Un issue mal scopeado se construye, se revisa y casi se mergea antes de que alguien note que no era lo pedido.

El gate distingue **lo que se dijo literalmente** de **el objetivo real**. La gente describe soluciones ("agrega un boton que…") cuando el problema es otro ("no puedo encontrar mis pedidos atrasados"). El slicing debe atacar el objetivo, no transcribir frases.

Mecanica del gate (Paso 5): presentar en texto el entendimiento + el breakdown propuesto (epic + slices + orden de olas), y recien ahi usar `AskUserQuestion` para confirmar / ajustar / corregir. **No** crear issues hasta tener el OK. Con `--yes` se omite (power users que confian en el breakdown), pero el default SIEMPRE confirma.

## Flujo

### Paso 1 — Sintetizar la necesidad (de la conversacion)

Releer la conversacion de esta sesion (y `--from=<archivo>` si se paso) y destilar:

- **Objetivo real** — el "para que", no la frase literal. 1-2 lineas.
- **Entidades / datos** — los sustantivos del dominio (productos, ventas, usuarios…).
- **Operaciones** — que se hace con cada entidad (ver, crear, editar, borrar, filtrar, aprobar…).
- **Restricciones** — auth/permisos, reglas de negocio, deadlines, dependencias mencionadas.
- **Supuestos y ambiguedades** — lo que NO quedo claro; se explicita en el gate, no se inventa.

Regla dura: **no agregar requisitos que no esten en la conversacion o el doc.** Si algo falta para slicear bien, es material del gate (preguntarlo), no para rellenar de oficio.

### Paso 2 — Aterrizar en el codebase (acotado)

Para que los issues nombren rutas/entidades REALES (no inventadas), un grounding breve — mismo espiritu acotado que b1-triage (grounding, no exploracion exhaustiva):

- Por cada entidad, un grep dirigido: `rg -l "<entidad>" src/routes src/lib/server/db/schema`.
- Si ya existe la ruta/feature → el slice es enhancement de algo existente (afecta titulo y alcance), o puede ser **duplicate** (no crear).
- Confirmar nombres de scope reales para las labels (`scope:<area>`).

Para entidades multiples o un codebase desconocido, lanzar **un** `Agent(subagent_type=Explore)` acotado ("ubica las rutas y tablas de X, Y, Z; reporta paths exactos") en vez de gastar el contexto principal. No mas de eso.

> Si `.codegraph/` existe en el proyecto, preferir `codegraph_search` para ubicar entidades/rutas — mas rapido que grep.

### Paso 3 — Slicear en vertical

Aplicar el principio de arriba. Para CADA slice definir:

- **id** estable de slice (ej. `s1-list`, `s2-upsert`) — interno, lo usa el plan para deps.
- **titulo** estilo conventional (`feat(scope): …`, `fix(scope): …`).
- **objetivo + pantalla(s)** con ruta, journey y criterios de aceptacion visuales.
- **alcance**: que entra en ESTE slice y que queda explicitamente para otro.
- **labels**: `feature|bug|enhancement` + `scope:<area>` (+ `simple|medium` como hint; b1-triage reconfirma).

Detalle del cuerpo del issue: ver `references/slicing-guide.md` (template + ejemplo completo). **Leer ese archivo solo al momento de redactar** los bodies.

### Paso 4 — Ordenar en olas (dependencias)

Asignar `blocked_by` (lista de slice-ids) a cada slice:

- El tracer bullet (ola 0) no depende de nada.
- Enriquecimientos dependen del tracer (y entre si donde corresponda).
- El **array final de issues debe quedar en orden topologico** (toda dep aparece antes que quien la usa) — el script lo exige.

Esto se materializa como la seccion `## Blocked by` en cada body (el script la inyecta resolviendo ids → #numeros reales). Es la MISMA convencion que `epic-graph.sh` de b10 parsea para calcular olas y el `closing_slice`.

**Cluster (opcional):** si ≥2 slices son secuenciales, del **mismo scope**, `simple|medium`, y conviene un PR combinado, marcarlo como cluster (con `--cluster-hint`) para sugerir luego `b10-ship --epic --cluster` (que invoca b8-swarm). Slices de scopes distintos NUNCA van al mismo cluster.

### Paso 5 — GATE de verificacion (humano)

Presentar al usuario, en texto:

1. **Entendimiento**: objetivo real + entidades + operaciones (1 parrafo).
2. **Supuestos/ambiguedades** detectados.
3. **Breakdown**: epic + lista de slices con su ola y deps (mostrar como arbol de olas).

Luego `AskUserQuestion` con opciones del tipo:

- "Crear estos issues tal cual" (recomendado si refleja lo pedido)
- "Ajustar el slicing" (mas/menos granular)
- "Cambiar el scope / falta o sobra algo"
- "No es lo que pedi"

Iterar hasta el OK. Con `--yes`, saltar este paso. **Nunca** crear antes del OK.

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

> Las deps van SOLO en `blocked_by` (ids), **no** escribir `## Blocked by` ni `#numeros` en el `body` — esos issues aun no existen; el script inyecta la seccion resolviendo ids → numeros reales.
> `closing_slice: "epic"` hace que el epic dependa de TODOS los subs y se vuelva el slice de cierre de b10 (build ultimo, tras epic-review). Util cuando el cierre del epic incluye limpieza/swap. Si no aplica, `null`.
> Con `--no-epic`: omitir la clave `epic` (issues sueltos, sin linkeo).

Correr el preview (no toca GitHub):

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/skills/b-pipeline}"
B0="$PLUGIN_ROOT/skills/b0-conversation-to-issues/scripts/create-epic.sh"
bash "$B0" "$PLAN_JSON" --dry-run
```

Mostrar el arbol de olas. Si `--dry-run` global: parar aca, reportar el path del plan para inspeccion, emitir `B0_DONE … mode=dry-run`.

### Paso 7 — Crear la estructura

```bash
bash "$B0" "$PLAN_JSON"
```

El script: asegura labels, crea cada sub-issue resolviendo deps, crea el epic (rollup) y vincula los sub-issues nativos via `epic-link.sh`. Es idempotente-lite (titulo identico abierto → reusa, no duplica). Parsear su ultima linea:

```
B0_DONE epic=<N|none> issues=<n1,n2,...> waves=<k> mode=created
```

### Paso 8 — Reportar + handoff a b10

Resumen corto en terminal:

- Epic creado (#N) + cantidad de slices + olas.
- Como seguir:
  - **Epic completo:** `/b-pipeline:b10-ship --epic=<N>` (drena el grafo respetando olas y gates).
  - **Con cluster sugerido:** `/b-pipeline:b10-ship --epic=<N> --cluster`.
  - **Un slice puntual primero:** `/b-pipeline:b7-issue-to-pr <n1>` (suele ser el tracer bullet).
  - **Preview del plan de b10:** `/b-pipeline:b10-ship --epic=<N> --dry-run`.

Ultima linea SIEMPRE (machine-readable, por si otro orquestador la consume):

```
B0_DONE epic=<N|none> issues=<csv> waves=<k> mode=<created|dry-run>
```

## Contrato con b10 (por que esto "encaja")

- **Dependencias** = seccion `## Blocked by` con `#N` en el body → `epic-graph.sh` la parsea para las olas.
- **Sub-issues nativos** via `epic-link.sh` → el epic muestra progreso nativo y `b10 --epic` los enumera (con fallback a los `#N` del rollup si el linkeo falla).
- **closing_slice** = el epic con `## Blocked by` sobre todos los subs (≥80% del grafo) → b10 lo construye ultimo, tras el gate de epic-review.
- **Cluster** = slices del mismo `scope`, `simple|medium` → candidatos a `b8-swarm` (1 PR combinado).
- Cada issue trae lo que **b1-triage** espera (entidad, operacion, scope, criterios) y lo que **b2/b7** necesitan (pantallas con ruta + journey + acceptance). El issue queda "ready-shaped" pero b1 igual lo re-triagea — b0 no reemplaza el triage.

## Que NO hacer

- **No slicear horizontal.** Nada de "issue del schema", "issue de las remote functions", "issue de la UI". Cada issue cruza el stack y entrega una pantalla usable.
- **No crear issues complex.** Un slice complex (8-15+ archivos) se parte en slices mas chicos. El bot no construye complex desatendido.
- **No inventar requisitos.** Solo lo que esta en la conversacion / el doc. Lo que falte se pregunta en el gate.
- **No crear sin el gate.** El default confirma con el usuario antes de tocar GitHub. Solo `--yes` lo salta.
- **No escribir `## Blocked by`/`#numeros` en los bodies del plan.** Deps van en `blocked_by` (ids); el script los resuelve.
- **No triagear ni construir aca.** b0 produce la estructura; b1 triagea, b7/b8 construyen, b9 cierra. No duplicar su logica.
- **No meter slices de scopes distintos en un cluster.** b8 exige cohesion tematica.
- **No usar `gh issue create` a mano** para esto — usar `create-epic.sh` (resuelve deps, linkea el epic, evita duplicados).

## Referencias

- `references/slicing-guide.md` — vertical vs horizontal, metodo tracer-bullet, ejemplo completo con grafo de deps y plan JSON, y el template de cuerpo de issue. Leer al redactar los bodies (Paso 3).
- `scripts/create-epic.sh` — creacion deterministica: labels + sub-issues + deps + epic + linkeo nativo. Soporta `--dry-run`.
- `../b10-ship/scripts/epic-graph.sh` — lo que b10 usa para leer este grafo (referencia del contrato de deps/olas).
