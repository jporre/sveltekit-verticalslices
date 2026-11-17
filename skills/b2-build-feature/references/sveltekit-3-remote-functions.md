---
schema_version: 1
document_type: "agent-instructions"
title: "SvelteKit 3 con remote functions"
updated_at: "2026-11-17"
language: "es"
---

# SvelteKit 3 con remote functions

Instrucciones reutilizables para proyectos SvelteKit 3 y Svelte 5. Copiar como `AGENTS.md` en el proyecto de aplicación o enlazar desde su archivo de instrucciones. Este documento no cambia la configuración del repositorio BNEX.

> **Uso dentro del plugin.** Esta guía es la referencia de prácticas (seguridad, caché, formularios, SSR, producción). La tabla de cambios de sintaxis SK2 → SK3 vive en `sveltekit-3.md`. El layout del feature es el de `slice-spec.md`: carpeta plana con `+page.svelte` y `data.remote.ts`. El contrato de errores del plugin se conserva: `error(status, 'mensaje', { code })`. No se crean `+page.server.ts`, `+layout.server.ts` ni `+page.ts`: el guard de página vive en `hooks.server.ts` y el de datos dentro de cada remote function.

## Antes de cambiar código

1. Leer `package.json`, lockfile, configuración Vite y convenciones existentes. Confirmar versiones instaladas, adaptador y entorno de ejecución.
2. Consultar [índice para LLMs](https://svelte.dev/docs/llms) y [documentación completa de Kit](https://svelte.dev/docs/kit/llms.txt) cuando se toque una API experimental o una migración. Leer la sección completa y sus advertencias. El texto comprimido puede omitir restricciones.
3. Aplicar reglas de la versión instalada. Si el proyecto sigue en v2, separar la migración de la funcionalidad solicitada. No mezclar recetas v2 y v3.
4. Usar remote functions para datos de interfaz. No introducir `load`, form actions tradicionales ni endpoints HTTP que dupliquen una remote function. Reservar `+server.ts` para contratos HTTP reales, como webhooks, integraciones externas o descargas que requieren control de respuesta.

Las APIs experimentales pueden cambiar incluso entre versiones menores. Conservar lockfile y revisar cambios antes de actualizar. Las reglas de seguridad de esta guía son obligatorias. Las optimizaciones requieren un caso concreto y medición.

## Base de v3

Fuente: [migración a SvelteKit 3](https://svelte.dev/docs/kit/migrating-to-sveltekit-3).

- La guía v3 consultada exige Node 22.17, TypeScript 6, Svelte 5.57.1, Vite 8.0.12 y `@sveltejs/vite-plugin-svelte` 7 como mínimos. Verificar requisitos al actualizar.
- Configurar en `vite.config.ts`, pasando opciones a `sveltekit`. `svelte.config.js` deja de admitirse. Opciones antes bajo `kit` pasan al nivel principal del plugin.
- Habilitar `experimental.remoteFunctions` y `compilerOptions.experimental.async`. Remote functions y expresiones `await` siguen siendo experimentales.
- Declarar alias `#lib` mediante `package.json#imports`. Usar extensiones de archivo en esos imports. `$lib` deja de generarse automáticamente.
- Usar `$app/state` en lugar de `$app/stores`, eliminado en v3. Usar `$app/env` en lugar de `$app/environment`.
- Definir variables en `src/env.ts` con `defineEnvVars` de `@sveltejs/kit/env`. Importar mediante `$app/env/private` o `$app/env/public`. Exponer únicamente variables declaradas con `public: true`.
- Extender `$app/tsconfig` y declarar `include` y `exclude`. No copiar la configuración generada de v2.
- Importar tipos de hooks desde `@sveltejs/kit/hooks` y tipos remotos desde `$app/server`.

Configuración mínima ilustrativa. Integrar con adaptador y opciones del proyecto:

```ts
import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vite';

export default defineConfig({
  plugins: [
    sveltekit({
      experimental: { remoteFunctions: true },
      compilerOptions: { experimental: { async: true } }
    })
  ]
});
```

## Autenticación y autorización

Fuentes: [auth](https://svelte.dev/docs/kit/auth), [autenticación en remote functions](https://svelte.dev/docs/kit/remote-functions#Implications-for-authentication), [contexto de petición](https://svelte.dev/docs/kit/remote-functions#Using-getRequestEvent).

- Resolver sesión en `handle` y guardar identidad verificada en `event.locals`. Cada remote function privada debe invocar un guard dentro de su callback, antes de leer o modificar datos. Compartir el helper, no omitir su llamada.
- Autorizar cada recurso y operación, además de autenticar. Derivar identidad y permisos de sesión validada. Tratar `id`, `userId`, `tenantId`, roles y campos ocultos enviados por cliente como entrada no confiable. Incluir restricciones de acceso en consultas y escrituras de base de datos.
- Para proteger páginas en hooks, comparar `event.route.id`, que identifica la ruta resuelta. `pathname.startsWith('/admin')` puede admitir `/%61dmin`. Incluir grupos y parámetros reales del identificador al definir rutas públicas. Tratar `route.id === null` de forma explícita.
- Un guard de rutas no protege por sí solo remote functions. Tampoco protegen datos ocultar botones, redirigir desde componentes o comprobar sesión en un layout.
- Dentro de `query`, `query.batch` y `query.live`, acceder a `event.url`, `event.params` o `event.route` lanza un error. Pasar slug, filtros y demás dependencias de navegación como argumentos validados.
- Dentro de `form` y `command`, esos campos describen la página llamante y son manipulables. Nunca usarlos para decidir permisos. En peticiones de queries, `handle` ve la URL del endpoint remoto, no la página.
- Obtener `getRequestEvent()` antes del primer `await` para compatibilidad con entornos sin `AsyncLocalStorage`. Conservar los datos necesarios en variables locales de la petición.
- Un helper compartido con `command` debe producir `error(401, 'Sesión requerida')`, no `redirect`. Los comandos no admiten `redirect`. `query` y `form` sí pueden redirigir cuando corresponde.
- Páginas prerenderizadas y archivos estáticos no pasan por `handle`. Mantener datos privados fuera de ambas salidas.
- Usar cookies de sesión con `httpOnly`, `secure` en producción y `sameSite` apropiado. Mantener alcance de dominio y ruta mínimo compatible con la aplicación. Para borrarlas, usar el mismo alcance con que se crearon.
- Al cerrar sesión o cambiar cuenta, organización o permisos, descartar o actualizar datos privados ya mostrados. La caché del cliente no representa una nueva autorización del servidor. Probar navegación atrás y queries todavía activas.

## Elegir la remote function

Fuente: [remote functions](https://svelte.dev/docs/kit/remote-functions).

| Necesidad | API | Restricción |
| --- | --- | --- |
| Lectura dinámica | `query` | Sin escrituras ni efectos secundarios de negocio. |
| Lecturas simultáneas por clave | `query.batch` | Agrupar también trabajo de base de datos. |
| Formulario | `form` | Preferir por su funcionamiento sin JavaScript. |
| Mutación fuera de formulario | `command` | Invocar desde interacción, nunca durante renderizado. |
| Datos públicos estables entre despliegues | `prerender` | Resultado publicado como archivo estático. |
| Datos en tiempo real | `query.live` | Comprobar soporte operativo para conexiones persistentes. |

- Colocar módulos `*.remote.ts` en `src`, fuera de directorios `server`. El navegador importa wrappers generados y el callback corre en servidor. Colocar clientes de base de datos, credenciales y helpers privados en módulos `server`.
- Toda remote function exportada genera una vía HTTP invocable por un atacante. TypeScript no valida peticiones.
- Validar argumentos con Standard Schema, usando biblioteca ya instalada. Validar también límites de longitud, tamaño de listas, paginación y valores permitidos. Reservar `'unchecked'` para casos documentados con validación equivalente dentro del callback.
- Devolver campos explícitos que necesita la interfaz. La ejecución en servidor no vuelve privados los valores devueltos, ni los datos incluidos en HTML de SSR.
- Mantener exports de módulos remotos limitados a APIs admitidas por Kit. Si un esquema se comparte con cliente para validación previa, exportarlo desde un módulo común, no desde `.remote.ts`.
- La serialización usa `devalue`, no solo JSON. Admite tipos como `Date` y `Map`. Para tipos personalizados, consultar `transport`; no convertir todo a JSON por costumbre.
- Remote functions no permiten establecer headers de respuesta. Solo `form` y `command` permiten escribir cookies. Usar hooks o endpoints específicos cuando el contrato requiera control HTTP.

## Caché, concurrencia y actualizaciones

Fuentes: [deduplicación](https://svelte.dev/docs/kit/remote-functions#query-Deduplication), [batch](https://svelte.dev/docs/kit/remote-functions#query.batch), [single-flight mutations](https://svelte.dev/docs/kit/remote-functions#Single-flight-mutations), [estado en servidor](https://svelte.dev/docs/kit/state-management#Avoid-shared-state-on-the-server).

- La caché de `query` se identifica por argumentos serializados. En servidor se limita a la petición. En cliente, consumidores con los mismos argumentos comparten instancia mientras esté en uso. No equivale a una caché persistente ni a sincronización entre usuarios.
- Pasar todas las dependencias de navegación como argumentos. Si cambia filtro o slug, derivar la nueva query de esos valores. Evitar capturar el valor inicial en un `const` que queda obsoleto al navegar.
- Objetos, `Map` y `Set` usados como argumentos de `query` y `prerender` se ordenan para calcular clave de caché. Si el orden cambia el significado, usar un array.
- Aprovechar deduplicación antes de agregar stores o una segunda biblioteca de caché. No copiar resultados a `$state` si basta con leer la query.
- Usar `query.batch` para listas con consultas por fila. El callback recibe entradas agrupadas y devuelve una función que resuelve cada entrada. Una consulta por entrada dentro del batch conserva el problema N+1. Mantener autorización para cada recurso.
- Lanzar operaciones independientes antes de esperarlas. Medir solicitudes y consultas SQL. Dos `$derived(await ...)` consecutivos pueden producir un waterfall en su primera ejecución, aunque sus actualizaciones posteriores sean independientes.
- Después de una mutación, actualizar queries afectadas desde el callback servidor mediante `.refresh()` o `.set(resultadoValidado)`. Kit incorpora actualizaciones en la misma respuesta. Hacerlo después de confirmar la transacción.
- `form` refresca todo por defecto. `command` no refresca automáticamente. Al llamar `.refresh()`, `.set()` o `.reconnect()` dentro de un `form`, se reemplaza el refresco global. Incluir todas las listas, detalles y contadores afectados.
- Refrescar la instancia con argumentos exactos. Actualizar `getItems()` no actualiza `getItems({ filter: 'active' })`. Si el cliente selecciona instancias mediante `.updates(...)`, el servidor debe aceptar consultas concretas mediante `requested(query, limiteFinito)`.
- Resolver cada entrada de `requested` con refresco, valor, reconexión o `ignore()`. Las entradas omitidas fallan en cliente. Mantener límites finitos porque el cliente controla cuántas solicita. Autorizar también las lecturas de refresco.
- Usar `.withOverride(...)` para actualización optimista cuando mejore interacción y exista recuperación ante fallo. El servidor sigue decidiendo resultado y permisos. Deshabilitar botones no evita duplicados externos, usar transacción o idempotencia cuando el negocio lo requiera.
- Reservar `refreshAll()` para cambios globales, por ejemplo sesión. En v3 reemplaza `invalidateAll()` y conserva `page.state`.
- Compartir pool de base de datos es válido. Compartir usuario actual, sesión, permisos o resultados privados en variables de módulo causa fugas entre peticiones. Usar `locals` o contexto por componente.

## Formularios

Fuente: [form](https://svelte.dev/docs/kit/remote-functions#form).

- Usar `<form {...miFormulario}>` y atributos generados con `miFormulario.fields.campo.as('text')`. En v3, un campo con `name` escrito manualmente provoca rechazo de la entrega.
- Usar API `.enhance(...)` de la instancia remota. No mezclarla con `use:enhance` de `$app/forms`, destinado a form actions tradicionales.
- En `.enhance`, invocar `form.submit()` y tratar su resultado booleano. Restablecer con `form.element.reset()` solo tras éxito cuando corresponda. El formulario personalizado no se limpia automáticamente.
- Usar `.for(idEstable)` cuando se repite un formulario por fila. Así cada instancia conserva sus valores, errores y estado pendiente.
- Prefijar campos sensibles con `_`, por ejemplo `_password`, para impedir que Kit los repueble en respuestas de validación sin JavaScript. Esto no los cifra ni sustituye HTTPS. Excluirlos también de resultados y logs.
- Los checkboxes sin marcar no envían valor. Esquema debe normalizar a `false`; selecciones múltiples vacías deben normalizarse según contrato, por ejemplo `[]`.
- Usar `invalid(...)` de `@sveltejs/kit` para errores de validación de negocio asociados a campos. La validación cliente mejora interacción, el servidor siempre vuelve a validar.
- Para validación cliente, usar `.preflight(esquema)` y mostrar `fields.campo.issues()` o `fields.allIssues()`. Ambos pueden devolver `undefined`. `.validate()` permite validar antes de enviar y `includeUntouched` controla campos todavía no editados.
- En archivos, usar `multipart/form-data` y validar tamaño, tipo permitido y contenido en servidor. Acotar tamaño total de petición en infraestructura y adaptador.
- Probar éxito, errores y redirect con JavaScript deshabilitado. Un `command` no ofrece esa degradación.

## SSR, reactividad y estados de espera

Fuentes: [await](https://svelte.dev/docs/svelte/await-expressions), [buenas prácticas Svelte](https://svelte.dev/docs/svelte/best-practices), [estado preservado](https://svelte.dev/docs/kit/state-management#Component-and-page-state-is-preserved).

- Mantener SSR como punto de partida. Usar queries directamente con `await` en componentes. No mover lectura inicial a `onMount` o `$effect`, porque pospone datos hasta cargar JavaScript y agrega un viaje de red.
- Elegir límites de espera conscientemente. Una `<svelte:boundary>` con snippet `pending` muestra ese snippet durante SSR y omite renderizar su contenido. Para contenido que debe estar en HTML inicial, permitir que SSR espere el `await` fuera de ese límite.
- `pending` cubre espera inicial. Para actualizaciones posteriores, usar estado de la query o `$effect.pending()` según contexto. Tratar también fallos, resultado vacío y reintento.
- Boundaries no capturan fallos arbitrarios de event handlers. Manejar errores de comandos en el handler correspondiente.
- Usar `$derived` para valores calculados y `$state` para estado editable. Evitar efectos que copian un estado en otro. `$effect` no corre durante SSR.
- SvelteKit reutiliza páginas y layouts entre navegaciones. Usar `$derived` para valores dependientes de props o parámetros. Probar pasar entre dos registros de la misma ruta dinámica sin recargar.
- Para arrays grandes que solo se reemplazan, considerar `$state.raw`; evita proxies profundos. Reasignar array u objeto al cambiarlo. No agregar `$state` a datos que no necesitan reactividad.
- Usar claves estables de entidad en `{#each}`, nunca índice para listas editables. Reservar `{#key}` para reinicio deliberado, porque destruye y recrea su contenido.
- Guardar filtros compartibles en URL, estado efímero de navegación en snapshots o `page.state`, y datos de negocio en servidor. En v3, copiar `page.url` con `new URL(page.url.href)` antes de modificarla.

## Seguridad de entrega y producción

Fuentes: [migración v3](https://svelte.dev/docs/kit/migrating-to-sveltekit-3), [configuración](https://svelte.dev/docs/kit/@sveltejs-kit-vite), [módulos privados](https://svelte.dev/docs/kit/server-only-modules), [adapter-node](https://svelte.dev/docs/kit/adapter-node).

- Mantener CSRF activo. V3 elimina `csrf.checkOrigin`; excepciones se declaran con orígenes completos en `csrf.trustedOrigins`. No usar `'*'`. CSRF no sustituye autorización, límites de abuso ni verificación de firma en webhooks.
- Detrás de proxy, configurar origen público real con `paths.origin` cuando no pueda deducirse de headers confiables. En `adapter-node`, tiene precedencia sobre `ORIGIN`. No confiar en headers de IP o protocolo que clientes puedan insertar directamente.
- No servir respuestas privadas desde una caché pública o service worker. Revisar reglas de CDN para HTML autenticado y endpoints remotos. Excluir respuestas `no-store`, especialmente streams de `query.live`.
- Usar `prerender` solo para datos públicos que pueden permanecer hasta siguiente despliegue. Su caché del navegador persiste entre recargas. Declarar `inputs` para argumentos que crawler no descubre. `dynamic: true` habilita casos no prerenderizados, sin convertir los resultados estáticos en privados.
- Una página completamente prerenderizada no admite `query` dinámica. Separar catálogo público prerenderizado de aplicación privada servida por adaptador con servidor.
- Mantener secretos en módulos privados. Revisar también retornos, HTML, errores y logs, porque protección de imports no filtra valores devueltos. Sanitizar contenido no confiable antes de `{@html}`.
- Configurar CSP según recursos de la aplicación. Evitar permitir scripts arbitrarios para resolver errores de integración.
- Usar `error(status, mensaje, datosOpcionales)` en v3. `error` y `redirect` lanzan excepciones de control; no tragarlas en un `catch` genérico.
- `handleError` recibe también errores esperados en v3. Clasificar antes de alertar. Validación remota llega con `kind: 'validation'`; devolver mensaje seguro, registrar solo metadatos necesarios y redactados. `handleValidationError` fue eliminado.
- Para redirects externos, permitir solo orígenes necesarios mediante opción `external`. Validar destinos de retorno; preferir rutas internas generadas con `resolve` de `$app/paths`.
- Probar límites de cuerpo, concurrencia, tiempos de espera y apagado con adaptador real. Incluir rate limiting para autenticación y operaciones costosas. Kit no resuelve límites de negocio mediante tipos.

## Optimizaciones según caso

Fuentes: [rendimiento](https://svelte.dev/docs/kit/performance), [enlaces](https://svelte.dev/docs/kit/link-options), [imágenes](https://svelte.dev/docs/kit/images), [live queries](https://svelte.dev/docs/kit/remote-functions#query.live).

- Medir build de producción, tamaño de JavaScript, latencia de datos y número de consultas SQL antes y después. Paginar en servidor y devolver columnas necesarias antes de agregar capas de caché.
- Cargar librerías grandes solo donde se usan. Optimizar imágenes con dimensiones explícitas y formatos adecuados. Reservar carga prioritaria para contenido visible inicial y diferir imágenes fuera de pantalla.
- Usar enlaces nativos y `resolve` para rutas con base o parámetros. Usar `asset` para archivos estáticos. V3 elimina `base`, `assets` y `resolveRoute` de `$app/paths`.
- Precargar según intención real. `preload-data` no garantiza ejecutar queries del componente. Verificar comportamiento con remote functions y configuración de `forkPreloads`, experimental, antes de atribuirle mejora. Usar precarga de código cuando baste. Desactivar atributos con `"false"`, no `"off"` en v3.
- En `query.live`, SSR consume primer valor y cierra iterador; cliente comparte conexión mientras exista uso activo. Implementar limpieza de suscripciones al cerrarse y validar capacidad del adaptador y proxy para mantener streams.
- `query.live` usa `.reconnect()`, no `.refresh()`. No tratarlo como registro durable de eventos, porque consumidores lentos pueden recibir solo último valor pendiente. Para permisos revocables, comprobar cómo se corta o reautoriza una conexión ya abierta.
- Tras despliegue, contemplar cliente antiguo con esquema remoto anterior. V3 actualiza `updated.current` también con llamadas remotas y otros eventos. Ofrecer recarga que preserve trabajo pendiente.

## Criterios de revisión

Antes de dar por terminado un cambio, verificar los puntos aplicables y reportar qué se comprobó:

- Invocar remote function sin sesión, con sesión vencida y con identificador de otro usuario u organización. Servidor debe rechazar acceso sin devolver datos ni escribir.
- Manipular argumentos y contexto de página. Autorización debe depender de sesión y recurso. Para guards de página, probar pathname codificado y rutas dinámicas.
- Cambiar slug, filtro y organización sin recarga completa. Datos deben corresponder a selección actual. Cerrar sesión y probar volver atrás.
- Confirmar actualización de lista, detalle y contadores tras mutación. Verificar solicitudes de red para no introducir un segundo viaje innecesario o refrescos globales.
- Probar formulario sin JavaScript, validación fallida, checkbox vacío, campos sensibles y envíos repetidos según riesgo de operación.
- Ejecutar scripts existentes de tipos, comprobación Svelte y build. Agregar pruebas de seguridad y comportamiento proporcionales al cambio, no pruebas que solo repitan código.
- Probar CSRF contra build de producción, donde Kit aplica esa comprobación. Inspeccionar caché y origen detrás del proxy de despliegue.
- Reportar mediciones de rendimiento si se afirma una mejora. Indicar verificaciones que no pudieron ejecutarse.
