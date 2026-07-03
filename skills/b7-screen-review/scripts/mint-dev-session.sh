#!/usr/bin/env bash
# mint-dev-session.sh — sesion dev scriptada para pasar el muro OAuth en screen-review.
#
# La app es OAuth-only; el screen-review no puede loguearse solo. En vez del ritual
# manual ("abri Chrome, logueate, re-corre"), este script inserta una fila de sesion
# valida directo en la DB del worktree y devuelve la cookie para inyectarla en el browser.
#
# Subcomandos:
#   mint <worktree>     Inserta una sesion (24h) y imprime SOLO `B7_SESSION_COOKIE=auth-session=<token>`.
#   verify <url>        curl -si -b "$B7_SESSION_COOKIE" <url>; clasifica 200 / permiso / invalida.
#   cleanup <worktree>  Borra la fila insertada (por hash guardado en .b7/dev-session.json).
#
# Seleccion de usuario (mint):
#   B7_SESSION_USER_ID    id directo del usuario (path confiable, sin conocer el schema).
#   B7_SESSION_EMAIL      email; se resuelve a id (usuario activo=2, con perfil que tenga rutas).
#   Sin ninguno de los dos -> exit 3 (fallback limpio: el caller cae al flujo manual, NO es error).
#
# Overrides de schema (por si el nombre real difiere de los defaults):
#   B7_SESSION_TABLE      default: app.user_session
#   B7_SESSION_COL_ID     default: id            (guarda sessionId = sha256(token) hex)
#   B7_SESSION_COL_USER   default: user_id
#   B7_SESSION_COL_EXP    default: expires_at    (timestamptz, now + 24h)
#   B7_USER_TABLE         default: app.ta_usuario
#   B7_USER_COL_ID        default: id
#   B7_USER_COL_EMAIL     default: email
#   B7_USER_COL_ACTIVO    default: activo   (se filtra = 2)
#
# Invariante de seguridad: el token en claro aparece UNA sola vez, en la linea
# `B7_SESSION_COOKIE=...` de stdout. Todo lo demas va a stderr y nunca incluye el token.
# En la DB y en .b7/dev-session.json solo vive el hash (sessionId), nunca el token.
set -euo pipefail

SUB="${1:-}"; ARG="${2:-}"

die() { echo "mint-dev-session: $*" >&2; exit 1; }
log() { echo "mint-dev-session: $*" >&2; }

# Lee DATABASE_URL del worktree sin imprimirlo. Prueba .env, .env.local, .env.development.
load_database_url() {
  local wt="$1" f val
  for f in .env .env.local .env.development .env.dev; do
    if [ -f "$wt/$f" ]; then
      val="$(grep -E '^[[:space:]]*(export[[:space:]]+)?DATABASE_URL=' "$wt/$f" | tail -1 || true)"
      if [ -n "$val" ]; then
        val="${val#*DATABASE_URL=}"
        # strip surrounding quotes
        val="${val%\"}"; val="${val#\"}"; val="${val%\'}"; val="${val#\'}"
        printf '%s' "$val"
        return 0
      fi
    fi
  done
  return 1
}

cmd_mint() {
  local wt="$ARG"
  [ -z "$wt" ] && die "usage: mint <worktree>"
  [ -d "$wt" ] || die "no es un directorio: $wt"

  if [ -z "${B7_SESSION_USER_ID:-}" ] && [ -z "${B7_SESSION_EMAIL:-}" ]; then
    log "sin B7_SESSION_USER_ID ni B7_SESSION_EMAIL — fallback al flujo manual (no es error)"
    exit 3
  fi

  local db
  db="$(load_database_url "$wt")" || { log "DATABASE_URL no encontrado en $wt/.env* — fallback"; exit 3; }
  [ -n "$db" ] || { log "DATABASE_URL vacio — fallback"; exit 3; }

  command -v openssl >/dev/null 2>&1 || die "openssl no disponible"
  command -v node    >/dev/null 2>&1 || die "node no disponible"

  # token base64url; sessionId = sha256(token) en hex (patron Lucia v3).
  local token session_id expires
  token="$(openssl rand -base64 18 | tr '+/' '-_' | tr -d '=')"
  session_id="$(printf '%s' "$token" | openssl dgst -sha256 | awk '{print $NF}')"
  # expira en 24h (UTC ISO); node lo parsea a timestamptz.
  if date -u -v+24H +%Y-%m-%dT%H:%M:%SZ >/dev/null 2>&1; then
    expires="$(date -u -v+24H +%Y-%m-%dT%H:%M:%SZ)"        # BSD/macOS
  else
    expires="$(date -u -d '+24 hours' +%Y-%m-%dT%H:%M:%SZ)" # GNU
  fi

  mkdir -p "$wt/.b7"

  # El token NO se pasa a node: node solo necesita el hash (session_id). Asi el token
  # nunca aparece en `ps`/argv/env de un subproceso. Resolucion de usuario + INSERT en node.
  local resolved_user
  resolved_user="$(
    cd "$wt" && \
    DATABASE_URL="$db" \
    B7_MINT_SESSION_ID="$session_id" \
    B7_MINT_EXPIRES="$expires" \
    B7_SESSION_TABLE="${B7_SESSION_TABLE:-app.user_session}" \
    B7_SESSION_COL_ID="${B7_SESSION_COL_ID:-id}" \
    B7_SESSION_COL_USER="${B7_SESSION_COL_USER:-user_id}" \
    B7_SESSION_COL_EXP="${B7_SESSION_COL_EXP:-expires_at}" \
    B7_USER_TABLE="${B7_USER_TABLE:-app.ta_usuario}" \
    B7_USER_COL_ID="${B7_USER_COL_ID:-id}" \
    B7_USER_COL_EMAIL="${B7_USER_COL_EMAIL:-email}" \
    B7_USER_COL_ACTIVO="${B7_USER_COL_ACTIVO:-activo}" \
    node --input-type=module <<'NODE'
const env = process.env;
const url = env.DATABASE_URL;
if (!url) { console.error('mint(node): DATABASE_URL vacio'); process.exit(11); }

async function getDriver(url) {
  try {
    const postgres = (await import('postgres')).default;
    const sql = postgres(url, { max: 1, idle_timeout: 2 });
    return {
      kind: 'postgres',
      query: async (text, params) => {
        // postgres.js usa tagged templates; usamos .unsafe para SQL parametrizado con $1..$n
        const rows = await sql.unsafe(text, params);
        return rows;
      },
      end: () => sql.end({ timeout: 3 }),
    };
  } catch (e) { if (e.code !== 'ERR_MODULE_NOT_FOUND') throw e; }
  const { Client } = await import('pg');
  const client = new Client({ connectionString: url });
  await client.connect();
  return {
    kind: 'pg',
    query: async (text, params) => (await client.query(text, params)).rows,
    end: () => client.end(),
  };
}

const T   = env.B7_SESSION_TABLE, CID = env.B7_SESSION_COL_ID, CUSER = env.B7_SESSION_COL_USER, CEXP = env.B7_SESSION_COL_EXP;
const UT  = env.B7_USER_TABLE, UCID = env.B7_USER_COL_ID, UCEMAIL = env.B7_USER_COL_EMAIL, UCACT = env.B7_USER_COL_ACTIVO;

const db = await getDriver(url);
try {
  let userId = env.B7_SESSION_USER_ID || null;
  if (!userId) {
    const email = env.B7_SESSION_EMAIL;
    const rows = await db.query(
      `SELECT ${UCID} AS id FROM ${UT} WHERE ${UCEMAIL} = $1 AND ${UCACT} = 2 ORDER BY ${UCID} LIMIT 1`,
      [email]
    );
    if (!rows || rows.length === 0) {
      console.error(`mint(node): sin usuario activo (activo=2) para el email dado en ${UT}`);
      process.exit(12);
    }
    userId = rows[0].id;
  }
  await db.query(
    `INSERT INTO ${T} (${CID}, ${CUSER}, ${CEXP}) VALUES ($1, $2, $3)`,
    [env.B7_MINT_SESSION_ID, userId, env.B7_MINT_EXPIRES]
  );
  // Unico stdout de node: el userId resuelto (no secreto). El shell lo captura.
  process.stdout.write(String(userId));
  console.error(`mint(node): sesion insertada (${db.kind}) user=${userId} exp=${env.B7_MINT_EXPIRES}`);
} finally {
  await db.end().catch(() => {});
}
NODE
  )" || die "el INSERT de la sesion fallo (ver stderr de node arriba)"

  # Guarda SOLO el hash + metadata para cleanup. Nunca el token.
  cat > "$wt/.b7/dev-session.json" <<JSON
{
  "session_id_sha256": "${session_id}",
  "user_id": "${resolved_user}",
  "table": "${B7_SESSION_TABLE:-app.user_session}",
  "col_id": "${B7_SESSION_COL_ID:-id}",
  "expires_at": "${expires}",
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
  chmod 600 "$wt/.b7/dev-session.json" 2>/dev/null || true

  log "sesion lista para user=${resolved_user} (expira ${expires}); hash en .b7/dev-session.json"
  # UNICA linea con el token en claro (stdout):
  printf 'B7_SESSION_COOKIE=auth-session=%s\n' "$token"
}

cmd_verify() {
  local url="$ARG"
  [ -z "$url" ] && die "usage: verify <url>   (cookie via env B7_SESSION_COOKIE)"
  local cookie="${B7_SESSION_COOKIE:-}"
  [ -z "$cookie" ] && die "B7_SESSION_COOKIE no seteado (esperado: auth-session=<token>)"
  command -v curl >/dev/null 2>&1 || die "curl no disponible"

  local resp status location
  resp="$(curl -si -m 15 -b "$cookie" "$url" 2>/dev/null || true)"
  [ -z "$resp" ] && { log "sin respuesta de $url (¿dev server abajo?)"; exit 2; }
  status="$(printf '%s' "$resp" | awk 'NR==1{print $2; exit}')"
  location="$(printf '%s' "$resp" | grep -i '^location:' | head -1 | awk '{print $2}' | tr -d '\r' || true)"

  case "$status" in
    200)
      log "verify: 200 OK — sesion valida y con permiso ($url)"
      echo "ok"; exit 0 ;;
    30[1237])
      if printf '%s' "$location" | grep -qiE '/(login|auth|signin)'; then
        log "verify: $status -> $location — sesion INVALIDA (bounce a login)"
        echo "invalida"; exit 3
      fi
      log "verify: $status -> $location — sesion valida pero sin permiso en la ruta"
      echo "permiso"; exit 4 ;;
    401|403)
      log "verify: $status — sesion valida pero sin permiso en la ruta"
      echo "permiso"; exit 4 ;;
    *)
      log "verify: status inesperado '$status' en $url"
      echo "desconocido"; exit 5 ;;
  esac
}

cmd_cleanup() {
  local wt="$ARG"
  [ -z "$wt" ] && die "usage: cleanup <worktree>"
  local meta="$wt/.b7/dev-session.json"
  if [ ! -f "$meta" ]; then
    log "cleanup: no hay .b7/dev-session.json — nada que borrar"
    exit 0
  fi
  local db
  db="$(load_database_url "$wt")" || { log "cleanup: DATABASE_URL no encontrado — dejo el json para retry"; exit 1; }

  ( cd "$wt" && DATABASE_URL="$db" B7_META="$meta" node --input-type=module <<'NODE'
import { readFileSync } from 'node:fs';
const env = process.env;
const meta = JSON.parse(readFileSync(env.B7_META, 'utf8'));
const T = meta.table || 'app.user_session';
const CID = meta.col_id || 'id';
const sid = meta.session_id_sha256;
if (!sid) { console.error('cleanup(node): falta session_id_sha256'); process.exit(11); }

async function getDriver(url) {
  try {
    const postgres = (await import('postgres')).default;
    const sql = postgres(url, { max: 1, idle_timeout: 2 });
    return { query: async (t,p)=>await sql.unsafe(t,p), end: ()=>sql.end({timeout:3}) };
  } catch (e) { if (e.code !== 'ERR_MODULE_NOT_FOUND') throw e; }
  const { Client } = await import('pg');
  const client = new Client({ connectionString: url });
  await client.connect();
  return { query: async (t,p)=>(await client.query(t,p)).rows, end: ()=>client.end() };
}

const db = await getDriver(env.DATABASE_URL);
try {
  await db.query(`DELETE FROM ${T} WHERE ${CID} = $1`, [sid]);
  console.error('cleanup(node): fila borrada');
} finally {
  await db.end().catch(()=>{});
}
NODE
  ) || { log "cleanup: el DELETE fallo — dejo .b7/dev-session.json para retry manual"; exit 1; }

  rm -f "$meta"
  log "cleanup: sesion borrada y .b7/dev-session.json removido"
}

case "$SUB" in
  mint)    cmd_mint ;;
  verify)  cmd_verify ;;
  cleanup) cmd_cleanup ;;
  *) echo "Usage: $0 {mint <worktree>|verify <url>|cleanup <worktree>}" >&2; exit 2 ;;
esac
