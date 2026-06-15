<!-- b7:status -->
<!--
  Comentario sticky de b7-issue-to-pr.
  publish-docs.sh lo edita en cada milestone via gh api PATCH.
  No editar a mano: cualquier cambio se sobrescribe en el próximo milestone.
-->

## 🤖 b7 — Estado del trabajo automático

**Estado actual**: ${STATUS_EMOJI} ${STATUS_LABEL}
**Última actualización**: ${UPDATED_AT}
**Modo**: ${MODE}
**Branch**: \`${BRANCH}\`

${SUMMARY_LINE}

### Avance

| Hito | Estado |
|------|--------|
| Triage | ${MILESTONE_TRIAGE} |
| Worktree | ${MILESTONE_WORKTREE} |
| Implementación | ${MILESTONE_IMPL} |
| Revisión visual de pantallas | ${MILESTONE_SCREENS} |
| Commit | ${MILESTONE_COMMIT} |
| Pull Request | ${MILESTONE_PR} |

### Plan de trabajo

${PLAN_BLOCK}
<!--
  PLAN_BLOCK se reemplaza por un checklist markdown:
  - [x] add-rut-field — Agregar columna rut a ta_persona y migración
  - [ ] remote-fn-update — Actualizar create_persona/update_persona
  Si plan=[] (triage no definió plan) se reemplaza por: "_Sin plan estructurado (tarea trivial)._"
  Items con `note` se renderizan con el note entre paréntesis al final.
-->

### Pantallas

${SCREENS_BLOCK}
<!--
  SCREENS_BLOCK se reemplaza por una tabla:
  | Pantalla | Ruta | Veredicto | Screenshot |
  |----------|------|-----------|------------|
  | BandejaTareasPage | /tareas | ✅ pass | <img src="..." width="200"> |
  El <img src> solo si hay URL alcanzable (PNG commiteado → raw blob URL, o asset subido).
  No hay upload automático: si no hay URL, poner el nombre del archivo como texto en vez de un <img> roto.
  Si screens=[] se reemplaza por: "_Esta tarea no requirió pantallas (cambio backend/infra)._"
-->

### Documentación generada

- **CHANGELOG**: ${CHANGELOG_LINK}
- **Pull Request**: ${PR_LINK}
- **Run report**: \`${RUN_REPORT_PATH}\`

### Próximos pasos

${NEXT_STEPS_BLOCK}
<!--
  Según STATUS:
  - in-progress → "El bot continúa trabajando. Volverá a comentar al avanzar."
  - dry-run-done → "Dry-run completo. Inspeccioná el worktree y promové con /b3-git-commit + /b4-pull-request."
  - pr-opened → "PR draft abierto. Revisar y marcar ready-for-review cuando esté ok."
  - aborted → "Bot detenido: ${ABORT_REASON}. Tomar manualmente desde acá."
  - bailed → "Bot baileó: ${BAIL_REASON}. No requiere acción del bot."
-->

---
<sub>Generado por `b7-issue-to-pr` (plugin b-pipeline)</sub>
