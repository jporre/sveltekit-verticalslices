# shadcn-svelte — estándar de diseño

Qué componente usar para qué patrón, tokens semánticos y dark mode. La mecánica de
imports (namespaced, `Select.Value`, bridges de campos) vive en `svelte5-not-react.md` §10
y `forms-recipe.md` — este archivo cubre la **decisión de diseño**, que es donde el
agente suele improvisar.

## Tabla patrón → componente

| Patrón | Componente | NUNCA |
|---|---|---|
| Confirmación destructiva (delete, revertir) | `AlertDialog` con `AlertDialog.Action` en la acción | `confirm()` / `alert()` nativos |
| Detalle o edición sin cambio de contexto | `Dialog` (con `Dialog.Content` scrolleable si el form es alto) | sub-ruta para un form de 2 campos |
| Panel lateral sobre la lista actual | `Sheet` | — |
| Selección con búsqueda sobre >15 opciones | `Combobox` | `<select>` nativo con 200 `<option>` |
| Selección simple (<15 opciones) | `Select` (ver AP8: nunca `Select.Value` — `Select.Trigger` + items) | `<select>` nativo |
| Carga de datos / lazy de zona | `Skeleton` con el shape del contenido | spinner suelto o texto "Cargando..." |
| Lista vacía (estado empty) | bloque centrado con texto + acción primaria (`Button href` o abre Dialog de creación) | tabla vacía sin explicación |
| Feedback de resultado de acción | `toast.success` / `toast.error` (sonner) | console.log, o toast para errores de validación de campo |
| Error de validación de campo | `fields.name.issues()` inline (forms-recipe) | toast |
| Fechas / montos | componente del proyecto o formateo helper; estilo con tokens | `<input type="date">` estilizado a mano sin razón |

Regla general: si el patrón aparece 2+ veces en el feature, es componente en `ui/`
(PascalCase) del feature; si aparece en 3+ features, es candidato a `$lib/components/ui/`
(ver slice-spec §Colocation).

## Tokens semánticos — nunca colores crudos

Estilo con tokens del tema, no con paleta directa:

```svelte
<!-- CORRECT — tokens semánticos (definidos en src/app.css, heredan dark mode) -->
<p class="text-muted-foreground">Sin envíos pendientes</p>
<Button variant="destructive">Eliminar</Button>

<!-- WRONG — colores crudos (se rompen en dark mode, duplican la paleta) -->
<p class="text-gray-400">Sin envíos pendientes</p>
<Button class="bg-red-500 hover:bg-red-600">Eliminar</Button>
```

Colores crudos (`text-red-500`, hex) solo con justificación `// ponytail:` y techo
(usualmente: nunca — existe un token para eso). Para estados sin token específico,
componer con los existentes (`text-destructive`, `text-muted-foreground`, `bg-muted`,
`border-border`) en vez de inventar clases.

## Dark mode

Se resuelve a nivel de tokens en `src/app.css` (clase `.dark` del tema shadcn). Los
componentes NO llevan clases condicionales por tema (`dark:bg-...` solo si el token
no cubre el caso, con justificación). Si el diseño exige un color que no existe como
token, la respuesta es agregar el token en `app.css`, no hardcodear en el componente.

## Checklist rápido (lo que el review visual de b7 va a ver)

- [ ] Ninguna acción destructiva sin `AlertDialog`
- [ ] Ningún `confirm()`/`alert()` nativo
- [ ] Sin spinner/texto de carga suelto donde va `Skeleton`
- [ ] Sin colores crudos — todo por token semántico
- [ ] Empty state con acción, no vacío silencioso
- [ ] Errores de campo inline con `issues()`, no en toast
