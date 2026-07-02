# Verification Checklist

Run this checklist after implementing every feature. Do not skip steps.

## Step 0: Branch Check

Before anything else, confirm you are NOT on master:

```bash
git branch --show-current
```

If it says `master` or `main`, STOP. Create a branch first:

```bash
git checkout -b feat/<feature-name>   # or fix/<description>
```

## Step 1: Type Check

```bash
pnpm check:machine
```

Fix ALL type errors before proceeding. Common fixes:

- Missing imports: add the import
- Wrong type: check InferSelectModel matches actual DB schema
- Optional vs required: add `?` or handle null case
- Remote function return type: ensure handler return matches expected type

## Step 2: Format

```bash
pnpm format
```

This auto-fixes formatting. Run it once, no need to check output.

## Step 3: Svelte Autofixer

Run the MCP tool `svelte-autofixer` on EACH `.svelte` file you created or modified:

```
svelte-autofixer({ filePath: "src/routes/<feature>/+page.svelte" })
```

The autofixer catches:

- Svelte 4 syntax (`on:click` -> `onclick`, `export let` -> `$props()`)
- Missing rune declarations
- Incorrect event handler syntax
- Slot vs snippet issues

If it reports issues, fix them and run again until clean.

## Step 4: Browser Test

### Start dev server (serve THIS checkout, not master)

Serví siempre desde el checkout actual — si estás en un worktree, usá su `./dev.sh`
(puerto propio del worktree), no `pnpm dev` (hardcodeado al puerto del repo principal).
Un dev server viejo en el puerto puede estar sirviendo master: no confíes en que "algo
responde", verificá que el listener sea ESTE checkout con `verify-port`:

```bash
# Desde el worktree:
nohup ./dev.sh > dev-server.log 2>&1 &   # levanta vite --strictPort en el puerto del worktree
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/skills/b-pipeline}"
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

## Step 5: Fix and Repeat

If any step found issues:

1. Fix the code
2. Go back to Step 1 (type check)
3. Repeat until clean

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

## Step 6: Finalize

After all verification passes, close out the work:

### Feature doc (`<feature>.md`)

Confirmar que existe `src/routes/<feature>/<feature>.md` (primera parada de debug):

- Feature NUEVO → creado con las 6 secciones del slice-spec (Proposito, Pantallas y rutas,
  Remote functions, Datos, Decisiones, Problemas conocidos).
- Feature EXISTENTE con `.md` → actualizado si el cambio altero contratos o pantallas.
- Feature legacy sin `.md` → generado esta primera vez que se toca.

### Update CHANGELOG

Add entry to `CHANGELOG.md` under a new date section:

```markdown
## [Sin versionar] - YYYY-MM-DD

### Agregado

- **Feature Name**: Brief description of what was added
```

### Commit on branch

Invoke `Skill b-pipeline:b3-git-commit` — it stages only your files (not unrelated
formatter changes), writes the conventional-commit message, and enforces the
clean-tree gate. Do not hand-write `git add`/`git commit` here.

### Report to user

Summarize clearly:

1. What was built (files, screens)
2. What was tested (type check, browser pages, operations)
3. What was NOT tested (if anything — e.g., "edit mode untested, no existing data")
4. Branch name and status (ready for review/merge)

Never say "done" without stating the testing status.

## Final Sign-Off

Before marking feature as complete, confirm ALL of these:

- [ ] Working on a branch (NOT master)
- [ ] Doc del feature `<feature>.md` presente (feature nuevo) o actualizada (contratos/pantallas cambiados)
- [ ] `pnpm check:machine` passes with zero errors in feature files
- [ ] `pnpm format` has been run
- [ ] All `.svelte` files pass `svelte-autofixer`
- [ ] Page loads in browser without console errors
- [ ] All CRUD operations work (create, read, update, delete)
- [ ] If feature has forms: BOTH create and edit mode tested
- [ ] Server terminal shows no errors during testing
- [ ] No React patterns in the code (grep for `useState`, `useEffect`, `onClick`, `on:click`)
- [ ] CHANGELOG.md updated
- [ ] Changes committed on feature branch
- [ ] User informed of what was and wasn't tested
