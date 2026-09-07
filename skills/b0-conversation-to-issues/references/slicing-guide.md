# Guía de slicing por pantalla + template de issue

Leer al redactar los bodies. Define cómo cortar la conversación en olas-pantalla y cómo se ve cada issue.

## La regla: una pantalla = una ola = 4 issues

La unidad es la **pantalla** (carpeta `src/routes/<feature>/`): es lo que el cliente usa y lo que puede revisar contra sus definiciones. Cada pantalla es una ola con, mínimo, estos issues (`kind`):

| kind | Entrega | Archivos | Depende de |
| --- | --- | --- | --- |
| `remote` | remote functions de la pantalla (`query`/`form`/`command`), SQL-first, `requireUser()` primero | `server/data.remote.ts` (+ schema Drizzle si falta) | infra de la ola, si hay |
| `ui` | `+page.svelte` + `ui/*.svelte` consumiendo las remote functions; criterios visuales | `+page.svelte`, `ui/`, `+page.server.ts` | `remote` |
| `tests` | unit de las remote functions + browser check de la pantalla | `*.test.ts` colocados en la carpeta | `ui` |
| `docs` | `docs/readme.md` de la carpeta + línea en `docs/ARCHITECTURE.md` | docs de la ruta | `ui` |

`infra` (opcional, sin `screen`): prefactor, schema compartido, refactor ancho. Nunca un issue "feature" horizontal ("todas las remote functions del módulo", "maquetar todo").

| Pregunta de control | Bien cortado | Mal cortado |
| --- | --- | --- |
| ¿La ola entrega UNA pantalla usable al cerrar? | Sí | No (capa técnica) o varias pantallas |
| ¿Los archivos de la ola viven en UNA carpeta de ruta? | Sí | Tocan varias rutas |
| ¿El usuario puede revisar sus definiciones contra la pantalla al cerrar la ola? | Sí | Estado intermedio |
| ¿Otra ola toca los mismos archivos? | No | Sí → mergear pantallas o cortar por sub-ruta |

## Remote functions: crear una vez, usar desde todas

Si una función sirve a más de una pantalla, vive en la pantalla que la creó y las demás la **importan** (`../<pantalla>/server/data.remote`). El body del issue `remote` declara dos listas: **reutiliza** (nombre + path existente) y **crea** (nombre + contrato). El grounding del Paso 2 es donde se descubre qué ya existe (`rg -n 'export const' src/routes --glob '*.remote.ts'`). b2 obliga al agente a repetir esa búsqueda antes de crear cualquier función.

## Tracer bullet

La primera ola es la pantalla más delgada del epic — normalmente el listado read-only: 1 tabla, 1 `query`, 1 `+page.svelte`, auth. Prueba que la arquitectura cierra con datos reales y sesión real.

## Cómo cortar (heurística)

1. **Una carpeta de ruta por ola.** `/productos` y `/productos/[id]` son pantallas distintas → olas distintas. Listar + crear/editar + borrar + filtrar de `/productos` van en la MISMA ola (es una pantalla).
2. **Cap de tamaño = b7.** Cada issue `simple|medium`. Si el `ui` o el `remote` de una pantalla pinta `complex`, cortar por **sub-ruta** (nunca por capa ni capacidad) hasta que cada uno quepa.
3. **Deps entre pantallas solo reales.** B depende de A únicamente si navega a A o importa una remote function de A. Pantallas independientes son olas paralelas (carpetas disjuntas).
4. **Orden dentro de la ola fijo:** `remote` → `ui` → `tests` + `docs`. Los 4 son del mismo scope → cluster natural (un PR por pantalla vía b8 en modo rápido).

> **Lo transversal NO es una pantalla.** auth, db, storage, notificaciones y audit viven en `$lib`. O son parte del alcance de un issue de la ola (ej. el `ui` exige sesión), o son un issue `infra` puntual.

## Prefactor — make the change easy, then make the easy change

Si el grounding muestra código que pelea contra el epic, UN issue `infra` `refactor(scope): …` antes de la primera pantalla que lo necesita. Condición dura: debe hacer más fácil una ola concreta de ESTE epic; limpieza general es b-setup-or-fix.

## Refactor ancho — expand–contract

Un cambio mecánico de blast radius repo-wide (rename de columna, retipado de símbolo compartido) se secuencia con la misma maquinaria, todos `infra`:

- **expand** (ola 0): agregar la forma nueva junto a la vieja.
- **migrate-\*** (ola 1, ancha): call sites en lotes por scope, `blocked_by: [expand]`.
- **contract** (ola final): borrar la forma vieja, `blocked_by` todos los migrate.

Si ni los lotes quedan verdes solos, `closing_slice: "epic"`.

## Ejemplo: "necesito gestionar los productos"

Objetivo real: **CRUD de productos con búsqueda y detalle**. Grounding: no existe `src/routes/productos/`; ya existe `get_categorias` en `src/routes/categorias/server/data.remote.ts`.

```
Ola 0 — /productos            Ola 1 — /productos/[id]
  productos-remote              detalle-remote  (importa get_producto de ola 0)
      └─ productos-ui               └─ detalle-ui
           ├─ productos-tests            ├─ detalle-tests
           └─ productos-docs             └─ detalle-docs
```

| id | screen | kind | título | blocked_by |
| --- | --- | --- | --- | --- |
| productos-remote | /productos | remote | feat(productos): remote functions de /productos | — |
| productos-ui | /productos | ui | feat(productos): pantalla /productos (listar, upsert, borrar, filtrar) | productos-remote |
| productos-tests | /productos | tests | test(productos): /productos | productos-ui |
| productos-docs | /productos | docs | docs(productos): /productos | productos-ui |
| detalle-remote | /productos/[id] | remote | feat(productos): remote functions de /productos/[id] | productos-remote |
| detalle-ui | /productos/[id] | ui | feat(productos): pantalla /productos/[id] | detalle-remote |
| detalle-tests | /productos/[id] | tests | test(productos): /productos/[id] | detalle-ui |
| detalle-docs | /productos/[id] | docs | docs(productos): /productos/[id] | detalle-ui |

`detalle-remote` reutiliza `get_producto` (creado en `productos-remote`) y `get_categorias` (ya existía); crea solo `get_historial_producto`.

Plan JSON (ordenado topológicamente, bodies abreviados):

```json
{
  "lang": "es",
  "scope": "productos",
  "epic": { "title": "Epic: Gestión de productos", "labels": ["scope:productos"], "closing_slice": null },
  "issues": [
    { "id": "productos-remote", "screen": "/productos", "kind": "remote",
      "title": "feat(productos): remote functions de /productos",
      "labels": ["feature", "scope:productos", "simple"], "blocked_by": [],
      "body": "## Objetivo\nDatos y operaciones de la pantalla /productos.\n\n## Entidad / datos\n`taProductos` (id, nombre, precio, categoriaId, createdAt). Crear con Drizzle si no existe.\n\n## Remote functions\n**Reutiliza:** `get_categorias` (`src/routes/categorias/server/data.remote.ts`).\n**Crea:** `get_productos(filtro?)` query · `upsert_producto` form (id opcional, Zod: nombre requerido, precio >= 0) · `delete_producto` command. Todas con `requireUser()` primero.\n\n## Seguridad / permisos\nSesión requerida.\n\n## Archivos previstos\n`src/routes/productos/server/data.remote.ts`, `src/lib/server/db/schema.ts` (si falta la tabla).\n\n## Alcance\nSolo remote functions + schema. Sin UI (productos-ui).\n\n## Complejidad estimada\nsimple." },
    { "id": "productos-ui", "screen": "/productos", "kind": "ui",
      "title": "feat(productos): pantalla /productos (listar, upsert, borrar, filtrar)",
      "labels": ["feature", "scope:productos", "medium"], "blocked_by": ["productos-remote"],
      "body": "## Objetivo\nGestionar productos desde una sola pantalla.\n\n## Pantalla\n- **Ruta**: `/productos`\n  - **Journey**: el usuario ve la tabla, busca/filtra por categoría, crea o edita en un form upsert, elimina con confirmación.\n  - **Criterios de aceptación (visuales)**:\n    - [ ] Tabla con nombre, precio y categoría; estado vacío claro.\n    - [ ] Un único formulario upsert; editar pre-puebla; errores de validación visibles; toast al guardar.\n    - [ ] Diálogo de confirmación antes de borrar; la fila desaparece.\n    - [ ] Búsqueda y filtro por categoría en vivo, reflejados en la URL.\n    - [ ] Sin sesión redirige a login.\n\n## Seguridad / permisos\nSesión requerida (`+page.server.ts`).\n\n## Archivos previstos\n`src/routes/productos/+page.svelte`, `src/routes/productos/ui/ProductoForm.svelte`, `src/routes/productos/+page.server.ts`.\n\n## Alcance\nSolo UI sobre las remote functions de productos-remote. Sin tests ni docs (productos-tests, productos-docs).\n\n## Complejidad estimada\nmedium." },
    { "id": "productos-tests", "screen": "/productos", "kind": "tests",
      "title": "test(productos): /productos",
      "labels": ["feature", "scope:productos", "simple"], "blocked_by": ["productos-ui"],
      "body": "## Objetivo\nCobertura de la pantalla /productos.\n\n## Alcance\nUnit de `get_productos`/`upsert_producto`/`delete_producto` (validación Zod, requireUser) + browser check de los criterios visuales de productos-ui.\n\n## Archivos previstos\n`src/routes/productos/server/data.remote.test.ts`, `src/routes/productos/productos.browser.test.ts`.\n\n## Complejidad estimada\nsimple." },
    { "id": "productos-docs", "screen": "/productos", "kind": "docs",
      "title": "docs(productos): /productos",
      "labels": ["feature", "scope:productos", "simple"], "blocked_by": ["productos-ui"],
      "body": "## Objetivo\nDocumentar la pantalla /productos para quien la mantenga.\n\n## Alcance\n`src/routes/productos/docs/readme.md` (pantalla, remote functions con contrato, tablas, permisos) + línea en `docs/ARCHITECTURE.md`.\n\n## Complejidad estimada\nsimple." }
  ]
}
```

(La ola 1 sigue el mismo patrón con `screen: "/productos/[id]"`.)

## Template de cuerpo de issue

Estructura mínima que satisface a b1-triage (entidad, operación, scope, criterios) y a b2/b7 (pantalla con ruta + journey + acceptance). Las secciones marcadas con su kind solo van en ese kind.

```markdown
## Objetivo
<1-2 líneas: qué obtiene el usuario; el "para qué" real>

## Entidad / datos                      (remote, infra)
<tablas Drizzle reales, campos clave. Si hay que crear schema, decirlo.>

## Remote functions                     (remote)
**Reutiliza:** <nombre> (<path existente>) …
**Crea:** <nombre> query|form|command — <contrato en una línea> …

## Pantalla                             (ui)
- **Ruta**: `/<feature>`
  - **Journey**: <usuario entra a X, hace Y, ve Z>
  - **Criterios de aceptación (visuales)**:
    - [ ] ...

## Seguridad / permisos
<sesión, roles, ownership. "Solo exige sesión" también se declara.>

## Archivos previstos
<paths EXACTOS dentro de `src/routes/<feature>/` (más schema si aplica). Fija la carpeta y habilita olas paralelas.>

## Alcance
<qué entra en ESTE issue y qué queda para los otros kinds de la misma pantalla>

## Complejidad estimada
simple | medium  (simple = 3-5 archivos, medium = 5-8)
```

Reglas del body:

- `screen` y `kind` van en el plan JSON, no en el body; el script agrega la label `kind:<k>`.
- Si existe design doc (`docs/plans/<tema>.md`), linkearlo al final (`> Diseño: docs/plans/<tema>.md`).
- **No** escribir `## Blocked by` ni `#números` — las deps van en `blocked_by` del plan; el script las inyecta.
- Issue `infra`: sin `## Pantalla`; criterios de aceptación no visuales. b7 corre igual con `screens: []`.
- Idioma del body = idioma de la conversación. Título en conventional: `feat(scope): …`, `test(scope): …`, `docs(scope): …`, `refactor(scope): …`.
