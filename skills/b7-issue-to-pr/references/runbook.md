# b7 — DoD, runbook y routing (detalle)

Cargado desde `SKILL.md` UNA vez, al CERRAR el run (o al depurar una invocación).
No se necesita durante el loop de implementación — por eso vive acá y no en el prefijo del fork.

## DEFINITION OF DONE — bloque verificable

Los 9 checks corren en UNA pasada con el subcomando determinístico (el orquestador NO los ejecuta a mano — mismo criterio, 1 turno):

```bash
bash "$PLUGIN_ROOT/skills/b7-issue-to-pr/scripts/guardrails.sh" dod-check "$WORKTREE" <N> "${PR_NUMBER:-none}"
# emite DOD 1=ok|warn|fail ... 9=ok|warn|fail y DOD_SUMMARY=ok|needs-human-review|fail
# exit 1 si hay fail. Checks 4/5 = skip cuando no hay PR (--dry-run/--no-pr).
```

Semántica por check (lo que dod-check implementa internamente — útil al depurar):

1. Worktree creado por `setup-worktree.sh`, rama != default (`verify-worktree` + branch check)
2. Sticky `<!-- b7:status -->` en el issue
3. ≥1 commit sobre la default y main tree limpio (`git status --porcelain` vacío en el repo principal)
4. PR draft abierto y labels sincronizadas (`in-review`, sin `ready`) — skip sin PR
5. `b6-pr-review` con veredicto publicado (`verdict.sh read` exit 0) — skip sin PR
6. Plan estructurado completo (`plan-check` exit 0)
7. Worktree limpio post-commit (`assert-clean.sh --fix`; exit 7 = artefactos persistentes → WARN, no fail)
8. Gate de regresión: fix sin test en el diff → WARN (`DOD_SUMMARY=needs-human-review`, no aborta)
9. Screen-review verificable (`screens-check`; exit 8 = run inválido)

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
