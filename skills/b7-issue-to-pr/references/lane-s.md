# Carril S — optimizaciones del run rápido

Leer este archivo SOLO cuando `classify-run` (paso 1b) emitió `RUN_LANE=S`. En carriles M y L nada de esto aplica.

## Paso 3 — render MECÁNICO de screens (sin LLM)

NO gastar una pasada de modelo diseñando el esqueleto — y desde el subcomando `render-screens` es el default de TODOS los carriles (ver SKILL.md paso 3):

```bash
bash "$PLUGIN_ROOT/skills/b7-issue-to-pr/scripts/guardrails.sh" render-screens \
  "$WORKTREE/.b7/triage.json" "$WORKTREE/.b7/screens"
```

El archivo resultante **preserva el contrato `criteria_file`** que consume `b7-screen-review` (mismos campos, mismo path `.b7/screens/<Name>.md`); solo cambia que el contenido sale de sustitución de plantilla en vez de razonamiento. Refinar con LLM solo si `acceptance_criteria_visual` vino vacío o el impl del paso 4 falla por esqueleto pobre.

## Paso 4 — agente de implementación e iteraciones

Invocar el agente `agents/b7-impl-s.md` (`model: sonnet`) en vez de `b2-build-feature`. Mismo contrato (feature colocado, Remote Functions, sin state global, errores estructurados), scope acotado, diffs mínimos. Los inputs del paso 4 (rutas a `.b7/triage.json`, `.b7/screens/`, `.b7/context.md`, pointers a forms-recipe y `bt1-data-table`, impact set Phase 1.5) son lane-agnósticos — pasarlos al agente tal como los define el paso 4. Además, el hard stop de **iterations baja a 3** (salvo `--max-iterations=N` explícito).

## Paso 5 — saltar la revisión visual SOLO si el diff es seguro

El carril rápido puede omitir el review visual **únicamente** cuando el diff **no toca** `*.svelte` **NI** `*.remote.ts` **NI** nada bajo `src/routes/`. Las memorias del owner exigen browser check en cualquier cambio de UI o de datos que alimentan una pantalla — un `.remote.ts` cambia lo que la pantalla muestra, así que **no** se salta. Regla observable:

```bash
# lane S: decidir si se puede saltar el review visual
. "$PLUGIN_ROOT/scripts/lib.sh"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-$(bp_default_branch)}"   # rama base real — nunca asumir master
LANE=$(python3 -c 'import json;print(json.load(open("'"$WORKTREE"'/.b7/state.json")).get("lane","M"))')
base=$(git -C "$WORKTREE" merge-base HEAD "$DEFAULT_BRANCH")
touched_ui=$(git -C "$WORKTREE" diff --name-only "$base" \
  | grep -qE '\.svelte$|\.remote\.ts$|^src/routes/' && echo 1 || echo 0)
if [ "$LANE" = S ] && [ "$touched_ui" = 0 ]; then
  echo "lane S + diff sin UI/remote/routes → skip review visual (nota al run-report)"
  # saltar a 5.9 (nada que apagar) / paso 6
fi
```

Si el diff **sí** toca alguno de esos patrones, la revisión visual corre igual que en M/L (no es opcional).

## Paso 8c — review light

Invocar `b6-pr-review "<PR> --auto --light"` — el `--light` (size-gate emitido por `pr-context.sh`, issue #3) recorta el review al tamaño chico del diff.

## No forzar el carril

El carril lo asigna `classify-run` desde `triage.json` (complexity + `files_likely`), no el modelo a ojo. No bajar a sonnet ni recortar iteraciones/review por cuenta propia cuando el run es M/L — eso reintroduce el bug que este carril evita.
