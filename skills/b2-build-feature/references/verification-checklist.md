# Verification Checklist — browser walkthrough

Los gates mecanicos (branch guard, `check:machine`, `format`, grep anti-React
scoped al diff, `test:unit` condicional, browser-gate) viven en
`scripts/verify.sh` — exit codes 3-6 estables y ultima linea machine-readable
`VERIFY_RESULT ... browser=required|not-needed svelte_files=<csv>`. El autofixer
(sobre `svelte_files`) y este walkthrough siguen siendo pasos del modelo
gatillados por esa linea (Phase 3 del SKILL.md).

Este documento es el how-to del browser test con `agent-browser`. Corre SOLO
cuando verify.sh reporta `browser=required`.

## Browser Test

### Start dev server (serve THIS checkout, not master)

Serví siempre desde el checkout actual — si estás en un worktree, usá su `./dev.sh`
(puerto propio del worktree), no `pnpm dev` (hardcodeado al puerto del repo principal).
Un dev server viejo en el puerto puede estar sirviendo master: no confíes en que "algo
responde", verificá que el listener sea ESTE checkout con `verify-port`:

```bash
# Desde el worktree:
nohup ./dev.sh > dev-server.log 2>&1 &   # levanta vite --strictPort en el puerto del worktree
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cat "$HOME/.claude/b-pipeline.root" 2>/dev/null || ls -d "$HOME"/.claude/plugins/marketplaces/b-pipeline* 2>/dev/null | head -1)}"
bash "$PLUGIN_ROOT/skills/b7-issue-to-pr/scripts/guardrails.sh" verify-port "<port>" "$(pwd)"
# exit 0 → B7_PORT_OK; exit 40 nadie escucha; exit 41 lo sirve otro cwd (p.ej. master)
```

### Navigate to the page

```bash
agent-browser open http://localhost:<port>/[country]/<feature>
```

### Check for errors

```bash
# Get a snapshot of the page state
agent-browser snapshot -i
```

Look for:

- Page loads without blank screen
- No JavaScript errors in browser console
- No server errors in the dev server log (dev-server.log)

### Test operations

**List/Read:**

```bash
agent-browser snapshot
# Verify data appears in the table/list
```

**Create:**

```bash
# Fill form fields
agent-browser fill @e<ref> "Test Item"
agent-browser fill @e<ref> "100"
# Submit
agent-browser click @e<ref>  # the submit button
# Verify new item appears
agent-browser snapshot
```

**Edit:**

```bash
# Click edit button on an item
agent-browser click @e<ref>
# Verify form pre-populates
agent-browser snapshot
# Modify and save
agent-browser fill @e<ref> "Updated Name"
agent-browser click @e<ref>  # submit
agent-browser snapshot
```

**Delete:**

```bash
agent-browser click @e<ref>  # delete button
# Handle confirm dialog if present
agent-browser click @e<ref>  # confirm
agent-browser snapshot
# Verify item removed
```

### Check server terminal

Look at the dev server log (dev-server.log) for:

- Unhandled promise rejections
- Database connection errors
- Permission/auth errors
- 500 responses

## Fix and Repeat

If any step found issues:

1. Fix the code
2. Re-correr `scripts/verify.sh` hasta exit 0
3. Repeat the walkthrough until clean

## Common Issues and Quick Fixes

| Symptom                                        | Likely Cause                        | Fix                                                |
| ---------------------------------------------- | ----------------------------------- | -------------------------------------------------- |
| Blank page                                     | Missing route file                  | Create `+page.svelte` in the feature route folder  |
| 401 error                                      | Auth check in remote fn             | Ensure user is logged in, or check `requireUser()` |
| Type error in template                         | Wrong property name                 | Check `InferSelectModel` types match DB columns    |
| Form doesn't submit                            | Missing `enhance()` or wrong spread | Use `{...form.enhance(...)}` pattern               |
| Form submits but list doesn't update           | Missing `.updates(query)`           | Add `await submit().updates(get_items)`            |
| Select doesn't work                            | Using `Select.Value`                | Use `<Select.Trigger placeholder="..." />` instead |
| `on:click` warning                             | Svelte 4 syntax                     | Change to `onclick`                                |
| Import error for shadcn                        | Named import                        | Use `import * as X from '...'`                     |
| Data not refreshing after delete               | Missing refresh                     | Add `get_items.refresh()` after delete command     |
| Console: "Cannot read properties of undefined" | Query returned null                 | Add null check or `?? []` fallback                 |
| Infinite loop in $effect                       | Using $effect for derived state     | Replace with `$derived()`                          |

## Finalize

El cierre del trabajo (doc `<feature>.md`, CHANGELOG, commit via b3, reporte) vive en
Phase 4 del SKILL.md — unica fuente.

## Final Sign-Off

Before marking feature as complete, confirm ALL of these:

- [ ] `scripts/verify.sh` exit 0 — `VERIFY_RESULT branch=ok check=ok react=ok test=ok|skipped` (branch, type check, format y grep anti-React absorbidos ahi)
- [ ] Doc del feature `<feature>.md` presente (feature nuevo) o actualizada (contratos/pantallas cambiados)
- [ ] All `.svelte` files (csv `svelte_files=` de VERIFY_RESULT) pass `svelte-autofixer`
- [ ] Si `browser=required`: page loads in browser without console errors
- [ ] All CRUD operations work (create, read, update, delete)
- [ ] If feature has forms: BOTH create and edit mode tested
- [ ] Server terminal shows no errors during testing
- [ ] CHANGELOG.md updated
- [ ] Changes committed on feature branch
- [ ] User informed of what was and wasn't tested
