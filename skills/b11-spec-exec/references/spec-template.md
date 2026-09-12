# SPEC — <título corto del cambio>

REPO: /ruta/absoluta/al/repo

## 0. Reglas fijas para el ejecutor

1. Trabajas SOLO dentro de `REPO` (la ruta de la línea `REPO:`). Fuera de él solo lees o copias desde los orígenes listados en las líneas `COPIAR:`.
2. No tocar `.git/` ni nada que esta spec no nombre. Sin commit, push, stash, checkout, reset, ni borrar archivos que no creaste tú.
3. Copias: ejecuta los comandos tal cual. Ediciones: con la herramienta Edit, texto exacto de BUSCAR → REEMPLAZAR, una vez. Si el texto de BUSCAR no aparece exactamente una vez: detente en ese paso, no improvises, no busques «algo parecido», y repórtalo.
4. No inventes pasos. Lo que no está en la spec no se hace: sin refactors, sin «mejoras», sin comentarios nuevos.
5. Aceptación: corre cada comando. Si uno falla, detente y reporta salida y exit code literales.
6. Nunca leas ni imprimas archivos `.env*`, keys ni tokens.
7. Termina con el informe de la última sección, con salidas literales. Reporta toda desviación, aunque sea menor.

## 1. Contexto

<Qué cambia y por qué, en 3-6 líneas. Precondición: `git status --porcelain` vacío en REPO.>

Preflight (ejecutar y comparar; si algo no calza, detenerse y reportar):

```bash
cd /ruta/absoluta/al/repo
git status --porcelain | wc -l          # esperado: 0
git log -1 --oneline                    # esperado: <sha> <asunto>
ls <orígenes de las copias>             # esperado: todos existen
```

## 2. Copias

<Una línea por archivo. `+x` marca ejecutable. Sin copias: borrar la sección.>

COPIAR: /ruta/absoluta/origen/archivo.md -> destino/relativo/archivo.md
COPIAR: /ruta/absoluta/origen/script.sh -> destino/relativo/script.sh +x

Comandos para el ejecutor (equivalentes a las líneas anteriores):

```bash
mkdir -p destino/relativo
cp /ruta/absoluta/origen/archivo.md destino/relativo/archivo.md
cp /ruta/absoluta/origen/script.sh destino/relativo/script.sh
chmod +x destino/relativo/script.sh
```

## 3. Ediciones

<Un par por cambio. BUSCAR aparece exactamente una vez en el archivo: mínimo 2 líneas de contexto o una línea inequívoca. Para insertar, REEMPLAZAR repite el BUSCAR completo más lo nuevo. Si un bloque lleva una valla ``` adentro, la valla exterior usa 4 acentos graves.>

### 3.1 <qué cambia>

ARCHIVO: ruta/relativa/archivo.md

BUSCAR:

```
texto exacto, único en el archivo
```

REEMPLAZAR:

```
texto nuevo
```

## 4. Aceptación

<Un comando por línea, cwd = REPO, todos deben salir 0. Nada que deje residuos (sin `py_compile`).>

```bash
test "$(grep -c 'texto nuevo' ruta/relativa/archivo.md)" -eq 1
bash -n destino/relativo/script.sh
```

## 5. Estado git esperado

<Salida literal de `git status --porcelain` al terminar. Directorios nuevos completos aparecen colapsados con `/`.>

```
 M ruta/relativa/archivo.md
?? destino/relativo/
```

## 6. Informe

Al terminar, responde exactamente con:

```
# Informe

## Pasos
| Paso | Resultado |
|---|---|
| Preflight | ok | <o qué no calzó> |
| Copias | ok — <n> archivos |
| Ediciones | ok — <n>/<n> BUSCAR encontrados una vez |
| Aceptación | ok — <n>/<n> comandos |
| Estado git | ok — <n> entradas |

## Salida literal
<`git status --porcelain` y `git diff --stat`>

## Desviaciones
<«ninguna», o cada una con el paso, qué pasó y qué hiciste (nada más que detenerte)>
```
