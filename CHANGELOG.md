# Changelog

All notable changes to this project are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/):
entries are grouped per release under `Added` / `Changed` / `Deprecated` /
`Removed` / `Fixed` / `Security`, newest release first. An `[Unreleased]`
section at the top collects changes that are committed but not yet released
(they move into the next versioned section on release).

The version lives in three places and all must match (see AGENTS.md rule 2):
the script header comment, `SCRIPT_VERSION`, and the version note in
`README.md`.

## [Unreleased]

(nothing yet — move finished entries into the next versioned section on
release)

## [0.9]

The current version number — unchanged since the `v0.9` tag even though a
lot landed afterwards (two reviewer rounds, the cleanup option, the test
suite). No new release has been cut; everything below ships (or will ship)
as 0.9.

### Added

- Full component menu: arrow-key TUI with 3rd-party + pkg groups, separator
  headers, per-row status colors (green `[installed]` / yellow `[update+]` /
  red `[reason]`), and a plain numbered text fallback for short terminals.
- Menu keys: `s` saves a Kilo backup, `u` updates installed tools in place,
  `p` installs prerequisites on demand (fresh Termux), `r` reloads after
  zoom-out/rotate, `a` bulk-toggles eligible rows, menu wraps at the edges.
- `--cleanup` flag and `cleanup` menu toggle: final pass that purges pip/uv
  caches and temp build dirs, `apt clean` archives, the cargo registry +
  rustup tmp, the go build/test cache (module cache kept), npm cache +
  `~/.npm`, tool-owned temp stubs, and `__pycache__`/`*.pyc` in the tool
  lib dirs. Prints the estimated reclaimable size upfront and the freed size
  afterwards. Ticking only `cleanup` runs the pass standalone.
- Kilo backup/restore (`--save-kilo`, `--restore-kilo`, menu key `s`):
  settings, login tokens, model choice, and chat sessions
  (`storage/`, session pointer, prompt history) in a chmod-600 archive with
  member allow-listing, link-member refusal, and `--no-same-owner` extract.
- `NEOFETCH_BLOCK_CAP=20` config constant: max body lines for a neofetch
  block to count as ours.
- `TP_WHY_DANGLING="link target missing"` constant, shared by the probe and
  the install gate (no string duplication).
- Named network timeout variables in the config block (`NET_CHECK_TIMEOUT`,
  `NET_CONNECT_TIMEOUT`, `GIT_PROBE_TIMEOUT`, `GH_API_TIMEOUT`,
  `PIP_INDEX_TIMEOUT`, `PIP_NET_TIMEOUT`, `PYPI_PROBE_TIMEOUT`,
  `DOWNLOAD_TIMEOUT`) — every network call uses one, never a literal.
- `pkg_noninteractive` helper: every `pkg install`/`upgrade`/`reinstall`
  and `apt full-upgrade` goes through it, so dpkg can never stop an
  unattended run at a conffile prompt.
- `pyc_size` helper: grand-total measurement of exactly what the cleanup's
  pyc step deletes (`__pycache__` dirs plus stray `*.pyc`).
- `menu_bulk_eligible` helper: one bulk-key rule for both menus.
- `comp_broken_why` status accessor next to `comp_status`.
- `sync_step` (cyan `==>`) header for the rc-file-sync result.
- `tests/` bats regression suite (`helpers.bash`, `rc_filters.bats`,
  `tp_gate.bats`, `rc_helpers.bats`): 27 tests covering the strip filters,
  `tp_gate` verdicts, `rc_rewrite` safety, and `ensure_bashrc_line` backups.
- `UNATTENDED` mode with `is_interactive` / `is_interactive_out` helpers:
  `-y` never prompts (mirror picker, rish source menu, kilocode method).
- `usage()` heredoc: `--help` works under `bash <(curl …)` where `$0` is an
  unreadable pipe.
- Exit code for scripted `-y` runs: `0` when everything succeeded or was
  skipped, `2` when any selected tool failed (other stages still run).
- `RESULT[tag]` per-tool outcome map, shown in the summary as
  Installed / Skipped / Failed groups with sequential next-steps numbering.
- `rc_backup` / `rc_rewrite` helpers with `<file>.tmx2tm.bak` snapshots,
  `bash -n` validation, and in-place writes that keep symlinks intact.
- EXIT/INT/TERM traps with a temp-file registry: Ctrl-C exits 130/143 with
  a visible cursor and no leftover temp dirs; background probe jobs never
  clean up for the main shell.
- `TUI_EXTRA_STREAM` (live output for long menu actions) and
  `TUI_EXTRA_REFRESH` (re-probe only after status-changing actions) arrays.
- `TUI_ITEM_BULK` array: the `a` bulk key ticks only eligible rows.
- `MENU_OPTIONS` array: option rows defined once for the menu, colors, and
  bulk rules.
- `python-pip` as an explicit base dependency (replaces `ensurepip`).
- Connectivity pre-check gating red verdicts (offline never paints false
  reds).

### Changed

- Starship snippet guard is now `declare -F starship_precmd` (persists for
  the life of the shell) instead of `STARSHIP_START_TIME`; older forms are
  upgraded in place.
- Neofetch snippet lives in `~/.bash_profile` only (zellij re-sources
  `.bashrc` per tab); the guard variable was dropped.
- Snippet syncs run twice per run: once before the stages (handles removals,
  covers cleanup-only runs) and once after (adds snippets for tools
  installed during the run). A cyan `Shell snippets synced` header marks the
  moment, only when something changed.
- Shizuku probe needs a single `git ls-remote` (shared between the diff and
  the state check); worst-case menu wait documented as a formula (~65 s).
- `update_apt` runs `apt full-upgrade` (like `pkg upgrade`) instead of
  `apt upgrade`.
- Menu cursor wraps around at the list edges.
- Dependencies auto-enable only when not already current: a green `core` or
  `rust` is reused, never force-reinstalled.
- pkg installs retry each package alone after a batch failure; per-tool
  failures warn and continue instead of aborting the run.
- `core` installer is downloaded to a temp file first (with timeouts and a
  non-empty check), then run — no more `curl | bash`.
- `tp_installed` is the single source of truth for 3rd-party presence
  (pydf also accepts `~/.local/bin/pydf`).
- Summary headings use green (`C_OK`); `C_BLUE` stays only for the TUI
  cursor row.
- Install instructions use `$TMPDIR` (Termux has no writable `/tmp`) and
  lead with the `bash <(curl …)` one-liner.

### Fixed

- Starship removal no longer deletes the user's own `fi` lines (block match
  only); edited snippets keep user lines; blanks stay verbatim.
- Neofetch strip no longer wipes to end-of-file on a missing end marker, and
  a second start marker flushes the open block instead of discarding it.
- A dangling `$PREFIX/bin/core` link is repaired (removed + reinstalled)
  instead of skipped as broken.
- Menu refresh preserves toggles unless a status actually changed, drops the
  `p` shortcut once prereqs land, and no longer fires after `s` (save).
- Text-menu `a` matches the TUI bulk rule; text-menu `u` honors toggles and
  refreshes labels afterwards.
- `.bashrc` backup is taken only when the file actually changes.
- Unbound `RESULT[$tag]` crash on the exit path under `set -u`.
- Menu never installs before confirmation.

## [0.6]

Initial tagged baseline: single-file Termux bundler (`tmx2tm.sh`) with the
component groups, Kilo settings backup and restore, and the ssh component.
See `git log v0.6` and earlier for details.
