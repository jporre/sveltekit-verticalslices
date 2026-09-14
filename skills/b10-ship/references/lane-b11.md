# Carril b11 — spec ejecutable en vez de b7 (fase 3 con `lane=b11`)

Se llega acá cuando el reconcile emitió `B10_TRIAGE=ready … lane=b11` (label `lane:b11` estampado por b0, o primera línea del body `Carril: b11`). El contrato de salida es EL MISMO de b7 — la línea `B7_DONE` final rutea las fases 4-5, el sticky y los labels sin ningún cambio en b10.

> **Regla dura: la SPEC nunca la escribe un fork.** Un `Agent(subagent_type="fork")` hereda el contexto completo de b10 y lo sigue engordando con la exploración de anclas (medido en issue #57: 16,4 M tokens de entrada, 134 turnos, 67 min por UN issue — el ejecutor barato fue el 1 % del costo). La SPEC la escribe un `Agent(subagent_type="general-purpose")` NUEVO con prompt acotado.

## Pasos

1. **Provision — idéntico a b7.** `guardrails.sh provision <N> <feat|fix|docs|test|chore> <slug> <scratch>` de b7 da worktree, lock/shard (`B7_PARALLEL=1` inline si aplica), heartbeat, sticky y labels. Nada nuevo acá; guardar `WORKTREE=` y `BRANCH=`.

2. **SPEC por agente acotado.** `Agent(subagent_type="general-purpose")` con prompt SOLO de: body del issue (incluida `## Archivos previstos`), ruta del template (`skills/b11-spec-exec/references/spec-template.md`), `REPO=<worktree>` y `DIR=${TMPDIR:-/tmp}/b11/<repo>/<slug>`. Presupuesto: el `--budget-files` del issue y tope ~30 turnos. El agente escribe `$DIR/SPEC.md` (+ archivos completos en `$DIR/files/`) siguiendo las reglas del paso 1 del SKILL de b11 (anclas de `Read`, prettier antes de anclar). Si necesita explorar más allá de los archivos previstos, NO explora: su última línea es `LANE_FALLBACK=b7 reason=<r>` y b10 despacha `Skill b-pipeline:b7-issue-to-pr "<N> --lang=es"` normal (el worktree provisionado se reusa — b7 lo detecta y retoma).

3. **Validar → ejecutar → certificar → revisar** (pasos 2-4 del SKILL de b11, desde el main context — son bash baratos):

   ```bash
   B11="$PLUGIN_ROOT/skills/b11-spec-exec"
   python3 "$B11/scripts/validate-spec.py" "$DIR/SPEC.md"          # SPEC OK o corregir/fallback
   bash "$B11/scripts/exec-spec.sh" "$DIR/SPEC.md"                 # línea EXEC … usd_lista=… (ok exige denials=0)
   python3 "$B11/scripts/validate-spec.py" "$DIR/SPEC.md" --check  # CHECK OK
   ```

   `b11-review` obligatorio si la spec toca `src/` (mismo dispatch del paso 4 de b11). Dos fallas seguidas del ejecutor con `SPEC OK` → `LANE_FALLBACK=b7`.

4. **Tests acotados.** vitest SOLO sobre los archivos tocados (`CI=true pnpm test:unit --run <archivos>` en el worktree, si el repo tiene vitest y la spec tocó `src/` o tests). La suite completa la corre b6 — no pagarla dos veces (issue #57: 28 de 67 min fueron la suite entera dentro del fork).

5. **Commit + PR + review.** `Skill b-pipeline:b3-git-commit` en el worktree; PR con `gh pr create --head <rama>` **desde el worktree** (b4 aborta en el cwd del repo principal); `Skill b-pipeline:b6-pr-review "<PR> --auto --light"`.

6. **Contrato de salida.** Última línea SIEMPRE, con el costo de ambos niveles (sin eso el "dos niveles" no es medible):

   ```
   B7_DONE issue=<N> pr=<url> status=ok lane=b11 exec_usd=<usd_lista de EXEC> spec_turns=<turnos del agente del paso 2>
   ```

   Fallas: `status=bailed` + razón en el sticky, igual que b7. Los tokens `lane=`/`exec_usd=`/`spec_turns=` son informativos (el parser de la fase 3 ignora `k=v` desconocidos) y van al reporte del run.
