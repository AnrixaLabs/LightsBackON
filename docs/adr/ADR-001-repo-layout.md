# ADR-001: Repository layout

- Status: Accepted (bootstrap, 29 Oct 2026)
- Resolves: HANDOFF section 2, issue 2

## Context
Blueprint section 8 lists the modules as `autoload/`, `network/`, `simulation/`, ... and separately lists `scripts/` as a root
directory. `content/` appears both as a root directory and as a module. Godot needs one `project.godot` location.

## Decision
- `project.godot` sits at the repository root; `res://` is the repo root.
- Root directories: `scenes/ scripts/ content/ assets/ tests/ tools/ docs/ reference/ art_source/`.
- Code modules live under `scripts/`: `scripts/autoload/`, `scripts/network/`, `scripts/simulation/`, `scripts/interaction/`,
  `scripts/actors/`, `scripts/world/`, `scripts/persistence/`, `scripts/progression/`, `scripts/ui/`. Ownership per CLAUDE.md section 5.
- `content/` is a root directory only (typed definitions and imported JSON data); it holds no executable scripts.
- Scenes mirror module names under `scenes/` (for example `scenes/ui/`).
- `docs/`, `tools/`, `reference/` and `art_source/` each contain a `.gdignore` so Godot never imports or exports them.
  `art_source/` is tracked through Git LFS (`.gitattributes`).
- Tests: `tests/unit/` (pure logic, headless), `tests/integration/` (scene/network logic, headless), `tests/manual/` (human checklists).
  Test scripts extend `res://tests/test_case.gd` by path.

## Consequences
Paths in the blueprint that omit `scripts/` are read with the prefix. `power_grid.gd` is `res://scripts/simulation/power_grid.gd`.
