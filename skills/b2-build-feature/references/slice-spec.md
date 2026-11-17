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

## Estructura: un feature es una carpeta de rutas

Un feature vive completo en su carpeta bajo `src/routes/` (o dentro de un route group / param:
`src/routes/(app)/<feature>/`, `src/routes/[country]/<feature>/` — la constante es UNA carpeta).
La mayoría de los features son dos archivos:

```
src/routes/<feature>/
  +page.svelte      pantalla: markup y componentes
  data.remote.ts    remote functions: toda la lectura y escritura de datos del feature
```

Otros archivos se agregan en la misma carpeta solo cuando hacen falta:

| Archivo                                     | Cuándo se justifica                                                                 |
| ------------------------------------------- | ----------------------------------------------------------------------------------- |
| `NombreComponente.svelte`                   | Un bloque se repite dentro del feature, o `+page.svelte` ya no se lee de una pasada |
| `schemas.ts`                                | El cliente necesita el schema zod (validación `preflight` de un formulario)         |
| `nombre.server.ts`                          | Lógica de servidor que no cabe con claridad en `data.remote.ts`                     |
| `*.spec.ts`, `*.svelte.spec.ts`, `*.e2e.ts` | Tests, junto al archivo que prueban                                                 |
| `README.md`                                 | Hay una decisión o un porqué que el código no explica                               |

Reglas:

- **`src/lib/` es solo para lo que usan 3 o más features.** Con dos consumidores, el segundo importa desde la carpeta del primero. Con el tercero, el código se mueve a `src/lib/`. La infraestructura transversal ya vive ahí: `src/lib/server/db.ts`, `src/lib/server/auth.ts`, `src/lib/server/auth-guards.ts`, `src/lib/auth-client.ts`.
- **Sin `load()`.** No crear `+page.server.ts`, `+layout.server.ts` ni `+page.ts` para traer datos: los datos llegan por remote functions. `+server.ts` solo para lo que una remote function no puede servir: webhooks, callbacks de OAuth, binarios, healthcheck, sitemap.
- **Código de servidor con sufijo `.server.ts`.** Dentro de `src/routes/`, una carpeta `server/` no protege nada: SvelteKit 3 solo trata `server/` como exclusiva de servidor fuera de `src/routes`. El sufijo sí hace fallar el build si el cliente importa el archivo.
- **Siempre `.ts`, nunca `.js`.**

La carpeta es plana: sin subcarpetas `server/`, `ui/`, `data/`, `docs/` ni `tests/`. Las únicas
subcarpetas son sub-rutas (`new/`, `[id]/`) con sus archivos `+`; sus datos salen del
`data.remote.ts` de la raíz del feature (`../data.remote`).

El INVARIANTE: todo el manejo de datos del feature vive en `data.remote.ts` — debuggear una
query = revisar UN archivo, siempre el mismo path en cualquier feature.

Feature típico = 2-4 archivos. Más archivos = sospecha de over-engineering.

**Protección de páginas.** El guard de página vive en `hooks.server.ts` (compara
`event.route.id`), no en un `load`. Los datos se protegen con el guard dentro de cada remote
function. Detalle: `sveltekit-3-remote-functions.md`, sección "Autenticación y autorización".

## Reglas de datos (`data.remote.ts`)

- **SQL-first**: filtros, group by, agregaciones, promedios y aritmética se resuelven EN SQL (Drizzle); JavaScript solo lo mínimo justificable (presentación, mapeos triviales). Si el JS re-filtra o re-suma lo que SQL puede hacer, está mal. **Carve-out**: SQL-first aplica a agregaciones, orden y filtros sobre datasets grandes; listas <1000 items se filtran/ordenan en cliente con `$derived` (AP14) — no fuerces una query por cada interacción de UI.
- **Prohibido `event.fetch`**: la remote function llama a Drizzle o a un cliente API directo, NUNCA a otro endpoint propio vía HTTP (ni `event.fetch` en load, ni fetch server-side interno). Es la misma capa de indirección prohibida al cliente, en su variante server.
- **Remote functions por default**: type-safe, se llaman desde cualquier parte, corren siempre en server (acceso seguro a env vars y cliente de db) y con async experimental se consumen con `await` directo en el componente.
- **`load()` no se usa para datos**: la deduplicación de queries por request hace gratis compartir una misma `query` entre componentes y páginas (el caso que antes justificaba `load`). No se crean `+page.server.ts`, `+layout.server.ts` ni `+page.ts`; `+server.ts` solo para consumidores externos (webhooks, callbacks de OAuth, binarios, healthcheck, sitemap) — nunca para datos internos.

## Constantes y schemas

- **Constantes estructurales** del feature (opciones de select, labels de estados, config fija) en un `.ts` de la carpeta del feature, tipadas `as const`. Si el negocio quiere editarla sin deploy → base de datos vía remote function; si 3+ features la importan → `$lib`.
- **Schemas (zod, único validador)**: inline en `data.remote.ts` por default. Se extraen a `schemas.ts` cuando un componente cliente también los necesita (validación `preflight`) — son isomórficos a propósito: nunca se exportan desde `data.remote.ts` ni desde un `.server.ts`.

## Frontera entre features

- `data.remote.ts` es la **API pública** del feature: cualquier feature puede importar sus remote functions (traen guard adentro, el cliente recibe stubs, la deduplicación hace gratis el uso compartido).
- Todo lo demás es **privado** mientras lo use un solo feature. Con un segundo consumidor, ese feature importa desde la carpeta del primero; con el tercero, el código se mueve a `$lib` (regla 3+).

## Lo permitido en `$lib` (excepciones taxativas)

| Que | Donde | Criterio |
| --- | --- | --- |
| Componentes shadcn-svelte | `$lib/components/ui/` | Libreria compartida, nunca del feature |
| Estilos globales / tokens | `src/app.css` | Paleta y tokens semánticos |
| Conexión y schema de DB | `$lib/server/db.ts` (o `$lib/server/db/`) | Infra compartida |
| Auth | `$lib/server/auth.ts`, `$lib/server/auth-guards.ts`, `$lib/auth-client.ts` | Infra compartida (`requireUser`/`requirePermission`) |
| Transversales genuinos | `$lib/server/` o `$lib/` | logger, format, helpers usados por 3+ features SIN lógica de negocio de ningún feature |

Test rápido: si la función conoce reglas de UN feature, NO es transversal — vive en
la carpeta del feature. Si la usan 3+ features y es genérica (formatear fecha,
loggear, validar sesión), va en `$lib`.

Prohibiciones que se mantienen siempre:
- Ningún `*.remote.ts` bajo `src/lib/server/` (el cliente lo importa).
- El archivo remote es `data.remote.ts` en la raíz del feature — UNO por feature; partirlo
  recién cuando el tamaño lo exija de verdad (`<nombre>.remote.ts` en la misma carpeta).
- Ninguna carpeta `server/` nueva dentro de `src/routes/`: no protege nada. El código
  server-only que no es remote lleva sufijo `.server.ts` (`pdf.server.ts`,
  `calculos.server.ts`); un import accidental desde un componente hace fallar el build.
- Sin capa service para CRUD simple: remote function consulta Drizzle directo.

## Tolerancia legacy

Proyectos existentes pueden tener features con un layout anterior: bajo
`src/lib/features/<feature>/`, con `<feature>.remote.ts` suelto, o con subcarpetas
`server/data.remote.ts`, `ui/`, `data/`, `docs/readme.md` y `tests/`. Regla:

- **Editar un feature legacy**: OK — seguir el patrón interno que ese feature ya usa.
  No migrar de layout como parte de un fix/feature chico (eso es un issue propio).
- **Crear un feature NUEVO**: SIEMPRE con el layout de arriba. Prohibido crear features
  nuevos bajo `src/lib/features/` o con subcarpeta `server/`.
- Migrar un legacy al layout canónico es un issue explícito o el peldaño E2 de
  b-setup-or-fix, nunca un efecto colateral.

## Doc del feature: `README.md` (solo si hay un porqué)

El `README.md` no es obligatorio. Se escribe cuando hay una decisión o un porqué que el
código no explica (regla de negocio no obvia, atajo `ponytail:` con techo, problema conocido).
Va en la raíz de la carpeta del feature y GitHub lo renderiza solo. No repite lo que el código
ya dice (lista de remote functions, tablas). No existe changelog local: git es el changelog
(`git log --follow src/routes/<feature>/`).

Al debuggear un feature, leer su `README.md` si existe ANTES de grep/exploración. Al modificar
un feature que ya lo tiene, actualizarlo en el mismo PR si el cambio invalida lo que dice.

## Checklist de conformidad (para review — b6 Area 2)

1. Archivos nuevos del feature dentro de `src/routes/<feature>/`, planos en la carpeta (o
   el legacy que ya habitaba, si el issue edita un legacy).
2. Nada nuevo bajo `src/lib/features/`; ninguna carpeta `server/` nueva dentro de `src/routes/`.
3. Manejo de datos NUEVO solo en `data.remote.ts`; SQL-first (filtros y agregaciones en la
   query, no en JS); sin `+page.server.ts`, `+layout.server.ts` ni `+page.ts` nuevos para datos.
4. Todo lo agregado a `$lib` cae en una fila de la tabla de excepciones o lo usan 3+ features
   (si no: mover al feature).
5. Sin duplicados: la función nueva no re-implementa un helper existente.
6. Sin código muerto: exports nuevos tienen consumidor; helpers que quedaron sin
   callers tras el cambio se eliminan.
7. Código server-only que no es remote lleva sufijo `.server.ts`. Archivos nuevos en `.ts`,
   nunca `.js`.
8. Tests junto al archivo que prueban (`*.spec.ts`, `*.svelte.spec.ts`, `*.e2e.ts`).
