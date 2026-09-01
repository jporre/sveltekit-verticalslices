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
  +page.server.ts              # solo guard/redirect de ruta (opcional); nunca load() para datos
  +page.ts / +layout.svelte / +error.svelte   # solo los que apliquen; siempre .ts, nunca .js
  server/
    data.remote.ts             # TODO el manejo de datos del feature (query/form/command + reglas de negocio)
    *.server.ts                # otra lógica server-only: sufijo .server.ts OBLIGATORIO (ver prohibiciones)
  ui/
    <Componente>.svelte        # componentes del feature, PascalCase
  data/
    *.ts                       # constantes estructurales (`as const`); schemas.ts si el cliente los necesita
  docs/
    readme.md                  # doc del feature (primera parada de debug — ver abajo)
    comments.md                # opcional: el porqué de código no obvio, anclado por símbolo
  tests/
    *.test.ts | *.svelte.test.ts | *.e2e.ts   # planos; el sufijo decide el runner (Node | Chromium | Playwright)
  new/ , [id]/                 # sub-rutas: solo sus archivos +; las subcarpetas viven únicamente en la raíz del feature
```

Ninguna subcarpeta es obligatoria — se crea cuando hay contenido (cero carpetas vacías). El INVARIANTE: todo el manejo de datos del feature vive en `server/data.remote.ts` — debuggear una query = revisar UN archivo, siempre el mismo path en cualquier feature.

Feature típico = 3-5 archivos, 15-35 KB. Más archivos = sospecha de over-engineering.

## Reglas de datos (`server/data.remote.ts`)

- **SQL-first**: filtros, group by, agregaciones, promedios y aritmética se resuelven EN SQL (Drizzle); JavaScript solo lo mínimo justificable (presentación, mapeos triviales). Si el JS re-filtra o re-suma lo que SQL puede hacer, está mal. **Carve-out**: SQL-first aplica a agregaciones, orden y filtros sobre datasets grandes; listas <1000 items se filtran/ordenan en cliente con `$derived` (AP14) — no fuerces una query por cada interacción de UI.
- **Prohibido `event.fetch`**: la remote function llama a Drizzle o a un cliente API directo, NUNCA a otro endpoint propio vía HTTP (ni `event.fetch` en load, ni fetch server-side interno). Es la misma capa de indirección prohibida al cliente, en su variante server.
- **Remote functions por default**: type-safe, se llaman desde cualquier parte, corren siempre en server (acceso seguro a env vars y cliente de db) y con async experimental se consumen con `await` directo en el componente.
- **`load()` no se usa para datos**: la deduplicación de queries por request hace gratis compartir una misma `query` entre componentes y páginas (el caso que antes justificaba `load`). `+page.server.ts` queda solo para guard/redirect de ruta; `+server.ts` solo para consumidores externos (webhooks, apps móviles) — nunca para datos internos.

## Data local y schemas (`data/`)

- **Constantes estructurales** del feature (opciones de select, labels de estados, config fija) en `data/*.ts`, tipadas `as const`. Si el negocio quiere editarla sin deploy → base de datos vía remote function; si 3+ features la importan → `$lib`.
- **Schemas (zod, único validador)**: inline en `data.remote.ts` por default. Se extraen a `data/schemas.ts` cuando un componente cliente también los necesita — son isomórficos a propósito: nunca en `server/` (el cliente no podría importarlos).

## Frontera entre features

- `server/data.remote.ts` es la **API pública** del feature: cualquier feature puede importar sus remote functions (traen guard adentro, el cliente recibe stubs, la deduplicación hace gratis el uso compartido).
- Todo lo demás es **privado**: `ui/`, `data/`, `server/*.server.ts`, `tests/`. Si otro feature lo necesita, se gradúa a `$lib` (regla 3+) o el corte de features está mal.
- Los tests del feature solo importan del propio feature o de `$lib` — importar de otro feature delata acoplamiento.
- Regla memorizable: *un feature conversa con otro solo a través de sus remote functions.*

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
- Todo archivo en `server/` que no sea `*.remote.ts` lleva sufijo `.server.ts`
  (`pdf.server.ts`, `calculos.server.ts`): el sufijo activa el enforcement server-only
  del compilador — la carpeta sola NO protege nada; un import accidental desde un
  componente se iría al bundle del cliente en silencio.
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

## Doc del feature: `docs/readme.md` (primera parada de debug)

Cada feature nuevo incluye un `docs/readme.md` con:

- **Propósito** (2-3 líneas, lenguaje de usuario)
- **Pantallas y rutas** (qué se ve, dónde)
- **Remote functions** (nombre + una línea de contrato cada una)
- **Datos** (tablas/vistas que toca)
- **Decisiones** (por qué se hizo así, atajos `ponytail:` relevantes)
- **Problemas conocidos**

El nombre es fijo (`readme.md`, mismo path en todo feature — el mismo argumento que
`data.remote.ts`) y GitHub lo renderiza solo al navegar la carpeta. `docs/comments.md`
es opcional: el porqué de código no obvio, anclado por nombre de símbolo (nunca por
número de línea — se pudre con el primer refactor). No existe changelog local: git es
el changelog (`git log --follow src/routes/<feature>/`).

Al debuggear un feature, leer su `readme.md` ANTES de grep/exploración. Al modificar un
feature que ya lo tiene, actualizarlo en el mismo PR si el cambio altera contratos
o pantallas. Features legacy: generar el `readme.md` la primera vez que un issue los toque.

## Checklist de conformidad (para review — b6 Area 2)

1. Archivos nuevos del feature dentro de `src/routes/<feature>/` (o el legacy que ya
   habitaba, si el issue edita un legacy).
2. Nada nuevo bajo `src/lib/features/`.
3. Manejo de datos NUEVO solo en `server/data.remote.ts`; SQL-first (filtros y
   agregaciones en la query, no en JS); sin `load()` nuevo para datos
   (`+page.server.ts` solo guard/redirect).
4. Todo lo agregado a `$lib` cae en una fila de la tabla de excepciones (si no: mover
   al slice o justificar como transversal 3+ features).
5. Sin duplicados: la funcion nueva no re-implementa un helper existente.
6. Sin codigo muerto: exports nuevos tienen consumidor; helpers que quedaron sin
   callers tras el cambio se eliminan.
7. Feature nuevo trae su `docs/readme.md`; feature tocado con contratos cambiados lo
   actualiza.
8. Imports entre features solo desde `server/data.remote.ts` ajeno (API pública);
   nada de `ui/`, `data/` ni `server/*.server.ts` de otro feature. Archivos nuevos
   en `server/` que no son remote llevan sufijo `.server.ts`.
