# Cierre de un run --dry-run

En dry-run el worktree se **mantiene**; los pasos 4 (PR + label `in-review`) y 5 (b6-review) se saltan, pero los pasos 1 y 2 (worktree, label `in-progress` + comentario sticky) ya ocurrieron. Decirle al usuario:

- Path del worktree (para `cd` e inspeccionar), del run report, y de `.b7/screens/` + `.b7/review/` (mockups + screenshots).
- Estado actual del issue: label `in-progress`, comentario sticky publicado.
- Como promover a PR: `cd <worktree>; git status; git diff` + `/b3-git-commit` + `/b4-pull-request` + mover el label a `in-review`.
