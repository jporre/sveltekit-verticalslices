# Comment Templates

Full examples for the evaluation comment posted in Step 7 of `b1-triage-issue`. The compact structure lives in `SKILL.md`. This file extends it with one fully-worked example per classification, in both Spanish and English where useful. Read this file only when actually drafting the comment.

## Ready issue (Spanish)

```markdown
## Evaluacion de Issue

**Estado**: Listo para desarrollo

### Entendimiento

Se solicita una pantalla CRUD para gestionar productos. Los comments #3 y #5 acotaron el alcance: incluir filtro por categoria y estado activo/inactivo, no estaba en el body original.

### Archivos afectados

- `src/lib/server/db/schema.ts` — tabla `taProducts` ya existe
- `src/routes/products/` — carpeta del feature (pagina + remote + componentes)

### Complejidad estimada

**Simple** — 1 entidad, 1 pantalla, CRUD estandar (3-4 archivos).

### Riesgos

- **perms**: ruta nueva requiere alta en `app.route_permissions` + assignment, o el guard del layout redirige a fallback.

### Plan propuesto

1. Crear `products.remote.ts` con `get_products`, `upsert_product`, `delete_product` (exporta tipos via `InferSelectModel`).
2. Crear `+page.svelte` con tabla y formulario upsert.
3. (Opcional) `+page.server.ts` con guard de permiso.
4. Verificar en navegador.
```

## Ready issue (English)

```markdown
## Issue Evaluation

**Status**: Ready for development

### Understanding

User wants a CRUD screen for products. Comments #3 and #5 narrowed the scope: include category and active-state filters (not in the original body).

### Affected files

- `src/lib/server/db/schema.ts` — `taProducts` table exists
- `src/routes/products/` — new feature folder (page + remote + components)

### Estimated complexity

**Simple** — 1 entity, 1 screen, standard CRUD (3-4 files).

### Risks

- **perms**: new route needs entry in `app.route_permissions` + assignment, or the layout guard redirects to fallback.

### Plan

1. Create `products.remote.ts` with `get_products`, `upsert_product`, `delete_product` (export types via `InferSelectModel`).
2. Create `+page.svelte` with table and upsert form.
3. (Optional) `+page.server.ts` with a permission guard.
4. Browser verification.
```

## Needs-clarification issue (Spanish)

```markdown
## Evaluacion de Issue

**Estado**: Necesita información

### Entendimiento actual

Se quiere mejorar el flujo de "ventas". El body menciona un filtro nuevo pero no precisa la entidad ni qué columna filtrar.

### Investigación previa

Existen dos tablas relevantes:
- `taVentas` (cabecera de venta)
- `taVentasDetalle` (líneas de venta)

La pantalla actual `src/routes/sales/+page.svelte` ya filtra por fecha y vendedor.

### Preguntas

1. ¿La pantalla a modificar es `SalesPage` o una pantalla nueva?
2. ¿El filtro aplica a la cabecera (`taVentas`) o a las líneas (`taVentasDetalle`)?
3. ¿Qué columna(s) deben filtrarse y con qué tipo de control (select, fecha, texto)?
4. ¿Hay criterios de aceptación: cantidad mínima de filtros, exportable, etc.?
```

## Duplicate issue (Spanish)

```markdown
## Evaluacion de Issue

**Estado**: Duplicado

Esta solicitud ya fue cubierta por #142 (mergeado en `master` el 2026-04-15) que agregó la pantalla `src/routes/products/+page.svelte`. Recomiendo cerrar este issue referenciando #142.

Si hay diferencias específicas con la implementación actual, por favor descríbelas y reabriremos.
```

## Blocked issue (Spanish)

```markdown
## Evaluacion de Issue

**Estado**: Bloqueado

Depende de #87 (refactor de `auth-middleware`), aún en progreso. Sin ese cambio, los nuevos endpoints no podrán validar permisos correctamente.

Sugerencia: marcar este issue como `blocked` hasta que #87 mergee, o reducir el alcance a la parte de UI que no toca permisos.
```

## Risk-flag phrasing (reusable bullets)

Cuando el checklist de Step 5 dispare, usar redacciones como estas para mantener consistencia en los comments:

- **security**: validar `requireUser` / `requirePermission` + error estructurado (`AUTH_REQUIRED`, `FORBIDDEN`).
- **data**: requiere Zod schema; si cambia tabla, incluir migración Drizzle y revisar impacto en `app.route_permissions`.
- **perms**: ruta nueva requiere alta en `app.route_permissions` + assignment, o el guard del layout redirige a fallback.
- **docs**: actualizar `docs/` (o un markdown colocado en la carpeta del feature) y agregar entrada al `CHANGELOG`.
