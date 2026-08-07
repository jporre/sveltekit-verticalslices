#!/usr/bin/env bash
# ABOUTME: diagnóstico mecánico de b-setup-or-fix — cuenta hits por peldaño E1-E6 sobre el
# ABOUTME: codebase entero y emite AUDIT_RESULT parseable. Solo lectura, cero cambios.
# Uso: audit.sh [ruta-src]   (default: src del cwd)
# Exit: 0 ok | 3 no es proyecto SvelteKit
set -uo pipefail

SRC="${1:-src}"
MAX_HITS=40   # ponytail: tope de líneas por check para no inundar el contexto; el conteo es completo igual
Q="[\"']"     # clase ERE "comilla simple o doble" — evita comillas literales en patrones

[ -f package.json ] && grep -q '"@sveltejs/kit"' package.json || { echo "AUDIT_ABORT no es un proyecto SvelteKit (falta @sveltejs/kit en package.json)"; exit 3; }

# grep -r con --include funciona en BSD (macOS) y GNU
g() { grep -rEn --include="$1" "$2" "$SRC" 2>/dev/null; }
# ponytail: cada check asigna a $h y recién ahí llama show — bash 3.2 (macOS) rompe
# comillas anidadas en $() dentro de argumentos, en asignaciones no
show() {
  local label="$1" hits="$2" n
  n=$(printf '%s' "$hits" | grep -c . || true)
  echo "-- $label: $n"
  [ -n "$hits" ] && printf '%s\n' "$hits" | head -$MAX_HITS
  echo "$n" >> /tmp/b-setup-or-fix-audit-counts.$$
}

rung() { # rung <var>: suma el acumulador en <var> y lo resetea
  local total=0 c
  while read -r c; do total=$((total + c)); done < /tmp/b-setup-or-fix-audit-counts.$$
  : > /tmp/b-setup-or-fix-audit-counts.$$
  eval "$1=$total"
}
: > /tmp/b-setup-or-fix-audit-counts.$$
trap 'rm -f /tmp/b-setup-or-fix-audit-counts.$$' EXIT

echo "=== STACK ==="
KIT_VERSION=$(node -e "try{console.log(require('./node_modules/@sveltejs/kit/package.json').version)}catch(e){console.log('unknown')}" 2>/dev/null || echo unknown)
echo "sveltekit=$KIT_VERSION"
# kit >= 2.62 acepta config inline en sveltekit() dentro de vite.config; sv >= 0.16 ya no genera svelte.config.js
CFG="svelte.config.js vite.config.js vite.config.ts"
grep -qE 'remoteFunctions[[:space:]]*:[[:space:]]*true' $CFG 2>/dev/null && echo "remote_functions_flag=yes" || echo "remote_functions_flag=no"
grep -qE 'async[[:space:]]*:[[:space:]]*true' $CFG 2>/dev/null && echo "async_flag=yes" || echo "async_flag=no"
FEATURES=$(find "$SRC/routes" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
echo "features=$FEATURES"

echo "=== E1 === base y seguridad"
grep -qE 'remoteFunctions[[:space:]]*:[[:space:]]*true' $CFG 2>/dev/null || { echo "-- falta kit.experimental.remoteFunctions (svelte.config.js o vite.config)"; echo 1 >> /tmp/b-setup-or-fix-audit-counts.$$; }
grep -qE 'async[[:space:]]*:[[:space:]]*true' $CFG 2>/dev/null || { echo "-- falta compilerOptions.experimental.async (svelte.config.js o vite.config)"; echo 1 >> /tmp/b-setup-or-fix-audit-counts.$$; }
grep -q '## Auth de pruebas' CLAUDE.md 2>/dev/null || { echo "-- CLAUDE.md sin seccion '## Auth de pruebas (browser)' — b7/epic-review no saben como obtener sesion (declararla: base-setup.md § 3)"; echo 1 >> /tmp/b-setup-or-fix-audit-counts.$$; }
h=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  grep -qE 'require(User|Permission|AnyPermission)' "$f" || h="$h$f
"
done < <(find "$SRC" \( -name '*.remote.ts' -o -name '*.remote.js' \) 2>/dev/null)
show "remote functions sin requireUser/requirePermission (SEC-B)" "$h"
h="$(g '*.server.ts' '^(let|var) ')"
show "estado mutable a nivel de modulo en .server.ts (SEC-E)" "$h"
h="$(grep -rEin --include='*.ts' "(api_?key|token|password|secret)$Q?[[:space:]]*[:=][[:space:]]*$Q[A-Za-z0-9_-]{8,}" "$SRC" 2>/dev/null | grep -v '\.test\.' || true)"
show "posibles secrets hardcodeados (SEC-D)" "$h"
rung E1

echo "=== E2 === estructura / colocación"
h="$(find "$SRC/lib/features" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)"
show "features bajo src/lib/features (CAL-5)" "$h"
h="$(find "$SRC/routes" -name '*.remote.*' 2>/dev/null | grep -v '/server/' || true)"
show "*.remote.ts fuera de server/ (canónico: <feature>/server/data.remote.ts)" "$h"
h="$(find "$SRC/lib/server" -name '*.remote.*' 2>/dev/null)"
show "*.remote.ts bajo src/lib/server (AP10)" "$h"
h="$(find "$SRC/routes" -name '*.svelte' ! -name '+*' 2>/dev/null | grep -v '/ui/' || true)"
show "componentes sueltos fuera de ui/ (mover a <feature>/ui/)" "$h"
h="$(find "$SRC/routes" -name '*.md' 2>/dev/null | grep -v '/docs/' || true)"
show "docs de feature fuera de docs/ (mover a <feature>/docs/)" "$h"
h="$(find "$SRC/routes" -name '*Page.svelte' 2>/dev/null)"
show "wrappers <Feature>Page.svelte" "$h"
rung E2

echo "=== E3 === data-layer legacy (migrar a remote functions)"
h="$(find "$SRC/routes" \( -name '+page.server.ts' -o -name '+page.ts' -o -name '+layout.server.ts' -o -name '+layout.ts' \) -print0 2>/dev/null | xargs -0 grep -lE 'export (const|async function|function) load' 2>/dev/null)"
show "load() en +page/+layout (migrar a query)" "$h"
h="$(find "$SRC/routes" -name '+page.server.ts' -print0 2>/dev/null | xargs -0 grep -l 'export const actions' 2>/dev/null)"
show "form actions (migrar a form())" "$h"
h="$(find "$SRC/routes" -name '+server.ts' 2>/dev/null)"
show "+server.ts internos (candidatos a query/command; webhooks externos NO)" "$h"
h=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  grep -q 'fetch(' "$f" && h="$h$f
"
done < <(grep -rl 'onMount' --include='*.svelte' "$SRC" 2>/dev/null)
show "onMount + fetch manual (AP2)" "$h"
h="$(g '*.svelte' "fetch\(${Q}/api")"
show "fetch a /api propio desde componentes" "$h"
rung E3

echo "=== E4 === runas Svelte 5 y stack"
h="$(g '*.svelte' 'on:[a-z]+={')"
show "eventos on: de Svelte 4 (AP6)" "$h"
h="$(g '*.svelte' 'export let ')"
show "export let (props Svelte 4)" "$h"
h="$(g '*.svelte' '<slot')"
show "<slot> (AP5, migrar a snippets)" "$h"
h="$(g '*.svelte' '^[[:space:]]*\$: ')"
show "\$: reactive statements (migrar a \$derived)" "$h"
h="$(g '*.svelte' '\$effect\(')"
show "\$effect (revisar: si computa valores es AP3)" "$h"
h="$(g '*.svelte' "import \{[^}]+\} from $Q\\\$lib/components/ui/")"
show "named imports shadcn (AP7; Button/Input/Label/Textarea/Badge/Separator son válidos)" "$h"
h="$(g '*' "from ${Q}lucide-svelte${Q}")"
show "lucide-svelte plano (AP9, usar @lucide/svelte/icons/x)" "$h"
h="$(g '*.svelte' 'Select\.Value')"
show "Select.Value (AP8, no existe)" "$h"
h="$(g '*.svelte' 'goto\(')"
show "goto() (AP1; solo sospechoso si envuelve navegación simple)" "$h"
rung E4

echo "=== E5 === desingeniería / duplicados (insumo para juicio LLM)"
h="$(g '*.ts' 'class [A-Za-z]+(Service|Repository|Factory|Manager)')"
show "clases Service/Repository/Factory/Manager (sospecha pass-through CAL-1..3)" "$h"
h="$(g '*.ts' '^export (async )?(function|const) ' | grep "$SRC/lib" || true)"
show "exports en src/lib (catálogo para pasada de duplicados DUP-1)" "$h"
rung E5

echo "=== E6 === comentarios y docs"
COMMENT_LINES=$(grep -rE --include='*.ts' --include='*.svelte' '^[[:space:]]*//' "$SRC" 2>/dev/null | grep -cv 'ponytail:' || true)
echo "-- líneas de comentario (sin ponytail): $COMMENT_LINES"
[ "$COMMENT_LINES" -gt 50 ] && echo "$COMMENT_LINES" >> /tmp/b-setup-or-fix-audit-counts.$$ || echo 0 >> /tmp/b-setup-or-fix-audit-counts.$$
h=""
while IFS= read -r d; do
  [ -n "$d" ] || continue
  ls "$d"/docs/*.md >/dev/null 2>&1 || ls "$d"/*.md >/dev/null 2>&1 || h="$h$d
"
done < <(find "$SRC/routes" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
show "features sin doc colocado (docs/<feature>.md) (CAL-6)" "$h"
[ -f docs/ARCHITECTURE.md ] || [ -f ARCHITECTURE.md ] || { echo "-- falta doc nivel repo (ARCHITECTURE.md)"; echo 1 >> /tmp/b-setup-or-fix-audit-counts.$$; }
rung E6

MODE=rescate
[ $((E2 + E3 + E4)) -eq 0 ] && [ "$FEATURES" -lt 3 ] && MODE=base
echo "AUDIT_RESULT mode=$MODE rungs=E1:$E1,E2:$E2,E3:$E3,E4:$E4,E5:$E5,E6:$E6 features=$FEATURES"
