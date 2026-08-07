#!/usr/bin/env bash
# scaffold-slice.sh — genera el esqueleto mínimo de un vertical slice colocado
# en src/routes/, siguiendo references/slice-spec.md (regla 99%). El modelo NO
# improvisa estructura: arranca de este esqueleto y lo rellena.
#
# Uso: bash scaffold-slice.sh <feature> [--route-group <g>]
#   <feature>        nombre del feature (kebab o snake). Ej: productos, orden-compra
#   --route-group <g> coloca el slice bajo src/routes/(<g>)/<feature>/
#
# Genera (mínimos COMPILABLES, sin service, sin carpetas vacías — ui/ y tests/ se
# crean recién cuando haya contenido):
#   src/routes/<feature>/+page.svelte
#   src/routes/<feature>/server/data.remote.ts
#   src/routes/<feature>/docs/<feature>.md
#
# Emite en la última línea: SCAFFOLD_OK dir=<path> files=<csv>
set -euo pipefail

FEATURE=""
ROUTE_GROUP=""
while [ $# -gt 0 ]; do
  case "$1" in
    --route-group) ROUTE_GROUP="${2:?--route-group requiere un valor}"; shift 2 ;;
    --route-group=*) ROUTE_GROUP="${1#*=}"; shift ;;
    -*) echo "ERROR: flag desconocida: $1" >&2; exit 2 ;;
    *) if [ -z "$FEATURE" ]; then FEATURE="$1"; else echo "ERROR: argumento extra: $1" >&2; exit 2; fi; shift ;;
  esac
done

if [ -z "$FEATURE" ]; then
  echo "Uso: scaffold-slice.sh <feature> [--route-group <g>]" >&2
  exit 2
fi

# Normalización de nombres.
# feat_kebab: nombre de carpeta/archivo (kebab).  feat_snake: identificadores JS.  feat_pascal: títulos.
feat_kebab="$(echo "$FEATURE" | tr '[:upper:] _' '[:lower:]--' | tr -s '-')"
feat_snake="$(echo "$feat_kebab" | tr '-' '_')"
feat_pascal="$(echo "$feat_kebab" | awk -F- '{for(i=1;i<=NF;i++){printf "%s%s", toupper(substr($i,1,1)), substr($i,2)}}')"

# Raíz del repo (para permitir invocar desde cualquier cwd).
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

if [ -n "$ROUTE_GROUP" ]; then
  # Grupo de ruta: envuelto en paréntesis, sin afectar la URL.
  rg="${ROUTE_GROUP#(}"; rg="${rg%)}"
  REL="src/routes/(${rg})/${feat_kebab}"
else
  REL="src/routes/${feat_kebab}"
fi
DIR="${REPO_ROOT}/${REL}"

if [ -d "$DIR" ]; then
  echo "ERROR: el slice ya existe: ${REL}" >&2
  exit 1
fi

mkdir -p "$DIR/server" "$DIR/docs"

REMOTE_FILE="server/data.remote.ts"
MD_FILE="docs/${feat_kebab}.md"

# --- server/data.remote.ts : el archivo CORE. TODO el manejo de datos del feature. ---
# Path fijo en todo feature: debug de una query = revisar este archivo, siempre.
cat > "${DIR}/${REMOTE_FILE}" <<REMOTE
import {query} from '\$app/server'

// Query base del slice. Reemplazar el placeholder por la consulta Drizzle directa
// (sin capa service): db.query.ta_${feat_snake}.findMany(...).
export const get_${feat_snake} = query(async () => {
	return [] as Array<{id: string}>
})
REMOTE

# --- +page.svelte : la pantalla. UI aquí; importa el remote colocado. ---
cat > "${DIR}/+page.svelte" <<PAGE
<script lang="ts">
import {get_${feat_snake}} from './server/data.remote'

const items = \$derived(await get_${feat_snake}())
</script>

<div class="space-y-6">
	<h1 class="text-2xl font-semibold">${feat_pascal}</h1>

	{#each items as item (item.id)}
		<p>{item.id}</p>
	{:else}
		<p class="text-muted-foreground">Sin registros.</p>
	{/each}
</div>
PAGE

# --- docs/<feature>.md : doc del slice (primera parada de debug). 6 secciones del spec. ---
cat > "${DIR}/${MD_FILE}" <<DOC
# ${feat_pascal}

## Propósito

<!-- 2-3 líneas en lenguaje de usuario: qué resuelve este feature. -->

## Pantallas y rutas

- \`/${feat_kebab}\` — <!-- qué se ve aquí -->

## Remote functions

- \`get_${feat_snake}\` — <!-- una línea de contrato -->

## Datos

<!-- tablas/vistas que toca: ta_${feat_snake}, ... -->

## Decisiones

<!-- por qué se hizo así; atajos ponytail: relevantes -->

## Problemas conocidos

<!-- ninguno por ahora -->
DOC

FILES="${REL}/+page.svelte,${REL}/${REMOTE_FILE},${REL}/${MD_FILE}"
echo "Slice creado en ${REL}/ (3 archivos: +page.svelte, ${REMOTE_FILE}, ${MD_FILE})"
echo "SCAFFOLD_OK dir=${REL} files=${FILES}"
