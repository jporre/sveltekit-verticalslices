---
name: b-setup-or-fix
description: 'El experto: audita un repo SvelteKit degradado (load functions y fetch manual en vez de remote functions, sintaxis Svelte 4, sobre-ingeniería, funciones duplicadas, exceso de comentarios, features desparramados) y lo migra por peldaños hacia la base canónica del plugin — o instala esa base en un proyecto nuevo. Usar SOLO cuando el usuario lo invoque directo: "rescata este repo", "limpia este proyecto", "audita el codebase", "define la base del proyecto", "genio de la botella". NO es review de un PR (eso es b6-pr-review) ni construcción de un feature nuevo (eso es b2-build-feature); ningún skill del pipeline lo encadena automático.'
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, AskUserQuestion, Skill, Agent
# model/effort omitidos a propósito: hereda los de la sesión — el diagnóstico y las migraciones necesitan el modelo más capaz disponible
---

## Argumentos recibidos

```text
$ARGUMENTS
```

Sin argumentos: flujo completo (diagnóstico → gate → escalera). Flags:

- **`--init`** — proyecto nuevo o sano: instala la base (E1 + docs semilla) y termina. No audita.
- **`--audit`** — solo FASES 0-2: diagnóstico + plan, ningún archivo se toca. Termina en el reporte.
- **`--feature=<slug>`** — acota E2-E6 a un solo feature (`src/routes/<slug>/`). Para repos grandes o rescates incrementales.
- **`--hasta=E<n>`** — sube la escalera solo hasta ese peldaño (ej. `--hasta=E3`). El plan igual muestra todos.

---


# b-setup-or-fix — base sana o rescate de repo SvelteKit

> **Multi-harness:** en pi, los mecanismos de Claude Code se mapean a equivalentes (`AskUserQuestion`→pregunta en texto, `Agent(subagent_type=…)`→tool `subagent`, `Skill(bN-…)`→`read` del SKILL.md de ese skill, `Workflow`→tool `subagent` con `workflowScript`, `PushNotification`→omitir). Tabla completa: README § *Instalación alternativa: pi*. En Claude Code todo funciona como está escrito.

Los otros skills del pipeline construyen y revisan **cambios** (un issue, un PR). Este opina sobre el **codebase entero**: detecta el código que se degradó — capas inútiles, event handlers que reinventan forms, datos que viajan por `load()`/`fetch` ignorando remote functions, duplicados, prosa — y lo migra por peldaños verificados hacia la misma doctrina que `b2-build-feature` usa para construir y `b6-pr-review` usa para revisar. El resultado: cada feature en su carpeta, remote functions como única vía de datos, runas Svelte 5, mínimo comentario, documentación en archivos.

**Reglas críticas:**

1. **Solo invocación directa del usuario.** Ningún skill (b7, b8, b10) lo encadena, ni siquiera al detectar deuda. Sugerir `/b-pipeline:b-setup-or-fix` es lo máximo permitido a terceros.
2. **Herramientas PRIMERO, análisis después.** Cada fase arranca con un comando; el juicio LLM filtra lo que el script contó.
3. **Nada se edita antes del gate humano de FASE 2.** El diagnóstico completo siempre precede al primer `Edit`.
4. **Un peldaño roto detiene la escalera.** Cada peldaño deja el repo verde (check + build vs baseline) antes del siguiente; si no verifica, se revierte ese peldaño y se para con reporte. Nunca se avanza sobre base rota.

---

## La escalera (tabla canónica)

Orden fijo: primero lo que habilita (config, seguridad), después mover archivos, después migrar datos, al final cosmética y docs (documentan el estado FINAL, no el intermedio). Detalle de transformaciones por peldaño: `references/fix-ladder.md` (misma numeración).

| Peldaño | Corrige | Riesgo |
|---|---|---|
| **E1 Base y seguridad** | flags `remoteFunctions`/`async` faltantes, scripts npm mínimos, infra `requireUser`/`requirePermission` inexistente, remote functions/endpoints sin guard, estado mutable a nivel de módulo en `.server.ts`, secrets hardcodeados | bajo |
| **E2 Estructura** | features fuera de `src/routes/<feature>/`, `*.remote.ts` fuera de `server/` (canónico: `server/data.remote.ts`), `*.remote.ts` bajo `src/lib/server/`, componentes sueltos fuera de `ui/`, docs fuera de `docs/`, wrappers `<Feature>Page.svelte`, sección Estructura stale en README/CLAUDE.md del repo | bajo-medio (mueve archivos: trazar callers antes) |
| **E3 Remote functions** | `load()` en `+page(.server).ts`, `export const actions`, `+server.ts` internos, `onMount`+`fetch`, mutaciones sin refresh → `query`/`form`/`command` + single-flight | medio-alto (cambia semántica SSR: feature por feature, nunca barrido ciego) |
| **E4 Runas y stack** | `on:click`, `export let`, `<slot>`, `$:`, `$effect` que computa, spreads inmutables sobre `$state`, named imports shadcn, `lucide-svelte`, `Select.Value` | medio |
| **E5 Desingenieria y duplicados** | capas pass-through (service/repository/factory para CRUD), helpers que solo reenvían, funciones duplicadas, código muerto | medio-alto (consolidar sin tests del survivor está prohibido) |
| **E6 Comentarios y docs** | prosa que explica el QUÉ (se preserva `// ponytail:`), `docs/readme.md` faltantes, doc nivel repo inexistente | bajo |

**Catálogos canónicos — citar, no duplicar.** Los antipatrones viven en `../b6-pr-review/references/sveltekit-antipatterns.md` (sus secciones 1-14 son lo que este skill llama `AP1`-`AP14`) y los checks de seguridad en `security-checklist.md`; el layout del slice en `../b2-build-feature/references/slice-spec.md` (gana ante cualquier contradicción); la escalera de simpleza en `../b2-build-feature/references/simplicity-ladder.md`. Las siglas `SEC-*`/`CAL-*`/`DUP-*`/`REG-*` son notación interna de este skill — tabla de mapeo a las secciones reales al inicio de `references/fix-ladder.md`. Este skill solo agrega lo propio: la escalera E1-E6, las recetas de migración y el modo base.

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
- `rung-verify.sh baseline` captura los errores **preexistentes** de check y build. Los peldaños se comparan contra este baseline — el genio nunca se atribuye errores que ya estaban, ni exige cero absoluto en un repo que llegó roto (se informa y se sigue).
- Con `--init`, correr igual este preflight completo (gate + rama + baseline) y saltar a **Modo base** (abajo).

## FASE 1: Diagnóstico (solo lectura)

```bash
bash "$PLUGIN_ROOT/skills/b-setup-or-fix/scripts/audit.sh"
```

Emite secciones `=== E1 ===` … `=== E6 ===` con los hits (archivo:línea) y una línea final parseable:

```text
AUDIT_RESULT mode=base|rescate rungs=E1:<n>,E2:<n>,E3:<n>,E4:<n>,E5:<n>,E6:<n> features=<n>
```

El script **cuenta**; el juicio LLM **filtra** antes de que algo sea hallazgo:

- Falsos positivos típicos a descartar: `goto()` post-acción (submit/delete), `$effect` para DOM/timers reales, `+server.ts` que es webhook externo (no se migra a remote function), `load` de página explícitamente pública, imports directos de shadcn permitidos (`Button`, `Input`, `Label`, `Textarea`, `Badge`, `Separator`).
- Lo que el script no ve, lo cubre una pasada LLM: indirección CAL-1..3 (trazar `*.remote.ts` → callees con `codegraph_explore` si hay `.codegraph/`, sino `rg`/Grep), duplicados DUP-1 en zonas calientes (`src/lib/utils`, `helpers`, formateo fecha/moneda, validación), código muerto (exports sin consumidor). Si el skill `finding-duplicate-functions` está disponible, invocarlo para E5; sino, comparación semántica manual sobre el catálogo de exportadas.
- `// ponytail:` marca simplificación deliberada: NO es hallazgo salvo que el techo nombrado ya se superó.
- Hallazgos con formato parseable de b6: `- **E<n>**: <archivo:línea> <descripción en una línea>`.

## FASE 2: Plan + GATE HUMANO (obligatorio, sin excepción)

Presentar el plan como tabla y **preguntar vía AskUserQuestion** hasta qué peldaño subir y, si el repo es grande, qué features entran en esta corrida:

```markdown
| Peldaño | Hallazgos | Riesgo | Qué se hace | Sale verde cuando |
|---|---|---|---|---|
| E1 Base y seguridad | 4 | bajo | flags + guard en 3 remote functions + 1 secret a $env | RUNG_VERIFY ok + audit E1=0 |
| E3 Remote functions | 12 | medio-alto | migrar 4 features: load->query, actions->form | cero load()/actions en el plan + check/build verdes |
| ... | | | | |
```

La columna **"Sale verde cuando"** es obligatoria: nombra el criterio MECÁNICO que determina que el peldaño se logró (RUNG_VERIFY, contadores del audit en 0, check-slice sin violaciones). La aprobación del gate versa sobre esos criterios — el usuario aprueba QUÉ prueba el éxito, no un "de acuerdo" genérico. Nunca preguntar sin la tabla completa visible en el mismo mensaje.

- `--hasta=E<n>` pre-fija el tope, pero la aprobación del plan sigue siendo humana.
- Con `--audit` (o si el usuario no aprueba): terminar aquí con el reporte y `B11_RESULT mode=audit rungs_done= rungs_blocked= features=<n>` (mismo shape siempre, campos vacíos incluidos — los parsers no adivinan).
- Rechazo con razón load-bearing ("ese +server.ts lo consume una app móvil") se anota en el reporte final para que una próxima corrida no lo re-sugiera.

## FASE 3: Ejecución por peldaño

Loop estricto por cada peldaño aprobado, en orden E1 → E6:

1. **Transformar** siguiendo `references/fix-ladder.md` (y `references/migrate-to-remote.md` para E3). E2/E5 mueven o borran símbolos: trazar callers ANTES (`codegraph_callers` o `rg -n '\b<simbolo>\('`) — un caller roto fuera del diff es BLOCKER, la misma regla de regresión de callers que aplica b6 (notación `REG` en fix-ladder.md).
2. **Verificar**:

   ```bash
   bash "$PLUGIN_ROOT/skills/b-setup-or-fix/scripts/rung-verify.sh" E<n>
   ```

   `RUNG_VERIFY ok` exige: check sin errores NUEVOS vs baseline + build no peor que baseline. Además: `svelte-autofixer` sobre cada `.svelte` tocado, y si hay dev server corriendo, browser test rápido de los features tocados (mismo criterio de b2: código que compila pero no se vio en browser NO está listo).
3. **Commitear** vía `Skill b3-git-commit` con mensaje `refactor(genie): E<n> <resumen>` — nunca `git add`/`git commit` a mano. Un peldaño = un commit; prohibido mezclar peldaños.
4. `RUNG_VERIFY fail` → revertir SOLO ese peldaño (`git checkout -- .` + limpiar untracked del peldaño), reportar por qué falló, y **DETENER la escalera**. Los peldaños ya commiteados quedan.

**Scope-growth**: archivo fuera del plan aprobado se declara antes de tocarlo (heredado de b2). E3 va feature por feature — cada feature migrado debe verificar antes del siguiente dentro del peldaño.

## FASE 4: Cierre y reporte

```bash
bash "$PLUGIN_ROOT/skills/b-setup-or-fix/scripts/audit.sh"   # re-correr para el delta
```

Reporte final, corto y con el delta primero:

```markdown
| Peldaño | Antes | Después |
|---|---|---|
| E3 Remote functions | 12 | 2 |

- Peldaños aplicados / omitidos / bloqueados (con razón).
- Deuda restante: candidatos a issues — ofrecer /b-pipeline:b0-conversation-to-issues, no crearlos solo.
- Frase de honestidad obligatoria: "Verifiqué types y build pero NO pude browser-testear <features> porque <razón>."
```

Última línea, machine-readable:

```text
B11_RESULT mode=init|audit|rescate rungs_done=<csv> rungs_blocked=<csv> features=<n>
```

Sugerir el siguiente paso (abrir PR vía b4, o próxima corrida con los features restantes) — **sin ejecutarlo**.

---

## Modo base (`--init`, o `AUDIT_RESULT mode=base`)

Para proyecto nuevo o sano (E2-E4 en cero y menos de 3 features — E5/E6 son señales blandas y no bloquean el modo). Sin `--init`, el gate de FASE 2 corre igual antes de tocar nada. Aplica `references/base-setup.md` completo:

1. Flags `kit.experimental.remoteFunctions: true` + `compilerOptions.experimental.async: true` — donde viva la config: `sveltekit({...})` en `vite.config` o `svelte.config.js` (regla de ubicación en `base-setup.md`; kit >= 2.62 ignora `svelte.config.js` si el plugin recibe opciones).
2. `$lib/server/auth.ts` con `requireUser`/`requirePermission` (formato `verbo:sustantivo`) si no existen.
3. **Auth de pruebas del browser**: analizar el repo (¿usuario seed solo-dev? ¿endpoint de login solo-dev? ¿mint en DB? ¿o login manual + cookies?), decidir la estrategia CON el usuario y declararla en la sección `## Auth de pruebas (browser)` del CLAUDE.md — análisis y template en `base-setup.md` § 3. b7-screen-review y el walkthrough de epic-review leen esa sección.
4. `CLAUDE.md` del repo con la doctrina en ~10 líneas + punteros a `slice-spec.md`.
5. `docs/ARCHITECTURE.md` semilla (stack, mapa de slices, decisiones).
6. Primer slice vía `../b2-build-feature/scripts/scaffold-slice.sh` solo si el usuario nombra un feature concreto — nada especulativo (YAGNI: cero capas, cero scaffolding "para después").
7. Verificar (`rung-verify.sh E1`) y commitear vía b3: `chore(genie): base sveltekit`.

Termina con `B11_RESULT mode=init rungs_done=E1 rungs_blocked= features=<n>`.

---

## Qué NO hacer

- Editar código antes del gate de FASE 2, o continuar la escalera tras un `RUNG_VERIFY fail`.
- Migrar a remote functions un repo cuya versión de SvelteKit no las soporta (< 2.27): E3 se reporta **bloqueado**, no se intenta (`AUDIT` lo detecta en `=== STACK ===`).
- Consolidar duplicados sin verificar que el survivor tiene tests que cubren a los borrados: ante duda, INVESTIGATE — nunca CONSOLIDATE automático.
- Borrar comentarios con contexto útil sin migrarlo antes al `docs/readme.md`. `// ponytail:` y TODO/FIXME accionables se preservan.
- Copiar los catálogos de b2/b6 dentro de este skill (drift documental).
- Resolver "rápido" un hallazgo agregando una capa nueva: la salida de cada peldaño es MENOS código, no más.
- Instalar service worker/PWA por iniciativa propia. Solo si el usuario lo pide, y ahí manda `references/pwa-setup.md`.

## Referencias

- `references/fix-ladder.md` — las transformaciones exactas de cada peldaño E1-E6 con pares MAL/BIEN. Leer al ejecutar FASE 3.
- `references/migrate-to-remote.md` — recetas R1-R7 de migración a remote functions (E3): load→query, actions→form, fetch→await, single-flight. Leer al ejecutar E3.
- `references/base-setup.md` — modo base completo: config canónica, guards, docs semilla, política de comentarios. Leer con `--init` o mode=base.
- `references/pwa-setup.md` — manifest, service worker, cache y flujo de update. Leer SOLO si el usuario pide PWA/offline/instalable; no es parte de la escalera ni del modo base.
- `scripts/audit.sh` — diagnóstico mecánico; secciones `=== E<n> ===` + `AUDIT_RESULT`. Exit 3 = no es SvelteKit.
- `scripts/rung-verify.sh` — `baseline` captura estado inicial; `E<n>` compara y emite `RUNG_VERIFY ok|fail rung=E<n>`.
- `../b6-pr-review/references/sveltekit-antipatterns.md` + `security-checklist.md` — catálogos AP/SEC canónicos.
- `../b2-build-feature/references/slice-spec.md` + `simplicity-ladder.md` + `feature-templates.md` — layout, doctrina de simpleza y templates canónicos.

## Notas

- **Repo sin tests**: `rung-verify` solo cubre types + build; E3/E5 pueden romper runtime sin detectarse. Decirlo en el reporte (frase de honestidad) y recomendar browser test antes del merge.
- **Baseline ya roto**: registrar los errores preexistentes en FASE 0 y comparar contra ellos; informar al usuario antes de seguir, nunca atribuírselos.
- **Skills externos opcionales**: `finding-duplicate-functions` (E5) y `using-remote-functions` (E3) pueden no existir — degradar a los references propios y decirlo en el reporte.
- **Repos grandes**: usar `--feature=<slug>` y correr el rescate en tandas; el reporte deja el backlog explícito.
- **Monorepos**: correr desde la raíz del proyecto SvelteKit, no del monorepo.
- Todo output de este skill en español neutro sin tildes, nunca voseo.
