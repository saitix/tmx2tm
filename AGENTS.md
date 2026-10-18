# AGENTS.md — tmx2tm repo guide

Minimal instructions for agents working in this repo.

## Repo layout

- `xpl-install-termux-tools.sh` — the installer (single bash file, `#!/data/data/com.termux/files/usr/bin/bash`).
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
4. **Verify before committing:** run `bash -n xpl-install-termux-tools.sh`
   (syntax) and `shellcheck xpl-install-termux-tools.sh` (lint; must be clean).
5. **`.bashrc` rule.** Never append blindly — always use the existing
   `ensure_bashrc_line` helper so re-runs stay idempotent.
6. **Target:** Termux on Android (aarch64) only. No `dialog`/`gum`
   dependencies; the menu is pure bash. Keep `$PREFIX`, `$HOME`, `pkg`
   assumptions intact.
7. **Commit style:** short imperative subject line (< 72 chars), blank line,
   then a body explaining what and why.
