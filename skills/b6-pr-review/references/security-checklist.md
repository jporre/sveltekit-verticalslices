# Checklist de Seguridad para PR Review

Las reglas canonicas viven inline en SKILL.md (Area 3: tabla por clasificacion + lista "Para TODO el diff"). Este archivo trae los ejemplos de codigo y los detalles que la tabla no repite (formato de permisos, mapeo operacion → permiso, apendice).

## 1. Archivos +page.server.ts y +layout.server.ts (funciones load)

Ejemplo del check de `locals.user` (regla: tabla del Area 3):

```typescript
// CORRECTO
export async function load({locals}) {
  if (!locals.user) error(401, {message: 'No autenticado', code: 'AUTH_REQUIRED'})
  // ...
}

// INCORRECTO — load sin verificacion devuelve datos a cualquiera
export async function load({params}) {
  return {items: await getItems(params.country)}
}
```

## 2. Remote Functions (`<feature>.remote.ts`)

Ejemplos de `requireUser()` / `requirePermission()` como primera operacion (regla: tabla del Area 3):

```typescript
// CORRECTO — con permiso unitario
export const get_informes = query(async () => {
  requirePermission('leer:informe')
  return listInformes()
})

// CORRECTO — solo autenticacion (datos propios del usuario)
export const get_mi_perfil = query(async () => {
  const user = requireUser()
  return getPerfil(user.id)
})

// INCORRECTO — sin verificacion
export const get_datos = query(async () => {
  return listDatos() // cualquier visitante puede llamar esto
})
```

### Formato de permisos

- Formato: `verbo:sustantivo` (ej: `leer:documento`, `crear:post`, `editar:tarea`)
- El verbo describe la accion: leer, crear, editar, eliminar, aprobar, exportar
- El sustantivo describe la entidad

### Mapeo operacion → permiso

| Operacion | Tipo remote function | Permiso esperado   |
| --------- | -------------------- | ------------------ |
| Listar    | query                | leer:[entidad]     |
| Ver       | query                | leer:[entidad]     |
| Crear     | form / command       | crear:[entidad]    |
| Editar    | form / command       | editar:[entidad]   |
| Eliminar  | command              | eliminar:[entidad] |
| Acciones  | command              | [accion]:[entidad] |

## 3. API Endpoints (+server.ts)

Ejemplos de auth via `locals.user` o API key (regla: tabla del Area 3):

```typescript
// Con sesion
export async function GET({locals}) {
  if (!locals.user) error(401, {message: 'No autenticado', code: 'AUTH_REQUIRED'})
}

// Con API key
export async function POST({request}) {
  const apiKey = request.headers.get('x-api-key')
  if (apiKey !== env.API_KEY) error(401, {message: 'API key invalida', code: 'INVALID_API_KEY'})
}
```

## 4. Errores estructurados

Ejemplos del formato `{ message, code }` (regla: lista "Para TODO el diff"):

```typescript
error(401, {message: 'No autenticado', code: 'AUTH_REQUIRED'})
error(403, {message: 'Sin permiso', code: 'FORBIDDEN'})
error(404, {message: 'No encontrado', code: 'NOT_FOUND'})
```

## 5. Datos sensibles

- No loggear tokens, passwords, o API keys

## 6. Estado compartido en servidor

Ejemplo del data leak (regla: lista "Para TODO el diff"):

```typescript
// MAL: este array se comparte entre TODOS los requests de todos los usuarios
let cache: Item[] = []

export async function load() {
  if (cache.length === 0) cache = await fetchItems()
  return {items: cache} // data leak entre usuarios
}
```

Si necesitas cache, usar un mecanismo explicito y seguro.

## Apendice: Patrones de referencia

Variante de `requirePermission` cuando la operacion acepta cualquiera de varios permisos:

```typescript
function requireAnyPermission(...permisos: string[]) {
  const {locals} = getRequestEvent()
  if (!locals.user) {
    error(401, {message: 'No autenticado', code: 'AUTH_REQUIRED'})
  }

  const userPermisos = locals.permissions?.profilePermissions ?? []
  if (!permisos.some(p => userPermisos.some(up => up.permiso === p))) {
    error(403, {message: `Requiere uno de: ${permisos.join(', ')}`, code: 'FORBIDDEN'})
  }
  return locals.user
}
```
