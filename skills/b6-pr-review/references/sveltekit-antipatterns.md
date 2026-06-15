# Anti-patrones SvelteKit (errores clasicos de devs React)

Referencia para detectar codigo que fue escrito "pensando en React" dentro de un proyecto SvelteKit con Svelte 5.

## 1. Navegacion con JS en vez de HTML

**Anti-patron**: Usar `goto()` o callbacks para navegacion simple.

```svelte
<!-- MAL -->
<Button onclick={() => goto('/ruta')}>Ir</Button>

<!-- BIEN -->
<Button href="/ruta">Ir</Button>
<a href="/ruta">Ir</a>
```

`goto()` solo se justifica despues de una accion programatica (submit, delete, etc).

## 2. Fetch manual en vez de remote functions o load

**Anti-patron**: Crear endpoints API y luego fetchear desde el componente con useEffect/onMount.

```svelte
<!-- MAL: fetch manual estilo React -->
<script>
import { onMount } from 'svelte'
let data = $state(null)
onMount(async () => {
  const res = await fetch('/api/items')
  data = await res.json()
})
</script>

<!-- BIEN: remote function -->
<script>
import { get_items } from './<feature>.remote'
const items = $derived(await get_items())
</script>
```

## 3. $effect para computar valores (en vez de $derived)

**Anti-patron**: Usar `$effect` para sincronizar estado derivado.

```svelte
<!-- MAL -->
<script>
let items = $state([])
let filtered = $state([])
$effect(() => {
  filtered = items.filter(i => i.active)
})
</script>

<!-- BIEN -->
<script>
let items = $state([])
let filtered = $derived(items.filter(i => i.active))
</script>
```

`$derived` es reactivo y sin side-effects. `$effect` solo para efectos reales (DOM, timers, logs).

## 4. Immutabilidad innecesaria (spreads para actualizar estado)

**Anti-patron**: Copiar objetos/arrays con spread para "disparar" reactividad.

```svelte
<!-- MAL: patron React de inmutabilidad -->
<script>
let user = $state({ name: '', email: '' })
function update() {
  user = { ...user, name: 'Alice' }  // innecesario
}
</script>

<!-- BIEN: mutacion directa (Svelte 5 lo trackea) -->
<script>
let user = $state({ name: '', email: '' })
function update() {
  user.name = 'Alice'
}
</script>
```

## 5. try/catch envolviendo error() o redirect()

**Anti-patron**: Capturar las excepciones de control de flujo de SvelteKit.

```typescript
// MAL — SvelteKit no puede manejar el error/redirect
try {
  if (!user) error(401, {message: '...', code: 'AUTH_REQUIRED'})
} catch (e) {
  console.error(e) // silencia el error de SvelteKit
}

// BIEN — dejar que SvelteKit lo maneje
if (!user) error(401, {message: '...', code: 'AUTH_REQUIRED'})
```

Si necesitas try/catch por otra razon, usa `isHttpError()` o `isRedirect()` para re-lanzar los de SvelteKit.

## 6. Slot syntax (Svelte 4) en vez de snippets (Svelte 5)

**Anti-patron**: Usar `<slot />` que es sintaxis de Svelte 4.

```svelte
<!-- BIEN: Svelte 5 -->
<script>
let {children, header} = $props()
</script>

<!-- MAL: Svelte 4 -->
<slot />
<slot name="header" />
{@render children()}
{@render header?.()}
```

## 7. Named imports de shadcn-svelte (en vez de namespace)

**Anti-patron**: Importar componentes shadcn individualmente.

```svelte
<!-- MAL -->
<script>
import { Card, CardHeader, CardTitle } from '$lib/components/ui/card'
</script>

<!-- BIEN -->
<script>
import * as Card from '$lib/components/ui/card'
</script>
<Card.Root><Card.Header><Card.Title>...</Card.Title></Card.Header></Card.Root>
```

## 8. Select.Value (no existe)

**Anti-patron**: Usar `<Select.Value>` que no existe en shadcn-svelte.

```svelte
<!-- MAL -->
<Select.Trigger><Select.Value>Elegir...</Select.Value></Select.Trigger>

<!-- BIEN -->
<Select.Trigger placeholder="Elegir..." />
```

## 9. Estado global mutable en servidor

**Anti-patron**: Variables a nivel de modulo en archivos `.server.ts` que acumulan estado entre requests.

```typescript
// MAL: este array se comparte entre TODOS los requests de todos los usuarios
let cache: Item[] = []

export async function load() {
  if (cache.length === 0) cache = await fetchItems()
  return {items: cache} // data leak entre usuarios
}
```

## 10. Eventos con on: (Svelte 4) en vez de on\* (Svelte 5)

```svelte
<!-- MAL: Svelte 4 -->
<button on:click={handler}>Click</button>

<!-- BIEN: Svelte 5 -->
<button onclick={handler}>Click</button>
```

## 11. Remote function en src/lib/server (prohibido)

Los archivos `.remote.ts` NO pueden estar dentro de `src/lib/server/` (el cliente los importa). Viven colocados en la carpeta de ruta del feature como `src/routes/<feature>/<feature>.remote.ts`, nunca como `data.remote.ts` generico.

## 12. Query sin refresh despues de mutacion

```svelte
<!-- MAL: esperar auto-invalidacion -->
<script>
await markDone({ id })
// la lista no se actualiza sola
</script>

<!-- BIEN: refresh explicito -->
<script>
await markDone({ id })
pendientesQ.refresh()
</script>
```

## 13. Filtrado servidor-side para datasets pequenos

Si el dataset tiene <1000 items, filtrar en cliente con `$derived`:

```svelte
<!-- MAL: round-trip al servidor para filtrar 50 items -->
<script>
let search = $state('')
const items = $derived(await get_items({ search }))
</script>

<!-- BIEN: filtrar en cliente -->
<script>
const allItems = $derived(await get_items())
let search = $state('')
let filtered = $derived(allItems.filter(i => i.name.includes(search)))
</script>
```

## 14. Lucide icons con import destructurado

```svelte
<!-- MAL -->
<script>
import { Plus } from 'lucide-svelte'
import { Plus } from '@lucide/svelte'
</script>

<!-- BIEN -->
<script>
import Plus from '@lucide/svelte/icons/plus'
</script>
```

## 15. Errores sin estructura (message + code)

```typescript
// MAL
error(400, 'Algo salio mal')
error(400, {message: 'Error'}) // falta code

// BIEN
error(400, {message: 'Titulo muy corto', code: 'INVALID_TITLE_LENGTH'})
```
