---
name: b11-spec-exec
description: 'Cambio mecánico en dos niveles: la sesión escribe una SPEC ejecutable (copias + ediciones exactas + aceptación), un validador determinista la ensaya en un clon, un modelo barato (GLM 5.3 Flash vía OpenRouter, o Haiku) la aplica en un `claude -p` aislado y el validador certifica byte a byte. Usar cuando el cambio ya está decidido archivo por archivo y no requiere descubrimiento: renames, bumps de versión, docs/config, ediciones dictadas, instalación de archivos ya escritos. NO para features ni bugs que exijan explorar o decidir (eso es b7/b2).'
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent
---

## Argumentos recibidos

```text
$ARGUMENTS
```

Acepta: descripción del cambio (la sesión escribe la spec) o ruta a una `SPEC.md` ya escrita. Flags: `--model <alias|proveedor/slug>` (ejecutor), `--review` (fuerza el revisor del paso 4), `--dry-run` (solo pasos 1-2).

---

# b11-spec-exec — spec ejecutable + modelo barato

> **Multi-harness:** en pi, `Agent(subagent_type=…)`→tool `subagent`; el resto es bash. Tabla completa: README § *Instalación alternativa: pi*.

Dos niveles. **Arriba** (esta sesión, modelo caro): decide y escribe una spec sin ambigüedad. **Abajo** (proceso `claude -p` aislado, modelo barato): la aplica sin pensar. **Entre medio**, `validate-spec.py`: ensaya la spec antes de gastar un token y certifica el resultado después. Si el validador puede aplicar la spec solo, el ejecutor no tiene nada que inventar.

**Por qué** (benchmark 2026-09-12, PROMPT 1.13, 14 archivos, ambos byte-idénticos al ensayo):

| Ejecutor | Turnos | Duración | Costo lista |
| --- | --- | --- | --- |
| Haiku 4.5 (plan) | 33 | 4 min 13 s | ≈ US$ 0,38 |
| GLM 5.3 Flash (OpenRouter) | 34 | 2 min 28 s | ≈ US$ 0,044 |

Escribir la spec cuesta más que ejecutarla. El ahorro real: el loop mecánico no consume cuota del plan ni contexto de la sesión, y el resultado es verificable sin leer el diff.

---

## Flujo

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cat "$HOME/.claude/b-pipeline.root" 2>/dev/null || ls -d "$HOME"/.claude/plugins/marketplaces/b-pipeline* 2>/dev/null | head -1)}"
B11="$PLUGIN_ROOT/skills/b11-spec-exec"
REPO="$(git rev-parse --show-toplevel)"
DIR="$HOME/.claude/b11/$(basename "$REPO")/<slug-del-cambio>"   # fuera del repo: no ensucia git status
mkdir -p "$DIR/files"
git -C "$REPO" status --porcelain | wc -l                          # debe ser 0; si no, detenerse
```

Precondición dura: árbol limpio. El validador clona `HEAD`; con cambios sin commitear el ensayo y la certificación miran cosas distintas.

### 1. Spec

Leer `references/spec-template.md` y escribir `$DIR/SPEC.md` con sus secciones 0-6 (la sección 0 va literal). Reglas al escribirla:

- **Archivos nuevos**: la sesión los escribe completos en `$DIR/files/…` y los declara con `COPIAR: origen -> destino [+x]`. El ejecutor copia, no redacta.
- **Ediciones**: `BUSCAR` sale de un `Read` del archivo, nunca de memoria; único en el archivo (2+ líneas de contexto o una línea inequívoca). Insertar = `REEMPLAZAR` repite el `BUSCAR` completo más lo nuevo. Un bloque que contiene ``` va cercado con 4 acentos graves.
- **Aceptación**: comandos con salida binaria (`test`, `grep -c`, `bash -n`, `jq`, `ast.parse`), cwd = repo, sin residuos (`__pycache__`, builds). Cada edición debe tener al menos un comando que la vea.
- **Estado git esperado**: cada archivo tocado, `?? dir/` colapsado para directorios nuevos completos.
- Nada de juicio delegado: si al escribir la spec aparece un "depende de cómo esté el archivo", el cambio no es de b11. Detenerse y decirlo.

### 2. Validar (ensayo determinista)

```bash
python3 "$B11/scripts/validate-spec.py" "$DIR/SPEC.md"
```

Debe terminar en `SPEC OK`. Con `SPEC FALLA` o `SPEC INVÁLIDA`: corregir la spec (anclas, comandos, estado esperado) y repetir. Nunca ejecutar una spec que no ensayó en verde. `--dry-run` termina aquí con el informe del validador.

### 3. Ejecutar (modelo barato, proceso aislado)

```bash
bash "$B11/scripts/exec-spec.sh" "$DIR/SPEC.md" [--model <x>] [--max-turns N]
```

Bash con `timeout: 600000`; con más de 15 pasos (copias + ediciones + comandos), `run_in_background` y esperar la notificación. Modelo: `--model` > `$B_PIPELINE_EXEC_MODEL` > `z-ai/glm-5.3-flash` si existe `OPENROUTER_API_KEY` > `haiku`. La key llega solo al proceso hijo por nombre de variable; nunca se imprime ni se pasa como argumento.

El script imprime una línea `EXEC model=… ok=si|no subtype=… turns=… dur=… in=… cache_read=… out=… usd_lista=… denials=… json=…` y luego el informe del ejecutor. Con `ok=no`:

1. Leer el informe: el ejecutor se detiene en el primer paso que no calza y lo reporta (BUSCAR no único, aceptación roja, preflight distinto).
2. Si el repo quedó a medias, volver al estado limpio (la precondición garantiza que todo cambio es del ejecutor): `git -C "$REPO" checkout -- . && git -C "$REPO" clean -fd -- <destinos de COPIAR>`.
3. Corregir la spec, volver al paso 2. Dos fallas seguidas del ejecutor con `SPEC OK` → reportar y parar; no reintentar a ciegas.

### 4. Certificar

```bash
python3 "$B11/scripts/validate-spec.py" "$DIR/SPEC.md" --check
```

`CHECK OK` = cada archivo tocado es byte a byte (y bit de ejecución) igual al ensayo, la aceptación pasa en el repo real y `git status --porcelain` es el esperado. Con `CHECK FALLA`: el ejecutor hizo algo distinto o de más. No parchar el repo a mano: revertir (paso 3.2) y volver a ejecutar, o ajustar la spec si el error era de ella.

**Revisor** solo si la spec toca `src/`, tests o migraciones, o con `--review`. Sin `model=` (hereda la sesión):

```text
Agent(subagent_type="b-pipeline:b11-review",
      prompt="SPEC=$DIR/SPEC.md REPO=$REPO EXEC_JSON=$DIR/SPEC.exec.json CHECK=<salida completa del --check>")
```

Devuelve `REVIEW veredicto=APROBADO|OBSERVACIONES|RECHAZADO …`. `RECHAZADO` → revertir y reportar; `OBSERVACIONES` → listarlas al usuario, sin corregir por cuenta propia.

### 5. Informe

Cuatro líneas y parar:

```text
SPEC  <ruta>  (<n> copias, <n> ediciones, <n> comandos)
EXEC  <línea EXEC literal>
CHECK OK|FALLA  — <resumen>            REVIEW <veredicto>|omitido
Desviaciones reportadas por el ejecutor: ninguna | <lista>
Siguiente: revisar `git diff --stat` y commitear (b3) — b11 no commitea.
```

---

## Qué NO hacer

- No usar b11 si hay que explorar, elegir entre alternativas o escribir código nuevo con criterio: eso es `b7-issue-to-pr` / `b2-build-feature`.
- No "arreglar a mano" lo que el ejecutor dejó mal: la spec es la fuente de verdad; se corrige la spec o se revierte.
- No ejecutar sin `SPEC OK` ni dar por bueno sin `CHECK OK`.
- No commitear, no tocar `.env*`, no imprimir `OPENROUTER_API_KEY`.

## Referencias

- `references/spec-template.md` — formato de la spec y reglas fijas del ejecutor.
- `scripts/validate-spec.py` — ensayo (`SPEC OK`) y certificación (`--check` → `CHECK OK`); `--keep` conserva el clon.
- `scripts/exec-spec.sh` — `claude -p` aislado (env propio, sin MCP, tools acotadas, `--max-turns`), línea `EXEC` con costo a lista desde `modelUsage`; `B_PIPELINE_EXEC_PRICES=in,out,cr,cw` ajusta precios.
- `agents/b11-review.md` — revisor de una pasada.
