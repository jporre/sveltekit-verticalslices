---
name: b3-security
description: Use when implementing authorization, permissions, or authentication in SvelteKit projects. Covers the verbo:sustantivo permission model, getLocals/requireUser pattern, and securing Remote Functions.
allowed-tools: Read, Write, Edit, Glob
---

# Seguridad en Remote Functions

Esta skill proporciona el modelo de seguridad y autorizacion para proyectos SvelteKit. Se activa cuando el usuario trabaja con permisos, autorizacion, autenticacion, o proteccion de Remote Functions.

**IMPORTANTE**: Los detalles de autenticacion (como se setea locals.user, que libreria de auth se usa) son especificos del proyecto. Consulta CLAUDE.md/AGENTS.md para eso. Esta skill cubre el modelo de permisos y los patrones de verificacion.

## Principios

1. **hooks.server.ts** autentica y asigna `event.locals.user` y `event.locals.permissions`
2. **Permisos atomicos** con formato `verbo:sustantivo` (ej: `leer:documento`, `crear:post`)
3. **Remote functions siempre ejecutan en servidor** -> verificacion critica aqui
4. **NO usar roles hardcodeados** (nada de `if role === 'admin'`)

## Formato de Permisos

```
verbo:sustantivo

Ejemplos:
- leer:documento
- crear:documento
- editar:documento
- eliminar:documento
- aprobar:solicitud
- exportar:informe
```

## Patron requireUser (Autenticacion)

```typescript
// src/lib/features/<feature>/data.remote.ts
import {query, getRequestEvent} from '$app/server'
import {error} from '@sveltejs/kit'

function requireUser() {
  const {locals} = getRequestEvent()
  if (!locals.user) {
    error(401, {message: 'No autenticado', code: 'AUTH_REQUIRED'})
  }
  return locals.user
}
```

## Patron requirePermission (Autorizacion)

```typescript
function requirePermission(permiso: string) {
  const {locals} = getRequestEvent()

  if (!locals.user) {
    error(401, {message: 'No autenticado', code: 'AUTH_REQUIRED'})
  }

  const permisos = locals.permissions?.profilePermissions ?? []
  if (!permisos.some(p => p.permiso === permiso)) {
    error(403, {message: `Requiere permiso: ${permiso}`, code: 'FORBIDDEN'})
  }

  return locals.user
}
```

## Uso en Remote Functions

### Query con autenticacion

```typescript
export const get_documentos = query(async () => {
  const user = requireUser()
  return listDocumentos(user.orgId) // llama a repo.server.ts
})
```

### Query con permiso especifico

```typescript
export const get_informes = query(async () => {
  requirePermission('leer:informe')
  return listInformes()
})
```

### Form con permiso

```typescript
export const crear_documento = form(schema, async ({titulo, contenido}) => {
  const user = requirePermission('crear:documento')
  await createDocumento(user.orgId, {titulo, contenido, autorId: user.id})
  return {ok: true}
})
```

### Multiples permisos (cualquiera)

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

## Errores Estructurados

```typescript
// Siempre usar objeto con message y code
error(401, {message: 'No autenticado', code: 'AUTH_REQUIRED'})
error(403, {message: 'Sin permiso', code: 'FORBIDDEN'})
error(404, {message: 'No encontrado', code: 'NOT_FOUND'})
```

## Mapeo de Operaciones a Permisos

| Operacion | Permiso requerido                          |
| --------- | ------------------------------------------ |
| Listar    | publico / leer:[entidad]                   |
| Ver       | publico / leer:[entidad]                   |
| Crear     | crear:[entidad]                            |
| Editar    | editar:[entidad]                           |
| Eliminar  | eliminar:[entidad]                         |
| Acciones  | [accion]:[entidad] (ej: aprobar:solicitud) |

## Donde Poner la Verificacion

```
src/lib/features/<feature>/
  data.remote.ts        # requireUser/requirePermission aqui
  server/
    repo.server.ts      # NO verificar permisos aqui (solo datos)
    service.server.ts   # Logica de negocio, puede verificar reglas
```

La verificacion de permisos va en `data.remote.ts` (la capa que expone al cliente). El repo.server.ts confia en que fue llamado correctamente.

## Datos de Prueba Recomendados

Mantener usuarios de prueba con diferentes permisos:

| Email           | Password | Permisos                     |
| --------------- | -------- | ---------------------------- |
| admin@test.com  | test123  | crear:\*, editar:\*, leer:\* |
| editor@test.com | test123  | crear:post, editar:post      |
| viewer@test.com | test123  | leer:post                    |
| none@test.com   | test123  | (ninguno)                    |
