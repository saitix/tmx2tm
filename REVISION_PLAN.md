# REVISION_PLAN.md — fixes from the v1.0 review

Work plan for a worker agent. Each task is self-contained and has acceptance
criteria. Line numbers refer to `tmx2tm.sh` at commit `2bfadb1` (v1.0) and will
drift as you edit, so locate code by the function names given.

## Ground rules (from AGENTS.md — read it first)

- Target is Termux on Android (aarch64). Keep the `$PREFIX`, `$HOME` and `pkg`
  assumptions, and keep the menu pure bash (no `dialog` or `gum`).
- Before every commit run `bash -n tmx2tm.sh` and `shellcheck tmx2tm.sh`, and
  (once task T exists) `bats tests/`. All must be clean. Note: shellcheck
  0.9.x reports the functions marked `# shellcheck disable=SC2329` as SC2317;
  that is a version mismatch, not a regression (`shellcheck -e SC2317` is the
  0.9.x equivalent of a clean run).
- Any user-visible change must update `README.md` in the same commit.
- Commit style: short imperative subject (< 72 chars), blank line, then a body
  saying what changed and why. One commit per task (or per closely related
  group) so each one can be reviewed and reverted on its own. Never `git push`.
- Follow the color rule (purple for in-progress, dim for info, green for
  results, yellow/pink for warnings, red for errors) and the unified status
  model. Use `comp_status` / `comp_suffix` / `menu_item_color`; never read
  `PKG_STATUS` / `TP_STATUS` directly outside the probe functions.
- All rc-file rewrites go through `rc_rewrite` (with `rc_backup`).
- Never re-run the script with `exec "$0"`; reloads must stay in-process.
- Delete this file in the final commit once every task is done.

## Suggested order

1. Task V (version demotion) — first, so every later commit is on 0.9
2. Task T (bats harness) together with C and F — write the failing tests
   first, then fix the filters until they pass
3. Tasks A, B, E (menu/selection behavior)
4. Tasks G, H, D (network timeouts, pkg prompts, cleanup figures)
5. Tasks L1–L8 (low priority and housekeeping)

---

## Task V — Demote the version to 0.9

**Why:** the README screenshot shows `tmx2tm.sh v0.9`; the release number
should match it.

**Fix:** set the version to `0.9` in all three places (AGENTS.md rule 2):
- script header comment `# Version: 0.9`
- `SCRIPT_VERSION="0.9"` in the config block
- `**Version: 0.9.**` note near the end of `README.md` (and the
  `Version: 0.9` mention in the same paragraph)

Do **not** bump it again for the other tasks in this plan; the whole batch
ships as 0.9.

**Acceptance:** `grep -n '1\.0' tmx2tm.sh README.md` finds no version
references; `bash tmx2tm.sh -V` prints `tmx2tm.sh v0.9`; the screenshot alt
text (`tmx2tm.sh v0.9 component menu`) now matches.

---

## High priority

### Task A — Ctrl-C no longer stops the script

**Where:** the temp registry / trap block near the top (around line 114):
`trap cleanup_temps EXIT INT TERM`.

**Problem:** a trap on INT that does not exit makes bash run the handler and
carry on. Verified in a pty:
- in the TUI, Ctrl-C runs the cleanup, then `read` waits again — the menu
  cannot be left with Ctrl-C;
- during a stage, Ctrl-C kills the current `pkg install` (rc 130) and the
  script continues with the next stage;
- during the parallel probes, the registered temp dirs are deleted while the
  background jobs still write into them, so tools flip to "missing".

**Fix:**
- Keep `cleanup_temps` on `EXIT` only.
- Add separate INT and TERM handlers that exit with the conventional codes
  (130 for INT, 143 for TERM); the EXIT trap then performs the cleanup once.
- Keep the `BASHPID` guard so background probe jobs never clean up for the
  main shell.
- Optional polish: on INT, print a newline + dim "Cancelled." before exiting
  so the prompt does not land mid-line (the menu `q` path already does this).

**Acceptance:**
- Ctrl-C in the TUI exits the script with status 130, cursor visible, colors
  reset, no registered temp paths left.
- Ctrl-C during a stage (e.g. a long `pkg install`) stops the whole run; no
  later stage starts.
- `bash -n` and shellcheck clean.

### Task B — Auto-enabled dependencies force a reinstall of green tools

**Where:** `apply_menu_result` (the "kilocode depends on core" and
"termux-shizuku-tools needs rust" blocks, around lines 1443–1453), together
with `tp_gate` and `install_pkg_tools`.

**Problem:** the auto-enabled dependency is marked `SELECTED=1` and then
`MENU_CONFIRMED=1` is set, so a dependency that is already current (green) is
treated as an explicit tick and force-reinstalled: `core` reruns its upstream
installer; `rust` triggers `pkg reinstall rust binutils` (~640 MB). With the
defaults this happens on a plain Enter whenever shizuku is yellow and rust is
green.

**Fix:**
- Only auto-enable a dependency whose `comp_status` is not `current`. When
  it is current, do not select it; print a dim info line such as
  "kilocode needs core; core already installed, using it".
- Keep the warn line for the case where the dependency really gets enabled.
- `install_kilocode` already checks `command -v core`; confirm it still works
  when core is green but unselected (it must not be skipped as "needs core").

**Acceptance:**
- Menu: tick only shizuku while rust is green → no `pkg reinstall` of rust;
  shizuku installs/updates normally.
- Menu: tick only kilocode while core is green → core's installer does not
  run; kilocode installs via the existing core.
- Menu: tick kilocode while core is missing → core is enabled and installed
  first (existing behavior).

### Task C — Starship strip filter deletes 3 arbitrary lines

**Where:** `_starship_strip_filter` (around line 1562).

**Problem:** after either marker it unconditionally skips the next three
lines (`skip=3`). If the user edited or shortened the snippet, their own lines
are deleted. The result still passes `bash -n`, so `rc_rewrite`'s safety net
does not catch it. Verified: a marker followed by `eval …`, `alias ll=…`,
`export EDITOR=vim` loses the alias and the export.

**Fix:** remove only lines that exactly match the known snippet, in order,
directly after the marker:
- current form (marker `# Initialize Starship only once, if installed`):
  `if [ -z "$STARSHIP_START_TIME" ] && command -v starship >/dev/null 2>&1; then`,
  `    eval "$(starship init bash)"`, `fi`
- legacy form (marker `# Initialize Starship only if installed`):
  `if command -v starship >/dev/null 2>&1; then`,
  `    eval "$(starship init bash)"`, `fi`

Rules for the filter:
- Drop the marker and then consume expected body lines one at a time; at the
  first line that does not match the expected next line, stop consuming and
  print that line (and everything after it) unchanged.
- If the matched body is incomplete (e.g. `if` matched but no `fi`), do not
  leave an unbalanced `if`: either keep the whole partial block untouched
  (marker included) or drop exactly the matched lines only when that keeps
  the file balanced. Pick one, document it in the comment above the filter,
  and cover it with a test (task T).
- Also drop the single blank line the installer writes before the marker, if
  it immediately precedes it, so repeated add/remove cycles do not
  accumulate blank lines. Optional, but test whichever behavior you choose.

**Acceptance:** all task-T starship cases pass; user lines after the marker
are never removed.

### Task D — Cleanup size figures are wrong

**Where:** `cleanup_stubs`, the two `.pyc` measurements (around lines 2172
and 2240).

**Problems:**
1. `du -sb --files0-from=- | tail -1` prints one line per file without `-c`,
   so `tail -1` takes only the last file's size. Verified: 7000 B reported
   for 21000 B of files.
2. The `find` prunes `__pycache__` directories, so the `.pyc` files inside
   them (where nearly all of them live) are never measured, yet line 2229
   deletes those directories.

**Fix:**
- Measure with a grand total (`du -cb … | tail -1`), and guard the empty
  case (no files → 0, not `du`'s cwd size: with no input `--files0-from`
  prints nothing, so default to 0).
- Measure both the `__pycache__` directories and stray `*.pyc` files outside
  them, i.e. exactly what the removal step deletes. Factor the measurement
  into one small helper used for both the "before" and "after" figures so
  they cannot drift apart.

**Acceptance:** in a scratch tree with `.pyc` files inside and outside
`__pycache__`, the estimate equals the real total (`du -cb` over the same
paths) and the "freed" figure equals the estimate after removal.

### Task E — `a` (toggle all) force-reinstalls every green tool

**Where:** `tui_checklist` key `a`, and the `a` command in
`show_text_menu`.

**Problem:** select-all ticks green rows too, and every ticked green row is a
forced reinstall (`MENU_CONFIRMED=1`) — including rust. A bulk key should not
trigger a mass reinstall.

**Fix:**
- "All on" ticks only rows whose default would be on (missing / outdated)
  plus the option rows that are currently on; green and broken component
  rows are left as they are. "All off" (when everything eligible is already
  on) clears every row, as today.
- Determine eligibility with `menu_default_state <tag>` for component tags;
  option rows (`apt_upgrade`, `no_storage`, `kilocode_native`, `cleanup`) are
  not components and keep today's toggle behavior.
  `tui_checklist` is generic, so pass eligibility in via an optional parallel
  array (e.g. `TUI_ITEM_BULK`, 1 = included in `a`), populated by
  `show_menu`/`refresh_menu_status`; without it `a` behaves as today.
- Green rows can still be ticked one by one with Space / their number to
  force a reinstall.
- Update the help line wording if needed (e.g. `a all (skips installed)`) and
  the README menu section.

**Acceptance:** with some green rows, pressing `a` ticks only missing/yellow
rows; pressing `a` again clears all; Space on a green row still ticks it.
Same in the text fallback menu.

### Task F — Neofetch filter cannot remove a user-edited block

**Where:** `_neofetch_strip_filter` and `_neofetch_has_closed_block`
(around lines 1637–1667).

**Problems:**
1. A block with both markers but more than 4 body lines hits `n > 4` and is
   flushed as "legacy": the start marker and leading `if/neofetch/fi` lines
   are dropped, but the rest — including the end marker and a closing `fi` —
   is printed. The result usually fails `bash -n`, `rc_rewrite` refuses, and
   the warning repeats on every run. When it does parse, an orphan end marker
   is left behind.
2. The `n <= 8` branch is dead code: `n > 4` always fires first.
3. `_neofetch_has_closed_block` still reports such a block as present, so
   the installer never repairs it either.

**Fix:**
- Treat start…end as one block whenever the end marker appears, regardless of
  body length (up to a sane cap, e.g. 20 lines, to avoid swallowing a file
  where the end marker belongs to something far away; beyond the cap, leave
  the file untouched). Drop the whole closed block — markers and body — on
  removal.
- Only when no end marker follows (the legacy unclosed variant) fall back to
  dropping the start marker plus the known snippet lines
  (`if … neofetch …; then`, `  neofetch --off` / `neofetch`, optional `fi`),
  stopping at the first line that is not one of them.
- Remove the dead branch; keep the comment above the filter accurate.
- Keep `_neofetch_has_closed_block` consistent with the filter (same marker
  and same cap rules).

**Acceptance:** all task-T neofetch cases pass; a closed block with a long
edited body is removed in one run and no orphan markers remain.

### Task G — Slow networks mark core/rish broken; timeouts are hardcoded

**Where:** `check_connectivity`, `tp_git_repo_state`, `tp_probe_git`,
`tp_probe_pip`, plus the installer downloads in `menu_update_tools`,
`install_rish` and `install_core`.

**Problem:** connectivity is checked once up front (`NET_GITHUB=1`); if the
later `git ls-remote` then hits its 10 s `timeout`, an installed core/rish is
reported `[source unreachable]` (red) and skipped. Separately, every timeout
is a magic number (5, 8, 10, 15, 60) scattered through the code.

**Fix (decision: increase the timeouts, no extra retry logic):**
- Add a "network timeouts" section to the config block at the top of the
  script (next to `SCRIPT_VERSION` and the `REPO_*` URLs), one variable per
  purpose, with a short comment each. Suggested names and new values:

  | Variable               | Used by                                              | Old | New |
  |------------------------|------------------------------------------------------|-----|-----|
  | `NET_CHECK_TIMEOUT`    | `check_connectivity` curl `--max-time`               | 5   | 10  |
  | `NET_CONNECT_TIMEOUT`  | every curl `--connect-timeout`                       | 5/10| 10  |
  | `GIT_PROBE_TIMEOUT`    | `timeout` around `git ls-remote` (both call sites)   | 10  | 30  |
  | `GH_API_TIMEOUT`       | GitHub API archived check `--max-time`               | 8   | 15  |
  | `PIP_INDEX_TIMEOUT`    | outer `timeout` around `pip index versions`          | 15  | 40  |
  | `PIP_NET_TIMEOUT`      | pip's own `--timeout`                                | 8   | 20  |
  | `PYPI_PROBE_TIMEOUT`   | `curl` to `pypi.org/simple/<pkg>/` `--max-time`      | 8   | 15  |
  | `DOWNLOAD_TIMEOUT`     | installer downloads (rish, core) `--max-time`        | 60  | 120 |

- Replace every hardcoded value with the variable. After the change,
  `grep -nE -- '--max-time [0-9]|--connect-timeout [0-9]|timeout [0-9]|--timeout [0-9]' tmx2tm.sh`
  must return nothing.
- The probes still run in parallel, so the worst-case menu wait is bounded by
  the slowest single probe (~`GIT_PROBE_TIMEOUT` + `GH_API_TIMEOUT`), not the
  sum; mention this in the comment above `probe_tp_status`.
- Update the comments that quote the old numbers (e.g. "Each curl is capped
  at 5s" in `check_connectivity`, "short --max-time" above `TP_STATUS`).
- AGENTS.md rule 9: replace "Every network call needs a `--max-time` /
  `timeout` cap" with a rule that every network call uses one of the named
  timeout variables (add a new variable rather than a literal).
- README: document the timeout variables briefly (where they live and what
  they bound), and note that the menu can take up to ~45 s on a very slow
  network.

**Acceptance:** no literal timeout numbers remain in network calls; the
connectivity line and probes behave as before on a normal network; with a
throttled network (e.g. `tc`/slow proxy) a git probe taking 15 s no longer
turns core/rish red.

### Task H — `pkg install` / `pkg reinstall` can block on a conffile prompt

**Where:** `install_base_deps`, `install_pkg_tools` (batch install, per-package
retry, and the reinstall loop) — around lines 1509, 1770, 1776, 1789.

**Problem:** unlike `update_apt` and `menu_update_tools`, these calls do not
pass `-o Dpkg::Options::="--force-confold"`, so a changed config file can stop
an unattended `-y` run at a dpkg prompt.

**Fix:** pass `DEBIAN_FRONTEND=noninteractive` and
`-o Dpkg::Options::="--force-confold"` to all four call sites. Consider one
small helper (e.g. `pkg_noninteractive <subcommand> <args…>`) used by every
`pkg install`/`upgrade`/`reinstall` call — including `update_apt` and
`menu_update_tools` — so the flags cannot drift again.

**Acceptance:** every `pkg install|upgrade|reinstall` and `apt upgrade` call
in the script carries `--force-confold`
(`grep -nE 'pkg (install|upgrade|reinstall)|apt upgrade' tmx2tm.sh` shows the
flag or the helper on every hit).

---

## Low priority and housekeeping

### L1 — Stale comment above the rc helpers
Line ~673 ("Append a line to ~/.bashrc only if it is not already present.")
sits above the backup helpers. Move it to directly above `ensure_bashrc_line`.

### L2 — `estyle` leaks between shortcut lines
In `_tui_render`, `local ei estyle=""` is declared once; `estyle` is never
reset inside the loop, so a style from one extra-key line carries over to the
next one that has no entry. Reset `estyle=""` at the start of each iteration.

### L3 — `refresh_menu_colors` hardcodes the option rows
It writes five empty entries for the options separator + 4 options by hand,
so adding an option silently shifts every color below. Derive the row layout
from one source of truth: e.g. define the options once (a `MENU_OPTIONS`
array of `tag|description` used by `show_menu` to build items), and have
`refresh_menu_colors` emit one empty entry per option from that same array.

### L4 — `rc_rewrite` temp file is not registered
Call `register_temp "$tmp"` after `mktemp` in `rc_rewrite`, so an interrupt
between `mktemp` and `rm` leaves nothing behind (the EXIT trap from task A
removes it).

### L5 — Duplicate `$PREFIX/tmp/pip-*` in cleanup
In Termux `$TMPDIR` is `$PREFIX/tmp`, so `"$PREFIX"/tmp/pip-*` duplicates
`"$TMPDIR"/pip-*` in both the measure list and the `rm -rf`. Remove the
`$PREFIX/tmp` entries. Use `"${TMPDIR:-$PREFIX/tmp}"` once (e.g. a local
`tmpd`) so an unset `TMPDIR` under `set -u` cannot expand to `/pip-*`.

### L6 — Text menu labels go stale after `u`
In `show_text_menu`, after `u` (`menu_update_tools_no_tui`) the
`[installed]` / `[update+]` suffixes and default toggles are not refreshed.
After `u`, run `check_connectivity`, `probe_pkg_status`, `probe_tp_status`,
then rebuild each component row's description via `COMP_DESC` + `comp_suffix`
and switch green/broken rows off — the same rules as `refresh_menu_status` —
and re-print the list. (`s` does not change any status; no refresh needed.)

### L7 — README says pkg failures are non-fatal, base deps still `die`
The "Notes" section says `apt update` / `apt upgrade` / `pkg install`
warnings are non-fatal, but `install_base_deps` still `die`s on failure (on
purpose: every later stage needs them). Keep the `die`; fix the README to say
base-dependency failures abort the run, while per-tool install failures are
recorded and the run continues (exit code 2).

### L8 — README screenshot alt text
Already says `v0.9`; after task V it matches the version again. Verify only;
no change needed unless task V is skipped.

---

## Task T — bats tests for the startup-file filters

**Goal:** regression tests for the rc-file editing — the riskiest code,
because it rewrites the user's own dotfiles. These tests would have caught C
and F.

**Layout:**
- `tests/helpers.bash` — loads the functions under test from `tmx2tm.sh`
  without running the installer.
- `tests/rc_filters.bats` — the cases below.

**Loading the functions:** `tmx2tm.sh` runs arg parsing and `main` at top
level and sets traps / `set -uo pipefail`, so it must not be sourced into the
bats process (an `EXIT` trap would replace bats' own). Instead, the helper
extracts the needed functions by name with awk (from the `^name() {` line to
the next `^}` line) into a temp file and sources that. Extract at least:
`_starship_strip_filter`, `_neofetch_strip_filter`,
`_neofetch_has_closed_block`, `rc_backup`, `rc_rewrite`, `register_temp`,
`info`, `warn`. Define `C_*` color variables as empty strings and
`TEMP_PATHS=()` / `declare -A RC_BACKED_UP=()` in the helper. Fail loudly if
a function name is not found (so a rename breaks the test, not silently
passes it).

Each test works in `$BATS_TEST_TMPDIR` with fixture files written inline via
`printf`/heredoc; assert exact output with a here-doc expected file and `diff`,
and check `bash -n` on every result.

**Starship cases (`_starship_strip_filter`):**
1. Current snippet only → removed completely.
2. Legacy snippet only → removed completely.
3. User `if …; then … fi` block before AND after the snippet → only the
   snippet goes; both user blocks remain byte-identical; `bash -n` passes.
4. Marker followed by an edited body (`eval …`, `alias ll=…`,
   `export EDITOR=vim`) → `alias` and `export` survive (bug C).
5. Marker followed by an incomplete body (`if` line, no `fi`) → result
   passes `bash -n` and matches the behavior chosen in task C.
6. No marker → output identical to input.
7. Idempotence: filtering twice equals filtering once.

**Neofetch cases (`_neofetch_strip_filter` / `_neofetch_has_closed_block`):**
1. Closed block as written by the installer → removed completely;
   `_neofetch_has_closed_block` true before, false after.
2. Closed block with a long edited body (6+ lines, own `if/fi`) → removed
   completely, no orphan `fi` or end marker, `bash -n` passes (issue F).
3. Legacy unclosed block (no `fi`, no end marker) followed by an unrelated
   user `if … fi` block → only the snippet lines go; the user block survives.
4. Start marker with no end marker and unrelated lines right after → those
   lines survive (no "wipe to EOF").
5. End marker far away (beyond the cap from task F) → file untouched.
6. No markers → output identical to input.
7. Idempotence.

**`rc_rewrite` cases:**
1. Filter output that fails `bash -n` → original file untouched, non-zero
   return, warning printed.
2. Symlinked rc file → still a symlink after a successful rewrite; target
   content updated.
3. Backup → `<file>.tmx2tm.bak` created once per run with the original
   content (second rewrite in the same run does not overwrite it).

**Docs:**
- AGENTS.md rule 4: add `bats tests/` to "Verify before committing", plus a
  note that any change to an rc-file filter needs a matching test case.
- README: a short "Development" / "Tests" section — how to install bats-core
  (e.g. `pkg install bats` on Termux if available, `npm i -g bats`, or the
  distro package) and run `bats tests/`. Tests run on any Linux; no Termux
  needed.

**Acceptance:** `bats tests/` passes after tasks C and F; temporarily
reverting C or F makes the corresponding cases fail.

---

## Out of scope

- Pinning upstream installers (core-termux, rish_installer,
  termux-shizuku-tools) to a commit/tag or verifying checksums.
- CI workflows.
