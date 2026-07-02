# Slice Spec — fuente unica del layout vertical-slice

Esta es la definicion canonica de la arquitectura que el pipeline construye y revisa.
Todos los skills (b0 slicing, b1 triage, b2 build, b6 review, b7 orquestacion, b8 swarm)
apuntan aca. Si otra instruccion contradice este archivo, gana este archivo.

## Objetivos (por que vertical slices)

1. **Todo el feature en UNA carpeta del filesystem** — evita confusion, evita cruce
   entre features, mantiene el contexto de trabajo acotado a una carpeta.
2. **Debug simple** — un error en la pantalla X se investiga en la carpeta X
   (empezando por su doc colocada, ver abajo).
3. **Optimizacion recurrente por pantalla** — cada slice se puede revisar, medir y
   refactorizar de forma aislada sin tocar el resto.

Calidad transversal exigida en todo slice: **cero duplicidad, cero codigo muerto,
funciones simples, one-liners donde alcance** (ver simplicity-ladder.md).

## La regla 99%

El **99% del codigo del feature vive en su carpeta de ruta** `src/routes/<feature>/`
(o dentro de un route group / param: `src/routes/(app)/<feature>/`,
`src/routes/[country]/<feature>/` — la constante es UNA carpeta):

```
src/routes/<feature>/
  +page.svelte                 # la pantalla (UI aqui; importa componentes hermanos)
  +page.server.ts              # load + guard de permiso (opcional pero recomendado)
  <feature>.remote.ts          # query/form/command + reglas de negocio simples
  <feature>-types.ts           # tipos (o exportarlos desde <feature>.remote.ts)
  <Feature>Form.svelte         # componentes hermanos, planos, PascalCase (sin subcarpeta ui/)
  schemas.ts                   # solo si la validacion es compleja
  <feature>.server.ts          # logica compleja (solo si aplica)
  <feature>.md                 # doc del feature (primera parada de debug — ver abajo)
  new/ , [id]/                 # sub-rutas con su propio +page.svelte (y *.remote.ts si aplica)
```

Feature tipico = 3-5 archivos, 15-35 KB. Mas archivos = sospecha de over-engineering.

## El 1% permitido en `$lib` (excepciones taxativas)

| Que | Donde | Criterio |
| --- | --- | --- |
| Componentes shadcn-svelte | `$lib/components/ui/` | Libreria compartida, nunca del feature |
| Estilos globales / tokens | `src/app.css` | Paleta y tokens semanticos |
| Conexion y schema de DB | `$lib/server/db/` | Infra compartida |
| Transversales genuinos | `$lib/server/` o `$lib/` | logger, auth (`requireUser`/`requirePermission`), format, helpers usados por 3+ features SIN logica de negocio de ningun feature |

Test rapido: si la funcion conoce reglas de UN feature, NO es transversal — vive en
la carpeta del feature. Si la usan 3+ features y es generica (formatear fecha,
loggear, validar sesion), va en `$lib`.

Prohibiciones que se mantienen siempre:
- Ningun `*.remote.ts` bajo `src/lib/server/` (el cliente lo importa).
- Archivo remote nombrado `<feature>.remote.ts`, nunca el generico `data.remote.ts`.
- Sin capa service para CRUD simple: remote function consulta Drizzle directo.

## Tolerancia legacy (`src/lib/features/`)

Proyectos existentes pueden tener features bajo `src/lib/features/<feature>/`
(patron anterior). Regla:

- **Editar un feature legacy**: OK — seguir el patron interno que ese feature ya usa.
  No migrar de carpeta como parte de un fix/feature chico (eso es un issue propio).
- **Crear un feature NUEVO**: SIEMPRE colocado en `src/routes/<feature>/`. Prohibido
  crear features nuevos bajo `src/lib/features/`.
- Migrar un legacy a slice colocado es un issue explicito, nunca un efecto colateral.

## Doc del feature: `<feature>.md` (primera parada de debug)

Cada feature nuevo incluye un `<feature>.md` colocado con:

- **Proposito** (2-3 lineas, lenguaje de usuario)
- **Pantallas y rutas** (que se ve, donde)
- **Remote functions** (nombre + una linea de contrato cada una)
- **Datos** (tablas/vistas que toca)
- **Decisiones** (por que se hizo asi, atajos `ponytail:` relevantes)
- **Problemas conocidos**

Al debuggear un feature, leer su `.md` ANTES de grep/exploracion. Al modificar un
feature que ya tiene `.md`, actualizarlo en el mismo PR si el cambio altera contratos
o pantallas. Features legacy: generar el `.md` la primera vez que un issue los toque.

## Checklist de conformidad (para review — b6 Area 2)

1. Archivos nuevos del feature dentro de `src/routes/<feature>/` (o el legacy que ya
   habitaba, si el issue edita un legacy).
2. Nada nuevo bajo `src/lib/features/`.
3. Todo lo agregado a `$lib` cae en una fila de la tabla de excepciones (si no: mover
   al slice o justificar como transversal 3+ features).
4. Sin duplicados: la funcion nueva no re-implementa un helper existente.
5. Sin codigo muerto: exports nuevos tienen consumidor; helpers que quedaron sin
   callers tras el cambio se eliminan.
6. Feature nuevo trae su `<feature>.md`; feature tocado con contratos cambiados lo
   actualiza.
