# b7 — paso 5: revisión visual de pantallas (detalle)

Cargado desde `SKILL.md` paso 5, SOLO cuando la rampa de entrada no dio skip.
Con `--no-screens`, `--dry-run`, `lane-s-no-ui` o `screens[]` vacío, no leer este archivo.

#### 5.0 Levantar el dev server del worktree (OBLIGATORIO antes del review)

**Causa histórica de que las pantallas nunca se revisaran:** nadie levantaba el dev server del worktree, así que `b7-screen-review` hacía `curl localhost:<port>` → sin respuesta → abortaba `fail`. Levantarlo acá:

```bash
# start: nohup ./dev.sh (log y pid en .b7/dev-server.*), poll del puerto hasta
# B7_DEV_SERVER_WAIT_SECS (default 120, deadline por tiempo transcurrido — lo implementa guardrails.sh).
# Si no responde: WARN sin abortar — verify-port abajo decide si se omiten screens.
bash "$PLUGIN_ROOT/skills/b7-issue-to-pr/scripts/guardrails.sh" dev-server start "$WORKTREE"
# Gate DURO: no basta con que algo responda en el puerto — tiene que ser ESTE
# worktree. verify-port compara el cwd del proceso listener con $WORKTREE
# (exit 40 = nadie escucha, exit 41 = lo sirve otro checkout, p.ej. la rama default).
RC=0
bash "$PLUGIN_ROOT/skills/b7-issue-to-pr/scripts/guardrails.sh" verify-port "$PORT" "$WORKTREE" || RC=$?
if [ "$RC" = 40 ]; then
  # exit 40: UN reintento (dev-server start + verify-port). Nunca mas de uno.
  bash "$PLUGIN_ROOT/skills/b7-issue-to-pr/scripts/guardrails.sh" dev-server start "$WORKTREE"
  RC=0
  bash "$PLUGIN_ROOT/skills/b7-issue-to-pr/scripts/guardrails.sh" verify-port "$PORT" "$WORKTREE" || RC=$?
fi
if [ "$RC" != 0 ]; then
  mkdir -p "$WORKTREE/.b7/review"
  printf '{"reason": "no-port"}\n' > "$WORKTREE/.b7/review/SKIPPED.json"
  echo "WARN: verify-port fallo (:${PORT} no sirve el worktree, exit $RC) — screens se omiten; SKIPPED.json reason=no-port"
fi
```

Reglas por exit code:

- **Exit 40** (nadie escucha): UN reintento como en el bloque de arriba — `dev-server start` + `verify-port`, nunca más de uno. Si persiste, escribir `SKIPPED.json` con `reason=no-port`, dejar nota explícita en el run-report y saltar a 5.9 (no abortar el run completo).
- **Exit 41** (el puerto lo sirve otro checkout): NO reintentar y NO matar el listener — puede ser el dev server legítimo de otra sesión b7/b8/b10 paralela; resolverlo queda manual, como hoy. Escribir `SKIPPED.json` con `reason=no-port`, nota en el run-report y saltar a 5.9.

**No revisar pantallas contra un server que no sea el del worktree** — ese fue el incidente que este gate previene (screen-review contra la rama default).

#### 5.1 Auth: estrategia declarada del repo, con fallback

**Primero, leer la estrategia que el repo declara** — sección `## Auth de pruebas (browser)` de su CLAUDE.md (la instala b-setup-or-fix; formato `clave: valor`). El método de auth depende del proyecto, su DB y sus criterios de seguridad — NO asumir uno:

```bash
sed -n '/^## Auth de pruebas/,/^## /p' "$WORKTREE/CLAUDE.md"
```

Dispatch por `estrategia:`:

- **`dev-user`** → el primer agente navega `login_url:` y llena el form con los VALORES de las env vars que `credenciales:` nombra (leerlas del entorno; NUNCA imprimirlas ni pegarlas en logs). Las cookies de esa sesión sirven para el resto del run.
- **`dev-endpoint`** → `curl -si "http://localhost:${PORT}<endpoint>"` captura el `Set-Cookie` → esa es `AUTH_COOKIE`. El endpoint solo existe en dev (404 en prod por diseño).
- **`session-mint`** → flujo A de abajo (`email_seed:` alimenta `B7_SESSION_EMAIL` si el entorno no lo trae).
- **`manual-cookies`** → en sesión interactiva: pedir al usuario UN login manual en el browser y reusar las cookies de esa sesión. Headless: pantallas protegidas → `not-evaluated (auth-required)` + nota en el run-report (no es `fail`).

Sin sección declarada: flujo A→B histórico de abajo, y dejar en el run-report: "declara `## Auth de pruebas (browser)` en CLAUDE.md (b-setup-or-fix modo base) para que los runs no improvisen el método".

**A. Intentar sesión scriptada (`mint-dev-session.sh`).** Inserta una fila de sesión válida en la DB del worktree y devuelve la cookie — sin ritual manual. Requiere `B7_SESSION_USER_ID` o `B7_SESSION_EMAIL` en el entorno del run:

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/skills/b-pipeline}"
MINT="$PLUGIN_ROOT/skills/b7-screen-review/scripts/mint-dev-session.sh"
AUTH_COOKIE=""
if COOKIE_LINE=$(bash "$MINT" mint "$WORKTREE" 2>>"$WORKTREE/.b7/dev-server.log"); then
  AUTH_COOKIE="${COOKIE_LINE#B7_SESSION_COOKIE=}"   # -> auth-session=<token>
  # Verificar contra una ruta protegida real del feature (usar la route de la 1a pantalla):
  if B7_SESSION_COOKIE="$AUTH_COOKIE" bash "$MINT" verify "http://localhost:${PORT}<primera-route>"; then
    echo "auth scriptada OK — se pasa auth_cookie a los sub-agentes"
  else
    echo "verify no dio 200 — descarto la cookie, sigo con flujo B (sin cookie)"
    AUTH_COOKIE=""
  fi
else
  echo "mint no disponible (sin B7_SESSION_USER_ID/EMAIL o DATABASE_URL) — flujo B (sin cookie)"
fi
```

`mint` sale 3 (fallback limpio) si faltan `B7_SESSION_USER_ID`/`B7_SESSION_EMAIL` o `DATABASE_URL` — **no** es error; simplemente no hay cookie y se sigue con el flujo B.

**B. Fallback: correr sin cookie.** Si no hubo cookie, el agente abre la ruta igual (browser propio vía `agent-browser`; no reusa la sesión del Chrome real). Dejar UNA línea en el run-report y en el sticky comment del issue:

> Pantallas protegidas quedaron `not-evaluated`: configura `B7_SESSION_USER_ID`/`B7_SESSION_EMAIL` + `DATABASE_URL` y re-corre para evaluarlas con sesión scriptada.

Si una pantalla vuelve `auth-required` (redirección a login, sin cookie), **no** es `fail` del feature: marcar la pantalla como `not-evaluated (auth-required)` en el run-report y seguir. Solo cuenta como `fail` un criterio visual incumplido con sesión válida.

> Restricción conocida (fuera de alcance de #14): la cookie es host-scoped (`localhost`). Si b7 y b8-swarm mintean en paralelo contra el mismo host, la última cookie pisa a las demás. Wiring de mint en b8-swarm es follow-up.

#### 5.2 Lanzar un sub-agente por pantalla

Para cada pantalla, lanzar **un agente del plugin** `b-pipeline:b7-screen-review` en paralelo (un Agent call por pantalla en el mismo turno):

```
Agent(
  subagent_type="b-pipeline:b7-screen-review",
  description="Visual review <ScreenName>",
  prompt="screen=<Name> route=<route> port=<PORT> worktree=$WORKTREE criteria_file=.b7/screens/<Name>.md out_dir=.b7/review states=<states_required de la pantalla, join por coma; fallback golden> auth_cookie=<AUTH_COOKIE>. Output: .b7/review/<Name>.json + .b7/review/<Name>-*.png"
)
```

Pasar `auth_cookie=<AUTH_COOKIE>` solo si 5.1-A dio una cookie válida (verify=200); si `AUTH_COOKIE` quedó vacío, omitir el param y las pantallas protegidas vuelven `auth-required` → `not-evaluated`.

`b7-screen-review` produce por pantalla:
- `<Name>.json`: `{verdict: pass|fail|warn, findings: [...], screenshots: [...]}` — campo aditivo `"infra_fail": true` cuando el review no corrió por falla de infra pura (ver agente)
- Una o más PNGs (golden path + edge cases)

Si alguna pantalla retorna `fail` (criterio visual incumplido con sesión válida), devolver findings al loop de implementación (paso 4) y rebudgetear iteración. Si retorna `warn` o `not-evaluated`, agregar al PR como nota pero seguir. `warn` con `"infra_fail": true` NO rebudgetea el paso 4: tratar la pantalla como `not-evaluated` con nota explícita en el run-report Y en el sticky comment del issue — mismo trato que el fallo de verify-port en 5.0 (el problema es de infra, no del código).

#### 5.9 Apagar el dev server y borrar la sesión scriptada

Pase lo que pase con el review, apagar el server que se levantó en 5.0 **y** borrar SIEMPRE la sesión que se minteó en 5.1-A (si la hubo). Ambos cleanups son idempotentes:

```bash
# Borrar la sesión scriptada (no falla si no se minteó ninguna).
bash "$PLUGIN_ROOT/skills/b7-screen-review/scripts/mint-dev-session.sh" cleanup "$WORKTREE" || true
# Apagar el dev server (silencioso si no hay pid file).
bash "$PLUGIN_ROOT/skills/b7-issue-to-pr/scripts/guardrails.sh" dev-server stop "$WORKTREE"
```
