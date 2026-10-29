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
