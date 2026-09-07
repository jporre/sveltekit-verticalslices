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

Invocar el agente `agents/b7-impl-s.md` en vez de `b2-build-feature` (modelo: el de la sesión). Mismo contrato (feature colocado, Remote Functions, sin state global, errores estructurados), scope acotado, diffs mínimos. Los inputs del paso 4 (rutas a `.b7/triage.json`, `.b7/screens/`, `.b7/context.md`, pointers a forms-recipe y `bt1-data-table`, impact set Phase 1.5) son lane-agnósticos — pasarlos al agente tal como los define el paso 4. Además, el hard stop de **iterations baja a 3** (salvo `--max-iterations=N` explícito).

## Paso 5 — saltar la revisión visual SOLO si el diff es seguro

Regla única para TODO carril (SKILL.md paso 5): `guardrails.sh ui-touched "$WORKTREE"` → `UI_TOUCHED=0` (diff sin `*.svelte`, `*.remote.ts` ni `src/routes/`) escribe `SKIPPED.json` con `reason=lane-s-no-ui`. Un `.remote.ts` cambia lo que la pantalla muestra, así que NO se salta. Con `UI_TOUCHED=1` la revisión corre igual que en M/L.

## Paso 8c — review light

Invocar `b6-pr-review "<PR> --auto --light"` — el `--light` (size-gate emitido por `pr-context.sh`, issue #3) recorta el review al tamaño chico del diff.

## No forzar el carril

El carril lo asigna `classify-run` desde `triage.json` (complexity + `files_likely`), no el modelo a ojo. No recortar iteraciones/review por cuenta propia cuando el run es M/L — eso reintroduce el bug que este carril evita.
