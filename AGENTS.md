# AGENTS.md — tmx2tm repo guide

Minimal instructions for agents working in this repo.

## Repo layout

- `tmx2tm.sh` — the installer (single bash file, `#!/data/data/com.termux/files/usr/bin/bash`).
- `README.md` — full user documentation. **Single source of truth for docs.**

## Rules

1. **Keep docs in sync.** Any functional change to the installer (new/removed
   component, new flag, changed stage, version bump) MUST update `README.md`
   in the same commit: component tables, relevant sections, and the version
   note at the top.
2. **Version rule.** The version lives in THREE places and all must match:
   - script file header comment (`# Version: X.Y`)
   - `SCRIPT_VERSION="X.Y"` in the config block
   - `**Version: X.Y.**` note at the top of `README.md`
   Bump it on every user-visible change.
3. **Adding a pkg tool.** A new entry needs ALL of these, in order:
   - file header comment list (`#   pkg tools:`), alphabetical
   - `PKG_TOOL_COMPONENTS=(...)` array, alphabetical
   - `PKG_COMPONENT[<tag>]=<pkg name(s)>` mapping
   - `PKG_COMPONENT_CMD[<tag>]=<verify binary>` ONLY if the binary differs
     from the tag (e.g. `rust`→`rustc`, `sqlite`→`sqlite3`, `golang`→`go`,
     `ssh`→`sshd`); omit otherwise
   - `COMP_DESC[<tag>]` menu description
   - `COMP_HINT[<tag>]` summary-hint (what to run after install)
   - `README.md` pkg-tools table row + any stage-specific section
4. **Verify before committing:** run `bash -n tmx2tm.sh`
   (syntax) and `shellcheck tmx2tm.sh` (lint; must be clean).
5. **`.bashrc` rule.** Never append blindly — always use the existing
   `ensure_bashrc_line` helper so re-runs stay idempotent.
6. **Target:** Termux on Android (aarch64) only. No `dialog`/`gum`
   dependencies; the menu is pure bash. Keep `$PREFIX`, `$HOME`, `pkg`
   assumptions intact.
7. **Commit style:** short imperative subject line (< 72 chars), blank line,
   then a body explaining what and why.
8. **Unified status model.** Both component groups share one state machine —
   `current` (green, `[installed]`), `outdated` (yellow, `[update+]`),
   `missing` (dim, no suffix), `broken` (red, `[reason]`, 3rd-party only).
   - Green and broken rows default to OFF in the menu (`menu_default_state`);
     yellow and missing default to ON.
   - Green + explicit menu tick = forced reinstall (`MENU_CONFIRMED`
     distinguishes menu ticks from `-y` select-all, where green is skipped).
   - Green + non-menu run = skip. Broken + selected = warn + skip, never die.
   - Look up state with `comp_status <tag>`, suffix with `comp_suffix <tag>`,
     color with `menu_item_color <tag>` — never read `PKG_STATUS`/`TP_STATUS`
     directly outside the probe functions.
   - 3rd-party probes live in `probe_tp_one` (pip via `pip index versions`,
     git via `ls-remote` + archived API check); `probe_tp_status` runs them
     in parallel. Every network call needs a `--max-time` cap.
   - `check_connectivity` MUST run before any network probe (menu, refresh,
     non-menu flow). Red verdicts require reachability: offline means
     installed→current, missing→missing — never broken. Gate new red logic
     on `NET_GITHUB` / `NET_PYPI` accordingly.
   - The `u`-action refresh is `refresh_menu_status` (both groups + toggles).
