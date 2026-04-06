# AGENTS.md

Operational guidance for coding agents working in `doubt.nvim`.
This file is intentionally practical: run commands exactly as listed, follow module ownership, and preserve existing behavior unless explicitly changing it.

## Project Snapshot

- Project: `doubt.nvim` (Neovim plugin for skeptical code review and handoff export).
- Language/runtime: Lua on Neovim APIs (`vim.api`, `vim.fn`, `vim.ui`, `vim.json`, `vim.uv`).
- Required dependency: `MunifTanjim/nui.nvim`.
- Entrypoints: `plugin/doubt.lua` bootstrap and `require("doubt").setup(...)`.
- Core workflow: create claims -> persist sessions -> refresh/reanchor freshness -> export XML/templates.

## Repository Layout

- `plugin/doubt.lua`: plugin bootstrap, command registration on load.
- `lua/doubt/init.lua`: top-level orchestration and public API.
- `lua/doubt/config.lua`: defaults, setup merge, highlights.
- `lua/doubt/claims.lua`: claim normalization, sorting, anchor validation.
- `lua/doubt/state.lua`: persistence and workspace-scoped session mutation.
- `lua/doubt/render.lua`: extmarks/signs/inline note rendering.
- `lua/doubt/panel.lua`: side panel UI and help modal.
- `lua/doubt/export.lua`: XML and template rendering.
- `lua/doubt/input.lua`: wrappers around `nui.input` and checklist input.
- `lua/doubt/commands.lua`: `:Doubt*` command wiring.
- `lua/doubt/keymaps.lua`: default keymaps and claim-kind mappings.
- `tests/*_spec.lua`: headless Neovim Lua specs.
- `tests/helpers/bootstrap.lua`: test bootstrap and minimal assertions.

## Build, Lint, and Test Commands

There is no separate build step and no configured linter/formatter in-repo (`stylua`, `luacheck`, `selene`, `make`, and CI config are absent).

Use Neovim headless execution for tests:

```bash
# Run full test suite (all spec files)
for file in tests/*_spec.lua; do nvim --headless -u NONE -c "luafile $file" -c "qa" || exit 1; done

# Run one specific test file (single-test workflow)
nvim --headless -u NONE -c "luafile tests/plugin_bootstrap_spec.lua" -c "qa"

# Example: run another specific spec file
nvim --headless -u NONE -c "luafile tests/claim_anchor_model_spec.lua" -c "qa"
```

Recommended verification flow for code changes:

1. Run the specific changed spec file(s) first.
2. Run the full suite before finalizing.
3. If behavior touches UI flows, do a quick manual Neovim smoke test (`:DoubtPanel`, claim add/edit/delete, export).

## Single-Test Guidance

- Tests are file-scoped scripts, not function-filtered unit tests.
- "Run a single test" means run one `*_spec.lua` file via `luafile`.
- Keep temporary state isolated using `vim.fn.tempname()` patterns (as existing tests do).
- When adding a new spec, use naming `tests/<feature>_spec.lua`.

## Coding Style and Conventions

### Formatting

- Use tabs for indentation in Lua files.
- Keep lines readable; prefer small helper functions over deep nesting.
- Preserve existing table literal and function-call formatting style in touched files.
- No auto-formatter is enforced; match local file style manually.

### Imports / Requires

- Place `local mod = require("...")` near file top.
- Prefer explicit module paths (`require("doubt.state")`, not dynamic require patterns).
- Typical ordering:
  1) internal `doubt.*` modules,
  2) third-party modules (`nui.*`),
  3) `local M = {}` and module-local state.
- Avoid circular dependencies; push shared pure logic into owning module instead.

### Types and Data Shapes (Lua)

- No static type system is configured; enforce shapes by normalization and guards.
- Normalize claims through `claims.normalize_claim(...)` before persistence/use.
- Keep claim fields stable (`id`, `kind`, `start_line`, `start_col`, `end_line`, `end_col`, `note`, `freshness`, `anchor`).
- Treat path keys as normalized via `vim.fs.normalize` before storing in state.
- Session names must be trimmed and non-empty.

### Naming

- Use `snake_case` for locals/functions.
- Keep module API on `local M = {}` with explicit exported function names.
- Use descriptive names for derived values (`session_name`, `workspace_key`, `normalized_claims`).
- Keep command/action names aligned with established `Doubt*` vocabulary.

### Error Handling and Notifications

- Prefer early returns for invalid states.
- Validate user inputs at boundaries (commands, input callbacks, persistence load).
- Route user-facing messages through `ctx.notify` where context exists.
- Use `vim.log.levels.INFO` for benign/empty states.
- Use `vim.log.levels.WARN` for invalid actions or unknown session/claim targets.
- Use `vim.log.levels.ERROR` for hard failures (save/load/export failures).
- Do not throw errors for expected UX paths when notify + return is sufficient.

### State, Persistence, and Integrity

- Keep persistence logic in `state.lua`; do not leak file I/O into UI modules.
- Workspace scoping lives under `state.workspaces[workspace_key]`; preserve this shape.
- Maintain deterministic claim order with `claims.sort_claims(...)`.
- Drop empty file claim buckets during normalization.
- Preserve freshness semantics:
  - `fresh`: anchor/range still valid,
  - `reanchored`: anchor found at updated location,
  - `stale`: ambiguous/missing/changed anchor.

### Commands, Keymaps, and UI Responsibilities

- Keep `commands.lua` and `keymaps.lua` as thin wiring layers.
- Put claim math/normalization in `claims.lua`, not panel/render modules.
- Put panel-specific interaction in `panel.lua`; rendering primitives in `render.lua`.
- Preserve existing keymap defaults and opt-out behavior (`keymaps = false` or per-key false).

### Testing Patterns

- Follow existing test style: `local t = dofile("tests/helpers/bootstrap.lua")`.
- Use `t.assert_eq` and `t.assert_match` helpers for assertions.
- Keep specs deterministic and isolated (explicit setup, no hidden shared globals).
- Validate both state mutation and user-visible behavior (notify text, mappings, buffer options).

## Export and Handoff Rules

- Canonical payload is raw XML grouped by file.
- `:DoubtExport` applies template wrappers; default template is configurable (currently `review`).
- Trusted export includes only `fresh` + `reanchored` claims.
- Stale claims are skipped and should be reported in notify output.
- Supported template variables: `{{xml}}`, `{{session}}`/`{{session_name}}`, `{{file_count}}`, `{{claim_count}}`.

## Scope and Change Discipline for Agents

- Make focused changes in owning module first; avoid cross-module refactors unless required.
- Do not silently alter command names, key defaults, or persistence schema.
- Do not commit `.planning` artifacts unless explicitly requested.
- If adding behavior, add or update matching spec coverage in `tests/`.

## Cursor / Copilot Instruction Files

At time of writing, no repo-local rule files were found:

- No `.cursor/rules/` directory.
- No `.cursorrules` file.
- No `.github/copilot-instructions.md` file.

If any of these are added later, treat them as higher-priority agent instructions and update this document accordingly.
