# REVISION_PLAN.md — fixes from the v0.9 review

Work plan for a worker agent. Each task is self-contained and has acceptance
criteria. Line numbers refer to `tmx2tm.sh` v0.9 (commit `b21c0e8`) and will
drift as you edit, so locate code by the function names given.

## Ground rules (from AGENTS.md — read it first)

- Target is Termux on Android (aarch64). Keep the `$PREFIX`, `$HOME` and `pkg`
  assumptions, and keep the menu pure bash (no `dialog` or `gum`).
- Before every commit run `bash -n tmx2tm.sh` and `shellcheck tmx2tm.sh`. Both
  must be clean (see task 13).
- Any user-visible change must update `README.md` in the same commit.
- Bump the version in all three places (script header, `SCRIPT_VERSION`,
  README note) once per batch of user-visible changes.
- Commit style: short imperative subject (< 72 chars), blank line, then a body
  saying what changed and why. One commit per task (or per closely related
  group) so each one can be reviewed and reverted on its own.
- Follow the color rule (purple for in-progress, dim for info, green for
  results, yellow/pink for warnings, red for errors) and the unified status
  model. Use `comp_status` / `comp_suffix` / `menu_item_color`; never read
  `PKG_STATUS` / `TP_STATUS` directly outside the probe functions.
- Never re-run the script with `exec "$0"`; reloads must stay in-process.

## Suggested order

1. Tasks 1, 2 and S1 (the risky shell-startup-file editing; do these together)
2. Tasks 6, 5, 3, 4 (robustness)
3. Tasks 8, 7, 9, 10, 11, S2 (correctness and cleanup)
4. Tasks 12–15 (docs and housekeeping)

---

## High priority

### Task 1 — Starship snippet removal strips every bare `fi` line

**Where:** `setup_starship_init`: the legacy-upgrade loop (around line 1435)
and the removal branch when starship is uninstalled (around line 1450).

**Problem:** It removes lines with `grep -vxF … -e 'fi'`, which deletes every
line in the file that is exactly `fi`, including the closing `fi` of the
user's own `if` blocks. That leaves `~/.bashrc` / `~/.bash_profile` unparsable
("unexpected end of file"). The removal branch runs on every install when the
starship binary is absent, not just once.

**Fix:**
- Remove the snippet as a block: find the marker line and delete only it plus
  the exact following lines that make up the snippet (`if …`, `eval …`, `fi`),
  and only when they appear in that order directly after the marker.
- Handle both the legacy marker (`# Initialize Starship only if installed`,
  unguarded `if`) and the current marker (`# Initialize Starship only once, if
  installed`, `STARSHIP_START_TIME` guard).
- Leave every line outside the matched block untouched, including blank
  lines and other `fi`s.
- Use the shared safe-rewrite helper from task S1 (backup plus in-place
  write) instead of `> "$f.tmp" && mv`.

**Acceptance:**
- An rc file containing a user `if …; then … fi` block plus the legacy
  snippet becomes the user block plus the guarded snippet, and still passes
  `bash -n`.
- With starship absent, the same file loses only the snippet and still passes
  `bash -n`.
- Running it twice gives the same result as running it once (idempotent).

### Task 2 — Neofetch block strip can delete the rest of the file

**Where:** `_strip_neofetch_block` inside `setup_neofetch_init` (around line
1500).

**Problem:** The awk range skips everything from the start marker until it
sees the end marker. If the end marker is missing (a truncated file or a hand
edit), every line after the start marker is deleted.

**Fix:**
- Strip a block only when the start marker has a matching end marker after
  it.
- For an unclosed legacy block, remove only the start marker plus the known
  snippet lines (`if …`, `  neofetch --off`, and its `fi` if present), then
  stop.
- Use the task S1 helper for the write.
- While here, delete the stale duplicate comment line at the top of the
  function's header comment (around line 1480: "kept in sync in
  ~/.bash_profile AND ~/.bashrc on").

**Acceptance:**
- A file with a start marker, the snippet lines and then unrelated
  user lines, but no end marker, keeps all the unrelated user lines.
- A properly closed block is removed exactly.
- The result passes `bash -n`.

### Task 3 — Menu actions can freeze on hidden prompts or show no progress

**Where:** `menu_update_tools` (the `pkg upgrade -y` call), `menu_install_prereqs`,
and `tui_checklist` (the extra-action branch that captures the action's output
with `$(…)`).

**Problems:**
- `pkg upgrade -y` without `--force-confold` can stop at a dpkg
  config-file prompt. Because the output is captured, the prompt is invisible
  and the menu looks frozen.
- The `p` action runs for minutes with no visible output.
- `ensure_termux_mirror` skips `termux-change-repo` when stdout is not a
  terminal, which is always the case under the capture, so `p` never shows
  the mirror picker.

**Fix:**
- Make `menu_update_tools` use the same non-interactive apt options as
  `update_apt`: `DEBIAN_FRONTEND=noninteractive` and
  `-o Dpkg::Options::=--force-confold`. Run `apt`/`pkg` update + upgrade with
  those options.
- Stop capturing output for the long-running actions (`u`, `p`). Let them
  write straight to the terminal below the menu, then wait for "Press any key
  to return", then clear the screen and redraw the menu in full instead of
  doing the line-counted erase. One way: add a per-action "stream" flag next
  to `TUI_EXTRA_FNS`. Keep capture for the short `s` action if you like.
- `menu_install_prereqs` should then be able to run `termux-change-repo`
  interactively when no mirror is chosen.
- Run streamed actions in a subshell (or otherwise keep them isolated) so
  their variable changes still don't leak into the menu state, as the comment
  on `menu_update_tools` requires.

**Acceptance:** With a short `sleep`/`echo` stub in place of the update or
prereqs body, output appears live, the menu redraws cleanly afterwards, and
toggles are preserved. The text fallback menu still works.

### Task 4 — `--help` is broken under `bash <(curl …)`

**Where:** the `-h|--help` case in the argument loop (around line 240).

**Problem:** It runs `sed` on `"$0"`. Under process substitution `$0` is a
partly-read pipe, so the output is a random chunk of code. The README
recommends exactly that one-liner.

**Fix:**
- Move the usage text into a `usage()` function that prints a heredoc. The
  argument loop runs before the helpers section, so define `usage()` above
  the loop.
- Keep the header comment block as the human-readable reference, but make
  sure the heredoc and the header's "Usage:" list stay in sync. Note in the
  header that `usage()` is the source of truth.

**Acceptance:** `PREFIX=/usr bash <(cat tmx2tm.sh) --help` and `bash
tmx2tm.sh --help` print the same complete usage text.

### Task 5 — Some network calls have no timeout

**Where:**
- `tp_git_repo_state` and `tp_probe_git` (`git ls-remote`)
- `tp_probe_pip` (`pip index versions`, `pip show` is local and fine)
- `menu_update_tools` (rish `curl`)
- `install_rish` and `install_core` (download `curl`)

**Fix:**
- Wrap `git ls-remote` in `timeout 10` (coreutils `timeout` is available in
  Termux). Also set `GIT_TERMINAL_PROMPT=0` so a gone or private repo never
  prompts for credentials.
- Give `pip index versions` options such as `--timeout 8 --retries 0`, and
  wrap it in `timeout 15` as a hard cap.
- Add `--max-time` (e.g. 60 for installer downloads) and
  `--connect-timeout 10` to every `curl` that lacks them.
- Update the AGENTS.md wording ("Every network call needs a `--max-time`
  cap") to say `--max-time` / `timeout` so it covers git and pip too.

**Acceptance:** `grep -n 'curl\|ls-remote\|pip index' tmx2tm.sh` shows a cap
on every network call. With network blocked (e.g. a bad DNS entry for
github.com), the menu probe finishes within about 15 s.

### Task 6 — No `trap`: Ctrl-C leaves a hidden cursor and leftover temp dirs

**Where:** global (near the output helpers) and `tui_checklist`.

**Fix:**
- Add a single EXIT/INT/TERM trap that:
  - restores the cursor (`tput cnorm`) and resets colors;
  - removes any temp files or directories registered in a global list.
    Make `check_connectivity`, `probe_tp_status`, `install_rish` and
    `menu_update_tools` register theirs in that list.
- On INT, exit with code 130 after cleanup.
- Make sure the trap does not interfere with the background probe jobs
  (subshells inherit traps; the cleanup should run only in the main shell,
  e.g. compare `$BASHPID` with a saved `$$`).

**Acceptance:**
- Pressing Ctrl-C in the TUI gives a visible cursor and no leftover
  `tmp.*` directories from this script.
- `shellcheck` stays clean.

---

## Medium priority

### Task 7 — `--cleanup` is wider than advertised and its size estimate is wrong

**Where:** `cleanup_stubs`.

**Fix:**
- Stop deleting `$TMPDIR/tmp.*`; it removes other programs' temp
  directories. Only remove temp paths this script created (tracked by the
  task 6 registry) or clearly tool-owned patterns (`pip-*`,
  `pip_build_*`, `core-*`, `rish*`).
- Do not run `apt autoremove -y` unattended. Either drop it or make it a
  separate, explicit option. If you keep it as an option, add the menu toggle,
  the flag, and the README entry.
- Change Go cleanup to build/test cache only (`go clean -cache -testcache`).
  Do not wipe the module cache (`-modcache`) by default.
- Fix the estimate: do not `du` the whole `~/.local/lib` and
  `$SHIZUKU_DIR` trees. Measure only the `__pycache__` / `*.pyc` portion for
  those two (already computed as `_pyc`), and add the whole-path sizes only
  for real cache directories. Remove the unresolved comment block that
  admits the miscount (around lines 1889–1892).
- Fix the four SC2015 `A && B || C` patterns here (see task 13).
- Update the `--cleanup` section of README.md to list exactly what is
  removed.

**Acceptance:** The estimated and freed sizes match within normal noise on a
test `$HOME`, and nothing outside the documented list is removed.

### Task 8 — `install_core` pipes curl into bash

**Where:** `install_core` (around line 1785).

**Fix:**
- Download `REPO_CORE_INSTALL` to a `mktemp` file first (with the task 5
  timeouts), check that the download succeeded and is not empty, then run
  `bash "$tmp"` and remove the file. Use the same pattern as `install_rish`.
- This also lets the upstream installer read keyboard input when it needs
  to.
- Out of scope: pinning a commit, tag or checksum. Keep fetching from
  `main`, as now.
- Update the README line that says "installed via: `curl -fsSL
  …/install.sh | bash`".

**Acceptance:** No `| bash` remains in `tmx2tm.sh` (outside comments that
warn against it), and the core install still works on a device.

### Task 9 — Three different "is it installed?" checks

**Where:** `tp_installed`, the inline checks in `menu_update_tools`, and the
inline checks in the `install_*` stages.

**Fix:**
- Make `tp_installed <tag>` the single source of truth and call it from
  `menu_update_tools` (for copyparty, ytdlp, pydf, shizuku, rish, core and
  kilocode).
- Where an install stage needs a more specific path (e.g. `install_core`
  checks `-x "$PREFIX/bin/core"`), keep that but add a comment explaining
  why it differs.
- Make pydf consistent with the other pip tools, also accepting
  `~/.local/bin/pydf`.

**Acceptance:** `grep -n 'command -v copyparty\|command -v yt-dlp\|command -v
pydf' tmx2tm.sh` only finds matches in `tp_installed` and in result messages.

### Task 10 — Hidden coupling between `refresh_menu_status` and `tui_checklist`

**Where:** `refresh_menu_status` and `tui_checklist`.

**Problems:**
- `refresh_menu_status` reads and writes `n`, `kinds`, `tags`, `descs` and
  `states`, which are locals of `tui_checklist`. This only works because of
  bash's dynamic scoping.
- The `p` shortcut stays listed after the prerequisites are installed.

**Fix:**
- Document the contract explicitly. Add a comment block in both functions
  listing the variables the refresh hook may read and write. Optionally,
  rename the locals with a `_tui_` prefix so the coupling can be found with
  grep.
- After the refresh, drop the `p` entry from `TUI_EXTRA_*` when
  `prereqs_missing` is false. Remember that `lines` (the redraw height) in
  `tui_checklist` depends on `extra`, so recompute `extra` and `lines` after
  the refresh hook runs.

**Acceptance:** After `p` succeeds, the menu redraws without the `p` line and
without leftover lines on screen.

### Task 11 — The summary lists tools that weren't installed

**Where:** `print_summary`, and every install stage.

**Fix:**
- Track the outcome of each tool in an associative array, e.g.
  `RESULT[tag]=installed|updated|skipped|failed|broken`. Set it in
  `install_pkg_tools` (per tag, using the verify binary), in `tp_gate`
  (skipped/broken), and in each `install_*` stage.
- In the summary:
  - Under "Installed tools", print only installed/updated tools.
  - Add a "Skipped" group and a "Failed" group, each with its reason.
- Number the "Next steps" lines in sequence with a counter instead of
  hardcoding 1/2/3.

**Acceptance:** On a `-y` run where one tool is broken, that tool appears
under "Skipped", not under "Installed tools". The steps are numbered 1..N
with no gaps.

---

## Docs and housekeeping

### Task 12 — Make install instructions consistent

- Change the script header comment (lines 6–13): use `"$TMPDIR/tmx2tm.sh"`
  instead of `/tmp/tmx2tm.sh` (Termux has no writable `/tmp`), and mention
  the `bash <(curl …)` one-liner that the README uses as the primary form.
- Make sure the header and the README agree on which form is primary.

### Task 13 — AGENTS.md numbering and a clean shellcheck

- Renumber the rules in AGENTS.md: there are two rule 8s and no rule 9
  (Color rule = 8, Unified status model = 9, Auto-commit = 10).
- Make `shellcheck tmx2tm.sh` print nothing. Rewrite the four SC2015
  `A && B || C` lines in `cleanup_stubs` (currently 1903, 1921, 1922, 1928)
  as explicit `if` statements. Do not add blanket disables.

### Task 14 — Code tidy-ups

- `show_menu` (around line 1114): `then        echo` is jammed onto the `if`
  line. Split it.
- `tui_checklist` `_tui_render` (around lines 765–773): fix the indentation of
  the extra-keys loop.
- `print_summary` uses `C_BLUE` for its section headings, which conflicts
  with the color rule. Use green (`C_OK`), since these are results.
  `C_BLUE` stays only for the TUI cursor row. Note that exception in
  AGENTS.md rule 8.
- Fix the stray indentation in the `while true` loop body of `show_menu`
  (the loop body is not indented relative to `while`).

### Task 15 — README typo

- Line 3: fix "instalation" → "installation". Leave "Termux 2 take many"
  exactly as it is (intentional wording).

---

## Robustness improvements

### Task S1 — Back up shell startup files before rewriting them

**Where:** every function that rewrites (not just appends to) `~/.bashrc` or
`~/.bash_profile`: `setup_starship_init` and `setup_neofetch_init`.
`ensure_bashrc_line` only appends, but route it through the backup too.

**Fix:**
- Add one helper, e.g. `rc_backup <file>`. Once per run per file, it copies
  the file to `<file>.tmx2tm.bak`, overwriting the previous run's backup.
  Track this in an associative array so it happens once per run.
- Add a second helper, e.g. `rc_rewrite <file> <filter-cmd…>`, that:
  - takes the backup, then writes the filtered content to a temp file;
  - checks the result with `bash -n`, and on failure leaves the original
    untouched and calls `warn`;
  - writes the content back in place (`cat tmp > file`), not with `mv`, so a
    symlinked dotfile stays a symlink and keeps its permissions.
- Print an `info` line naming the backup path the first time a file is
  backed up.
- Document the `.tmx2tm.bak` files in README.md (where they are and how to
  restore).
- Extend AGENTS.md rule 5: all rc-file rewrites must go through
  `rc_rewrite`.

**Acceptance:**
- A symlinked `~/.bashrc` is still a symlink after a run.
- A `.tmx2tm.bak` exists.
- A filter that would produce an unparsable file is refused, and the
  original is unchanged.

### Task S2 — Make `-y` (unattended) mode more forgiving

**Where:** the `die` calls inside the install stages: `install_pkg_tools`
(`pkg install` / `pkg reinstall`), `install_pip_tools`,
`install_shizuku_tools` (clone), `install_rish`, `install_core` and
`install_kilocode`.

**Fix:**
- Keep `die` for preconditions that make the whole run pointless:
  `require_termux`, `install_base_deps`, an unreadable restore archive.
- For individual tools, replace `die` with "record failure, `warn`,
  continue". Use the `RESULT` map from task 11 so the failure shows in the
  summary.
- For `pkg install` of several tools at once: if the batch fails, retry each
  package one by one, so one bad package doesn't block the rest. Record which
  ones failed.
- Respect dependencies: if `core` failed, mark `kilocode` as skipped with the
  reason "needs core" instead of attempting it. Likewise, warn on shizuku if
  `rust` failed.
- Exit code: 0 if everything selected succeeded or was skipped as current;
  non-zero (e.g. 2) if any tool failed. Document this in README.md (useful
  for scripted `-y` runs).

**Acceptance:** In a `-y` run where one pip install fails (simulate with a
bad package name), the other stages still run, the summary lists the
failure, and the exit code is non-zero.

---

## Finish checklist (for each PR)

- [ ] `bash -n tmx2tm.sh` passes
- [ ] `shellcheck tmx2tm.sh` prints nothing
- [ ] README.md updated for every user-visible change
- [ ] Version bumped in all three places (once per batch)
- [ ] AGENTS.md updated where a rule changed (tasks 5, 13, 14, S1)
- [ ] Manual smoke test on Termux: menu run, `-y` run, re-run (idempotent),
      `--help` via `bash <(cat tmx2tm.sh)`
- [ ] Delete this file (or mark tasks done) once all tasks are merged
