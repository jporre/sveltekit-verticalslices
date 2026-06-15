# Checklist de Seguridad para PR Review

## 1. Archivos +page.server.ts y +layout.server.ts (funciones load)

Toda funcion `load` que devuelva datos protegidos DEBE verificar autenticacion:

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

**Excepciones validas**: Paginas publicas (login, landing, marketing) no necesitan auth.

## 2. Remote Functions (`<feature>.remote.ts`)

Toda remote function DEBE llamar `requireUser()` o `requirePermission('verbo:sustantivo')` como primera operacion:

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
- NO usar roles hardcodeados (`if role === 'admin'`)

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

Endpoints deben verificar autenticacion via `locals.user` o API key:

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

Todos los errores DEBEN usar el formato con `message` y `code`:

```typescript
error(401, {message: 'No autenticado', code: 'AUTH_REQUIRED'})
error(403, {message: 'Sin permiso', code: 'FORBIDDEN'})
error(404, {message: 'No encontrado', code: 'NOT_FOUND'})
```

**No usar**: `error(401, 'string')` ni `throw new Error('...')` para errores HTTP.

## 5. Datos sensibles

- No exponer `_id` internos de MongoDB sin serializar
- No loggear tokens, passwords, o API keys
- No hardcodear secrets en el codigo (usar `$env/static/private` o `$env/dynamic/private`)
- Verificar que `serialize()` se usa al devolver datos de MongoDB

## 6. Estado compartido en servidor

- No usar variables mutables a nivel de modulo en archivos `.server.ts` como cache informal
- El servidor maneja multiples requests; un singleton mutable filtra datos entre usuarios
- Si necesitas cache, usar un mecanismo explicito y seguro
