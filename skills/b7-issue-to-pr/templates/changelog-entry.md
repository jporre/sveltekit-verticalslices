<!--
  Entrada CHANGELOG generada por b7-issue-to-pr.
  Tono: técnico-analítico para devs futuros leyendo historia.
  Se inserta bajo la sección [Unreleased] del CHANGELOG.md raíz.
-->

### ${TYPE_LABEL} — ${SCOPE} (#${ISSUE_NUMBER})

${SUMMARY_TECHNICAL}
<!--
  SUMMARY_TECHNICAL: 1-3 frases técnicas. Qué se cambió y por qué.
  Ej: "Agrega remote function get_tareas_by_estado y nueva pantalla BandejaTareasPage para reemplazar el filtrado client-side que escalaba mal a >2k tareas."
-->

**Pantallas afectadas**: ${SCREENS_LIST}
<!-- "BandejaTareasPage (/tareas), DetalleTareaPage (/tareas/[id])" o "—" si no hay -->

**Archivos clave**:
${FILES_KEY_LIST}
<!--
  - `src/routes/${SCOPE}/${SCOPE}.remote.ts` — nueva query + permission check
  - `src/routes/${SCOPE}/+page.svelte` — UI principal
-->

**Riesgos / consideraciones**:
${RISKS_BLOCK}
<!--
  - Migración requerida: ${MIGRATION_NOTE}
  - Permiso nuevo registrado: ${PERM_NEW}
  - Posible impacto en cache: ${CACHE_NOTE}
  - "Sin riesgos identificados" si nada aplica.
-->

**Métricas del run**: ${ITER_COUNT} iter · ${FILES_CHANGED} archivos · ${NET_LINES} líneas netas · ${WALL_CLOCK}

**Links**: [issue #${ISSUE_NUMBER}](${ISSUE_URL}) · [PR #${PR_NUMBER}](${PR_URL}) · [run report](${RUN_REPORT_PATH})
