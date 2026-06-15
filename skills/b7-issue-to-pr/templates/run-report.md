# b7 run ${RUN_ID}

- **issue**: #${ISSUE_NUMBER} — ${ISSUE_TITLE}
- **mode**: ${MODE}
- **branch**: \`${BRANCH}\`
- **worktree**: \`${WORKTREE_DIR}\`
- **started**: ${STARTED_UTC}
- **finished**: ${FINISHED_UTC}
- **wall-clock**: ${WALL_CLOCK}
- **status**: ${STATUS}  <!-- ok | aborted | bailed -->

## Triage

- verdict: ${TRIAGE_VERDICT}
- type: ${TRIAGE_TYPE}
- scope: \`${TRIAGE_SCOPE}\`
- complexity: ${TRIAGE_COMPLEXITY}
- security review required: ${TRIAGE_SECURITY}
- summary: ${TRIAGE_SUMMARY}

## Pantallas

${SCREENS_TABLE}
<!--
  | Pantalla | Ruta | Veredicto | Iteraciones impl | Screenshot golden |
  |----------|------|-----------|------------------|-------------------|
  | BandejaTareasPage | /tareas | ✅ pass | 3 | .b7/review/BandejaTareasPage-golden.png |
  Si screens=[] reemplazar por: "_Sin pantallas (cambio backend/infra)._"
-->

## Iteraciones

| # | check | lint | test | files | net lines | error-hash |
|---|-------|------|------|-------|-----------|------------|
${ITERATION_ROWS}

Final: ${FINAL_ITER_STATUS} tras ${ITER_COUNT}/${MAX_ITER} iteraciones.

## Budget

- files changed: ${FILES_CHANGED} / ${BUDGET_FILES}
- net lines added: ${NET_LINES} / ${BUDGET_LINES}
- wall-clock: ${WALL_CLOCK} / 30 min

## Último log con error (filtrado)

```
${LAST_LOG_TAIL}
```

## Documentación generada

- CHANGELOG entry: ${CHANGELOG_LINE_LINK}
- Issue comment (sticky): ${ISSUE_COMMENT_URL}
- PR body: ${PR_BODY_INLINED_OR_LINK}

## PR

${PR_BLOCK}  <!-- "(dry-run — no PR opened)" o link block -->

## Abort reason

${ABORT_REASON}  <!-- vacío cuando status=ok -->

## Notas para el humano

- worktree retenido para inspección: \`cd ${WORKTREE_DIR}\`
- promover manual: `git status && git diff` → `/b3-git-commit` → `/b4-pull-request`
- descartar: `git worktree remove ${WORKTREE_DIR} && git branch -D ${BRANCH}`
- pantallas y screenshots en: \`${WORKTREE_DIR}/.b7/review/\`
