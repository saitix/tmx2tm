# install-termux-tools.sh

Fresh-install installer for a new Termux instance.

**Version: 0.6.** The version is defined once as `$SCRIPT_VERSION` in the
config block, echoed by `-V`/`--version`, shown in the menu title and the
final summary, and mirrored in the script file header (`Version: 0.6`).
Bump all of them together when changing the script.

## Overview

Single-file, dependency-light installer that bootstraps a fresh Termux with a
curated set of tools. Everything is plain bash; the only interactivity is a
built-in arrow-key TUI (no dialog/gum required). It is safe to re-run: each
stage is idempotent (already-installed tools are skipped or updated).

This script was assembled by inspecting an existing, working Termux setup and
copying the exact install steps each tool uses on this device. To recreate it
elsewhere, reproduce the stages below (sources are listed with each tool).

## Quick start

```bash
chmod +x xpl-install-termux-tools.sh
bash xpl-install-termux-tools.sh              # interactive menu (arrow keys)
bash xpl-install-termux-tools.sh -y           # unattended: install everything
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
| telnet     | telnet                                              | `inetutils`         |
| uv         | uv - Astral Python toolchain                        | `uv`                |
| zellij     | zellij - terminal multiplexer                       | `zellij`            |

When `golang` is selected, the installer also persists the Go workspace to
`~/.bashrc` (idempotently, via `ensure_bashrc_line`):

```bash
export GOPATH="$HOME/go"
export PATH="$GOPATH/bin:$PATH"
```

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
| Enter       | confirm selection                                   |
| q           | quit / cancel                                       |

In the TUI the shortcut keys are rendered in bold white (Up, Down, Space, a,
s, u, Enter, q) next to their dim descriptions so they stand out.

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
bash xpl-install-termux-tools.sh --save-kilo=/sdcard/kilo-backup.tar.gz
```

On the new device (restore, then install everything in one go):

```bash
bash xpl-install-termux-tools.sh --restore-kilo=/sdcard/kilo-backup.tar.gz -y
```

Full unattended install of every tool:

```bash
bash xpl-install-termux-tools.sh -y
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

## Notes / limitations

- Termux/Android only; requires `$PREFIX` (the script aborts otherwise).
- Targets aarch64 (all downloads/pkgs are the arm64 Termux builds).
- The TUI truncates lines to the terminal width, so it renders correctly on
  very narrow screens (e.g. a folded phone). If the terminal is too short
  to fit the whole checklist, the menu is skipped and every component is
  installed (the cursor-up redraw needs one line per menu row).
- `apt update` / `apt upgrade` / `pkg install` may print warnings; these are
  non-fatal (the installer warns and keeps going).
- The "rust" pkg tool (rust + binutils) is large (~640 MB installed). It is
  needed because shizuku's `setup.sh` compiles jiter and pydantic-core from
  source (no Android wheels); building them takes several minutes on-device.
- Re-running is safe; edits you make to `~/.bashrc` are only appended once.
