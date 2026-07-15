# Modo diseño — de idea cruda a plan sliceable

Leer cuando b0 entra en modo diseño (Paso 0). Define la entrevista, el design doc y la convergencia. El modo diseño NO escribe codigo, NO abre worktrees, NO crea issues: conversa, decide y documenta hasta que el plan aguanta el slicing.

## Arranque

1. **Hubo conversacion previa en la sesion:** partir con un **resumen inteligente** — objetivo tentativo, entidades, operaciones, decisiones ya tomadas, ambiguedades abiertas — presentarlo al usuario y tomarlo como input. La entrevista arranca desde las ambiguedades, nunca desde cero (re-preguntar lo ya conversado quema paciencia).
2. **Sesion fresca con solo una idea:** pedir la idea en 1-2 lineas si no esta, y arrancar la entrevista.
3. **Retomar un diseño de otra sesion:** `--from=docs/plans/<tema>.md` — el doc es el estado; la entrevista continua desde sus `## Supuestos` abiertos.

## Entrevista — reglas duras

- **UNA pregunta a la vez** via `AskUserQuestion`. Nunca varias preguntas en un mensaje — abruma y las respuestas se contaminan.
- Cada pregunta trae la **respuesta recomendada como primera opcion** (sufijo "(Recomendado)") con el porque en la descripcion.
- **Hechos se miran, no se preguntan:** antes de cada pregunta, verificar en el codebase lo verificable (codegraph si el probe da ok, sino `rg`): rutas existentes, tablas, patrones vigentes. Las DECISIONES son del usuario; los hechos no.
- **Resolver dependencias entre decisiones en orden:** si una respuesta invalida preguntas posteriores, va primero (ej. "¿una pantalla o dos?" antes que "¿que columnas tiene la tabla?").
- Alinear cada rama a la metodologia del plugin: vertical slices, tracer bullet, tamaño b7 (simple|medium), screen-first. Si el usuario propone algo horizontal o complex, la pregunta lo muestra y recomienda el corte vertical.
- Ideas propias van como pregunta con recomendacion, **no como hecho consumado** — regla dura de b0: no agregar requisitos que el usuario no pidio.
- El usuario puede cortar cuando quiera ("crea los issues ya") → convergencia forzada; lo no resuelto queda como Supuestos visibles en el gate.

## Checklist de convergencia

La entrevista termina cuando cierra el checklist (o el usuario fuerza):

- [ ] Objetivo real (el "para que", 1-2 lineas)
- [ ] Entidades + datos clave (contrastadas con tablas reales del grounding)
- [ ] Operaciones por entidad
- [ ] Pantallas: ruta + journey por operacion
- [ ] Seguridad: quien puede hacer que (roles, ownership) por pantalla
- [ ] Restricciones y reglas de negocio
- [ ] Riesgos/ambiguedades: resueltos o aceptados como supuesto explicito
- [ ] Olas tentativas (que puede construirse junto — deps solo REALES)

Con el checklist cerrado, **proponer** converger via `AskUserQuestion` ("diseño completo — ¿paso a slicear?"). Con el OK → continuar en el Paso 2 (grounding fino) del flujo normal del SKILL.

## Design doc — `docs/plans/<slug-tema>.md`

Escribirlo/actualizarlo **a medida que las decisiones se cierran**, no al final: sobrevive compactacion de contexto y sesiones (una idea puede madurar en dias). Secciones fijas:

```markdown
# <Tema> — plan de diseño
> Estado: en-diseño | listo-para-issues | issues-creados (#<epic>)

## Objetivo
## Entidades y datos
## Pantallas y journeys
## Seguridad y permisos
## Decisiones
<una linea por decision cerrada: que se decidio y por que>
## Supuestos y descartes
## Olas tentativas
## Reglas de ejecucion
- Estructura de carpetas: <paths reales donde vive cada pieza — del grounding>
- Prueba funcional en browser por pantalla (criterios visuales en cada issue)
- Codigo sin comentarios, salvo restriccion que el codigo no puede mostrar
- Sin sobre-ingenieria: la solucion mas simple que funciona
- Seguridad: validacion en el borde + authz por pantalla segun este doc
```

- `## Reglas de ejecucion` es la UNICA copia de las normas globales — los bodies de los issues linkean el doc, no repiten las reglas (n copias divergen).
- El doc NO se commitea durante el diseño (es working tree del usuario); b0 lo commitea docs-only al crear el epic (Paso 7 del SKILL).
- `epic-review` de b10 lee `docs/plans/*.md` para la matriz de cobertura: este doc es ese contrato.
