# b7 — DoD, runbook y routing (detalle)

Cargado desde `SKILL.md` UNA vez, al CERRAR el run (o al depurar una invocación).
No se necesita durante el loop de implementación — por eso vive acá y no en el prefijo del fork.

## DEFINITION OF DONE — bloque verificable

Antes de devolver el resumen final al usuario, el orquestador **debe** correr estos checks
observables y exhibir el resultado de cada uno. Si alguno falla, el run no terminó.

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cat "$HOME/.claude/b-pipeline.root" 2>/dev/null || ls -d "$HOME"/.claude/plugins/marketplaces/b-pipeline* 2>/dev/null | head -1)}"
. "$PLUGIN_ROOT/scripts/lib.sh"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-$(bp_default_branch)}"   # rama base real — nunca asumir master
# 1. Worktree existe, fue creado por setup-worktree.sh, y la rama está sobre la rama default
bash "$PLUGIN_ROOT/skills/b7-issue-to-pr/scripts/guardrails.sh" verify-worktree "$WORKTREE"
git -C "$WORKTREE" rev-parse --abbrev-ref HEAD       # feat/<N>-... o fix/<N>-...
# 2. Comentario sticky en el issue
gh issue view <N> --json comments -q '.comments[].body' | grep -q '<!-- b7:status -->'
# 3. Commits existen (al menos uno) y la rama default no se tocó
git -C "$WORKTREE" log "$DEFAULT_BRANCH"..HEAD --oneline | wc -l   # >= 1
git -C "$REPO_MAIN" status --porcelain                  # vacío
# 4. PR draft abierto y labels del issue sincronizadas
gh pr list --head "$(git -C "$WORKTREE" rev-parse --abbrev-ref HEAD)" --json number,isDraft,url
gh issue view <N> --json labels -q '.labels[].name'     # contiene "in-review", no "ready"/"auto-pr"
# 5. b6-pr-review ejecutado, veredicto publicado en el PR (lector unico del marker)
bash "$PLUGIN_ROOT/skills/b6-pr-review/scripts/verdict.sh" read <PR>   # exit 0 obligatorio (exit 3 = sin review)
# 6. Plan estructurado completo (todos los items done o plan vacío)
bash "$PLUGIN_ROOT/skills/b7-issue-to-pr/scripts/publish-docs.sh" plan-check --worktree "$WORKTREE"   # exit 0 obligatorio
# 7. Worktree limpio post-commit (NADA fuera del commit — exit 0 obligatorio)
bash "$PLUGIN_ROOT/skills/b1-add-worktree/scripts/assert-clean.sh" "$WORKTREE" --fix
# 8. Gate de regresion: un fix cuyo diff no toca ningun test degrada a needs-human-review (NO aborta)
if [ "$(jq -r '.type' "$WORKTREE/.b7/triage.json")" = "fix" ] \
   && ! git -C "$WORKTREE" diff --name-only "$DEFAULT_BRANCH"..HEAD | grep -qE '\.(test|spec)\.'; then
  echo "FIX_SIN_TEST — fix sin test de regresion; status=needs-human-review"
fi
# 9. Screen-review verificable: JSON de review por cada pantalla del triage, o SKIPPED.json con
#    reason valido (exit 8 = run invalido: falta review sin skip valido, o algun verdict=fail)
bash "$PLUGIN_ROOT/skills/b7-issue-to-pr/scripts/guardrails.sh" screens-check "$WORKTREE"
```

Si el check 7 sale 6 (código sin commitear), volver a invocar `b3-git-commit` en el worktree y pushear — el run NO está terminado con trabajo fuera del commit. Si sale 7 (artefactos persistentes que `--fix` no pudo excluir), listarlos en el run-report como warning y continuar — mismo criterio que b9 PASO 1.5: los artefactos no invalidan el run.

Si el check 8 imprime `FIX_SIN_TEST`, el run no aborta pero su status final es `needs-human-review` (no `ok`): un fix que no toca tests necesita que un humano confirme que la ausencia de regresión es aceptable. Si hubo waiver explícito, la degradación es la misma (ver "Waiver explícito" en el paso 1).

Si el check 9 sale 8, el run NO está terminado: falta el JSON de review de alguna pantalla sin skip válido, o hay un `verdict: fail` sin resolver — volver al paso 5 (o al loop del paso 4 si el fail es de criterio visual) antes de cerrar. Exit 3 = rama base irresoluble en el cross-check (problema de entorno, no del run): también bloquea — parar con diagnóstico, no adivinar. `not-evaluated` NO es fail (pass-through con nota). Con `triage.screens[]` vacío o ausente, `screens-check` sale 0 directo sin exigir artefactos.

### Frases prohibidas al cerrar el run

Estas frases significan "abandoné a mitad de camino" y son síntoma del bug que este skill busca evitar. Si estás por escribirlas, el run no está terminado — ejecuta el paso pendiente:

- "Ready for b3-git-commit + b4-pull-request"
- "Listo para commit / Listo para PR"
- "Pendiente: abrir PR / correr review"
- "Próximos pasos: <algo del pipeline>"
- "Worktree con cambios sin commitear" (excepto en `--dry-run` explícito)

En `--wet` el cierre válido es: branch + commits + PR URL + review adjunto + labels actualizadas. En `--dry-run` el cierre válido es: branch + commits opcionales + worktree listo para inspección + label `in-progress` + comentario sticky.

## Sub-agentes y routing de modelo

| Paso | Sub-agente | Modelo | Razón |
|------|-----------|--------|-------|
| 4 Implementación | `Agent(b-pipeline:b7-impl)` en M/L · `agents/b7-impl-s.md` en S | sonnet en S y M, opus en L (`model` del Agent call) | Aislar contexto de exploración + tool calls verbosos. Orquestador solo recibe resumen. **Nunca `general-purpose`**: su toolset `*` arrastra todos los schemas MCP al prompt del sub-agente, en cada turno del loop. |
| 5 Revisión visual | `Agent(b-pipeline:b7-screen-review)` — agente del plugin | sonnet (multimodal, no necesita opus) | Toolset de browser (`agent-browser`) es independiente. Paralelizar por pantalla. Output binario (PNG) no contamina contexto. |
| Triage (`b1-triage-issue`) | Skill directo (`context: fork`) | sonnet — la decisión de scope está anclada al schema de `.b7/triage.json` | Determinístico y rápido; sub-agente sería overkill. |
| Commit / PR / log summarizers | Skill directo | haiku cuando sea posible | Idem. |


## Invocación headless

```bash
# Default (wet) — corre los 5 pasos completos: worktree, sticky, commits, PR+labels, review
claude -p --permission-mode acceptEdits "Use skill b7-issue-to-pr with arguments: 142"
# Flags combinables con el numero de issue:
#   --directives='agregale columna rut'   directivas inline del usuario
#   --dry-run                             inspeccionar antes de PR
#   --no-screens                          issue puramente backend
```

Cuando el usuario invoca de forma interactiva con texto pegado (`/b7-issue-to-pr #121 hola agrega el campo X`), el skill interpreta `121` como issue y el resto como `--directives`. El pipeline corre los 5 pasos igual que en headless.
