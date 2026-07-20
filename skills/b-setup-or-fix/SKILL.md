---
name: b-setup-or-fix
description: 'El experto: audita un repo SvelteKit degradado (load functions y fetch manual en vez de remote functions, sintaxis Svelte 4, sobre-ingenieria, funciones duplicadas, exceso de comentarios, features desparramados) y lo migra por peldaños hacia la base canonica del plugin — o instala esa base en un proyecto nuevo. Usar SOLO cuando el usuario lo invoque directo: "rescata este repo", "limpia este proyecto", "audita el codebase", "define la base del proyecto", "genio de la botella". NO es review de un PR (eso es b6-pr-review) ni construccion de un feature nuevo (eso es b2-build-feature); ningun skill del pipeline lo encadena automatico.'
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, AskUserQuestion, Skill, Agent
# model/effort omitidos a proposito: hereda los de la sesion — el diagnostico y las migraciones necesitan el modelo mas capaz disponible
---

## Argumentos recibidos

```text
$ARGUMENTS
```

Sin argumentos: flujo completo (diagnostico → gate → escalera). Flags:

- **`--init`** — proyecto nuevo o sano: instala la base (E1 + docs semilla) y termina. No audita.
- **`--audit`** — solo FASES 0-2: diagnostico + plan, ningun archivo se toca. Termina en el reporte.
- **`--feature=<slug>`** — acota E2-E6 a un solo feature (`src/routes/<slug>/`). Para repos grandes o rescates incrementales.
- **`--hasta=E<n>`** — sube la escalera solo hasta ese peldaño (ej. `--hasta=E3`). El plan igual muestra todos.

---

# b-setup-or-fix — base sana o rescate de repo SvelteKit

Los otros skills del pipeline construyen y revisan **cambios** (un issue, un PR). Este opina sobre el **codebase entero**: detecta el codigo que se degrado — capas inutiles, event handlers que reinventan forms, datos que viajan por `load()`/`fetch` ignorando remote functions, duplicados, prosa — y lo migra por peldaños verificados hacia la misma doctrina que `b2-build-feature` usa para construir y `b6-pr-review` usa para revisar. El resultado: cada feature en su carpeta, remote functions como unica via de datos, runas Svelte 5, minimo comentario, documentacion en archivos.

**Reglas criticas:**

1. **Solo invocacion directa del usuario.** Ningun skill (b7, b8, b10) lo encadena, ni siquiera al detectar deuda. Sugerir `/b-pipeline:b-setup-or-fix` es lo maximo permitido a terceros.
2. **Herramientas PRIMERO, analisis despues.** Cada fase arranca con un comando; el juicio LLM filtra lo que el script conto.
3. **Nada se edita antes del gate humano de FASE 2.** El diagnostico completo siempre precede al primer `Edit`.
4. **Un peldaño roto detiene la escalera.** Cada peldaño deja el repo verde (check + build vs baseline) antes del siguiente; si no verifica, se revierte ese peldaño y se para con reporte. Nunca se avanza sobre base rota.

---

## La escalera (tabla canonica)

Orden fijo: primero lo que habilita (config, seguridad), despues mover archivos, despues migrar datos, al final cosmetica y docs (documentan el estado FINAL, no el intermedio). Detalle de transformaciones por peldaño: `references/fix-ladder.md` (misma numeracion).

| Peldaño | Corrige | Riesgo |
|---|---|---|
| **E1 Base y seguridad** | flags `remoteFunctions`/`async` faltantes, scripts npm minimos, infra `requireUser`/`requirePermission` inexistente, remote functions/endpoints sin guard, estado mutable a nivel de modulo en `.server.ts`, secrets hardcodeados | bajo |
| **E2 Estructura** | features fuera de `src/routes/<feature>/`, `data.remote.ts` generico, `*.remote.ts` bajo `src/lib/server/`, subcarpetas `ui/`, wrappers `<Feature>Page.svelte` | bajo-medio (mueve archivos: trazar callers antes) |
| **E3 Remote functions** | `load()` en `+page(.server).ts`, `export const actions`, `+server.ts` internos, `onMount`+`fetch`, mutaciones sin refresh → `query`/`form`/`command` + single-flight | medio-alto (cambia semantica SSR: feature por feature, nunca barrido ciego) |
| **E4 Runas y stack** | `on:click`, `export let`, `<slot>`, `$:`, `$effect` que computa, spreads inmutables sobre `$state`, named imports shadcn, `lucide-svelte`, `Select.Value` | medio |
| **E5 Desingenieria y duplicados** | capas pass-through (service/repository/factory para CRUD), helpers que solo reenvian, funciones duplicadas, codigo muerto | medio-alto (consolidar sin tests del survivor esta prohibido) |
| **E6 Comentarios y docs** | prosa que explica el QUE (se preserva `// ponytail:`), `<feature>.md` faltantes, doc nivel repo inexistente | bajo |

**Catalogos canonicos — citar, no duplicar.** Los antipatrones viven en `../b6-pr-review/references/sveltekit-antipatterns.md` (sus secciones 1-14 son lo que este skill llama `AP1`-`AP14`) y los checks de seguridad en `security-checklist.md`; el layout del slice en `../b2-build-feature/references/slice-spec.md` (gana ante cualquier contradiccion); la escalera de simpleza en `../b2-build-feature/references/simplicity-ladder.md`. Las siglas `SEC-*`/`CAL-*`/`DUP-*`/`REG-*` son notacion interna de este skill — tabla de mapeo a las secciones reales al inicio de `references/fix-ladder.md`. Este skill solo agrega lo propio: la escalera E1-E6, las recetas de migracion y el modo base.

---

## FASE 0: Preflight

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cat "$HOME/.claude/b-pipeline.root" 2>/dev/null || ls -d "$HOME"/.claude/plugins/marketplaces/b-pipeline* 2>/dev/null | head -1)}"
. "$PLUGIN_ROOT/scripts/lib.sh"

grep -q '"@sveltejs/kit"' package.json || echo "ABORT: no es un proyecto SvelteKit"   # gate barato ANTES de crear rama o pagar el baseline
git status --porcelain               # debe salir vacio; sucio => ABORT: working tree sucio, commitea o stashea
git checkout -b "genie/$(date +%Y%m%d)-<slug>" "$(bp_default_branch)"   # rama nueva DESDE la default — nunca colgada de una feature branch a medias

bash "$PLUGIN_ROOT/skills/b-setup-or-fix/scripts/rung-verify.sh" baseline
```

- `<slug>` corto describiendo el alcance (`rescate`, `init`, o el `--feature`).
- `rung-verify.sh baseline` captura los errores **preexistentes** de check y build. Los peldaños se comparan contra este baseline — el genio nunca se atribuye errores que ya estaban, ni exige cero absoluto en un repo que llego roto (se informa y se sigue).
- Con `--init`, correr igual este preflight completo (gate + rama + baseline) y saltar a **Modo base** (abajo).

## FASE 1: Diagnostico (solo lectura)

```bash
bash "$PLUGIN_ROOT/skills/b-setup-or-fix/scripts/audit.sh"
```

Emite secciones `=== E1 ===` … `=== E6 ===` con los hits (archivo:linea) y una linea final parseable:

```text
AUDIT_RESULT mode=base|rescate rungs=E1:<n>,E2:<n>,E3:<n>,E4:<n>,E5:<n>,E6:<n> features=<n>
```

El script **cuenta**; el juicio LLM **filtra** antes de que algo sea hallazgo:

- Falsos positivos tipicos a descartar: `goto()` post-accion (submit/delete), `$effect` para DOM/timers reales, `+server.ts` que es webhook externo (no se migra a remote function), `load` de pagina explicitamente publica, imports directos de shadcn permitidos (`Button`, `Input`, `Label`, `Textarea`, `Badge`, `Separator`).
- Lo que el script no ve, lo cubre una pasada LLM: indireccion CAL-1..3 (trazar `*.remote.ts` → callees con `codegraph_explore` si hay `.codegraph/`, sino `rg`/Grep), duplicados DUP-1 en zonas calientes (`src/lib/utils`, `helpers`, formateo fecha/moneda, validacion), codigo muerto (exports sin consumidor). Si el skill `finding-duplicate-functions` esta disponible, invocarlo para E5; sino, comparacion semantica manual sobre el catalogo de exportadas.
- `// ponytail:` marca simplificacion deliberada: NO es hallazgo salvo que el techo nombrado ya se supero.
- Hallazgos con formato parseable de b6: `- **E<n>**: <archivo:linea> <descripcion en una linea>`.

## FASE 2: Plan + GATE HUMANO (obligatorio, sin excepcion)

Presentar el plan como tabla y **preguntar via AskUserQuestion** hasta que peldaño subir y, si el repo es grande, que features entran en esta corrida:

```markdown
| Peldaño | Hallazgos | Riesgo | Que se hace |
|---|---|---|---|
| E1 Base y seguridad | 4 | bajo | flags + guard en 3 remote functions + 1 secret a $env |
| E3 Remote functions | 12 | medio-alto | migrar 4 features: load->query, actions->form |
| ... | | | |
```

- `--hasta=E<n>` pre-fija el tope, pero la aprobacion del plan sigue siendo humana.
- Con `--audit` (o si el usuario no aprueba): terminar aqui con el reporte y `B11_RESULT mode=audit rungs_done= rungs_blocked= features=<n>` (mismo shape siempre, campos vacios incluidos — los parsers no adivinan).
- Rechazo con razon load-bearing ("ese +server.ts lo consume una app movil") se anota en el reporte final para que una proxima corrida no lo re-sugiera.

## FASE 3: Ejecucion por peldaño

Loop estricto por cada peldaño aprobado, en orden E1 → E6:

1. **Transformar** siguiendo `references/fix-ladder.md` (y `references/migrate-to-remote.md` para E3). E2/E5 mueven o borran simbolos: trazar callers ANTES (`codegraph_callers` o `rg -n '\b<simbolo>\('`) — un caller roto fuera del diff es BLOCKER, la misma regla de regresion de callers que aplica b6 (notacion `REG` en fix-ladder.md).
2. **Verificar**:

   ```bash
   bash "$PLUGIN_ROOT/skills/b-setup-or-fix/scripts/rung-verify.sh" E<n>
   ```

   `RUNG_VERIFY ok` exige: check sin errores NUEVOS vs baseline + build no peor que baseline. Ademas: `svelte-autofixer` sobre cada `.svelte` tocado, y si hay dev server corriendo, browser test rapido de los features tocados (mismo criterio de b2: codigo que compila pero no se vio en browser NO esta listo).
3. **Commitear** via `Skill b3-git-commit` con mensaje `refactor(genie): E<n> <resumen>` — nunca `git add`/`git commit` a mano. Un peldaño = un commit; prohibido mezclar peldaños.
4. `RUNG_VERIFY fail` → revertir SOLO ese peldaño (`git checkout -- .` + limpiar untracked del peldaño), reportar por que fallo, y **DETENER la escalera**. Los peldaños ya commiteados quedan.

**Scope-growth**: archivo fuera del plan aprobado se declara antes de tocarlo (heredado de b2). E3 va feature por feature — cada feature migrado debe verificar antes del siguiente dentro del peldaño.

## FASE 4: Cierre y reporte

```bash
bash "$PLUGIN_ROOT/skills/b-setup-or-fix/scripts/audit.sh"   # re-correr para el delta
```

Reporte final, corto y con el delta primero:

```markdown
| Peldaño | Antes | Despues |
|---|---|---|
| E3 Remote functions | 12 | 2 |

- Peldaños aplicados / omitidos / bloqueados (con razon).
- Deuda restante: candidatos a issues — ofrecer /b-pipeline:b0-conversation-to-issues, no crearlos solo.
- Frase de honestidad obligatoria: "Verifique types y build pero NO pude browser-testear <features> porque <razon>."
```

Ultima linea, machine-readable:

```text
B11_RESULT mode=init|audit|rescate rungs_done=<csv> rungs_blocked=<csv> features=<n>
```

Sugerir el siguiente paso (abrir PR via b4, o proxima corrida con los features restantes) — **sin ejecutarlo**.

---

## Modo base (`--init`, o `AUDIT_RESULT mode=base`)

Para proyecto nuevo o sano (E2-E4 en cero y menos de 3 features — E5/E6 son señales blandas y no bloquean el modo). Sin `--init`, el gate de FASE 2 corre igual antes de tocar nada. Aplica `references/base-setup.md` completo:

1. `svelte.config.js` con `kit.experimental.remoteFunctions: true` + `compilerOptions.experimental.async: true`.
2. `$lib/server/auth.ts` con `requireUser`/`requirePermission` (formato `verbo:sustantivo`) si no existen.
3. `CLAUDE.md` del repo con la doctrina en ~10 lineas + punteros a `slice-spec.md`.
4. `docs/ARCHITECTURE.md` semilla (stack, mapa de slices, decisiones).
5. Primer slice via `../b2-build-feature/scripts/scaffold-slice.sh` solo si el usuario nombra un feature concreto — nada especulativo (YAGNI: cero capas, cero scaffolding "para despues").
6. Verificar (`rung-verify.sh E1`) y commitear via b3: `chore(genie): base sveltekit`.

Termina con `B11_RESULT mode=init rungs_done=E1 rungs_blocked= features=<n>`.

---

## Que NO hacer

- Editar codigo antes del gate de FASE 2, o continuar la escalera tras un `RUNG_VERIFY fail`.
- Migrar a remote functions un repo cuya version de SvelteKit no las soporta (< 2.27): E3 se reporta **bloqueado**, no se intenta (`AUDIT` lo detecta en `=== STACK ===`).
- Consolidar duplicados sin verificar que el survivor tiene tests que cubren a los borrados: ante duda, INVESTIGATE — nunca CONSOLIDATE automatico.
- Borrar comentarios con contexto util sin migrarlo antes al `<feature>.md`. `// ponytail:` y TODO/FIXME accionables se preservan.
- Copiar los catalogos de b2/b6 dentro de este skill (drift documental).
- Resolver "rapido" un hallazgo agregando una capa nueva: la salida de cada peldaño es MENOS codigo, no mas.
- Instalar service worker/PWA por iniciativa propia. Solo si el usuario lo pide, y ahi manda `references/pwa-setup.md`.

## Referencias

- `references/fix-ladder.md` — las transformaciones exactas de cada peldaño E1-E6 con pares MAL/BIEN. Leer al ejecutar FASE 3.
- `references/migrate-to-remote.md` — recetas R1-R7 de migracion a remote functions (E3): load→query, actions→form, fetch→await, single-flight. Leer al ejecutar E3.
- `references/base-setup.md` — modo base completo: config canonica, guards, docs semilla, politica de comentarios. Leer con `--init` o mode=base.
- `references/pwa-setup.md` — manifest, service worker, cache y flujo de update. Leer SOLO si el usuario pide PWA/offline/instalable; no es parte de la escalera ni del modo base.
- `scripts/audit.sh` — diagnostico mecanico; secciones `=== E<n> ===` + `AUDIT_RESULT`. Exit 3 = no es SvelteKit.
- `scripts/rung-verify.sh` — `baseline` captura estado inicial; `E<n>` compara y emite `RUNG_VERIFY ok|fail rung=E<n>`.
- `../b6-pr-review/references/sveltekit-antipatterns.md` + `security-checklist.md` — catalogos AP/SEC canonicos.
- `../b2-build-feature/references/slice-spec.md` + `simplicity-ladder.md` + `feature-templates.md` — layout, doctrina de simpleza y templates canonicos.

## Notas

- **Repo sin tests**: `rung-verify` solo cubre types + build; E3/E5 pueden romper runtime sin detectarse. Decirlo en el reporte (frase de honestidad) y recomendar browser test antes del merge.
- **Baseline ya roto**: registrar los errores preexistentes en FASE 0 y comparar contra ellos; informar al usuario antes de seguir, nunca atribuirselos.
- **Skills externos opcionales**: `finding-duplicate-functions` (E5) y `using-remote-functions` (E3) pueden no existir — degradar a los references propios y decirlo en el reporte.
- **Repos grandes**: usar `--feature=<slug>` y correr el rescate en tandas; el reporte deja el backlog explicito.
- **Monorepos**: correr desde la raiz del proyecto SvelteKit, no del monorepo.
- Todo output de este skill en español neutro sin tildes, nunca voseo.
