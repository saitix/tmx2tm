# REVISION_PLAN.md — fixes from the round-3 review

Work plan for a worker agent. Each task is self-contained and has acceptance
criteria. Line numbers refer to `tmx2tm.sh` at commit `a1b9b75` (v0.9) and
will drift as you edit, so find code by the function names given.

## Ground rules (from AGENTS.md — read it first)

- Target is Termux on Android (aarch64). Keep the `$PREFIX`, `$HOME` and `pkg`
  assumptions, and keep the menu pure bash (no `dialog` or `gum`).
- Before every commit run `bash -n tmx2tm.sh`, `shellcheck tmx2tm.sh` and
  `bats tests/`. All three must pass. With shellcheck 0.9.x, the
  `SC2329` disables show up as `SC2317` info; check with
  `shellcheck -e SC2317 tmx2tm.sh`.
- Any rc-file filter change needs a matching bats test (AGENTS.md rule 4).
  Write the test first and confirm it fails on the current code.
- Any user-visible change must update `README.md` in the same commit.
- Every rc-file rewrite goes through `rc_rewrite`; appends to `~/.bashrc` go
  through `ensure_bashrc_line`.
- Follow the color rule and the unified status model (AGENTS.md rules 8 and 9).
  Read state with `comp_status` / `comp_suffix` / `menu_item_color`.
- Every network call uses a named timeout variable from the config block.
- Never re-run the script with `exec "$0"`; reloads must stay in-process.
- Commit style: short imperative subject (< 72 chars), blank line, then a body
  saying what changed and why. One commit per task (or per closely related
  group) so each can be reviewed and reverted on its own. Never `git push`.

## Version

Stay on **0.9** for this batch: the README screenshot caption says v0.9 and
the last round deliberately kept it there. This departs from the "bump on
every user-visible change" rule on purpose. If the owner wants a bump instead,
change all three places together (script header, `SCRIPT_VERSION`, README
note) in the final commit.

## Order

1. H1 → H3 → H2 (each with its bats test)
2. M1, then M2 + M3 together, then M4, M5, M6
3. L1–L10
4. Final commit: delete this file

---

## High priority

### H1 — Neofetch filter can delete user lines (and the whole file)

**Where:** `_neofetch_strip_filter` (around line 1804) and
`setup_neofetch_init` (around line 1839).

**Problem:** The awk rule `$0 == s { inb=1; n=0; next }` runs before the
`inb { ... }` buffering rule. When a second start marker appears while a block
is still open (an unclosed legacy block followed later by a proper block),
the buffered lines (user lines included) are thrown away. In the review's
reproduction the whole output was empty. `rc_rewrite` accepts this, because an
empty file passes `bash -n`.

`setup_neofetch_init` makes this layout likely: when the profile has a start
marker but no closed block, it calls `rc_rewrite … || true` and appends a new
block **even if the cleanup was refused**, leaving an unclosed legacy block
followed by a fresh one.

**Fix:**
- In the filter, when the start marker shows up while `inb` is set, flush
  the open buffer first using the same rule as an unclosed block at end of
  file (`flush_legacy`: drop leading known snippet lines, print the rest).
  Then start the new block.
- In `setup_neofetch_init`, if the cleanup `rc_rewrite` fails, `warn` and
  **do not append** a new block (leave the file as it was). Also don't set
  `RC_CHANGED`.

**Tests (`tests/rc_filters.bats`):**
- Input: realistic legacy unclosed block
  (`if [[ $- == *i* ]] && command -v neofetch >/dev/null 2>&1; then`,
  `  neofetch --off`, no `fi`), then `export USERVAR=1`, `alias keep=me`, then a
  full closed block. Expected output, exactly: the two user lines, and nothing
  else.
- Two closed blocks back to back: both are removed and the lines around them
  are kept.
- Idempotent: running the filter on its own output changes nothing.

**Acceptance:** the tests above fail on `a1b9b75` and pass after the fix; the
existing neofetch tests still pass.

### H3 — Starship filter rewrites blank lines outside the snippet

**Where:** `_starship_strip_filter` (around line 1707), the
`/^[[:space:]]*$/` rule and `END` block.

**Problem:** Every run of blank lines in the file is squeezed to one, and
whitespace-only lines become empty lines. That breaks the rule that every line
outside the matched block is left untouched. It only fires when a rewrite
happens (legacy upgrade, or starship removed).

**Fix:**
- Hold pending blank or whitespace-only lines **verbatim** in a buffer
  instead of a single flag.
- On a marker line: drop only the **last** pending blank (the one the
  installer wrote with `printf '\n%s\n'`), print the others verbatim, then
  consume the block as today.
- On any other line, and in `END`: print all pending lines verbatim.

**Tests:**
- Several blank runs (2–3 lines) and a whitespace-only line in user content,
  plus a snippet at the end. Expected: user content byte-for-byte unchanged,
  snippet and the one blank before it gone (compare with `diff`, not line
  counts).
- Tighten `starship: user if-blocks before and after survive` to check the
  exact output.
- Idempotent test still passes.

### H2 — Broken `core` symlink can never be repaired

**Where:** `probe_tp_one` (core branch, around line 634), `tp_gate` (around
line 694), `install_core` (around line 2167).

**Problem:** A dangling `$PREFIX/bin/core` is reported as `broken` /
`link target missing`. `tp_gate` skips **every** broken row, so
`install_core` returns before its link-removal and reinstall code. This
contradicts AGENTS.md rule 9 (EXCEPTION) and README ("selecting it removes the
stale link and runs the official installer").

**Fix:**
- Add a constant next to the other config, e.g.
  `TP_WHY_DANGLING="link target missing"`, and use it both in `probe_tp_one`
  and in `tp_gate`. No string literal duplication.
- In `tp_gate`, a `broken` row whose reason equals `TP_WHY_DANGLING` returns 0
  (proceed, `TP_FORCE=0`) and prints an `info` line saying the stale link will
  be replaced. All other broken reasons keep today's warn and skip.
- Keep the "broken rows default OFF" menu rule. The user must tick the row
  (or use `-y`) to trigger the repair.
- `install_core` already removes the link and, since `-x` fails, runs the
  installer. Verify that path end to end.

**Tests (new `tests/tp_gate.bats`, using `load_functions tp_gate` plus stubs
for `ensure_tp_status`, `info`, `warn`, `record_result`):**
- `broken` + `TP_WHY_DANGLING` → return 0, nothing recorded.
- `broken` + `archived` → return 1, recorded as broken.
- `current` + `MENU_CONFIRMED=1` → return 0 with `TP_FORCE=1`;
  `MENU_CONFIRMED=0` → return 1, recorded skipped.

**Acceptance:** README section on the red status and AGENTS.md rule 9 are both
accurate.

---

## Medium priority

### M1 — `-y` still blocks on prompts when a TTY is attached

**Where:** `ensure_termux_mirror` (`termux-change-repo`, around line 1615),
`install_rish` (around line 2139), `install_kilocode` (around line 2250).

**Problem:** Each one goes silent only when stdin is **not** a TTY. Running
`bash tmx2tm.sh -y` in a terminal still opens the mirror picker, the rish
source menu and the kilocode method prompt. README says `-y` is unattended.

**Fix:**
- Add `UNATTENDED=0` to the runtime options. Set it to 1 when `SHOW_MENU=never`
  (`-y`, `--yes`, `--no-menu`).
- Add one helper, e.g. `is_interactive() { [ "$UNATTENDED" -eq 0 ] && [ -t 0 ]; }`
  (plus `[ -t 1 ]` where the existing check had it), and use it in all three
  places.
- With `-y`: link the bundled default mirror; run rish with
  `--silent --source default`; pick the kilocode recommended method.

**Acceptance:** README `-y` row, rish notes and the repo/apt stage section
say that `-y` never prompts. `--menu -y` (both given): last flag wins, as today;
document it if needed.

### M2 — Worst-case probe time is understated (and shizuku probes twice)

**Where:** `tp_probe_git` (shizuku branch, around line 592),
`tp_git_repo_state`, config comment (around line 148), README (around line 256).

**Problem:** For an installed shizuku, `git ls-remote` runs twice (once
directly, once inside `tp_git_repo_state`), then the GitHub API call: up to
30 + 30 + 15 = 75 s. The pip probe can take up to `PIP_INDEX_TIMEOUT` +
`PYPI_PROBE_TIMEOUT` = 55 s. `check_connectivity` adds up to 10 s before
that. The README and the config comment say "~45 s".

**Fix:**
- Make one `ls-remote` call serve both purposes. For example, split
  `tp_git_repo_state` into an `ls-remote` step that returns the head SHA and a
  separate `tp_git_archived <repo>` API check, then reuse the head in the
  shizuku branch.
- Rewrite the config comment as a formula, not a number:
  worst case ≈ `NET_CHECK_TIMEOUT` + max(`GIT_PROBE_TIMEOUT` + `GH_API_TIMEOUT`,
  `PIP_INDEX_TIMEOUT` + `PYPI_PROBE_TIMEOUT`). With today's values that is
  10 + max(45, 55) = 65 s.
- Update the README to give the same figure and say what it depends on.

**Acceptance:** `grep -c 'git ls-remote' tmx2tm.sh` drops by one; README and
comment agree.

### M3 — Every menu shortcut triggers a full silent re-probe

**Where:** `tui_checklist` (extra-action branch, around line 995),
`refresh_menu_status` (around line 1221), `show_menu` extra-key setup.

**Problems:**
1. `TUI_REFRESH_FN` runs after **every** extra key, including `s` (save
   backup), which changes nothing. It re-runs the connectivity check and all
   probes (up to ~65 s after M2) without any notice, so the menu looks frozen.
2. The refresh turns OFF every green/broken row, which also wipes a green row
   the user had ticked on purpose to force a reinstall.

**Fix:**
- Add a parallel array `TUI_EXTRA_REFRESH` (1 = run `TUI_REFRESH_FN` after
  this action). Set `s=0`, `u=1`, `p=1`. Keep it in sync wherever the
  `TUI_EXTRA_*` arrays are rebuilt (including the `p`-drop loop in
  `refresh_menu_status` and the resets in `show_menu`). Document it in the
  tui_checklist header comment.
- Print a purple `progress`/`announce` notice ("Refreshing status, please
  wait...") before the re-probe starts.
- In `refresh_menu_status`, snapshot each component's `comp_status` before
  the re-probe. Only force a row OFF when its status **changed** into
  `current` or `broken`. Rows whose status didn't change keep the user's
  toggle.
- Apply the same two rules to the text-menu `u` branch in `show_text_menu`.

**Acceptance:** README "Update (menu key 'u')" section and AGENTS.md rule 9
(the `u`-action refresh bullet) describe the new behavior.

### M4 — Text-menu `a` turns on options the TUI's `a` leaves off

**Where:** `refresh_menu_colors` (option bulk rule, around line 1203) and
`show_text_menu` `a|A` branch (around line 1437).

**Problem:** In the TUI, `a` only turns on options that were already on when
the menu was built. In the text menu, `a` turns on **every** option, including
`no_storage`, `cleanup` and `kilocode_native`.

**Fix:** Add one helper, e.g. `menu_bulk_eligible <tag>`: components →
`menu_default_state` is `on`; options → `menu_option_state` is `on`. Use it in
both `refresh_menu_colors` (to fill `TUI_ITEM_BULK`) and the text menu `a`
branch, so the rule lives in one place.

**Acceptance:** both menus' `a` produce the same set of ticked rows for the
same starting state.

### M5 — `update_apt` runs `apt upgrade`, not a full upgrade

**Where:** `update_apt` (around line 1631).

**Problem:** The comment says full upgrade, but the code runs `apt upgrade -y`,
which holds back packages whose dependencies changed. Termux's own
`pkg upgrade` runs `apt full-upgrade`.

**Fix:** use `pkg_noninteractive apt full-upgrade -y`. Update the step text,
the README "Repository / apt upgrade stage" section (`apt full-upgrade -y`)
and the header comment if it mentions it.

### M6 — `.bashrc` backup is overwritten on every run

**Where:** `ensure_bashrc_line` (around line 751).

**Problem:** `rc_backup "$BASHRC"` runs before the presence check. Every
golang, pip or shizuku run with nothing to add still overwrites
`~/.bashrc.tmx2tm.bak` and prints "Backed up …". After two runs the README's
undo instructions no longer restore the pre-tmx2tm file.

**Fix:** call `rc_backup` only inside the `if ! grep -qxF …` branch, right
before the append. Check the other `rc_backup` call sites: the starship and
neofetch append paths are already reached only when something is added, so
leave them alone.

**Tests (`tests/rc_filters.bats` or a new `tests/rc_helpers.bats`):**
- Line already present → no `.tmx2tm.bak` created, file unchanged.
- Line missing → backup holds the original content, line appended once.

**Acceptance:** README "Notes / limitations" says a backup is taken only when
the installer actually changes the file.

---

## Low priority

### L1 — "Shell snippets synced" header in cyan

**Where:** `main` (both `done_step "Shell snippets synced"` calls, around lines
2590 and 2626); output block at the top; AGENTS.md rule 8.

**Problem:** It uses `done_step` (green `==>`), which AGENTS.md rule 8 reserves
for the final "Installation complete" header.

**Fix:**
- Add `C_CYAN` to the color block (for example `$'\e[38;5;51m'`) and one
  helper, e.g. `sync_step()`, using the `==>` header layout in cyan. Use it
  for both calls.
- Amend AGENTS.md rule 8: cyan (`sync_step`) is reserved for the
  rc-file-sync result header. Name it as a second explicit exception next to
  `done_step`, and keep "never add a new blue/progress-colored helper" for
  everything else.
- Mention the cyan header in README where the snippet syncs are described.

### L2 — Direct status-map reads outside the probes

**Where:** `tp_gate` (`TP_STATUS[$tag]` around lines 698 and 705) and
`install_pkg_tools` (`PKG_STATUS[$c]` around lines 1908, 1923 and 1977).

**Fix:** use `comp_status <tag>` everywhere. Reading `TP_BROKEN_WHY` for the
reason text is fine, or add a small `comp_broken_why <tag>` accessor and use it
in `comp_suffix` and `tp_gate`. Behavior must not change; the H2 `tp_gate`
tests cover it.

### L3 — `NEOFETCH_BLOCK_CAP` constant instead of hard-coded `21`

**Where:** `_neofetch_strip_filter` (`n <= 21`, `n > 21`, around lines 1824
and 1827) and `_neofetch_has_closed_block` (`n<=21`, around line 1836). The
comment above the filter already refers to `NEOFETCH_BLOCK_CAP`, which doesn't
exist yet.

**Fix:**
- Add `NEOFETCH_BLOCK_CAP=20` to the config block with a comment: maximum
  number of **body** lines between the start and end markers.
- Pass it into both awk programs with `-v cap="$NEOFETCH_BLOCK_CAP"` and
  replace the three literals with `cap + 1` (the counter includes the end
  marker line). No literal `21` (or `20`) may remain in either function.
- `tests/helpers.bash` extracts only functions, so the variable won't be set
  in tests. Have `setup_stubs` read the real value from `tmx2tm.sh` (for
  example `grep '^NEOFETCH_BLOCK_CAP='` and `eval`), so tests always use the
  script's value instead of a copy.

**Acceptance:** `grep -nE '\b2[01]\b' tmx2tm.sh` finds nothing in the two
neofetch functions; the existing "long edited closed block" and "end marker
beyond cap" tests pass unchanged.

### L4 — Stale or wrong comments

- `menu_update_tools` header: remove the sentence about `SELECTED` mutations
  (the function no longer touches `SELECTED`) and the "caller captures its
  output" note (it now streams).
- `main`, the comment above the first snippet sync (around line 2581): it says
  snippets are removed only when the tool is "absent and not selected", but the
  code doesn't check selection. Say what the code does: binary absent → snippet
  removed. The post-install pass re-adds it for tools installed during this run.
- `probe_tp_status` header ("bounded by the per-call --max-time flags") and
  the `check_connectivity` comments: point to the named timeout variables.
- The neofetch filter comment: reword it to match L3.

### L5 — Text-menu `u` ignores the toggles

**Where:** `menu_update_tools_no_tui` (around line 1538).

**Problem:** It updates every installed 3rd-party tool, while the TUI `u` only
updates toggled-on ones.

**Fix:** pass the text menu's current on-tags into `TUI_ON_TAGS` (build the
list from `tags`/`states` in `show_text_menu`, the same way the TUI builds
`on_tags`). Delete the "updates everything" comment. README "Update (menu key
'u')" applies to both menus.

### L6 — Starship guard is weaker than documented

**Where:** `setup_starship_init`, `_starship_strip_filter`, README starship
section, AGENTS.md rule 5.

**Problem:** README says the snippet evals "at most once per shell tree".
`STARSHIP_START_TIME` is not exported and starship clears it after the first
prompt, so the guard only stops a second eval **during the same startup**. A
later `source ~/.bashrc` (which the summary tells the user to run) evals
starship again and prepends to `PS0` again each time.

**Fix:**
- Change the guard to something that persists for the life of the shell, e.g.
  `if ! declare -F starship_precmd >/dev/null 2>&1 && command -v starship >/dev/null 2>&1; then`.
  The function exists once init has run in this shell and is never inherited
  by child shells, so each new shell still inits exactly once.
- Keep the marker text. Add the new `if` line to the filter's `is_body` set,
  and keep the old `STARSHIP_START_TIME` and legacy `if` lines in it so older
  forms are still recognized.
- Upgrade path: if the marker is present but the body is an older form
  (STARSHIP_START_TIME guard), rewrite it to the new form through
  `rc_rewrite` + the strip filter, then append the current snippet, the same
  way the legacy upgrade works today.
- README: describe it as "once per shell" (re-sourcing is a no-op). Update
  AGENTS.md rule 5 to name the new guard.

**Tests:** previous guarded form → upgraded to the new form; new form →
unchanged (idempotent); strip still removes all three forms.

### L7 — Summary lists unselected green pkg tools as "skipped"

**Where:** `install_pkg_tools`, the second loop over unselected components
(around line 1921).

**Problem:** Unselected pkg tools that are already up to date show up under
"Skipped" in the summary; unselected 3rd-party tools don't. The summary should
cover only what the user (or `-y`) selected.

**Fix:** drop that loop, so only selected-but-green tools are recorded as
skipped. Keep the `info` "Already installed (latest), skipping" line for
selected tools only.

### L8 — Harden `--restore-kilo` against link members

**Where:** `restore_kilo` (around line 2525).

**Problem:** The member-name allow-list accepts any entry under
`.local/share/kilo/storage/`, including symlinks and hard links. GNU tar
already refuses `..` paths, but a symlink member followed by a file written
through it is a known extraction trick.

**Fix:** in addition to the name check, list the archive with
`tar -tvzf` and refuse it if any entry's type character is not `-` (regular
file) or `d` (directory). Also extract with `--no-same-owner`.

**Tests (optional, new `tests/restore.bats`):** a symlink member is refused;
a normal backup made by `save_kilo` is accepted.

### L9 — Make `python-pip` an explicit base dependency

**Where:** `BASE_PKG_DEPS`, `install_pip_tools`.

**Problem:** pip arrives only as a *recommended* package of `python`
(Termux's `python` package sets `TERMUX_PKG_RECOMMENDS="python-ensurepip-wheels, python-pip"`).
`python -m ensurepip --upgrade` then installs a second, pip-managed copy over
the pkg-managed one.

**Fix:** add `python-pip` to `BASE_PKG_DEPS` (next to `python`) and remove the
`ensurepip` line. Update the README base-dependencies list.

### L10 — README covers the two snippet-sync passes

**Where:** README starship and neofetch sections.

**Problem:** The last four commits (`e1c4609`, `4cc85e5`, `96c6969`,
`a1b9b75`) changed user-visible behavior without updating README:
- syncs now run on every run, including cleanup-only runs;
- a second pass runs after the install stages;
- the header is printed only when something changed.

**Fix:** add a short paragraph covering these three points, plus the cyan
header from L1. Version: see the Version section above.

---

## Out of scope

- Connectivity-check download cost (full github.com page; mirror base-URL
  probe). The owner has excluded it from this batch.
- Version pinning or checksums for the upstream installers, and CI.

## Done when

- Every task above is committed with its tests and README/AGENTS.md updates.
- `bash -n tmx2tm.sh`, shellcheck and `bats tests/` are clean.
- This file is deleted in the final commit.
