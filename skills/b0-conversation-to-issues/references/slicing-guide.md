# Guia de slicing vertical + template de issue

Leer al redactar los bodies (Paso 3 del skill). Define como cortar la conversacion en slices verticales y como se ve cada issue.

## Vertical vs horizontal — la regla

Un slice es **vertical** si, al mergearse solo, un usuario **puede hacer algo** de punta a punta: dato (Drizzle) → remote function → pantalla (`+page.svelte`). Es **horizontal** si entrega una capa tecnica que por si sola no sirve.

| Pregunta de control | Vertical | Horizontal |
| --- | --- | --- |
| ¿Se puede usar en el browser al mergear? | Si | No |
| ¿b7-screen-review puede verificarlo visualmente? | Si (tiene pantalla) | No (no hay flujo) |
| ¿Cierra algo util para el usuario? | Si | No (parcial) |
| ¿Cruza el stack? | Si | No (una sola capa) |

Si la respuesta es "No" en cualquiera, el slice esta mal cortado. Re-cortar.

## Tracer bullet

El primer slice atraviesa **todo el stack** por el camino mas delgado posible — normalmente **listar la entidad en read-only**:

- 1 tabla Drizzle (o la existente), 1 `query` (`get_<entidad>`), 1 `+page.svelte` con la tabla, auth.
- Prueba que la arquitectura cierra (datos reales en pantalla real con sesion real).
- Todo lo demas (crear, editar, borrar, filtrar) **depende** de el y se agrega encima.

Analogia: la bala trazadora confirma la trayectoria antes de gastar el resto del cargador.

## Como cortar (heuristica)

1. **Una operacion por slice.** Listar / crear-editar / borrar / filtrar / exportar son slices distintos. (Crear y editar van **juntos**: en SvelteKit es UN formulario upsert con `id` opcional — no separar.)
2. **Una pantalla o flujo corto por slice.** Si aparecen 4+ pantallas en un slice, es complex → partir.
3. **Cap de tamaño = b7.** simple 3-5 archivos, medium 5-8. Si pinta 8-15+ (complex), partir hasta que cada parte sea simple|medium.
4. **Deps minimas.** Solo lo que de verdad bloquea (casi todo depende del tracer; los enriquecimientos rara vez dependen entre si salvo que compartan UI).
5. **Cohesion de scope para cluster.** Slices secuenciales del mismo `scope`, `simple|medium`, son candidatos a un PR combinado (b8). Scopes distintos → nunca el mismo cluster.

## Ejemplo completo: "necesito gestionar los productos"

Conversacion → objetivo real: **CRUD de productos con busqueda**. Grounding: no existe `src/routes/productos/` → feature nueva, scope `productos`.

Grafo de slices:

```
        s1-list (tracer, ola 0)
         /        \
  s2-upsert     s3-delete      (ola 1, independientes entre si)
         \        /
        s4-filter               (ola 2)
```

| id | titulo | op | complejidad | blocked_by |
| --- | --- | --- | --- | --- |
| s1-list | feat(productos): listar productos | listar (tracer) | simple | — |
| s2-upsert | feat(productos): crear y editar producto | upsert | medium | s1-list |
| s3-delete | feat(productos): eliminar con confirmacion | borrar | simple | s1-list |
| s4-filter | feat(productos): filtros y busqueda | filtrar | simple | s2-upsert, s3-delete |

s2 y s3 quedan en la misma ola, mismo scope, simple|medium → **cluster sugerido** (un PR via b8).

Plan JSON resultante (ordenado topologicamente):

```json
{
  "lang": "es",
  "scope": "productos",
  "epic": {
    "title": "Epic: Gestion de productos",
    "labels": ["scope:productos"],
    "closing_slice": null
  },
  "issues": [
    {
      "id": "s1-list",
      "title": "feat(productos): listar productos (tracer bullet)",
      "labels": ["feature", "scope:productos", "simple"],
      "blocked_by": [],
      "body": "## Objetivo\nVer el listado de productos para empezar a gestionarlos. Tracer bullet: prueba el stack completo (Drizzle -> remote function -> pantalla) en read-only.\n\n## Entidad / datos\n`taProductos` (id, nombre, precio, categoria, createdAt). Si la tabla no existe, crearla con Drizzle.\n\n## Pantalla\n- **Ruta**: `/productos`\n  - **Journey**: el usuario entra a /productos y ve la tabla de productos existentes.\n  - **Criterios de aceptacion (visuales)**:\n    - [ ] La tabla lista nombre, precio y categoria.\n    - [ ] Estado vacio claro cuando no hay productos.\n    - [ ] La ruta exige sesion (redirect a login si no hay).\n\n## Alcance (slice vertical)\nSolo lectura: `get_productos` + tabla. NO incluye alta/edicion/borrado/filtros (otros slices).\n\n## Complejidad estimada\nsimple (3-5 archivos: schema?, `productos.remote.ts`, `+page.svelte`, `+page.server.ts`)."
    },
    {
      "id": "s2-upsert",
      "title": "feat(productos): crear y editar producto",
      "labels": ["feature", "scope:productos", "medium"],
      "blocked_by": ["s1-list"],
      "body": "## Objetivo\nDar de alta y editar productos desde la misma pantalla del listado.\n\n## Entidad / datos\n`taProductos`. Validacion con Zod (nombre requerido, precio >= 0).\n\n## Pantalla\n- **Ruta**: `/productos`\n  - **Journey**: el usuario completa el formulario upsert (un solo form, `id` opcional) y el producto aparece/actualiza en la tabla.\n  - **Criterios de aceptacion (visuales)**:\n    - [ ] Un unico formulario upsert (crear y editar), no dos.\n    - [ ] Editar pre-puebla el formulario con el producto elegido.\n    - [ ] Errores de validacion visibles; toast de exito al guardar.\n\n## Alcance (slice vertical)\nAgrega `upsert_producto` (form) y el formulario en la pantalla existente. NO incluye borrado ni filtros.\n\n## Complejidad estimada\nmedium (5-8 archivos)."
    },
    {
      "id": "s3-delete",
      "title": "feat(productos): eliminar producto con confirmacion",
      "labels": ["feature", "scope:productos", "simple"],
      "blocked_by": ["s1-list"],
      "body": "## Objetivo\nEliminar productos con un dialogo de confirmacion para evitar borrados accidentales.\n\n## Pantalla\n- **Ruta**: `/productos`\n  - **Journey**: el usuario hace click en eliminar, confirma en el dialogo, y la fila desaparece.\n  - **Criterios de aceptacion (visuales)**:\n    - [ ] Dialogo de confirmacion antes de borrar.\n    - [ ] La fila se quita de la tabla al confirmar; toast de exito.\n\n## Alcance (slice vertical)\nAgrega `delete_producto` (command) + dialogo. NO toca el formulario ni los filtros.\n\n## Complejidad estimada\nsimple (3-4 archivos)."
    },
    {
      "id": "s4-filter",
      "title": "feat(productos): filtros y busqueda",
      "labels": ["feature", "scope:productos", "simple"],
      "blocked_by": ["s2-upsert", "s3-delete"],
      "body": "## Objetivo\nEncontrar productos rapido filtrando por categoria y texto.\n\n## Pantalla\n- **Ruta**: `/productos`\n  - **Journey**: el usuario escribe en la busqueda y/o elige categoria; la tabla se filtra en vivo.\n  - **Criterios de aceptacion (visuales)**:\n    - [ ] Busqueda por texto filtra la tabla en vivo (`$derived`, client-side <1000 items).\n    - [ ] Selector de categoria filtra la tabla.\n    - [ ] Estado del filtro reflejado en la URL.\n\n## Alcance (slice vertical)\nFiltrado client-side sobre el listado ya existente. Depende de tener alta y borrado para tener datos que filtrar.\n\n## Complejidad estimada\nsimple (1-3 archivos tocados)."
    }
  ]
}
```

## Template de cuerpo de issue

Estructura minima que satisface a b1-triage (entidad, operacion, scope, criterios) y a b2/b7 (pantallas con ruta + journey + acceptance):

```markdown
## Objetivo
<1-2 lineas: que obtiene el usuario; el "para que" real, no la frase literal>

## Entidad / datos
<entidades REALES del codebase (tablas Drizzle, campos clave). Si hay que crear schema, decirlo.>

## Pantalla(s)
- **Ruta**: `/<feature>`
  - **Journey**: <usuario entra a X, hace Y, ve Z>
  - **Criterios de aceptacion (visuales)**:
    - [ ] ...
    - [ ] ...

## Alcance (slice vertical)
<que entra en ESTE slice y que queda explicitamente para otro>

## Complejidad estimada
simple | medium  (simple = 3-5 archivos, medium = 5-8)
```

Reglas del body:

- **No** escribir `## Blocked by` ni `#numeros` aqui — las deps van en `blocked_by` (slice-ids) del plan; el script las inyecta resolviendo a numeros reales.
- Slice **backend puro** (sin pantalla): reemplazar `## Pantalla(s)` por `## Remote functions / endpoints` con los criterios de aceptacion no-visuales. b7 corre igual con `screens: []`.
- Idioma del body = idioma de la conversacion (lo posta b1 al reportero en su idioma; manten coherencia).
- Titulo en conventional: `feat(scope): …`, `fix(scope): …`, `enhancement` para mejoras de algo existente.
