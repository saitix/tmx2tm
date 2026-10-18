# tmx2tm.sh

Termux 2 take many. A bundler for packages and 3rd party apps on a termux instalation / or a Fresh-install installer for a new Termux instance

![tmx2tm.sh v0.9 component menu](https://github.com/user-attachments/assets/fa3f3936-0690-47b5-b54f-cd259f3e4952)

## Overview

Single-file, dependency-light installer that bootstraps a fresh Termux with a
curated set of tools. Everything is plain bash; the only interactivity is a
built-in arrow-key TUI (no dialog/gum required). It is safe to re-run: each
stage is idempotent (already-installed tools are skipped or updated).

This script was assembled by inspecting an existing, working Termux setup and
copying the exact install steps each tool uses on this device. To recreate it
elsewhere, reproduce the stages below (sources are listed with each tool).


## Quick start

Run directly from GitHub in Termux's Bash (no clone needed):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/saitix/tmx2tm/main/tmx2tm.sh)
```

Bash's process substitution supplies the script separately from stdin, so
the interactive menu still works. Append flags after `)` (for example, `-y`
to install everything without the menu). Do NOT use `curl ... | bash`:
the menu needs stdin for keyboard input.

The shorter form streams the download into Bash: execution can start before
the download finishes, and a `curl` failure does not reliably make Bash fail.
For a download-first alternative that runs only after `curl` succeeds, use
Termux's writable `$TMPDIR` rather than `/tmp`:

```bash
curl -fsSL https://raw.githubusercontent.com/saitix/tmx2tm/main/tmx2tm.sh -o "$TMPDIR/tmx2tm.sh" && bash "$TMPDIR/tmx2tm.sh"
```

Unattended, using the download-first form (install everything, no menu):

```bash
curl -fsSL https://raw.githubusercontent.com/saitix/tmx2tm/main/tmx2tm.sh -o "$TMPDIR/tmx2tm.sh" && bash "$TMPDIR/tmx2tm.sh" -y
```

Or clone and run locally:

```bash
git clone https://github.com/saitix/tmx2tm.git
cd tmx2tm
bash tmx2tm.sh              # interactive menu (arrow keys)
bash tmx2tm.sh -y           # unattended: install everything
```

## What it installs

Base pkg dependencies (always):

```text
python termux-api git nodejs curl wget openssh nmap android-tools
root-repo ncurses-utils glow gh ripgrep jq unzip
```

Selectable components. The menu groups them under separator headers,
"3rd-party tools" then "pkg tools", each sorted alphabetically. The OPTION
toggles are listed last.

### 3rd-party tools

| Tag       | Description                              | Install method                        |
|-----------|------------------------------------------|---------------------------------------|
| copyparty | copyparty - HTTP file server             | `pip install --user -U copyparty`     |
| core      | core-termux - modular dev environment    | official `install.sh`                 |
| kilocode  | kilocode-cli - AI coding agent           | `core install ai --kilocode-cli`      |
| pydf      | pydf - python disk-free formatter        | `pip3 install pydf`                   |
| rish      | rish - Shizuku Remote Shell              | `rish_installer.sh` (upstream)        |
| shizuku   | termux-shizuku-tools - rish/Shizuku helpers | `git clone` + `setup.sh`           |
| ytdlp     | yt-dlp - YouTube downloader              | `pip install --user -U yt-dlp`        |

### pkg tools

| Tag        | Description                                         | Package(s)          |
|------------|-----------------------------------------------------|---------------------|
| bat        | bat - cat clone with syntax highlighting            | `bat`               |
| dig        | dig - DNS lookup                                    | `dnsutils`          |
| elinks     | elinks - text-mode web browser                      | `elinks`            |
| golang     | golang - Go toolchain; GOPATH/bin on PATH           | `golang`            |
| mc         | mc - Midnight Commander                             | `mc`                |
| neofetch   | neofetch - system info                              | `neofetch`          |
| ranger     | ranger - console file manager                       | `ranger`            |
| rust       | rust - Rust toolchain (jiter/pydantic-core)         | `rust binutils`     |
| shellcheck | shellcheck - shell script static analysis           | `shellcheck`        |
| sqlite     | sqlite - SQLite database CLI (sqlite3)              | `sqlite`            |
| ssh        | ssh - OpenSSH server + client (sshd on port 8022)   | `openssh`           |
| starship   | starship - cross-shell prompt (starship.rs)         | `starship`          |
| telnet     | telnet                                              | `inetutils`         |
| uv         | uv - Astral Python toolchain                        | `uv`                |
| zellij     | zellij - terminal multiplexer                       | `zellij`            |

When `golang` is selected, the installer also persists the Go workspace to
`~/.bashrc` (idempotently, via `ensure_bashrc_line`):

```bash
export GOPATH="$HOME/go"
export PATH="$GOPATH/bin:$PATH"
```

When `starship` is installed, the installer keeps its init snippet in sync in
**both** `~/.bash_profile` and `~/.bashrc` on every run (zellij sources
`~/.bashrc` for its panes even inside a login shell, so one file is not
enough). The snippet evals at most once per shell tree — `STARSHIP_START_TIME`
is set by starship's own init on first eval, so a second sourcing is a no-op
instead of a double-rendered prompt:

```bash
# Initialize Starship only once, if installed
if [ -z "$STARSHIP_START_TIME" ] && command -v starship >/dev/null 2>&1; then
    eval "$(starship init bash)"
fi
```

Legacy unguarded snippets are upgraded in place. If starship is not installed
(e.g. the user uninstalled it), the snippet is removed from both files so
shells stay clean. The sync only runs when the installer itself runs under
bash.

### Options (listed last, after the pkg tools)

| Toggle          | Effect                                                              |
|-----------------|---------------------------------------------------------------------|
| apt_upgrade     | apt update & upgrade before installing (recommended; on by default) |
| no_storage      | skip termux-setup-storage                                           |
| kilocode_native | kilocode: auto-pick the recommended native method (no prompt)       |

Upstream sources used by the git/core/rish stages:

- termux-shizuku-tools: <https://github.com/jecis-repos/termux-shizuku-tools.git>
- core-termux: <https://github.com/DevCoreXOfficial/core-termux>
  (installed via: `curl -fsSL .../main/install.sh | bash`)
- rish_installer: <https://github.com/merbah3266/rish_installer>
  (installed via: `rish_installer.sh`, see the rish notes below)

### rish stage notes (merbah3266/rish_installer, Bash edition)

- Downloads `rish_installer.sh` to a temp file and runs it in bash.
- Passes `--reinstall` when a rish already exists (`$PREFIX/bin/rish` or
  `~/rish`), so re-runs refresh it instead of stalling on a confirmation.
- Interactive session: the installer's own source menu is shown
  (offline extract from the installed Shizuku APK is recommended).
- Non-interactive session: runs with `--silent --source default`, i.e.
  extract from the installed Shizuku app, falling back to the latest
  RikkaApps/Shizuku GitHub release.
- Installs rish + `rish_shizuku.dex` into `$PREFIX/bin`, or `~/rish`
  fallback; runs after termux-shizuku-tools so this (extracted, patched)
  rish wins.
- `unzip` is installed up front; upstream also has a BusyBox fallback.
- Needs the Shizuku app running and this terminal authorized in it.

### termux-shizuku-tools setup.sh notes

- Its step [6/7] runs `pip install anthropic google-genai requests`.
  Neither jiter (anthropic) nor pydantic-core (google-genai/pydantic) has
  an Android wheel, so pip builds them from source and needs the rust
  toolchain; without it, pip's isolated build tries rustup, which has no
  `aarch64-unknown-linux-android` target, and the stage fails.
- Fix: the "rust" pkg tool (rust + binutils) is installed first, and it is
  auto-enabled whenever shizuku is selected. `setup.sh` is then run with
  `CARGO_BUILD_JOBS=1`, which avoids the Android "Text file busy" race when
  cargo executes freshly written build scripts (hit while building
  pydantic-core under parallel jobs).
- A `setup.sh` failure now warns instead of aborting, since the rish/env/
  symlink steps before the pip step have usually already succeeded.

## Menu keys (interactive TUI)

| Key         | Action                                              |
|-------------|-----------------------------------------------------|
| Up / Down (or k / j) | move the cursor                          |
| Space       | toggle the highlighted item                         |
| a           | toggle every item                                   |
| s           | save a kilocode backup (see below), stay in the menu |
| u           | update what is already installed (see below)        |
| p           | install prerequisites, then reload the menu (fresh Termux) |
| Enter       | confirm selection                                   |
| q           | quit / cancel                                       |

In the TUI the shortcut keys are rendered in bold white (Up, Down, Space, a,
s, u, p, Enter, q) next to their dim descriptions so they stand out.

The `p` key appears only when base prerequisites are missing (fresh Termux:
the status probes run degraded without `git`/`pip`/`tput`). It installs the
prerequisites (`apt update & upgrade` plus the base pkg dependencies) and
reloads the menu with full status colors and checks. The text fallback menu
offers the same `p` command.

Pkg-tool rows are colored by install state: **green** = installed and at the
latest version, **yellow** = installed but an update is available (suffixed
`[update+]`), default dim color = not installed. Installed rows also
carry an `[installed]` suffix. The legend under the menu explains the colors,
and the cursor row keeps its blue highlight so it stays visible. Colors are
re-probed after the `u` update action, so they refresh without leaving the
menu. "Latest" is read from the apt package index (`apt list --upgradable`),
so it reflects the last `apt update` — a stale index may show green for a
tool that has a newer version upstream.

3rd-party rows follow the same rules, plus **red** = the upstream source is
unreachable, archived, or gone (suffixed with the reason, e.g.
`[source unreachable]`, `[archived]`, `[not on PyPI]`). Red rows default to
unchecked — installing from a dead source cannot work — and stay skipped
with a warning even if ticked. A stale install symlink (link present, target
gone — e.g. `$PREFIX/bin/core` pointing into a deleted clone) is also red,
as `[link target missing]`; selecting it removes the stale link and runs the
official installer, which re-links correctly. Installed pip tools compare `pip show`
against `pip index versions`; the shizuku clone compares local HEAD with the
remote; core/kilocode/rish count as installed when their binaries exist. The
probes run in parallel in the background (about a second for all tools) with
a purple "please wait" notice while they run.

Before probing, the installer checks connectivity to the three source
families (GitHub, PyPI, and the configured apt mirror) and prints the result
(`Connectivity: github=1 pypi=1 pkg-mirror=1`). Red verdicts require the
corresponding source to be reachable: in airplane mode an unreachable repo
is "unknown", not "gone" — installed tools stay green, missing tools stay
dim — so offline never paints false reds.

At install time, green tools (already at the latest version) are not
reinstalled: in the menu they default to **unchecked**, so confirming without
touching them skips the pointless reinstall and the toggles stay consistent
with the colors. If you tick a green tool anyway, it is force-reinstalled at
install time (`pkg reinstall` for pkg tools, `pip --force-reinstall` /
installer rerun for 3rd-party tools). In non-menu runs (`-y` / no TTY)
everything is selected by default, so green tools are skipped there instead
of reinstalled. The skip list is printed, and if nothing needs installing the
install step is omitted entirely. For non-menu runs the status is probed at
the stages, after `apt update`, so "latest" is judged on a fresh index.

## Update (menu key 'u')

Refreshes tools without leaving the menu:

- pkg tools: a single `pkg update && pkg upgrade` upgrades them all, so
  their individual toggles do not matter.
- 3rd-party tools: each one toggled on is updated only if it is already
  installed (missing ones are skipped):

| Tool      | Update command                                          |
|-----------|---------------------------------------------------------|
| copyparty | `pip install --user -U copyparty`                       |
| ytdlp     | `pip install --user -U yt-dlp`                          |
| pydf      | `pip3 install -U pydf`                                  |
| shizuku   | `git pull` + `setup.sh` (`CARGO_BUILD_JOBS=1`)          |
| rish      | `rish_installer.sh --reinstall --silent --source default` |
| core      | `core update core`                                      |
| kilocode  | `core update ai --kilocode-cli`                         |

The action uses the menu's current toggles, prints its output, then returns to
the menu (press 'u' again to re-run, 'q' to leave). It never installs a tool
that is not already present.

Because the action's output is captured and shown only when it finishes, a
purple "working, please wait" line appears immediately when 's' or 'u' is
pressed. The same notice is printed when the install flow starts, so a slow
download or source build is never mistaken for a frozen menu.

## Command-line options

| Option                  | Effect                                                     |
|-------------------------|------------------------------------------------------------|
| `-y`, `--yes`, `--no-menu` | skip the menu and install all components                |
| `--menu`                | force the menu even when other flags are present           |
| `--no-storage`          | skip the termux-setup-storage permission prompt            |
| `--no-apt-upgrade`      | skip the apt update & upgrade + mirror check stage         |
| `--kilocode-native`     | kilocode: auto-pick the recommended glibc method           |
| `--save-kilo[=PATH]`    | back up current Kilo settings + tokens, then exit (default: `~/.kilo-backup.tar.gz`) |
| `--restore-kilo[=PATH]` | restore that backup, then continue installing              |
| `-V`, `--version`       | print the script version and exit                          |
| `-h`, `--help`          | print the header/usage block                               |

## Repository / apt upgrade stage

Before any pkg install the installer (unless `--no-apt-upgrade` / the option is
turned off) makes the repositories usable and refreshes them:

1. If no mirror has been chosen yet (no
   `$PREFIX/etc/termux/chosen_mirrors` symlink), it runs `termux-change-repo`
   so you can pick a group. Unattended runs (no TTY) instead link the
   bundled default mirror. Without a wired repo the pkg stages fail at curl.
2. Runs `apt update && apt upgrade -y` so package indexes are current and an
   older base image is fully upgraded before the tools are installed.

The menu toggle "apt update & upgrade before installing" is on by default.

## Kilo / kilocode settings + tokens

The kilocode-cli stores its state under:

```text
~/.config/kilo/kilo.jsonc          settings / permissions
~/.local/share/kilo/auth.json      login tokens (kilo.access/refresh/expires)
~/.local/state/kilo/model.json     selected model
```

(`kilo-rc.db` = session history, `models.json` = cache; both are ignored.)

"Save backup" (menu key 's', or `--save-kilo`) tars those three files into a
chmod-600 archive so the installer itself never contains live credentials.
The 's' menu key always writes to the default path (`~/.kilo-backup.tar.gz`);
a custom path applies only to `--save-kilo`/`--restore-kilo`. "Restore"
(`--restore-kilo`) first validates that the archive contains only those three
members, then extracts them into `$HOME` and re-applies 600 perms; a wrong or
hostile archive is refused. If both `--save-kilo` and `--restore-kilo` are
given, the backup runs and the restore is skipped.

> [!CAUTION]
> The archive holds live login tokens. Keep it private, do not commit
> it, and move it to trusted storage (e.g. `/sdcard` or an encrypted location)
> when carrying it to a new device.

## Typical workflows

One-time on the current device, to capture your Kilo login:

```bash
bash tmx2tm.sh --save-kilo=/sdcard/kilo-backup.tar.gz
```

On the new device (restore, then install everything in one go):

```bash
bash tmx2tm.sh --restore-kilo=/sdcard/kilo-backup.tar.gz -y
```

Full unattended install of every tool:

```bash
bash tmx2tm.sh -y
```

## After install

```bash
source ~/.bashrc          # pick up ~/.local/bin and ~/bin
shizuku-status            # if termux-shizuku-tools was installed
rish                      # if the rish component was installed (needs Shizuku)
core list                 # browse core-termux modules
kilocode                  # AI agent (also symlinked as `kilo`)
```

### SSH server (if the `ssh` component was installed)

The component installs `openssh` (Termux sshd listens on **port 8022**).
`openssh` stays in the base dependencies too, since git and other stages need
the client — deselecting `ssh` in the menu only skips the verification hint.

```bash
sshd                      # start the server
ssh -p 8022 <user>@<device-ip>   # connect from another machine
pkill sshd                # stop the server
```
**Version: 0.9.** The version is defined once as `$SCRIPT_VERSION` in the
config block, echoed by `-V`/`--version`, shown in the menu title and the
final summary, and mirrored in the script file header (`Version: 0.9`).
Bump all of them together if/when changing the script.

## Notes / limitations

- Termux/Android only; requires `$PREFIX` (the script aborts otherwise).
- Targets aarch64 (all downloads/pkgs are the arm64 Termux builds).
- The TUI truncates lines to the terminal width, so it renders correctly on
  very narrow screens (e.g. a folded phone). If the terminal is too short
  to fit the whole checklist, a plain numbered text menu is shown instead
  (same items and defaults; type numbers to toggle, `a` for all, `s`/`u`/`p`
  for backup/update/prerequisites, `r` for zoom-out-and-reload, Enter to
  confirm, `q` to quit). The menu always comes first — nothing is installed
  before you confirm a selection. If the fallback appears only because the
  terminal is short, zoom out or rotate to landscape and press `r`: the menu
  rebuilds with fresh probes and the full TUI opens when it fits again.
- On a fresh Termux without `git`/`pip` yet, the status probes degrade to
  presence-only verdicts (installed = green, missing = dim, never red);
  full version/source checks activate once the base dependencies are in.
- `apt update` / `apt upgrade` / `pkg install` may print warnings; these are
  non-fatal (the installer warns and keeps going).
- The "rust" pkg tool (rust + binutils) is large (~640 MB installed). It is
  needed because shizuku's `setup.sh` compiles jiter and pydantic-core from
  source (no Android wheels); building them takes several minutes on-device.
- Re-running is safe; edits you make to `~/.bashrc` are only appended once.
