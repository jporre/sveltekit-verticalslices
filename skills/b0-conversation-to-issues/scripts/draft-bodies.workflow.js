export const meta = {
  name: 'b0-draft-bodies',
  description: 'Redacción paralela de los bodies de slices ya aprobados en el gate',
  phases: [{ title: 'draft', detail: 'un agent() por slice, read-only sobre la conversación ya destilada' }],
}
const A = (typeof args === 'string') ? JSON.parse(args) : (args || {})
const BODY = { type: 'object', required: ['id', 'body'],
  properties: { id: { type: 'string' }, body: { type: 'string' } } }

phase('draft')
const bodies = (await parallel(A.slices.map(s => () =>
  agent(
    `Redacta SOLO el body markdown del slice "${s.id}" (${s.title}). ` +
    `Sigue EXACTO el template de references/slicing-guide.md. Idioma: ${A.lang}. ` +
    `Criterios de aceptación APROBADOS en el gate: ${JSON.stringify(s.criterios || [])} — ` +
    `elabóralos en los checks visuales del body; PROHIBIDO inventar criterios nuevos. ` +
    `Grounding (rutas/tablas reales): ${A.grounding}. ` +
    `Para la sección "## Alcance (slice vertical)", estos son los OTROS slices del epic ` +
    `(lo que queda para cada uno): ${JSON.stringify(A.slices)}. ` +
    `PROHIBIDO escribir "## Blocked by" o #números — las deps las inyecta el script. ` +
    `Devuelve {id:"${s.id}", body:"<markdown>"}.`,
    { label: `body:${s.id}`, phase: 'draft', schema: BODY }
  )
))).filter(Boolean)
return { bodies }
