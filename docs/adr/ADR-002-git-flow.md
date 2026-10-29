# ADR-002: Git flow

- Status: Accepted (bootstrap, 29 Oct 2026)

## Decision
- `main` is the integration branch. It only changes through pull requests. No direct pushes, no force-pushes, no history rewrites.
- One branch per backlog task: `task/<ID>-<slug>` (for example `task/G01-power-grid`). Claude Code cloud sessions may be forced onto a
  `claude/...` branch; then every commit message carries the task ID (`G01: port evaluator`).
- One PR per task (or per small batch of tightly coupled tasks), opened into `main`, with the evidence file `docs/evidence/<ID>.md` in the same PR.
- Milestone gates are annotated tags on the merge commit that closes the gate: `gate-F`, `gate-G`, `gate-V`, `gate-A`, `gate-D`, `gate-CT`,
  `gate-H`, `gate-B`, `gate-R`. A tag is created only after the owner accepts the gate report.
- Commit and push after every logical step; a cloud session can end at any time.
- Line endings are LF everywhere (`.gitattributes`); large art originals go through Git LFS under `art_source/`.
- Never committed: `private/`, `steam_appid.txt`, Steamworks SDK files, tokens, export credentials (`.gitignore`).

## Consequences
The repo is the shared memory between cloud and local sessions; conversation history is not. Status lives in `docs/backlog.json`.

## Addendum (30 Oct 2026, ADR-015)
- Desktop worktree sessions work on `claude/<slug>` branches like cloud sessions; the task-ID-in-every-commit rule applies.
- Cut each task branch from `origin/main`. Do not branch a task from another unmerged task branch: the V04/V05/V06/V08 stack needed five
  cross-merges to propagate review fixes. If a task needs unmerged work, finish and merge that PR first.
- Workflow or tooling changes that are not a backlog task get their own small PR, separate from task PRs.
- Merged task branches may be deleted on GitHub after merge (owner's call); the PR keeps the history.
