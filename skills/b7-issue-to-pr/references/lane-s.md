# Carril S — optimizaciones del run rapido

Leer este archivo SOLO cuando `classify-run` (paso 1b) emitio `RUN_LANE=S`. En carriles M y L nada de esto aplica.

## Paso 3 — render MECANICO de screens (sin LLM)

NO gastar una pasada de modelo diseñando el esqueleto. Renderizar `.b7/screens/<Name>.md` directamente desde `triage.json` — un bloque por cada `screen` con su `route`, `user_journey` y `acceptance_criteria_visual`. El archivo resultante **preserva el contrato `criteria_file`** que consume `b7-screen-review` (mismos campos, mismo path `.b7/screens/<Name>.md`); solo cambia que el contenido sale de sustitucion de plantilla en vez de razonamiento. Ejemplo minimo por pantalla:

```bash
# lane S: render mecanico de cada screen del triage (sin modelo)
python3 - "$WORKTREE/.b7/triage.json" "$WORKTREE/.b7/screens" <<'PY'
import json, os, sys
triage, outdir = sys.argv[1], sys.argv[2]
os.makedirs(outdir, exist_ok=True)
for s in json.load(open(triage)).get("screens", []):
    lines = [f"# {s['name']}  ({s['route']})", "",
             f"Journey: {s.get('user_journey','')}", "", "Criterios visuales:"]
    lines += [f"- {c}" for c in s.get("acceptance_criteria_visual", [])]
    open(os.path.join(outdir, f"{s['name']}.md"), "w").write("\n".join(lines) + "\n")
PY
```

## Paso 4 — agente de implementacion e iteraciones

Invocar el agente `agents/b7-impl-s.md` (`model: sonnet`) en vez de `b2-build-feature`. Mismo contrato (feature colocado, Remote Functions, sin state global, errores estructurados), scope acotado, diffs minimos. Los inputs del paso 4 (rutas a `.b7/triage.json`, `.b7/screens/`, `.b7/context.md`, pointers a forms-recipe y `bt1-data-table`, impact set Phase 1.5) son lane-agnosticos — pasarlos al agente tal como los define el paso 4. Ademas, el hard stop de **iterations baja a 3** (salvo `--max-iterations=N` explicito).

## Paso 5 — saltar la revision visual SOLO si el diff es seguro

El carril rapido puede omitir el review visual **unicamente** cuando el diff **no toca** `*.svelte` **NI** `*.remote.ts` **NI** nada bajo `src/routes/`. Las memorias del owner exigen browser check en cualquier cambio de UI o de datos que alimentan una pantalla — un `.remote.ts` cambia lo que la pantalla muestra, asi que **no** se salta. Regla observable:

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

Si el diff **si** toca alguno de esos patrones, la revision visual corre igual que en M/L (no es opcional).

## Paso 8c — review light

Invocar `b6-pr-review "<PR> --auto --light"` — el `--light` (size-gate emitido por `pr-context.sh`, issue #3) recorta el review al tamaño chico del diff.

## No forzar el carril

El carril lo asigna `classify-run` desde `triage.json` (complexity + `files_likely`), no el modelo a ojo. No bajar a sonnet ni recortar iteraciones/review por cuenta propia cuando el run es M/L — eso reintroduce el bug que este carril evita.
