# Slice Spec — fuente única del layout vertical-slice

Esta es la definición canónica de la arquitectura que el pipeline construye y revisa.
Todos los skills (b0 slicing, b1 triage, b2 build, b6 review, b7 orquestación, b8 swarm)
apuntan acá. Si otra instrucción contradice este archivo, gana este archivo.

## Objetivos (por qué vertical slices)

1. **Todo el feature en UNA carpeta del filesystem** — evita confusión, evita cruce
   entre features, mantiene el contexto de trabajo acotado a una carpeta.
2. **Debug simple** — un error en la pantalla X se investiga en la carpeta X
   (empezando por su doc colocada, ver abajo).
3. **Optimización recurrente por pantalla** — cada slice se puede revisar, medir y
   refactorizar de forma aislada sin tocar el resto.

Calidad transversal exigida en todo slice: **cero duplicidad, cero código muerto,
funciones simples, one-liners donde alcance** (ver simplicity-ladder.md).

## La regla 99%

El **99% del código del feature vive en su carpeta de ruta** `src/routes/<feature>/`
(o dentro de un route group / param: `src/routes/(app)/<feature>/`,
`src/routes/[country]/<feature>/` — la constante es UNA carpeta):

```
src/routes/<feature>/
  +page.svelte                 # la pantalla (importa de ./ui/ y ./server/data.remote)
  +page.server.ts              # guard de permiso (opcional); load() solo según la regla de datos
  +page.ts / +layout.svelte / +error.svelte   # solo los que apliquen
  server/
    data.remote.ts             # TODO el manejo de datos del feature (query/form/command + reglas de negocio)
  ui/
    <Componente>.svelte        # componentes del feature, PascalCase
  docs/
    <feature>.md               # doc del feature (primera parada de debug — ver abajo)
  tests/
    *.test.ts                  # tests del feature
  new/ , [id]/                 # sub-rutas con su +page.svelte; sus datos también salen de ../server/data.remote.ts
```

Ninguna subcarpeta es obligatoria — se crea cuando hay contenido (cero carpetas vacías). El INVARIANTE: todo el manejo de datos del feature vive en `server/data.remote.ts` — debuggear una query = revisar UN archivo, siempre el mismo path en cualquier feature.

Feature típico = 3-5 archivos, 15-35 KB. Más archivos = sospecha de over-engineering.

## Reglas de datos (`server/data.remote.ts`)

- **SQL-first**: filtros, group by, agregaciones, promedios y aritmética se resuelven EN SQL (Drizzle); JavaScript solo lo mínimo justificable (presentación, mapeos triviales). Si el JS re-filtra o re-suma lo que SQL puede hacer, está mal.
- **Remote functions por default**: type-safe, se llaman desde cualquier parte, corren siempre en server (acceso seguro a env vars y cliente de db) y con async experimental se consumen con `await` directo en el componente.
- **`load()` es la excepción**: útil solo cuando un mismo dato se reparte a varios componentes de la ruta a la vez — pocos casos donde gana a una remote function. En la duda, remote function.

## El 1% permitido en `$lib` (excepciones taxativas)

| Que | Donde | Criterio |
| --- | --- | --- |
| Componentes shadcn-svelte | `$lib/components/ui/` | Libreria compartida, nunca del feature |
| Estilos globales / tokens | `src/app.css` | Paleta y tokens semánticos |
| Conexión y schema de DB | `$lib/server/db/` | Infra compartida |
| Transversales genuinos | `$lib/server/` o `$lib/` | logger, auth (`requireUser`/`requirePermission`), format, helpers usados por 3+ features SIN lógica de negocio de ningún feature |

Test rápido: si la función conoce reglas de UN feature, NO es transversal — vive en
la carpeta del feature. Si la usan 3+ features y es genérica (formatear fecha,
loggear, validar sesión), va en `$lib`.

Prohibiciones que se mantienen siempre:
- Ningun `*.remote.ts` fuera de `server/` del feature: ni suelto en la raíz de la ruta
  (patrón anterior `<feature>.remote.ts`), ni bajo `src/lib/server/` (el cliente lo importa).
- El archivo remote es `server/data.remote.ts` — UNO por feature; partirlo recién cuando
  el tamaño lo exija de verdad, y siempre dentro de `server/`.
- Sin capa service para CRUD simple: remote function consulta Drizzle directo.

## Tolerancia legacy

Proyectos existentes pueden tener features bajo `src/lib/features/<feature>/` (patrón
viejo) o con el layout colocado anterior (`<feature>.remote.ts` y componentes sueltos
en la raíz de la ruta). Regla:

- **Editar un feature legacy**: OK — seguir el patrón interno que ese feature ya usa.
  No migrar de layout como parte de un fix/feature chico (eso es un issue propio).
- **Crear un feature NUEVO**: SIEMPRE con el layout de arriba. Prohibido crear features
  nuevos bajo `src/lib/features/`.
- Migrar un legacy al layout canónico es un issue explícito o el peldaño E2 de
  b-setup-or-fix, nunca un efecto colateral.

## Doc del feature: `docs/<feature>.md` (primera parada de debug)

Cada feature nuevo incluye un `docs/<feature>.md` con:

- **Propósito** (2-3 líneas, lenguaje de usuario)
- **Pantallas y rutas** (qué se ve, dónde)
- **Remote functions** (nombre + una línea de contrato cada una)
- **Datos** (tablas/vistas que toca)
- **Decisiones** (por qué se hizo así, atajos `ponytail:` relevantes)
- **Problemas conocidos**

Al debuggear un feature, leer su `.md` ANTES de grep/exploración. Al modificar un
feature que ya tiene `.md`, actualizarlo en el mismo PR si el cambio altera contratos
o pantallas. Features legacy: generar el `.md` la primera vez que un issue los toque.

## Checklist de conformidad (para review — b6 Area 2)

1. Archivos nuevos del feature dentro de `src/routes/<feature>/` (o el legacy que ya
   habitaba, si el issue edita un legacy).
2. Nada nuevo bajo `src/lib/features/`.
3. Manejo de datos NUEVO solo en `server/data.remote.ts`; SQL-first (filtros y
   agregaciones en la query, no en JS); `load()` nuevo solo con la excepción declarada.
4. Todo lo agregado a `$lib` cae en una fila de la tabla de excepciones (si no: mover
   al slice o justificar como transversal 3+ features).
5. Sin duplicados: la funcion nueva no re-implementa un helper existente.
6. Sin codigo muerto: exports nuevos tienen consumidor; helpers que quedaron sin
   callers tras el cambio se eliminan.
7. Feature nuevo trae su `docs/<feature>.md`; feature tocado con contratos cambiados lo
   actualiza.
