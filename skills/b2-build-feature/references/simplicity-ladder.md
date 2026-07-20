# Simplicity ladder (lazy by default)

La regla del proyecto: **el código más simple que funciona, gana.** Capas de más, indirecciones y abstracciones especulativas son deuda, no rigor. Esta es la disciplina de construcción que b2 sigue al escribir y que b6 usa como lente al revisar.

> El antipatrón a evitar: un `query` que llama a una función que llama a una abstracción Drizzle de otra función que recién hace la query. Cuatro saltos para una query. Si una pantalla necesita sus datos, `<feature>.remote.ts` hace la query Drizzle directo. Punto.

## La escalera — frena en el primer peldaño que aguante

Antes de escribir código, sube esta escalera y párate apenas algo resuelve el caso:

1. **¿Hace falta que exista?** Necesidad especulativa = no lo hagas, y dilo en una línea. (YAGNI)
2. **¿Lo hace la stdlib / SvelteKit?** Úsalo.
3. **¿Lo cubre una feature nativa de la plataforma?** `<input type="date">` antes que una lib de picker. CSS antes que JS. Constraint de DB (o índice) antes que lógica de app. `href` antes que `goto()`.
4. **¿Lo resuelve una dependencia YA instalada?** Úsala. Nunca agregues una nueva para lo que se hace en unas líneas. (shadcn-svelte, drizzle, zod, svelte-sonner ya están.)
5. **¿Cabe en una línea?** Una línea.
6. **Recién ahí:** el mínimo código que funciona.

La escalera es un reflejo, no un proyecto de investigación. Dos peldaños sirven → toma el más alto y sigue. La primera solución perezosa que funciona es la correcta.

## Reglas

- **Sin abstracciones no pedidas:** nada de interfaz con una sola implementación, factory para un solo producto, config para un valor que nunca cambia, "service layer" para CRUD simple. (En este proyecto: auth va en la remote function, no en un servicio; los datos los trae la remote function, no un repositorio.)
- **Sin boilerplate "para después".** Después se scaffoldeará solo.
- **Borrar antes que agregar.** Aburrido antes que ingenioso — lo ingenioso es lo que alguien descifra a las 3am.
- **La menor cantidad de archivos.** El diff más corto que funciona gana. (Calza con el cap de b2: 3-5 archivos colocados; más = sobre-ingeniería.)
- **Dos opciones de stdlib del mismo tamaño:** la que es correcta en los edge cases. Perezoso = escribir menos código, no elegir el algoritmo más endeble.
- **Pedido complejo:** entrega la versión perezosa y cuestiónala en la misma respuesta: "Hice X; Y lo cubre. ¿Necesitas X completo? Dímelo." Nunca te trabes en una respuesta que puedes defaultear.

## El marcador `// ponytail:`

Una simplificación deliberada se marca con un comentario `ponytail:` — así se lee como **intención, no ignorancia**. Es la excepción sancionada a la regla general de "no comentarios": marca un atajo con techo conocido.

```ts
// ponytail: filtro client-side, <1000 items. Si crece, mover a query con WHERE + índice.
const visibles = $derived(items.filter(i => i.activo))
```

Si el atajo tiene un techo conocido (lock global, scan O(n²), heurística naive), el comentario **nombra el techo y el camino de upgrade**:

```ts
// ponytail: lock global; locks por-cuenta si el throughput molesta.
```

Sin techo riesgoso, basta `// ponytail: esto existe` para que el reviewer sepa que la simpleza es a propósito.

## Output al terminar

Código primero. Después, máximo tres líneas cortas: qué se omitió y cuándo agregarlo. Sin ensayos, sin tour de features, sin notas de diseño. **Si la explicación es más larga que el código, borra la explicación** — cada párrafo defendiendo una simplificación es complejidad de vuelta, disfrazada de prosa.

(Excepción: si el usuario pidió explícitamente un reporte, walkthrough o notas por fase, eso no es deuda — entrégalo completo. La regla es solo contra prosa NO pedida.)
