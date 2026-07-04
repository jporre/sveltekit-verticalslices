export const meta = {
  name: 'b0-draft-bodies',
  description: 'Redaccion paralela de los bodies de slices ya aprobados en el gate',
  phases: [{ title: 'draft', detail: 'un agent() por slice, read-only sobre la conversacion ya destilada' }],
}
const A = (typeof args === 'string') ? JSON.parse(args) : (args || {})
const BODY = { type: 'object', required: ['id', 'body'],
  properties: { id: { type: 'string' }, body: { type: 'string' } } }

phase('draft')
const bodies = (await parallel(A.slices.map(s => () =>
  agent(
    `Redacta SOLO el body markdown del slice "${s.id}" (${s.title}). ` +
    `Segui EXACTO el template de references/slicing-guide.md. Idioma: ${A.lang}. ` +
    `Grounding (rutas/tablas reales): ${A.grounding}. ` +
    `Para la seccion "## Alcance (slice vertical)", estos son los OTROS slices del epic ` +
    `(lo que queda para cada uno): ${JSON.stringify(A.slices)}. ` +
    `PROHIBIDO escribir "## Blocked by" o #numeros — las deps las inyecta el script. ` +
    `Devolve {id:"${s.id}", body:"<markdown>"}.`,
    { label: `body:${s.id}`, phase: 'draft', schema: BODY }
  )
))).filter(Boolean)
return { bodies }
