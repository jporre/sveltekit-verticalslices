# PWA en SvelteKit — instalable y offline sin romper los datos

> Se aplica SOLO cuando el usuario pide PWA, offline, instalable o "app para el celular". No es parte del modo base ni de ningún peldaño E1-E6: una app que anda bien online no necesita service worker. Layout del slice y doctrina de datos: `../../b2-build-feature/references/slice-spec.md` (gana ante cualquier contradicción de este archivo).
>
> Verificado contra docs oficiales de SvelteKit/MDN y contra el source de `@sveltejs/kit@2.70.1` (julio 2026). Lo no verificado está marcado explícito al final.

## Gate previo (contestar antes de escribir código)

| Pregunta | Si la respuesta es... |
|---|---|
| ¿Se usa con red intermitente real (terreno, bodega, movilidad)? | No → solo manifest, sin service worker. P1 y listo. |
| ¿Los datos que se ven offline cambian por usuario? | Sí → NUNCA cachear esas respuestas; ver P4. |
| ¿Alguien pidió push notifications? | No → no instalar nada de push (YAGNI). |

Un manifest solo (P1) ya hace la app instalable con icono propio y sin barra del browser. Eso cubre el 80% de los pedidos de "hazla PWA". El service worker se agrega recién cuando hay requisito offline concreto.

## P1 — Manifest (instalabilidad)

`static/manifest.webmanifest`:

```json
{
  "name": "<Nombre completo>",
  "short_name": "<Nombre corto>",
  "start_url": "/",
  "scope": "/",
  "display": "standalone",
  "background_color": "#ffffff",
  "theme_color": "#000000",
  "icons": [
    { "src": "/icons/icon-192.png", "sizes": "192x192", "type": "image/png" },
    { "src": "/icons/icon-512.png", "sizes": "512x512", "type": "image/png" },
    { "src": "/icons/maskable-512.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable" }
  ]
}
```

En `src/app.html`, dentro de `<head>`:

```html
<link rel="manifest" href="%sveltekit.assets%/manifest.webmanifest" />
```

- La lista de campos obligatorios es **política de Chromium, no de la spec**: W3C declara todos los miembros opcionales. Chromium exige `name` o `short_name`, icons de 192px y 512px, `start_url`, `display` o `display_override`, y `prefer_related_applications` en false o ausente. Chrome ya está experimentando con aflojarla — no tratarla como permanente.
- Extensión `.webmanifest`, no `.json`: `manifest.json` en `static/` puede chocar con el manifest interno de build de SvelteKit (kit#5803).
- Requiere **https, o localhost/127.0.0.1**. Pitfall clásico: probar desde el teléfono con `vite dev --host` por IP LAN (`http://192.168.x.x:5173`) no es ni https ni localhost, entonces no aparece el prompt de instalación y se pierde media hora buscando el bug en el manifest.
- El service worker **ya no es requisito de instalabilidad** (Chrome 108 móvil / 112 desktop), pero la heurística del prompt automático todavía mira que exista un handler de `fetch`.

## P2 — Service worker (solo si hay requisito offline)

`src/service-worker.ts` se bundlea y **auto-registra** sin escribir código de registro. El módulo es `$service-worker` (no `$app/service-worker`) y exporta `base`, `build`, `files`, `prerendered`, `version`.

```ts
/// <reference types="@sveltejs/kit" />
/// <reference lib="webworker" />

import { base, build, files, prerendered, version } from '$service-worker';

const self = globalThis.self as unknown as ServiceWorkerGlobalScope;

const CACHE = `cache-${version}`;
const ASSETS = [...build, ...files, ...prerendered];
const OFFLINE = `${base}/offline`;

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(CACHE).then((cache) => cache.addAll(ASSETS)));
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      for (const key of await caches.keys()) {
        if (key !== CACHE && !key.startsWith('sveltekit:')) await caches.delete(key);
      }
    })()
  );
});

self.addEventListener('message', (event) => {
  if (event.data?.type === 'SKIP_WAITING') self.skipWaiting();
});

self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET') return;

  const url = new URL(event.request.url);
  if (!url.protocol.startsWith('http')) return;

  async function respond() {
    const cache = await caches.open(CACHE);

    // assets con hash de contenido: cache-first, son inmutables
    if (ASSETS.includes(url.pathname)) {
      const cached = await cache.match(url.pathname);
      if (cached) return cached;
    }

    // todo lo demás: red, y NUNCA se escribe al cache (ver P3)
    try {
      const response = await fetch(event.request);
      if (!(response instanceof Response)) throw new Error('respuesta inválida de fetch');
      return response;
    } catch (err) {
      const cached = await cache.match(url.pathname);
      if (cached) return cached;
      if (event.request.mode === 'navigate') {
        const offline = await cache.match(OFFLINE);
        if (offline) return offline;
      }
      throw err;
    }
  }

  event.respondWith(respond());
});
```

La página offline es un slice normal prerenderizado — así entra sola al array `prerendered` y no hace falta cachearla aparte:

```ts
// src/routes/offline/+page.ts
export const prerender = true;
```

- El filtro de `activate` preserva las caches `sveltekit:*` porque son de SvelteKit (P4), no tuyas. Borrarlas tira el cache de datos prerenderizados en cada deploy.
- `activate` NO llama `clients.claim()`: el control se toma vía el flujo de update de P5, no a la fuerza.
- **Dev**: el service worker no se bundlea en `vite dev`, y `build`/`prerendered` son arrays vacíos. La lógica de precache es un no-op silencioso en dev. Toda validación va contra `vite build && vite preview`.

### Diferencia vs el ejemplo de los docs oficiales

El ejemplo de los docs de SvelteKit hace `cache.put(event.request, response.clone())` sobre cualquier respuesta 200 de la rama network-first. En una app con auth eso escribe HTML SSR y respuestas de query **de un usuario** en un cache compartido por origen. La versión de arriba simplemente **nunca escribe al cache en runtime**: solo sirve lo precacheado en `install`. Menos código y sin clase entera de bug.

## P3 — Qué se cachea y qué no

| Recurso | Estrategia | Por qué |
|---|---|---|
| `build` (JS/CSS con hash) | cache-first, precache | inmutables por definición |
| `files` (`static/`) | cache-first, precache | cambian solo por deploy |
| `prerendered` (HTML de build) | cache-first, precache | igual para todos los usuarios |
| HTML SSR de páginas dinámicas | red, sin escribir cache | trae datos del usuario logueado |
| Remote functions (`/_app/remote/*`) | red, sin escribir cache | idem — ver la trampa abajo |

**La trampa que hay que conocer** (verificada en el source de kit 2.70.1, no en docs):

- `query` sale como **GET** a `${base}/_app/remote/<id>?payload=...` (`client/remote-functions/query/index.js`).
- `command`, `form` y `query.batch` salen como **POST** al mismo path.

O sea el `if (event.request.method !== 'GET') return;` del ejemplo oficial **salta los commands y forms pero NO salta las queries**. Un service worker que escriba al cache toda respuesta GET 200 termina guardando datos autenticados de un usuario y sirviéndoselos a otro en el mismo dispositivo. El SW de P2 no tiene el problema porque no escribe nada en runtime; si igual se agrega cache dinámico, excluir explícito:

```ts
if (url.pathname.startsWith(`${base}/_app/remote/`)) return;
// ponytail: appDir default; ajustar si kit.appDir está customizado
```

## P4 — Datos offline: usar lo que SvelteKit ya trae

Antes de escribir una sola línea de cache de datos: el flavor **`prerender` de remote functions ya guarda su resultado en la Cache API del navegador**, sobrevive reloads y se limpia solo cuando el usuario visita un deploy nuevo (cache `sveltekit:${version}`, `client/remote-functions/prerender.svelte.js`).

```ts
// MAL — cachear respuestas de query a mano en el service worker
// (fuga de datos entre usuarios + invalidación propia que mantener)

// BIEN — <feature>.remote.ts: datos que cambian a lo sumo por deploy
import { prerender } from '$app/server';

export const get_catalogo = prerender(async () => {
  return db.select().from(catalogo);
});
```

Aplica a catálogos, paramétricas, configuración, contenido — todo lo que cambia por redeploy y no por usuario. **No** aplica a datos por usuario ni a nada que deba estar fresco: eso es `query`, va por red, y offline simplemente no está disponible.

Si hace falta que datos por usuario sobrevivan offline, eso ya no es cache: es sincronización, con conflictos y cola de escritura. Decirlo explícito al usuario antes de construirlo — es un feature, no un flag.

## P5 — Updates (el punto más frágil)

Tres hechos que se combinan mal:

1. Un service worker nuevo queda en `waiting` hasta que **todas** las pestañas del viejo se cierran. Un refresh no alcanza.
2. Las navegaciones client-side de SvelteKit **no disparan** chequeo de update; SvelteKit solo llama `registration.update()` como recuperación de error.
3. Una navegación client-side a una página ya cacheada "tiene éxito" con contenido viejo, sin error y sin reload (kit#3666, abierto desde 2022).

Resultado sin manejo explícito: deploy que nunca llega al usuario. El componente va una vez en el layout raíz:

```svelte
<!-- src/routes/UpdatePrompt.svelte -->
<script lang="ts">
  import { afterNavigate } from '$app/navigation';

  let waiting = $state<ServiceWorker | null>(null);

  $effect(() => {
    if (!navigator.serviceWorker) return;

    let reloading = false;
    navigator.serviceWorker.addEventListener('controllerchange', () => {
      if (reloading) return;
      reloading = true;
      location.reload();
    });

    navigator.serviceWorker.ready.then((reg) => {
      if (reg.waiting) waiting = reg.waiting;
      reg.addEventListener('updatefound', () => {
        const sw = reg.installing;
        sw?.addEventListener('statechange', () => {
          if (sw.state === 'installed' && navigator.serviceWorker.controller) waiting = sw;
        });
      });
    });
  });

  afterNavigate(async () => {
    const reg = await navigator.serviceWorker?.ready;
    void reg?.update();
  });
</script>

{#if waiting}
  <button onclick={() => waiting?.postMessage({ type: 'SKIP_WAITING' })}>
    Nueva versión disponible - actualizar
  </button>
{/if}
```

- El reload va en `controllerchange`, **no** justo después del `postMessage`: skipWaiting es asíncrono.
- El guard `reloading` es obligatorio: sin él, la primera instalación recarga la página sola.
- `location.reload()` destruye el estado del router y de los formularios. Por eso es un botón que el usuario aprieta, no un reload automático.
- Este es de los pocos `$effect` legítimos del proyecto: suscripción a eventos reales del navegador, no cómputo derivado.

## iOS / Safari

- No existe `beforeinstallprompt`: un botón de "instalar" propio no funciona. Detectar y mostrar instrucciones de Compartir > Agregar a inicio.
- iOS 16.4+ permite instalar desde Safari, Chrome, Edge, Firefox y Orion; 16.3 y anteriores solo Safari.
- Detección: `matchMedia('(display-mode: standalone)').matches` o `navigator.standalone`.
- Safari macOS tampoco tiene `beforeinstallprompt`: usa File > Add to Dock.

## Herramientas: a mano vs plugin

Default: **service worker a mano**. Los docs oficiales lo describen como "probably a good solution for most users" y mandan a Workbox/`vite-plugin-pwa` a una sección "Other solutions" para quienes ya vienen de Workbox.

`@vite-pwa/sveltekit` no aporta la lista de archivos — `$service-worker` ya la da. Lo único que agrega de verdad es un precache manifest con **revisión por archivo** (`{url, revision}`), o sea un asset que cambia invalida solo a sí mismo en vez de todo el `cache-${version}`. Eso importa recién con muchos MB de assets y deploys frecuentes. A cambio trae: `kit.serviceWorker.register: false` obligatorio con cualquier virtual module, hack de `define` para importar módulos `workbox-*`, un rebuild post-build porque el SW se compila antes del adapter, y el `<link rel="manifest">` igual a mano. Serwist es una tercera vía con receta SvelteKit oficial y el mismo tradeoff.

Regla: agregar el plugin recién cuando la granularidad de invalidación sea un problema **medido**, no antes.

## Verificación (checklist de browser, no de types)

`vite build && vite preview`, y en el browser:

- [ ] DevTools > Application > Manifest sin errores, iconos resueltos
- [ ] Application > Service Workers: activado, sin quedar en "waiting" al primer load
- [ ] Application > Cache Storage: `cache-<version>` con build + files + prerendered; **verificar que no haya HTML de páginas autenticadas ni nada bajo `/_app/remote/`**
- [ ] Network con throttling Offline: navegación a ruta cacheada anda, ruta no cacheada cae a `/offline`
- [ ] Deploy nuevo con la pestaña abierta → aparece el prompt de update; al aceptar, recarga una sola vez
- [ ] Instalar en un teléfono real (Android e iOS): icono, splash, sin barra de browser
- [ ] Logout con la app instalada → reabrir → no queda contenido del usuario anterior visible

La categoría PWA de Lighthouse ya no es vía de verificación confiable; el chequeo real es el panel Application más dispositivo real.

## Qué NO hacer

- Agregar service worker "porque es PWA" cuando el pedido era solo el icono instalable.
- Copiar el ejemplo de los docs tal cual en una app con auth: cachea HTML SSR y queries autenticadas en un cache compartido.
- Cachear respuestas de `query`: son GET, el filtro de método no las salta, y traen datos del usuario.
- Borrar caches `sveltekit:*` en `activate`: son de SvelteKit, no tuyas.
- `skipWaiting()` incondicional en `install`: cambia el código abajo de una sesión en uso.
- Recargar automático al detectar update: el usuario pierde lo que estaba escribiendo.
- Dar por bueno un service worker que solo compila: en `vite dev` la lógica de precache es un no-op y no probaste nada.

## No verificado en esta ronda

Marcado explícito para que nadie lo cite como confirmado: estado real de Web Push en iOS/iPadOS 2026 (más allá del requisito de instalar en Home Screen), soporte de Badging API en Safari, política de evicción de storage de iOS y su efecto sobre el precache, y qué reemplazó formalmente a la categoría PWA de Lighthouse. También sin fuente primaria: comportamiento del edge cache de adapter-vercel. Si el usuario pide alguna de esas, investigar antes de afirmar.
