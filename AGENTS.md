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
   - `setup_starship_init` is the exception pattern: it syncs the guarded
     snippet in BOTH `~/.bash_profile` and `~/.bashrc` on EVERY run
     (zellij reads `.bashrc` inside login shells), upgrades the legacy
     unguarded form, and REMOVES the snippet from both files when the
     starship binary is gone. Marker: `# Initialize Starship only once,
     if installed` + `STARSHIP_START_TIME` guard.
   - `setup_neofetch_init` syncs its block in `~/.bash_profile` ONLY
     (zellij would re-run a `.bashrc` copy per tab).
   - ALL rc-file rewrites (not just appends) MUST go through `rc_rewrite`
     (with `rc_backup` snapshots to `<file>.tmx2tm.bak`): it validates the
     result with `bash -n` and writes back in place so symlinks survive.
6. **Target:** Termux on Android (aarch64) only. No `dialog`/`gum`
   dependencies; the menu is pure bash. Keep `$PREFIX`, `$HOME`, `pkg`
   assumptions intact.
7. **Commit style:** short imperative subject line (< 72 chars), blank line,
   then a body explaining what and why.
8. **Color rule.** Every displayed action or status that shows something in
   progress is PURPLE: stage headers via `step()` (purple `==>`), wait
   notices via `announce()`, in-progress sub-statuses via `progress()`
   (purple, info-indented). Static notices stay dim (`info`), results stay
   green (`ok`/`done_step`), warnings yellow/pink (`warn`), errors red
   (`die`/red menu rows). The one exception: `done_step()` (green `==>`)
   for the final "Installation complete" header, which is a result, not
   progress. Summary section headings use green (`C_OK`); `C_BLUE` stays
   only for the TUI cursor row. Never add a new blue/progress-colored
   helper — reuse these.
9. **Unified status model.** Both component groups share one state machine —
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
     in parallel. Every network call needs a `--max-time` / `timeout` cap
     (curl: `--max-time` + `--connect-timeout`; git: `timeout` +
     `GIT_TERMINAL_PROMPT=0`; pip: `--timeout` + `timeout`).
   - `check_connectivity` MUST run before any network probe (menu, refresh,
     non-menu flow). Red verdicts require reachability: offline means
     installed→current, missing→missing — never broken. Gate new red logic
     on `NET_GITHUB` / `NET_PYPI` accordingly.
   - EXCEPTION: `dangling_link()` (symlink present, target gone) is broken
     regardless of network — the local install is at fault, not the source.
     Report as `[link target missing]`; the install stage must remove the
     stale link and reinstall instead of dying.
   - The `u`-action refresh is `refresh_menu_status` (both groups + toggles).
   - The text fallback menu signals rc 42 after `p`; `show_menu` loops to
     rebuild and re-probe. NEVER re-exec "$0" to reload: under
     `bash <(curl ...)` $0 is an exhausted /dev/fd pipe, so exec runs an
     empty script and exits silently. In-process loops only.
   - Text-menu `r` (zoom out and reload) signals rc 43 for the same loop;
     a reload is a fresh re-probed look, not a resume of picked toggles.
10. **Auto-commit.** After any addition/correction/removal to the repo,
    commit the changes with a short/brief summary (per the commit style
    above). Never `git push` — pushing is always done manually.
