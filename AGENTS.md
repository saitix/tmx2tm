# AGENTS.md — tmx2tm repo guide

Minimal instructions for agents working in this repo.

## Repo layout

- `tmx2tm.sh` — the installer (single bash file, `#!/data/data/com.termux/files/usr/bin/bash`).
- `README.md` — full user documentation. **Single source of truth for docs.**
- `CHANGELOG.md` — notable changes per release (Keep a Changelog format).
  **Update it in the same commit as any user-visible change:** new features
  go under `Added`, behavior changes under `Changed`, phased-out features
  under `Deprecated`, deleted features under `Removed`, bug fixes under
  `Fixed`, vulnerabilities under `Security`. Unreleased work accumulates in
  the `[Unreleased]` section at the top; it moves into a versioned section
  on release. Never edit a shipped version section to add new entries —
  only to correct a factual error about that release.

## Rules

1. **Keep docs in sync.** Any functional change to the installer (new/removed
   component, new flag, changed stage, version bump) MUST update `README.md`
   in the same commit: component tables, relevant sections, and the version
   note at the top.
   CHANGELOG.md is also to be updated acording to its rules (if and how)
3. **Version rule.** The version lives in THREE places and all must match:
   - script file header comment (`# Version: X.Y`)
   - `SCRIPT_VERSION="X.Y"` in the config block
   - `**Version: X.Y.**` note at the top of `README.md`
   Bump it on every user-visible change.
4. **Adding a pkg tool.** A new entry needs ALL of these, in order:
   - file header comment list (`#   pkg tools:`), alphabetical
   - `PKG_TOOL_COMPONENTS=(...)` array, alphabetical
   - `PKG_COMPONENT[<tag>]=<pkg name(s)>` mapping
   - `PKG_COMPONENT_CMD[<tag>]=<verify binary>` ONLY if the binary differs
     from the tag (e.g. `rust`→`rustc`, `sqlite`→`sqlite3`, `golang`→`go`,
     `ssh`→`sshd`); omit otherwise
   - `COMP_DESC[<tag>]` menu description
   - `COMP_HINT[<tag>]` summary-hint (what to run after install)
   - `README.md` pkg-tools table row + any stage-specific section
5. **Verify before committing:** run `bash -n tmx2tm.sh`
   (syntax), `shellcheck tmx2tm.sh` (lint; must be clean), and `bats tests/`
   (rc-file filter regression tests). Any change to an rc-file filter needs
   a matching test case.
6. **`.bashrc` rule.** Never append blindly — always use the existing
   `ensure_bashrc_line` helper so re-runs stay idempotent.
   - `setup_starship_init` is the exception pattern: it syncs the guarded
     snippet in BOTH `~/.bash_profile` and `~/.bashrc` on EVERY run
     (zellij reads `.bashrc` inside login shells), upgrades the legacy
     unguarded form, and REMOVES the snippet from both files when the
     starship binary is gone. Marker: `# Initialize Starship only once,
     if installed` + `declare -F starship_precmd` guard (older
     `STARSHIP_START_TIME` and legacy `if command -v starship` forms are
     recognized by the strip filter and upgraded).
   - `setup_fastfetch_init` syncs its block in `~/.bash_profile` ONLY
     (zellij would re-run a `.bashrc` copy per tab). It also removes the v0.9
     neofetch block (markers `NEOFETCH_LEGACY_*`) from both files on every
     run: fastfetch replaced neofetch, and the installer never uninstalls
     packages. Both blocks are handled by the shared `_block_strip_filter` /
     `_block_has_closed` with per-block constants from the config block.
   - ALL rc-file rewrites (not just appends) MUST go through `rc_rewrite`
     (with `rc_backup` snapshots to `<file>.tmx2tm.bak`): it validates the
     result with `bash -n` and writes back in place so symlinks survive.
7. **Target:** Termux on Android (aarch64) only. No `dialog`/`gum`
   dependencies; the menu is pure bash. Keep `$PREFIX`, `$HOME`, `pkg`
   assumptions intact.
8. **Commit style:** short imperative subject line (< 72 chars), blank line,
   then a body explaining what and why.
9. **Color rule.** Every displayed action or status that shows something in
   progress is PURPLE: stage headers via `step()` (purple `==>`), wait
   notices via `announce()`, in-progress sub-statuses via `progress()`
   (purple, info-indented). Static notices stay dim (`info`), results stay
   green (`ok`/`done_step`), warnings yellow/pink (`warn`), errors red
   (`die`/red menu rows). Two explicit exceptions: `done_step()` (green
   `==>`) for the final "Installation complete" header, and `sync_step()`
   (cyan `==>`) for the rc-file-sync result header — both are results, not
   progress. Summary section headings use green (`C_OK`); `C_BLUE` stays
   only for the TUI cursor row. Never add a new blue/progress-colored
   helper — reuse these.
10. **Unified status model.** Both component groups share one state machine —
   `current` (green, `[installed]`), `outdated` (yellow, `[update+]`),
   `missing` (dim, no suffix), `broken` (red, `[reason]`, 3rd-party only).
   - Green and broken rows default to OFF in the menu (`menu_default_state`);
     yellow and missing default to ON.
   - Green + explicit menu tick = forced reinstall (`MENU_CONFIRMED`
     distinguishes menu ticks from `-y` select-all, where green is skipped).
   - Green + non-menu run = skip. Broken + selected = warn + skip, never die.
    - Look up state with `comp_status <tag>`, suffix with `comp_suffix <tag>`,
      color with `menu_item_color <tag>`, broken reason with
      `comp_broken_why <tag>` — never read `PKG_STATUS`/`TP_STATUS` /
      `TP_BROKEN_WHY` directly outside the probe functions.
   - 3rd-party probes live in `probe_tp_one` (pip via `pip index versions`,
     git via `ls-remote` + archived API check); `probe_tp_status` runs them
     in parallel. Every network call must use one of the named timeout
     variables in the config block (`NET_*`, `GIT_*`, `PIP_*`, `PYPI_*`,
     `GH_*`, `DOWNLOAD_*`) — add a new variable rather than a literal.
   - `check_connectivity` MUST run before any network probe (menu, refresh,
     non-menu flow). Red verdicts require reachability: offline means
     installed→current, missing→missing — never broken. Gate new red logic
     on `NET_GITHUB` / `NET_PYPI` accordingly.
    - EXCEPTION: `dangling_link()` (symlink present, target gone) is broken
      regardless of network — the local install is at fault, not the source.
      Report as `TP_WHY_DANGLING`; `tp_gate` lets this reason proceed so the
      install stage removes the stale link and reinstalls instead of dying.
    - The `u`-action refresh is `refresh_menu_status`, gated by
      `TUI_EXTRA_REFRESH` (only actions that change statuses trigger it; `s`
      does not) and prints a purple notice first. It forces a row OFF only
      when its status CHANGED into current/broken — unchanged rows keep the
      user's toggle.
   - The text fallback menu signals rc 42 after `p`; `show_menu` loops to
     rebuild and re-probe. NEVER re-exec "$0" to reload: under
     `bash <(curl ...)` $0 is an exhausted /dev/fd pipe, so exec runs an
     empty script and exits silently. In-process loops only.
   - Text-menu `r` (zoom out and reload) signals rc 43 for the same loop;
     a reload is a fresh re-probed look, not a resume of picked toggles.
11. **Auto-commit.** After any addition/correction/removal to the repo,
    commit the changes with a short/brief summary (per the commit style
    above). Never `git push` — pushing is always done manually.
