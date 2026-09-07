---
name: b7-issue-to-pr
description: 'Pipeline autónomo issue -> PR DRAFT centrado en pantallas; se detiene en el PR draft, NO mergea. Entrada directa SOLO cuando el usuario quiere parar en el PR: "issue N hasta PR", "abre PR del issue N", "sin merge". NO es la entrada default de "resuelve/trabaja/arregla el issue N" — eso rutea a b10-ship (que invoca este skill como fase de build); un cluster de issues relacionadas en un solo PR es b8-swarm.'
allowed-tools: Bash, Read, Edit, Write, Skill, Agent
context: fork
# model: sin definir a propósito — hereda el de la sesión (alias opus/sonnet no resuelven vía OpenRouter).
effort: low
---

# Pipeline autónomo Issue → PR (b7) — orientado a pantallas

> **Multi-harness:** en pi, `AskUserQuestion`→pregunta en texto, `Agent(subagent_type=…)`→tool `subagent`, `Skill(bN-…)`→`read` del SKILL.md, `PushNotification`→omitir. Tabla completa: README § *Instalación alternativa: pi*.

Glue skill: encadena skills existentes (`b1-triage-issue`, `b1-add-worktree`, `b2-build-feature`, `b3-git-commit`, `b4-pull-request`, `b6-pr-review`). **No duplicar su lógica.** El valor de b7 es la orquestación, los budgets, el flujo por pantallas (features colocados en `src/routes`) y el rastro documental. "Tarea" = issue de GitHub.

**Regla de oro de tokens:** todo lo determinista ya vive en `scripts/`. Un paso = una llamada a script + leer sus líneas `K=V`. No re-implementar gates en prosa, no leer logs completos, no leer `references/` hasta el punto indicado.

## Los 5 pasos obligatorios — NO saltarse

Con un número de issue se ejecutan los 5 en orden, aunque el prompt traiga instrucciones inline (van a `user_directives`, refinan scope, no lo atajan). Si un paso falla por entorno, abortar y reportar.

1. **Worktree** — `provision` (usa `setup-worktree.sh --headless`). Prohibido editar el repo principal.
2. **Comentario sticky en el issue** — lo postea `provision` (marker `<!-- b7:status -->`).
3. **Commit(s) via b3-git-commit** — conventional commits.
4. **PR draft + labels** — `b4-pull-request --draft`, cuerpo de `publish-docs.sh pr-body` (con `Closes #<issue>`); labels `ready → in-progress → in-review`.
5. **b6-pr-review sobre el PR** — veredicto publicado; blockers re-iteran o escalan.

## DEFINITION OF DONE

Al CERRAR el run, una sola pasada:

```bash
bash "$PLUGIN_ROOT/skills/b7-issue-to-pr/scripts/guardrails.sh" dod-check "$WORKTREE" <N> "${PR_NUMBER:-none}"
# DOD 1..9=ok|warn|fail y DOD_SUMMARY=ok|needs-human-review|fail; exit 1 si hay fail
```

- `fail` → NO cerrar: completar el check y re-correr.
- `needs-human-review` (fix sin test o waiver) → status final `needs-human-review`.
- Detalle de cada check: `references/runbook.md` (leer solo al depurar).

**Última línea OBLIGATORIA del run** (la parsea b10-ship):

```
B7_DONE issue=<N> pr=<url|none> status=ok|needs-human-review|bailed|aborted screens=<ok|skipped-<r>|fail|none> [lane=<S|M|L>]
```

`screens=`: `ok` = cada pantalla del triage tiene JSON de review sin `verdict: fail`; `skipped-<r>` = existe `.b7/review/SKIPPED.json` con `reason=<r>`; `fail` = algún review en fail; `none` = triage sin screens.

**Frases prohibidas al cerrar** (`references/runbook.md`): "listo para commit/PR", "pendiente: abrir PR", "próximos pasos: <algo del pipeline>". Si vas a escribirlas, el run NO terminó — ejecuta el paso.

## Argumentos

```
<issue> [--dry-run | --wet] [--max-iterations=N] [--budget-files=N] [--no-pr]
        [--no-screens] [--light-review] [--no-changelog] [--lang=es|en]
        [--directives="<texto>"] [--force-complex]
```

**Argumentos recibidos:** `$ARGUMENTS` — única vía de entrada al fork. Primer token = issue; resto = flags; texto libre = `--directives`. Vacío o sin sustituir → abortar pidiendo el número.

Defaults: `--wet`, `--max-iterations=6`, `--budget-files=25`, screens habilitadas, `--lang` autodetectado. `--dry-run` hace worktree + sticky + implementación, sin PR ni label `in-review`. `--light-review`/`--no-changelog` los pasa b10 en modo epic (review light para todo carril; CHANGELOG al rollup).

## Principio: enfocado en pantallas

Cada feature se triagea, diseña, implementa y revisa como pantallas (`screens[]` del triage: `route`, `user_journey`, `acceptance_criteria_visual`, `success_metrics`, `states_required`). Layout colocado: UI en `src/routes/<feature>/+page.svelte`, datos en `server/data.remote.ts`, componentes en `ui/<Componente>.svelte`. Spec: `$PLUGIN_ROOT/skills/b2-build-feature/references/slice-spec.md`. Sin `screens[]` (backend/infra) b7 corre igual, sin review visual, `screens=none` y sin `SKIPPED.json`.

## Workflow

### 0. Bootstrap (script)

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cat "$HOME/.claude/b-pipeline.root" 2>/dev/null || ls -d "$HOME"/.claude/plugins/marketplaces/b-pipeline* 2>/dev/null | head -1)}"
G="$PLUGIN_ROOT/skills/b7-issue-to-pr/scripts/guardrails.sh"
PD="$PLUGIN_ROOT/skills/b7-issue-to-pr/scripts/publish-docs.sh"
bash "$PLUGIN_ROOT/skills/b7-issue-to-pr/scripts/run.sh" $ARGUMENTS   # preflight + lock + cache-issue + context-snapshot + init-state
# leer SCRATCH_DIR= y LOCK_PATH= de su salida. Exit ≠0 = preflight falló: reportar y salir, no arreglar el entorno.
```

`run.sh` deja el lock **retenido a propósito** (persistido en `state.json.lock_file`); toda ruta terminal lo libera (ver Manejo de errores).

### 1. Triage

`Skill(b1-triage-issue "<N> --auto")` pidiéndole escribir `$SCRATCH_DIR/triage.json` según `templates/triage-output.schema.json` (incluye `plan[]` de 3–8 items y `user_directives` si hubo texto inline). Luego:

```bash
bash "$G" triage-gates "$SCRATCH_DIR/triage.json" [--force-complex]
# TRIAGE_GATE=ok | no-pr | bail:<verdict-x|fix-sin-evidence|complex>; exit 4 = triage inválido (corregir y re-validar)
```

- `bail:*` → comentar en el issue (idioma `TRIAGE_LANG`) por qué el bot bailó, `release-lock`, salir 0. Sin worktree ni PR.
- `no-pr` → `security_review_required`: forzar `--no-pr` y marcar revisión humana en el reporte.
- `--force-complex` (lo pasa b10 tras confirmación humana) deja continuar un `complex`; registrarlo en sticky y run-report.

`plan[]` se verifica al cierre (DoD #6): los sub-agentes marcan `publish-docs.sh plan-done <id> --worktree "$WORKTREE"`. Waiver del `regression-test` (fix sin harness): `plan-done regression-test` con nota `waived: <razón>` → status final `needs-human-review`.

### 2. Provision — PASOS OBLIGATORIOS #1 y #2 + carril

```bash
eval "$(bash "$G" provision <N> <feat|fix> <slug-corto> "$SCRATCH_DIR" <wet|dry-run>)"
export WORKTREE BRANCH PORT DEFAULT_BRANCH RUN_LANE   # exit 30/31 = abortar, nada fue escrito en el repo
```

Hace en una pasada: worktree headless (prohibido `git worktree add` directo, un hook lo bloquea), `verify-worktree`, mueve `.b7/*`, heartbeat, `classify-run` (S si simple y ≤5 archivos; L si complex; M el resto), milestone `started`, sticky, labels `ready→in-progress`.

Desde acá **toda** escritura opera sobre `$WORKTREE`. Si `pwd` es el repo principal, detenerse. **Carril S:** leer `references/lane-s.md` ahora (agente `b7-impl-s`, 3 iteraciones).

### 3. Esqueletos de pantalla (script)

```bash
bash "$G" render-screens "$WORKTREE/.b7/triage.json" "$WORKTREE/.b7/screens"
```

El LLM solo refina un esqueleto si `acceptance_criteria_visual` vino vacío o si el paso 4 falla por esqueleto pobre.

### 4. Implementación (loop bounded)

Agente: `Agent(subagent_type="b-pipeline:b7-impl")` en M/L, `b7-impl-s` en S. Sin `model=`: hereda el de la sesión. **Prohibido `general-purpose`** (mete todos los schemas MCP en cada turno). Pasarle:

- Rutas a `.b7/triage.json`, `.b7/screens/`, `.b7/context.md`, `$WORKTREE`.
- Layout colocado, Remote Functions, sin state global, errores `error(STATUS,{message,code})`.
- Si hay form crear/editar: pointer a `skills/b2-build-feature/references/forms-recipe.md`. Si `data_table: true`: usar skill `bt1-data-table` si existe, fallback shadcn Table + paginación server-side.
- Si el plan modifica símbolos existentes: Phase 1.5 de b2 (impact set) y persistir `publish-docs.sh state-set impact_files=<csv|[]>`; scope-growth se declara en el sticky antes de codear.

Tras cada pasada, al inicio de cada iteración `bash "$G" heartbeat "$WORKTREE"`, luego skip-by-scope sobre el diff vs base (`check:machine` si hay `.ts|.svelte|.js`; `lint` si además `.css`; `test:unit` si hay `.test|.spec`), re-corriendo solo lo que estaba rojo en `.b7/iter-status.json`:

```bash
pnpm check:machine -- --threshold error 2>&1 | tee .b7/iter-$N-check.log   # idem lint -- --quiet / test:unit -- --run --reporter=dot
```

Si falla: `scripts/log-filter.sh` → `.tail`; `scripts/error-hash.sh` → `.hash`; hash igual al de la iteración anterior = **abort por no-progress**; si no, alimentar al agente solo el `.tail` + delta del plan.

Pasada final cuando todo está verde: `(cd "$WORKTREE" && bash "$PLUGIN_ROOT/skills/b2-build-feature/scripts/verify.sh")` (exit 0 habilita commit; 3-6 vuelve al loop). Hard stops: iteraciones 6 (3 en S), 25 archivos, 1500 líneas netas, 30 min, hash repetido. `bash "$G" check-budget "$WORKTREE"` mide. Hitar budget = abort + comentar issue.

### 5. Revisión visual (sub-agente por pantalla)

Rampa de skip, en orden; todo skip escribe `$WORKTREE/.b7/review/SKIPPED.json` = `{"reason":"<r>"}` con `<r>` ∈ `no-screens-flag | lane-s-no-ui | no-port | dry-run`, y salta a 5.9:

1. `screens[]` vacío → saltar el paso entero SIN escribir `SKIPPED.json`.
2. `--no-screens` → `no-screens-flag`. 3. `--dry-run` → `dry-run`.
4. `bash "$G" ui-touched "$WORKTREE"` emite `UI_TOUCHED=0` (diff sin `*.svelte`, `*.remote.ts` ni `src/routes/`) → `lane-s-no-ui`. Aplica a **todo carril**; no es juicio del modelo.

Sin skip: **leer y seguir `references/screens-step.md`** (5.0 dev server + `verify-port`, 5.1 auth según `## Auth de pruebas (browser)` del CLAUDE.md del repo, 5.2 un `Agent(b-pipeline:b7-screen-review)` por pantalla en el mismo turno, 5.9 cleanup siempre). `verdict: fail` con sesión válida → volver al paso 4; `warn`/`infra_fail`/`auth-required` → nota, no rebudgetea. Sin puerto recuperable → `no-port`.

### 6. Commit — PASO OBLIGATORIO #3

Precondición: `bash "$G" screens-check "$WORKTREE"` exit 0 (8 = falta review o hay fail → volver a 5/4; 3 = base irresoluble). Con `verify.sh` verde y budgets OK: `publish-docs.sh changelog` (salvo `--no-changelog`) y luego `Skill(b3-git-commit)`. En `--dry-run` no se commitea: avisar que el worktree quedó para inspección. En `--wet` seguir directo a 7 → 8.

### 7. Publicar docs (script)

`bash "$PD" all --worktree "$WORKTREE"` → CHANGELOG + sticky del issue + `.b7/pr-body.md`. Idempotente, sin LLM.

### 8. PR draft + labels + review — PASOS OBLIGATORIOS #4 y #5

Salvo `--dry-run`/`--no-pr`:

```bash
# Skill(b4-pull-request "--draft --label auto-pr-bot --body-file .b7/pr-body.md") → PR_NUMBER/PR_URL
gh issue edit <N> --remove-label in-progress --add-label in-review
bash "$PD" milestone pr-opened --worktree "$WORKTREE"
bash "$PD" state-set pr_url="$PR_URL" pr_number="$PR_NUMBER" pr_link="$PR_URL" --worktree "$WORKTREE"
bash "$PD" issue-comment --worktree "$WORKTREE"
for a in "$WORKTREE"/.b7/review/*-attach.sh; do [ -f "$a" ] && bash "$a"; done   # screenshots al PR
bash "$G" screen-marker "$WORKTREE" "$PR_NUMBER"     # marker que consume el gate SCREEN_EVIDENCE de b6 — exactamente uno
bash "$G" impact-drift "$WORKTREE"                   # señal, nunca gate: si lista archivos, nota en consola/run-report/sticky
bash "$G" heartbeat "$WORKTREE"
```

Luego `Skill(b6-pr-review "<PR> --auto --light")`. **`--light` es el default** (el review profundo lo hace un humano o el epic-review); omitirlo solo si el usuario pidió review completo explícitamente. b6 publica su veredicto solo — no re-postear. Verificar:

```bash
bash "$PLUGIN_ROOT/skills/b6-pr-review/scripts/verdict.sh" read <PR> || echo "WARN: b6 no publicó — postear .b7/review/pr-<PR>.md como fallback"
```

`blockers > 0` → volver al paso 4 si hay budget, si no `needs-human-review`. Warnings no bloquean. Frontera: b7 NO mergea; eso es `b9-close`.

### 9. Run report y cierre

`bash scripts/render-report.sh` desde `.b7/state.json` → `~/.claude/projects/<slug>/b7-runs/<UTC>-issue-<N>.md`. Después `dod-check`, `release-lock`, `B7_DONE`. En `--dry-run` leer `references/dry-run.md`.

## Sub-agentes

| Paso | Sub-agente | Modelo |
|------|-----------|--------|
| 4 | `Agent(b-pipeline:b7-impl)` (M/L) · `b7-impl-s` (S) | el de la sesión |
| 5 | `Agent(b-pipeline:b7-screen-review)` × pantalla, en paralelo | el de la sesión |
| 1, 6, 8 | `Skill` directo (`b1-triage-issue`, `b3-git-commit`, `b4-pull-request`, `b6-pr-review`) | el de la sesión |

## Manejo de errores

- Toda ruta de abort: `bash "$PD" aborted --worktree "$WORKTREE"` (sticky + CHANGELOG `[Aborted]`), run report, y `bash "$G" release-lock "$(jq -r '.lock_file // empty' "$WORKTREE/.b7/state.json")"` (sin `state.json` todavía: `release-lock` sin arg).
- **El lock NO se libera solo.** Éxito, abort y bail lo liberan. Fallback: lock sin tocar 2h se recupera en el próximo preflight.
- Si `publish-docs.sh` falla (`gh` caído), log a stderr y continuar.

## Qué NO hacer

- No escribir triage ni mensajes de commit propios. No bypassear budgets con números más altos: escalar a humano.
- No tocar `package.json`, lockfiles, `.env*`, `*.pem`, `*.key`, `secrets/`, configs de build/CI ni `scripts/*.sh` (el hook `pre-commit-budget.sh` los rechaza; bypass humano `B7_BUDGET_OVERRIDE=1`).
- No leer `git diff` ni logs completos: `.b7/diff-stat.txt`, `Read` con `offset/limit`, `log-filter.sh`.
- No saltarse `b7-screen-review` fuera de la rampa del paso 5; cada skip deja `SKIPPED.json`.

## Referencias (carga bajo demanda — este archivo se paga en cada turno, una reference una vez)

- `runbook.md` — DoD detallado, frases prohibidas, invocación headless. Al cerrar o depurar.
- `screens-step.md` — 5.0–5.9. Solo si la rampa no dio skip.
- `lane-s.md` — carril S. `dry-run.md` — cierre de un dry-run.
- `templates/` — triage-output.schema.json, issue-comment.md, pr-release-notes.md, changelog-entry.md, run-report.md.
