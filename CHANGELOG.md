# Changelog

## [Unreleased]

<!--
  Entrada CHANGELOG generada por b7-issue-to-pr.
  Tono: técnico-analítico para devs futuros leyendo historia.
  Se inserta bajo la sección [Unreleased] del CHANGELOG.md raíz.
-->

### feat —  (#13)

2 hooks nuevos (env-probe.sh, block-env-dump.sh) + wiring en hooks.json (Bash y Read) + nota de convencion en guardrails.sh.
### — — b7-pipeline (#12)

publish-docs.sh state-set/milestone (whitelist python3), render-report.sh exit 4 en vars indefinidas, init-state siembra claves faltantes y borra started_utc duplicado.
<!--
  SUMMARY_TECHNICAL: 1-3 frases técnicas. Qué se cambió y por qué.
  Ej: "Agrega remote function get_tareas_by_estado y nueva pantalla BandejaTareasPage para reemplazar el filtrado client-side que escalaba mal a >2k tareas."
-->

**Pantallas afectadas**: —
<!-- "BandejaTareasPage (/tareas), DetalleTareaPage (/tareas/[id])" o "—" si no hay -->

**Archivos clave**:
hooks/env-probe.sh, hooks/block-env-dump.sh, hooks/hooks.json, skills/b7-issue-to-pr/scripts/guardrails.sh
<!--
  - `src/routes//.remote.ts` — nueva query + permission check
  - `src/routes//+page.svelte` — UI principal
-->

**Riesgos / consideraciones**:
Over-block deliberado (verbo de dump que mencione .env). Falso positivo se esquiva usando env-probe.sh o .env.example.
<!--
  - Migración requerida: 
  - Permiso nuevo registrado: 
  - Posible impacto en cache: 
  - "Sin riesgos identificados" si nada aplica.
-->

**Métricas del run**: 0 iter · 0 archivos · 0 líneas netas · —

**Links**: [issue #13](https://github.com/jporre/sveltekit-verticalslices/issues/13) · [PR #—](—) · [run report](—)
—
<!--
  - `src/routes/b7-pipeline/b7-pipeline.remote.ts` — nueva query + permission check
  - `src/routes/b7-pipeline/+page.svelte` — UI principal
-->

**Riesgos / consideraciones**:
Bajo: cambios acotados a scripts del pipeline b7.
<!--
  - Migración requerida: ninguna
  - Permiso nuevo registrado: ninguno
  - Posible impacto en cache: ninguna
  - "Sin riesgos identificados" si nada aplica.
-->

**Métricas del run**: 1 iter · 0 archivos · 0 líneas netas · —

**Links**: [issue #12](https://github.com/jporre/sveltekit-verticalslices/issues/12) · [PR #—](—) · [run report](—)



