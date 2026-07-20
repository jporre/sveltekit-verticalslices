# ${PR_TITLE}

> ${SUMMARY_COMMERCIAL}
<!--
  SUMMARY_COMMERCIAL: una frase tipo release notes, qué obtiene el usuario.
  Ej: "Ahora puedes filtrar la bandeja de tareas por estado y asignado en un solo clic."
  Ej: "Las notificaciones de campañas SMS muestran el detalle del proveedor cuando fallan."
-->

## ✨ Lo que cambia para el usuario

${USER_FACING_CHANGES}
<!--
  Lista bullet, lenguaje natural, sin jerga técnica.
  - Nueva pantalla X que permite Y.
  - Tiempos de carga del listado Z bajan a la mitad.
  - Errores ahora muestran el código del proveedor.
-->

## 🖼️ Pantallas entregadas

${SCREENS_GALLERY}
<!--
  Para cada screen del triage:
  ### ${SCREEN_NAME} — `${SCREEN_ROUTE}`
  ${SCREEN_USER_JOURNEY}

  | Estado | Captura |
  |--------|---------|
  | Golden path | <img src="..." width="400"> |
  | Empty | <img src="..." width="400"> |
  | Error | <img src="..." width="400"> |
  El <img src> solo si hay URL alcanzable (PNG commiteado → raw blob URL, o asset subido).
  No hay upload automático (attach.sh solo postea nombres): si no hay URL, poner el nombre del PNG como texto.

  **Veredicto revisión visual**: ${SCREEN_VERDICT}
-->

## 🧪 Cómo probarlo

${TEST_PLAN}
<!--
  Checklist accionable:
  - [ ] Abrir /tareas y verificar el filtro por estado.
  - [ ] Crear una tarea nueva y confirmar que aparece sin recargar.
  - [ ] Forzar un error de red y confirmar el toast.
-->

## 🔧 Cambios técnicos

<details>
<summary>Resumen técnico (click para expandir)</summary>

${TECH_SUMMARY}
<!--
  - Feature: src/routes/${SCOPE}/
  - Remote functions agregadas: ${REMOTE_FNS}
  - Migraciones DB: ${MIGRATIONS}
  - Files changed: ${FILES_CHANGED} / Net lines: ${NET_LINES}
  - Iteraciones implementación: ${ITER_COUNT}
-->

</details>

## 🛡️ Seguridad y calidad

- Permisos requeridos: ${PERMS_REQUIRED}
- Revisión de seguridad humana: ${SECURITY_REVIEW_FLAG}
- Type-check: ${CHECK_STATUS}
- Tests unitarios: ${TEST_STATUS}
- Lint: ${LINT_STATUS}

## 📎 Referencias

- Closes #${ISSUE_NUMBER}
- Run report: \`${RUN_REPORT_PATH}\`
- CHANGELOG entry: [\`CHANGELOG.md\`](../blob/${BRANCH}/CHANGELOG.md)

---
<sub>🤖 Generado automáticamente por `b7-issue-to-pr` · revisión visual con `b7-screen-review` (plugin b-pipeline)</sub>
