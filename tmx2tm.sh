#!/data/data/com.termux/files/usr/bin/bash
#
# tmx2tm.sh
# Fresh-install installer for a new Termux instance.
#
# Run directly from git (downloads the script to a temp file, then runs it
# with your own shell, so all flags work and stdin stays usable):
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/saitix/tmx2tm/main/tmx2tm.sh)
#   curl -fsSL https://raw.githubusercontent.com/saitix/tmx2tm/main/tmx2tm.sh -o "$TMPDIR/tmx2tm.sh" && bash "$TMPDIR/tmx2tm.sh"
#   curl -fsSL https://raw.githubusercontent.com/saitix/tmx2tm/main/tmx2tm.sh -o "$TMPDIR/tmx2tm.sh" && bash "$TMPDIR/tmx2tm.sh" -y
#
# (Do NOT pipe curl into bash: the script reads stdin for its interactive
# menu, so `curl ... | bash` would break the TUI.)
# (Termux has no writable /tmp: use "$TMPDIR" for the download-first form.)
#
# Version: 0.9
#
# Installs (selectable via a built-in arrow-key TUI, or non-interactive with -y).
# Components are grouped and sorted alphabetically, mirroring the menu order:
#
#   3rd-party tools:
#     copyparty              (HTTP file server, pip --user)
#     core / core-termux     (official install.sh)
#     kilocode-cli           (via: core install ai --kilocode-cli)
#     pydf                   (python disk-free formatter, pip3)
#     rish                   (Shizuku Remote Shell, via rish_installer)
#     termux-shizuku-tools   (git clone + setup.sh)
#     yt-dlp                 (YouTube downloader, pip --user)
#
#   pkg tools:
#     bat                    (cat clone with syntax highlighting)
#     dig                    (DNS lookup, from dnsutils)
#     elinks                 (text-mode web browser)
#     golang                 (Go toolchain; adds $GOPATH/bin to PATH in ~/.bashrc)
#     mc                     (Midnight Commander file manager)
#     neofetch               (system info)
#     ranger                 (console file manager)
#     rust                   (Rust toolchain; builds jiter/pydantic-core for shizuku)
#     ShellCheck             (shell script static analysis)
#     sqlite                 (SQLite database CLI, sqlite3)
#     ssh                    (OpenSSH server/client; sshd on port 8022)
#     starship               (cross-shell prompt, starship.rs)
#     telnet                 (from inetutils)
#     uv                     (Astral Python toolchain)
#     zellij                 (terminal multiplexer)
#
# Before the pkg stages it runs apt update & upgrade - selecting a repository
# mirror via termux-change-repo first if none is set - so the installers work.
# Also installs all required pkg dependencies up front.
# The menu is pure bash (no dialog/gum dependency); it needs only a TTY.
# In the menu, 's' saves a Kilo backup and 'u' updates installed tools in place.
#
# Usage:
#   bash tmx2tm.sh                 # interactive arrow-key menu
#   bash tmx2tm.sh -y              # non-interactive: install everything
#   bash tmx2tm.sh --no-storage    # skip termux-setup-storage prompt
#   bash tmx2tm.sh --no-apt-upgrade    # skip the apt update/upgrade + repo check
#   bash tmx2tm.sh --cleanup           # remove install stubs + caches after installing
#   bash tmx2tm.sh --kilocode-native   # kilocode: auto-pick recommended glibc method
#   bash tmx2tm.sh --menu          # force the menu even next to other flags
#   bash tmx2tm.sh --save-kilo[=PATH]      # back up current Kilo settings + tokens (default ~/.kilo-backup.tar.gz)
#   bash tmx2tm.sh --restore-kilo[=PATH]   # restore Kilo settings, then install
#   bash tmx2tm.sh -V              # print the version
#   bash tmx2tm.sh --help
#
# Kilo/kilocode settings (~/.config/kilo/kilo.jsonc), login tokens
# (~/.local/share/kilo/auth.json) and model choice (~/.local/state/kilo/model.json)
# are stored in a protected chmod-600 archive, never embedded in this script.
#
# Target: Termux on Android (aarch64).

set -uo pipefail

# ---------------------------------------------------------------- output ----
C_RESET=$'\e[0m'
C_BLUE=$'\e[38;5;39m'
C_DIM=$'\e[38;5;244m'
C_OK=$'\e[38;5;42m'
C_WARN=$'\e[38;5;213m'
C_HL=$'\e[38;5;213m'
C_KEY=$'\e[1;37m'   # bold white, used for shortcut keys
C_ERR=$'\e[1;31m'
C_PURPLE=$'\e[38;5;135m'   # "working / please wait" notices
C_YELLOW=$'\e[38;5;220m'   # pkg tool installed but upgradable (menu status)
C_CYAN=$'\e[38;5;51m'      # rc-file sync result header (sync_step)

step() { printf '\n%s==>%s %s%s%s\n' "$C_PURPLE" "$C_RESET" "$C_HL" "$1" "$C_RESET"; }
announce() { printf '\n%s%s%s\n' "$C_PURPLE" "$1" "$C_RESET"; }
info() { printf '    %s%s%s\n' "$C_DIM" "$1" "$C_RESET"; }
# In-progress sub-status (indented like info, but purple per the color rule:
# every displayed action or status that shows something in progress is purple;
# static notices stay dim, results stay green/yellow/red).
progress() { printf '    %s%s%s\n' "$C_PURPLE" "$1" "$C_RESET"; }
ok()   { printf '    %s[ok]%s %s\n' "$C_OK" "$C_RESET" "$1"; }
warn() { printf '    %s[!]%s %s\n' "$C_WARN" "$C_RESET" "$1"; }
die()  { printf '\n%s[ERROR]%s %s\n' "$C_ERR" "$C_RESET" "$1" >&2; exit 1; }
done_step() { printf '\n%s==>%s %s%s%s\n' "$C_OK" "$C_RESET" "$C_OK" "$1" "$C_RESET"; }
# Cyan variant reserved for the rc-file-sync result header (the one exception
# next to done_step; see AGENTS.md rule 8).
sync_step() { printf '\n%s==>%s %s%s%s\n' "$C_CYAN" "$C_RESET" "$C_CYAN" "$1" "$C_RESET"; }

# Non-interactive pkg/apt wrapper: every install/upgrade/reinstall goes
# through here so dpkg can never stop an unattended run at a conffile prompt.
pkg_noninteractive() {
    DEBIAN_FRONTEND=noninteractive "$@" -o Dpkg::Options::="--force-confold"
}

# Temp registry + exit trap: every mktemp path registers here so errors never
# leave temp dirs behind or a hidden cursor. cleanup_temps runs on EXIT only;
# INT/TERM handlers below exit with the conventional codes so Ctrl-C actually
# stops the script (a trap on INT that does not exit would let the script
# carry on). Cleanup runs only in the main shell (BASHPID check) so
# background probe jobs that inherit the trap do not wipe paths out from
# under each other.
declare -a TEMP_PATHS=()
MAIN_PID=$$
# Set to 1 by the rc-file syncs when they add/remove a snippet; main uses it
# to print the post-install marker only when something actually changed.
RC_CHANGED=0
register_temp() { TEMP_PATHS+=("$1"); }
# shellcheck disable=SC2329  # invoked via trap
cleanup_temps() {
    [ "${BASHPID:-$$}" = "$MAIN_PID" ] || return 0
    local p
    for p in "${TEMP_PATHS[@]}"; do [ -e "$p" ] && rm -rf "$p" 2>/dev/null; done
    tput cnorm 2>/dev/null || true
    printf '%s' "$C_RESET"
}
# shellcheck disable=SC2329  # invoked via trap
on_int() {
    [ "${BASHPID:-$$}" = "$MAIN_PID" ] || exit 130
    printf '\n  %sCancelled.%s\n' "$C_DIM" "$C_RESET"
    exit 130
}
# shellcheck disable=SC2329  # invoked via trap
on_term() {
    [ "${BASHPID:-$$}" = "$MAIN_PID" ] || exit 143
    exit 143
}
trap cleanup_temps EXIT
trap on_int INT
trap on_term TERM

# ---------------------------------------------------------------- config ----
SCRIPT_VERSION="0.9"
REPO_SHIZUKU="https://github.com/jecis-repos/termux-shizuku-tools.git"
REPO_CORE_INSTALL="https://raw.githubusercontent.com/DevCoreXOfficial/core-termux/main/install.sh"
REPO_RISH_INSTALL="https://raw.githubusercontent.com/merbah3266/rish_installer/main/rish_installer.sh"

# Network timeouts (seconds): every network call uses one of these — never a
# literal. Probes run in parallel, so the worst-case menu wait is bounded by
# the formula: NET_CHECK_TIMEOUT + max(GIT_PROBE_TIMEOUT + GH_API_TIMEOUT,
# PIP_INDEX_TIMEOUT + PIP_NET_TIMEOUT) — with today's values 10 + max(45, 55)
# = 65 s — not the sum of all probes.
NET_CHECK_TIMEOUT=10    # check_connectivity curl --max-time
NET_CONNECT_TIMEOUT=10  # every curl --connect-timeout
GIT_PROBE_TIMEOUT=30    # timeout around git ls-remote (both call sites)
GH_API_TIMEOUT=15       # GitHub API archived check --max-time
PIP_INDEX_TIMEOUT=40    # outer timeout around pip index versions
PIP_NET_TIMEOUT=20      # pip's own --timeout
PYPI_PROBE_TIMEOUT=15   # curl to pypi.org/simple/<pkg>/ --max-time
DOWNLOAD_TIMEOUT=120    # installer downloads (rish, core) --max-time

# Broken reason for a dangling install symlink (link present, target gone).
# Special-cased in tp_gate: unlike a dead upstream, the fix is local —
# remove the link and rerun the installer — so the install stage proceeds.
TP_WHY_DANGLING="link target missing"

# Maximum number of BODY lines between the neofetch start/end markers for the
# block to count as ours; beyond this the end marker is assumed to belong to
# something else and the file is left untouched.
NEOFETCH_BLOCK_CAP=20

SHIZUKU_DIR="$HOME/termux-shizuku-tools"
BASHRC="$HOME/.bashrc"
BASH_PROFILE="$HOME/.bash_profile"

# pkg dependencies shared by the complex tools (always installed).
BASE_PKG_DEPS=(
    python python-pip termux-api
    git nodejs curl wget openssh nmap android-tools root-repo
    ncurses-utils glow gh ripgrep jq
    unzip                       # rish APK extraction (upstream has a BusyBox fallback)
)

# Selectable components: 3rd-party tools, then pkg tools. Each group is
# alphabetical. The menu renders a separator header before each group.
THIRD_PARTY_COMPONENTS=(copyparty core kilocode pydf rish shizuku ytdlp)
PKG_TOOL_COMPONENTS=(bat dig elinks golang mc neofetch ranger rust shellcheck sqlite ssh starship telnet uv zellij)
ALL_COMPONENTS=("${THIRD_PARTY_COMPONENTS[@]}" "${PKG_TOOL_COMPONENTS[@]}")

# Components that are simple pkg packages -> pkg name(s). A value may list more
# than one package (space separated); all of them are installed for the entry.
declare -A PKG_COMPONENT=(
    [uv]=uv
    [bat]=bat
    [zellij]=zellij
    [neofetch]=neofetch
    [mc]=mc
    [dig]=dnsutils
    [telnet]=inetutils
    [shellcheck]=shellcheck
    [elinks]=elinks
    [golang]=golang
    [ranger]=ranger
    [sqlite]=sqlite
    [ssh]=openssh
    [starship]=starship
    [rust]="rust binutils"      # toolchain + ar/ld, needed to build Rust extensions
)

# Command used to verify a pkg-tool component is really present (defaults to the
# component tag). rust installs rustc/cargo, not a `rust` command; sqlite
# installs the sqlite3 CLI; golang installs the `go` command; ssh verifies the
# `sshd` server binary (the point of the entry), not the `ssh` client.
declare -A PKG_COMPONENT_CMD=(
    [rust]=rustc
    [sqlite]=sqlite3
    [golang]=go
    [ssh]=sshd
)

declare -A COMP_DESC=(
    # 3rd-party tools
    [copyparty]="copyparty - HTTP file server (pip)"
    [core]="core-termux - modular dev environment"
    [kilocode]="kilocode-cli - AI coding agent (via core)"
    [pydf]="pydf - python disk-free formatter (pip3)"
    [rish]="rish - Shizuku Remote Shell (rish_installer)"
    [shizuku]="termux-shizuku-tools - rish/Shizuku helpers (git)"
    [ytdlp]="yt-dlp - YouTube downloader (pip)"
    # pkg tools
    [bat]="bat - cat clone with syntax highlighting (pkg)"
    [dig]="dig - DNS lookup (dnsutils)"
    [elinks]="elinks - text-mode web browser (pkg)"
    [golang]="golang - Go toolchain (pkg; adds \$GOPATH/bin to PATH)"
    [mc]="mc - Midnight Commander (pkg)"
    [neofetch]="neofetch - system info (pkg)"
    [ranger]="ranger - console file manager (pkg)"
    [rust]="rust - Rust toolchain (builds jiter/pydantic-core for shizuku)"
    [shellcheck]="shellcheck - shell script static analysis (pkg)"
    [sqlite]="sqlite - SQLite database CLI (sqlite3)"
    [ssh]="ssh - OpenSSH server + client (pkg; sshd on port 8022)"
    [starship]="starship - cross-shell prompt (pkg)"
    [telnet]="telnet - inetutils"
    [uv]="uv - Astral Python toolchain (pkg)"
    [zellij]="zellij - terminal multiplexer (pkg)"
)
declare -A COMP_HINT=(
    [copyparty]="copyparty -h"
    [core]="core"
    [kilocode]="kilocode / kilo"
    [pydf]="pydf"
    [rish]="rish  (needs the Shizuku app running)"
    [shizuku]="$SHIZUKU_DIR (see ~/.termux_shizuku_help)"
    [ytdlp]="yt-dlp <url>"
    [bat]="bat <file>"
    [dig]="dig example.com"
    [elinks]="elinks <url>"
    [golang]="go version"
    [mc]="mc"
    [neofetch]="neofetch"
    [ranger]="ranger"
    [rust]="rustc --version"
    [shellcheck]="shellcheck --version"
    [sqlite]="sqlite3 my.db"
    [ssh]="sshd (port 8022); ssh -p 8022 <host>"
    [starship]="starship --version"
    [telnet]="telnet <host> <port>"
    [uv]="uv --version"
    [zellij]="zellij"
)

# Runtime state / options.
declare -A SELECTED=()
for _c in "${ALL_COMPONENTS[@]}"; do SELECTED[$_c]=1; done
# Set to 1 when the interactive menu actually ran and the user confirmed a
# selection. install_pkg_tools uses it to tell an explicit menu tick of a
# green (current) tool — forced reinstall — apart from -y / fallback runs
# where everything is selected by default and green tools must be skipped.
MENU_CONFIRMED=0

# Kilo / kilocode config locations (the kilocode-cli uses these same paths).
KILO_CONFIG_DIR="$HOME/.config/kilo"
KILO_DATA_DIR="$HOME/.local/share/kilo"
KILO_STATE_DIR="$HOME/.local/state/kilo"
DEFAULT_KILO_BACKUP="$HOME/.kilo-backup.tar.gz"

SETUP_STORAGE=1
KILOCODE_NATIVE=0
APT_UPGRADE=1     # run apt update & upgrade (and pick a mirror) before pkg stages
CLEANUP=0         # remove install stubs + caches after installing
SHOW_MENU=auto   # auto | force | never
UNATTENDED=0      # 1 with -y/--yes/--no-menu: never prompt, pick defaults
SAVE_KILO=0
RESTORE_KILO=0
KILO_SAVE_PATH="$DEFAULT_KILO_BACKUP"
KILO_RESTORE_PATH="$DEFAULT_KILO_BACKUP"

# True when this run may show prompts: not -y and stdin (and stdout, where the
# original checks had it) is a TTY. Used by the mirror picker, rish and
# kilocode so `-y` in a terminal still runs fully unattended.
is_interactive() {
    [ "$UNATTENDED" -eq 0 ] && [ -t 0 ]
}
is_interactive_out() {
    [ "$UNATTENDED" -eq 0 ] && [ -t 0 ] && [ -t 1 ]
}

# usage() is the source of truth for --help (works under bash <(...) where
# $0 is an unreadable pipe). Keep the header comment's Usage list in sync.
usage() {
    cat <<'USAGE'
tmx2tm.sh - Fresh-install installer for a new Termux instance.

Run directly from git:
  bash <(curl -fsSL https://raw.githubusercontent.com/saitix/tmx2tm/main/tmx2tm.sh)
  curl -fsSL https://raw.githubusercontent.com/saitix/tmx2tm/main/tmx2tm.sh -o "$TMPDIR/tmx2tm.sh" && bash "$TMPDIR/tmx2tm.sh"

Usage:
  bash tmx2tm.sh                 # interactive arrow-key menu
  bash tmx2tm.sh -y              # non-interactive: install everything
  bash tmx2tm.sh --no-storage    # skip termux-setup-storage prompt
  bash tmx2tm.sh --no-apt-upgrade    # skip the apt update/upgrade + repo check
  bash tmx2tm.sh --cleanup           # remove install stubs + caches after installing
  bash tmx2tm.sh --kilocode-native   # kilocode: auto-pick recommended glibc method
  bash tmx2tm.sh --menu          # force the menu even next to other flags
  bash tmx2tm.sh --save-kilo[=PATH]      # back up current Kilo settings + tokens (default ~/.kilo-backup.tar.gz)
  bash tmx2tm.sh --restore-kilo[=PATH]   # restore Kilo settings, then install
  bash tmx2tm.sh -V              # print the version
  bash tmx2tm.sh --help
USAGE
}

for arg in "$@"; do
    case "$arg" in
        --no-storage)       SETUP_STORAGE=0 ;;
        --no-apt-upgrade)   APT_UPGRADE=0 ;;
        --cleanup)            CLEANUP=1 ;;
        --kilocode-native)  KILOCODE_NATIVE=1 ;;
        --menu)             SHOW_MENU=force ;;
        -y|--yes|--no-menu) SHOW_MENU=never; UNATTENDED=1 ;;
        --save-kilo)        SAVE_KILO=1 ;;
        --save-kilo=*)      SAVE_KILO=1; KILO_SAVE_PATH="${arg#*=}" ;;
        --restore-kilo)     RESTORE_KILO=1 ;;
        --restore-kilo=*)   RESTORE_KILO=1; KILO_RESTORE_PATH="${arg#*=}" ;;
        -h|--help)
            usage
            exit 0
            ;;
        -V|--version)
            printf 'tmx2tm.sh v%s\n' "$SCRIPT_VERSION"
            exit 0
            ;;
        *) die "Unknown option: $arg" ;;
    esac
done

# --------------------------------------------------------------- helpers ----
require_termux() {
    if [ -z "${PREFIX:-}" ] || [ ! -d "$PREFIX" ]; then
        die "This script must be run inside Termux (PREFIX is not set)."
    fi
}

is_selected() { [ "${SELECTED[$1]:-0}" = "1" ]; }

# ------------------------------------------------ pkg status for menu -------
# Probe installed/upgradable state for the pkg-tool components so the menu can
# color them (see the unified rules under "menu (TUI)"). Results are cached in
# PKG_STATUS (tag -> state); refresh_menu_status recomputes after the 'u'
# update action so colors stay accurate if the menu is redrawn.
#
# "Upgradable" is read from the apt package index via `apt list --upgradable`.
# That reflects the last `apt update`: a stale index may report "latest" for a
# tool that has a newer version upstream. The menu legend says so.
declare -A PKG_STATUS=()

probe_pkg_status() {
    PKG_STATUS=()
    local upgradable c p pkgs missing=0 outdated=0
    upgradable=" $({ apt list --upgradable 2>/dev/null || true; } | awk -F/ 'NR>1 && $1!="" {print $1}') "
    for c in "${PKG_TOOL_COMPONENTS[@]}"; do
        missing=0; outdated=0
        for p in ${PKG_COMPONENT[$c]}; do
            if ! dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q "ok installed"; then
                missing=1
                break
            fi
            case "$upgradable" in
                *" $p "*) outdated=1 ;;
            esac
        done
        if [ "$missing" -eq 1 ]; then
            PKG_STATUS[$c]="missing"
        elif [ "$outdated" -eq 1 ]; then
            PKG_STATUS[$c]="outdated"
        else
            PKG_STATUS[$c]="current"
        fi
    done
}

# Status suffix appended to a component's menu description.
# Unified rule for pkg and 3rd-party rows: [installed] / [update+] / [reason];
# empty for missing tools. Broken (red) rows carry the reason: e.g.
# [source unreachable], [archived], [not on PyPI].
comp_suffix() {
    local st why
    st="$(comp_status "$1")"
    case "$st" in
        current)  printf ' [installed]' ;;
        outdated) printf ' [update+]' ;;
        broken)
            why="$(comp_broken_why "$1")"
            printf ' [%s]' "$why" ;;
        *)        printf '' ;;
    esac
}

# Unified status lookup for any component tag: current|outdated|missing|broken.
# pkg tags read PKG_STATUS, 3rd-party tags read TP_STATUS; unknown tags and
# empty maps fall back to missing.
comp_status() {
    case " ${PKG_TOOL_COMPONENTS[*]} " in
        *" $1 "*) printf '%s' "${PKG_STATUS[$1]:-missing}" ;;
        *)        printf '%s' "${TP_STATUS[$1]:-missing}" ;;
    esac
}

# Broken-reason accessor (3rd-party rows); use this instead of reading
# TP_BROKEN_WHY outside the probe functions.
comp_broken_why() {
    printf '%s' "${TP_BROKEN_WHY[$1]:-source gone}"
}

# Row color for any component tag by probe state: green = installed+latest,
# yellow = installed+upgradable, red = broken source, default = not installed.
menu_item_color() {
    case "$(comp_status "$1")" in
        current)  printf '%s' "$C_OK" ;;
        outdated) printf '%s' "$C_YELLOW" ;;
        broken)   printf '%s' "$C_ERR" ;;
        *)        printf '' ;;
    esac
}

# Default menu toggle for any component tag. Green (nothing to do) and broken
# (nothing can be done — the source is dead) default to off; the user can
# still tick a green row to force a reinstall. Missing and yellow default on.
menu_default_state() {
    case "$(comp_status "$1")" in
        current|broken) printf 'off' ;;
        *)              printf 'on' ;;
    esac
}

# ------------------------------------- third-party status for menu -------
# Same state model as the pkg tools, plus "broken" (red): the component's
# upstream source is unreachable, archived, or gone. Probes run in parallel
# background jobs (one per tool) so the menu does not wait on slow networks;
# every network call uses one of the NET_*/GIT_*/PIP_* timeout variables and
# failures fall back to a safe verdict instead of hanging. Results land in
# TP_STATUS (tag -> state) with reasons in TP_BROKEN_WHY (tag -> e.g.
# "source unreachable").
declare -A TP_STATUS=()
declare -A TP_BROKEN_WHY=()

# Connectivity flags (1 = reachable, 0 = not), set by check_connectivity
# before any network probe runs. Red verdicts REQUIRE the corresponding source
# to be reachable: when offline, an unreachable repo is "unknown", not
# "gone" — installed tools fall back to current (green), missing tools to
# missing (dim). This keeps airplane mode from painting everything red.
# NET_PKG is informational only (shown in the connectivity line; useful when
# `apt update` later fails): the pkg probe can only read the local index, and
# a stale index already carries its documented caveat.
NET_GITHUB=0
NET_PYPI=0
NET_PKG=0

# Fast parallel reachability check for the three source families the probes
# depend on: github (git tools), PyPI (pip tools), and the configured apt
# mirror (pkg index freshness). Each curl uses NET_CHECK_TIMEOUT; the three
# run in parallel so the worst case is ~NET_CHECK_TIMEOUT, and offline fails
# fast (no route).
check_connectivity() {
    NET_GITHUB=0; NET_PYPI=0; NET_PKG=0
    local tmpnet mirror
    tmpnet=$(mktemp -d 2>/dev/null) || return 0
    register_temp "$tmpnet"
    ( curl -fsSL --max-time "$NET_CHECK_TIMEOUT" -o /dev/null https://github.com >/dev/null 2>&1 \
        && echo 1 >"$tmpnet/gh" || echo 0 >"$tmpnet/gh" ) &
    ( curl -fsSL --max-time "$NET_CHECK_TIMEOUT" -o /dev/null https://pypi.org/simple/ >/dev/null 2>&1 \
        && echo 1 >"$tmpnet/pypi" || echo 0 >"$tmpnet/pypi" ) &
    mirror=$(apt-cache policy 2>/dev/null | grep -o 'http[^ ]*' | head -1)
    ( [ -n "$mirror" ] && curl -fsSL --max-time "$NET_CHECK_TIMEOUT" -o /dev/null "$mirror" >/dev/null 2>&1 \
        && echo 1 >"$tmpnet/pkg" || echo 0 >"$tmpnet/pkg" ) &
    wait
    NET_GITHUB=$(cat "$tmpnet/gh" 2>/dev/null || echo 0)
    NET_PYPI=$(cat "$tmpnet/pypi" 2>/dev/null || echo 0)
    NET_PKG=$(cat "$tmpnet/pkg" 2>/dev/null || echo 0)
    rm -rf "$tmpnet"
    info "Connectivity: github=$NET_GITHUB pypi=$NET_PYPI pkg-mirror=$NET_PKG"
}

# Upstream git repo (owner/repo) for the tools fetched from git. Tools without
# an entry (pip packages, kilocode via core) skip the git reachability check.
declare -A TP_GIT_REPO=(
    [shizuku]="jecis-repos/termux-shizuku-tools"
    [core]="DevCoreXOfficial/core-termux"
    [rish]="merbah3266/rish_installer"
)

# pip package name per pip-based tool tag.
declare -A TP_PIP_NAME=(
    [copyparty]="copyparty"
    [ytdlp]="yt-dlp"
    [pydf]="pydf"
)

# Local presence check per 3rd-party tag. Mirrors what the install stages and
# the 'u' update action treat as "installed".
# True when $1 is a symlink whose target does not resolve (stale install
# link, e.g. $PREFIX/bin/core pointing into a deleted clone). command -v and
# -x both report "missing" for these, hiding the real cause — detect them
# explicitly so the menu can mark the row broken with an explainer instead.
dangling_link() {
    [ -L "$1" ] && [ ! -e "$1" ]
}

tp_installed() {
    case "$1" in
        copyparty) command -v copyparty >/dev/null 2>&1 || [ -x "$HOME/.local/bin/copyparty" ] ;;
        ytdlp)     command -v yt-dlp >/dev/null 2>&1 || [ -x "$HOME/.local/bin/yt-dlp" ] ;;
        pydf)      command -v pydf >/dev/null 2>&1 || [ -x "$HOME/.local/bin/pydf" ] ;;
        shizuku)   [ -d "$SHIZUKU_DIR/.git" ] ;;
        rish)      [ -e "$PREFIX/bin/rish" ] || [ -e "$HOME/rish" ] ;;
        core)      command -v core >/dev/null 2>&1 ;;
        kilocode)  command -v kilocode >/dev/null 2>&1 ;;
    esac
}

# Remote HEAD SHA for owner/repo via one ls-remote call; empty on failure.
# Kept separate from the archived check so shizuku's diff needs only ONE
# ls-remote (the shared state helper below reuses this result).
tp_git_remote_head() {
    GIT_TERMINAL_PROMPT=0 timeout "$GIT_PROBE_TIMEOUT" \
        git ls-remote "https://github.com/$1.git" HEAD 2>/dev/null | awk '{print $1}'
}

# Archived flag from the GitHub API; empty when the API is silent (rate
# limit, offline) — reachability already covered the offline case.
tp_git_archived() {
    local archived
    archived=$(curl -fsSL --max-time "$GH_API_TIMEOUT" --connect-timeout "$NET_CONNECT_TIMEOUT" "https://api.github.com/repos/$1" 2>/dev/null \
        | grep -o '"archived": *[a-z]*' | awk '{print $2}')
    [ "$archived" = "true" ] && echo archived
}

# Upstream git state for owner/repo: ok | unreachable | archived.
# Unreachable = `git ls-remote` failed (repo gone, network down, host down).
tp_git_repo_state() {
    local head
    head=$(tp_git_remote_head "$1")
    if [ -z "$head" ]; then
        echo unreachable
        return
    fi
    if [ -n "$(tp_git_archived "$1")" ]; then
        echo archived
    else
        echo ok
    fi
}

# Probe one pip-based tool. Installed version comes from `pip show`, latest
# from `pip index versions`. No pip yet (fresh Termux — pip arrives with the
# base deps AFTER the menu): presence-only verdict, never red.
# If the index cannot be read but PyPI itself is alive, the install is fine
# and the version is just unknown -> current. If PyPI has no such package at
# all -> broken (e.g. removed or renamed).
tp_probe_pip() {
    local tag="$1" pkg="${TP_PIP_NAME[$1]}"
    tp_installed "$tag" || { printf 'missing\n\n'; return; }
    if ! command -v pip >/dev/null 2>&1 && ! command -v pip3 >/dev/null 2>&1; then
        printf 'current\n\n'
        return
    fi
    local inst latest
    inst=$(pip show "$pkg" 2>/dev/null | awk '/^Version: /{print $2; exit}')
    latest=$(timeout "$PIP_INDEX_TIMEOUT" pip index versions --timeout "$PIP_NET_TIMEOUT" --retries 0 "$pkg" 2>/dev/null \
        | sed -n 's/^Available versions: //p' | cut -d, -f1 | tr -d ' ')
    if [ -n "$latest" ]; then
        if [ -n "$inst" ] && [ "$inst" = "$latest" ]; then
            printf 'current\n\n'
        else
            printf 'outdated\n\n'
        fi
        return
    fi
    # Index unreadable: only PyPI itself can tell "removed" from "offline".
    # No PyPI reachability -> unknown, not gone: installed stays current.
    if [ "$NET_PYPI" -eq 0 ]; then
        printf 'current\n\n'
        return
    fi
    if curl -fsSL --max-time "$PYPI_PROBE_TIMEOUT" --connect-timeout "$NET_CONNECT_TIMEOUT" "https://pypi.org/simple/$pkg/" >/dev/null 2>&1; then
        printf 'current\n\n'
    else
        printf 'broken\nnot on PyPI\n'
    fi
}

# Probe one git-based tool (shizuku, core, rish installer repo).
# Not installed: the source must be alive for an install to work — dead source
# means broken, but only when GitHub itself is reachable (offline verdicts
# would be false reds: missing stays missing). Installed: compare local HEAD
# with the remote (shizuku has a real clone); archived upstream always means
# broken per the red rule (the API call only runs when GitHub is reachable,
# so an archived verdict is trustworthy).
tp_probe_git() {
    local tag="$1" repo="${TP_GIT_REPO[$1]}"
    local state remote_head local_head
    # No git yet (fresh Termux — git arrives with the base deps AFTER the
    # menu): presence-only verdict, never red (source state unknown).
    if ! command -v git >/dev/null 2>&1; then
        tp_installed "$tag" && printf 'current\n\n' || printf 'missing\n\n'
        return
    fi
    if ! tp_installed "$tag"; then
        if [ "$NET_GITHUB" -eq 0 ]; then
            printf 'missing\n\n'
            return
        fi
        state="$(tp_git_repo_state "$repo")"
        case "$state" in
            ok)         printf 'missing\n\n' ;;
            archived)   printf 'broken\narchived\n' ;;
            *)          printf 'broken\nsource unreachable\n' ;;
        esac
        return
    fi
    if [ "$tag" = "shizuku" ]; then
        if [ "$NET_GITHUB" -eq 0 ]; then
            # Offline: cannot diff against the remote; the working clone
            # counts as current rather than broken.
            printf 'current\n\n'
            return
        fi
        remote_head=$(tp_git_remote_head "$repo")
        if [ -z "$remote_head" ]; then
            printf 'broken\nsource unreachable\n'
            return
        fi
        local_head=$(git -C "$SHIZUKU_DIR" rev-parse HEAD 2>/dev/null)
        # Reuse the single ls-remote above: only the archived check remains.
        if [ -n "$(tp_git_archived "$repo")" ]; then
            printf 'broken\narchived\n'
        elif [ -n "$local_head" ] && [ "$local_head" = "$remote_head" ]; then
            printf 'current\n\n'
        else
            printf 'outdated\n\n'
        fi
        return
    fi
    # core / rish: no local clone to diff; installed means working. Offline or
    # API-silent means current; only a reachable-but-archived upstream is red.
    if [ "$NET_GITHUB" -eq 0 ]; then
        printf 'current\n\n'
        return
    fi
    state="$(tp_git_repo_state "$repo")"
    case "$state" in
        archived)   printf 'broken\narchived\n' ;;
        unreachable) printf 'broken\nsource unreachable\n' ;;
        *)          printf 'current\n\n' ;;
    esac
}

# Probe one 3rd-party tool; prints state on line 1, broken reason on line 2.
# A dangling install symlink (link present, target gone) is broken regardless
# of network state — the local install itself is at fault, not the source.
probe_tp_one() {
    case "$1" in
        core)
            if dangling_link "$PREFIX/bin/core"; then
                printf 'broken\n%s\n' "$TP_WHY_DANGLING"
                return
            fi
            tp_probe_git "$1" ;;
        shizuku|rish) tp_probe_git "$1" ;;
        copyparty|ytdlp|pydf) tp_probe_pip "$1" ;;
        kilocode)
            # Installed via core, no own upstream to check: present = current.
            tp_installed kilocode && printf 'current\n\n' || printf 'missing\n\n' ;;
        *) printf 'missing\n\n' ;;
    esac
}

# Probe all 3rd-party tools in parallel background jobs. Runs check_connectivity
# first so offline verdicts stay honest (no false reds in airplane mode).
# Each job writes its two-line result to a temp file; this function waits for
# all of them, then fills TP_STATUS / TP_BROKEN_WHY. Slow networks are bounded
# by the named timeout variables (NET_*/GIT_*/PIP_*/PYPI_*/GH_*) in the probes.
probe_tp_status() {
    TP_STATUS=()
    TP_BROKEN_WHY=()
    local tmpdir c
    tmpdir=$(mktemp -d 2>/dev/null) || { warn "Cannot create temp dir for probe"; return 1; }
    register_temp "$tmpdir"
    for c in "${THIRD_PARTY_COMPONENTS[@]}"; do
        ( probe_tp_one "$c" >"$tmpdir/$c" 2>/dev/null ) &
    done
    wait
    local state why
    for c in "${THIRD_PARTY_COMPONENTS[@]}"; do
        if [ -f "$tmpdir/$c" ]; then
            { read -r state; read -r why || why=""; } <"$tmpdir/$c"
            TP_STATUS[$c]="${state:-missing}"
            [ -n "$why" ] && TP_BROKEN_WHY[$c]="$why"
        else
            TP_STATUS[$c]="missing"
        fi
    done
    rm -rf "$tmpdir"
}

# Probe once, reuse afterwards. Menu runs probe before opening; non-menu runs
# probe at the stages. Never re-probe blindly: the 'u' refresh calls the
# explicit probe functions.
ensure_tp_status() {
    [ "${#TP_STATUS[@]}" -gt 0 ] || probe_tp_status
}

# Per-tool outcome map for the summary (task 11) and forgiving -y mode (S2):
# RESULT[tag]="status|detail", status in installed|updated|skipped|failed|broken.
declare -A RESULT=()
record_result() { RESULT[$1]="$2|${3:-}"; }

# Gate for a 3rd-party install stage. Sets TP_FORCE (0/1). Returns 0 = proceed
# (fresh install, update, or forced reinstall of a green tool after an explicit
# menu tick), 1 = skip (green tool in a non-menu run, or broken source).
# Broken + selected never dies mid-run: warn and skip instead.
TP_FORCE=0
tp_gate() {
    local tag="$1" why
    TP_FORCE=0
    ensure_tp_status
    case "$(comp_status "$tag")" in
        current)
            if [ "$MENU_CONFIRMED" -eq 1 ]; then TP_FORCE=1; return 0; fi
            info "'$tag' already installed (latest), skipping"
            record_result "$tag" skipped "already installed (latest)"
            return 1 ;;
        broken)
            # A dangling install link is a LOCAL fault the install stage can
            # repair itself (remove the link, rerun the installer), so it
            # proceeds instead of skipping. Any other reason (archived,
            # unreachable) is a dead source: warn and skip.
            why="$(comp_broken_why "$tag")"
            if [ "$why" = "$TP_WHY_DANGLING" ]; then
                info "'$tag' has a stale link ($TP_WHY_DANGLING); it will be replaced"
                return 0
            fi
            warn "'$tag' skipped ($why)"
            record_result "$tag" broken "$why"
            return 1 ;;
        *) return 0 ;;
    esac
}

# Backup + rewrite helpers for shell startup files: rewriting must never
# corrupt the file or break symlinks. rc_backup snapshots once per run per
# file to <file>.tmx2tm.bak; rc_rewrite filters via a temp file, validates
# with bash -n, then writes back in place (cat >) so symlinks keep working.
declare -A RC_BACKED_UP=()
rc_backup() {
    local f="$1"
    [ -n "${RC_BACKED_UP[$f]:-}" ] && return 0
    if [ -e "$f" ]; then
        cp -p "$f" "$f.tmx2tm.bak" 2>/dev/null \
            && info "Backed up $f -> $f.tmx2tm.bak"
    fi
    RC_BACKED_UP[$f]=1
}
# rc_rewrite <file> <filter-function> [args...]: run filter reading the file
# on stdin and writing the new content on stdout. Refuses to touch the file
# when the filtered result fails bash -n.
rc_rewrite() {
    local f="$1"; shift
    rc_backup "$f"
    local tmp
    tmp=$(mktemp) || { warn "mktemp failed; leaving $f untouched"; return 1; }
    register_temp "$tmp"
    if "$@" <"$f" >"$tmp" 2>/dev/null; then
        if bash -n "$tmp" 2>/dev/null; then
            cat "$tmp" >"$f"
        else
            warn "Filtered $f failed syntax check; leaving original untouched"
            rm -f "$tmp"
            return 1
        fi
    else
        warn "Filter failed for $f; leaving original untouched"
        rm -f "$tmp"
        return 1
    fi
    rm -f "$tmp"
}
# Append a line to ~/.bashrc only if it is not already present. The backup
# is taken only when something will actually be appended, so no-op runs
# never overwrite the previous run's .tmx2tm.bak.
ensure_bashrc_line() {
    local line="$1"
    if ! grep -qxF "$line" "$BASHRC" 2>/dev/null; then
        rc_backup "$BASHRC"
        printf '\n%s\n' "$line" >> "$BASHRC"
        info "Added to ~/.bashrc: $line"
    fi
}

# --------------------------------------------------------- TUI (pure bash) ----
# Arrow-key multi-select checklist. No external dependencies.
#
# Usage: tui_checklist "<title>" <result_var> "tag|description|on|off" ...
#   - Up/Down (or k/j) move, Space toggles, 'a' toggles all, Enter confirms,
#     q cancels. Selected tags are written to <result_var> (space separated).
#
# Optional extra single-key actions: set the parallel arrays TUI_EXTRA_KEYS,
# TUI_EXTRA_DESCS, TUI_EXTRA_BUSY and TUI_EXTRA_FNS before calling. Each key runs
# its function below the block, then redraws the menu. The function is called
# with the currently toggled-on tags in the environment variable TUI_ON_TAGS.
# TUI_EXTRA_BUSY is an immediate "working" notice printed above the (captured)
# action output, so a slow action does not look like a frozen UI.
# TUI_ITEM_COLOR is an optional parallel array (one entry per item, separators
# get an empty entry): an ANSI color code applied to the item's text so callers
# can highlight entries (e.g. installed = green, upgradable = yellow).
# TUI_REFRESH_FN is an optional function name called after an extra action
# finishes, so the caller can refresh per-item state (like TUI_ITEM_COLOR)
# before the menu redraws.
# TUI_LEGEND, when non-empty, adds one status-legend line under the help lines
# (green = installed, yellow = update+, red = source gone).
# TUI_EXTRA_STYLE is an optional parallel array for the extra-key description
# lines: an ANSI style applied to the whole "key description" line instead of
# the default (bold-white key + dim description). Used to make one shortcut
# stand out (e.g. the prerequisites installer in bold white).
# TUI_EXTRA_STREAM is an optional parallel array: 1 = run the action live on
# the terminal (for long actions like update/prereqs), 0/empty = capture and
# print when done (for short actions like save). Streamed actions run in a
# subshell so their variable changes do not leak into the menu state.
# TUI_EXTRA_REFRESH is an optional parallel array: 1 = run TUI_REFRESH_FN
# after this action (only actions that change statuses, e.g. u/p; s = 0 so a
# save never triggers the silent re-probe).
# Refresh-hook contract (TUI_REFRESH_FN): the hook runs in the menu's scope
# and may read/write these tui_checklist locals: n, kinds, tags, descs,
# states. It may also modify TUI_EXTRA_* to add/drop shortcuts; after it
# returns, `extra` and `lines` are recomputed before the redraw.
TUI_EXTRA_KEYS=()
TUI_EXTRA_DESCS=()
TUI_EXTRA_BUSY=()
TUI_EXTRA_FNS=()
TUI_EXTRA_STYLE=()
TUI_EXTRA_STREAM=()
TUI_EXTRA_REFRESH=()
# TUI_ITEM_BULK is an optional parallel array (one entry per item, separators
# get an empty entry): 1 = the `a` bulk key may turn this row on. Component
# rows use menu_default_state (green/broken = 0, missing/yellow = 1) so bulk
# never force-reinstalls; option rows are always 1.
TUI_ITEM_BULK=()
TUI_ITEM_COLOR=()
TUI_REFRESH_FN=""
TUI_LEGEND=""

tui_checklist() {
    local title="$1" result_var="$2"
    shift 2

    local -a tags=() descs=() states=() kinds=()
    local e rest
    for e in "$@"; do
        if [ "${e%%|*}" = "sep" ]; then
            tags+=("")
            descs+=("${e#*|}")
            states+=("")
            kinds+=("sep")
        else
            tags+=("${e%%|*}")
            rest="${e#*|}"
            descs+=("${rest%%|*}")
            states+=("${rest##*|}")
            kinds+=("item")
        fi
    done

    local n=${#tags[@]}
    [ "$n" -gt 0 ] || { printf -v "$result_var" '%s' ""; return 0; }

    # Start on the first selectable (non-separator) entry.
    local cur=0
    while [ "$cur" -lt "$n" ] && [ "${kinds[$cur]}" = sep ]; do cur=$((cur + 1)); done
    if [ "$cur" -ge "$n" ]; then printf -v "$result_var" '%s' ""; return 0; fi
    local extra=${#TUI_EXTRA_KEYS[@]}
    local legend_lines=0 lines=0
    [ -n "${TUI_LEGEND:-}" ] && legend_lines=1
    lines=$((n + 3 + extra + legend_lines))   # title + items + 2 help lines (+ legend + one per extra key)
    local i

    # Terminal width. Truncate every rendered line to fit so that nothing
    # wraps: wrapping would make the block taller than $lines and break the
    # cursor-up redraw on narrow screens (e.g. a folded phone).
    local cols
    cols=$(tput cols 2>/dev/null) || cols=""
    case "$cols" in ''|*[!0-9]*) cols="${COLUMNS:-80}" ;; esac
    local width=$((cols - 1))
    [ "$width" -lt 1 ] && width=1

    # Truncate the variable named by $1 in place (no subshell).
    _tui_fit() {
        local -n _fs="$1"
        if (( ${#_fs} > width )); then _fs="${_fs:0:width}"; fi
    }

    # Print one line from styled segments (style1 text1 style2 text2 ...).
    # Visible text is truncated to $width so styles never cause wrapping.
    _tui_line() {
        local remaining=$width out="" style text
        while [ "$#" -ge 2 ]; do
            style="$1"; text="$2"; shift 2
            [ "$remaining" -le 0 ] && break
            if [ "${#text}" -gt "$remaining" ]; then text="${text:0:$remaining}"; fi
            out+="${style}${text}${C_RESET}"
            remaining=$((remaining - ${#text}))
        done
        printf '%s\033[K\n' "$out"
    }

    _tui_render() {
        local t="$title"
        _tui_fit t
        printf '%s%s%s\033[K\n' "$C_HL" "$t" "$C_RESET"
        for ((i = 0; i < n; i++)); do
            if [ "${kinds[$i]}" = sep ]; then
                local sep_line pad
                sep_line="-- ${descs[$i]} "
                _tui_fit sep_line
                printf -v pad '%*s' $((width - ${#sep_line})) ''
                sep_line+="${pad// /-}"
                printf '%s%s%s\033[K\n' "$C_HL" "$sep_line" "$C_RESET"
                continue
            fi
            local mark="[ ]" line item_color=""
            [ "${states[$i]}" = on ] && mark="[x]"
            # Per-item status color (set by the caller via TUI_ITEM_COLOR):
            # green = installed+latest, yellow = installed+upgradable.
            # The cursor row keeps its blue highlight so it stays visible.
            [ "${#TUI_ITEM_COLOR[@]}" -gt "$i" ] && item_color="${TUI_ITEM_COLOR[$i]}"
            if [ "$i" -eq "$cur" ]; then
                line="> $mark ${descs[$i]}"
                _tui_fit line
                printf '%s%s%s\033[K\n' "$C_BLUE" "$line" "$C_RESET"
            elif [ -n "$item_color" ]; then
                line="  $mark ${descs[$i]}"
                _tui_fit line
                printf '%s%s%s\033[K\n' "$item_color" "$line" "$C_RESET"
            else
                line="  $mark ${descs[$i]}"
                _tui_fit line
                printf '%s%s%s\033[K\n' "$C_DIM" "$line" "$C_RESET"
            fi
        done
        _tui_line "$C_KEY" 'Up' "$C_DIM" '/' "$C_KEY" 'Down' "$C_DIM" ' move  ' "$C_KEY" 'Space' "$C_DIM" ' toggle'
        _tui_line "$C_KEY" 'a' "$C_DIM" ' all (skips installed)  ' "$C_KEY" 'Enter' "$C_DIM" ' confirm  ' "$C_KEY" 'q' "$C_DIM" ' quit'
        if [ -n "${TUI_LEGEND:-}" ]; then
            _tui_line "$C_OK" 'green' "$C_DIM" ' = installed  ' "$C_YELLOW" 'yellow' "$C_DIM" ' = update+  ' "$C_ERR" 'red' "$C_DIM" ' = source gone'
        fi
        local ei estyle=""
        for ((ei = 0; ei < extra; ei++)); do
            estyle=""
            [ "${#TUI_EXTRA_STYLE[@]}" -gt "$ei" ] && estyle="${TUI_EXTRA_STYLE[$ei]}"
            if [ -n "$estyle" ]; then
                _tui_line "$estyle" "${TUI_EXTRA_KEYS[$ei]} ${TUI_EXTRA_DESCS[$ei]}"
            else
                _tui_line "$C_KEY" "${TUI_EXTRA_KEYS[$ei]}" "$C_DIM" " ${TUI_EXTRA_DESCS[$ei]}"
            fi
        done
    }

    _tui_clear() { printf '\033[%dA\033[J' "$lines"; }

    # Move the cursor by $1 rows, skipping separator headers. Wraps around
    # at the top/bottom so the cursor circles over the list.
    _tui_move() {
        local d="$1"
        local j=$cur tries=0
        while [ "$tries" -lt "$n" ]; do
            j=$(( (j + d + n) % n ))
            tries=$((tries + 1))
            [ "${kinds[$j]}" = sep ] && continue
            cur=$j
            changed=1
            return
        done
    }

    tput civis 2>/dev/null || true
    _tui_render

    local key changed
    while true; do
        changed=0
        IFS= read -rsn1 key
        if [ "$key" = $'\x1b' ]; then
            local rest2
            read -rsn2 -t 0.1 rest2
            key="$key$rest2"
        fi

        # Extra single-key actions (e.g. s = save, u = update). These run the
        # caller's function below the block with the current toggles exposed via
        # TUI_ON_TAGS, print its output, then redraw the menu.
        if [ "$extra" -gt 0 ] && [ -n "$key" ]; then
            local ei action=-1 on_tags=""
            for ((ei = 0; ei < extra; ei++)); do
                [ "$key" = "${TUI_EXTRA_KEYS[$ei]}" ] && { action=$ei; break; }
            done
            if [ "$action" -ge 0 ]; then
                for ((i = 0; i < n; i++)); do
                    [ "${kinds[$i]}" = item ] || continue
                    [ "${states[$i]}" = on ] && on_tags+="${tags[$i]} "
                done
                local stream=0
                [ "${#TUI_EXTRA_STREAM[@]}" -gt "$action" ] && stream="${TUI_EXTRA_STREAM[$action]}"
                if [ "$stream" = "1" ]; then
                    # Long action: stream live below the menu so prompts and
                    # progress are visible, then full-clear and redraw.
                    tput cnorm 2>/dev/null || true
                    _tui_clear
                    ( TUI_ON_TAGS="${on_tags% }" "${TUI_EXTRA_FNS[$action]}" )
                    printf '  %sPress any key to return...%s' "$C_DIM" "$C_RESET"
                    IFS= read -rsn1 _ || true
                    clear 2>/dev/null || printf '\033[2J\033[H'
                    tput civis 2>/dev/null || true
                else
                    local out ol
                    # Show an immediate notice: the action's own output is captured
                    # below, so without this a slow action looks like a frozen menu.
                    local busy="${TUI_EXTRA_BUSY[$action]:-Working, please wait...}"
                    _tui_fit busy
                    printf '%s%s%s\033[K\n' "$C_PURPLE" "$busy" "$C_RESET"
                    out=$(TUI_ON_TAGS="${on_tags% }" "${TUI_EXTRA_FNS[$action]}" 2>&1)
                    printf '\033[1A\033[2K'   # erase the notice again
                    tput cnorm 2>/dev/null || true
                    _tui_clear
                    printf '%s\n' "$out"
                    ol=$(printf '%s\n' "$out" | wc -l)
                    printf '  %sPress any key to return...%s' "$C_DIM" "$C_RESET"
                    IFS= read -rsn1 _ || true
                    printf '\033[%dA\033[J' "$((ol + 1))"
                    tput civis 2>/dev/null || true
                fi
                # Refresh per-item state (e.g. pkg status colors after 'u')
                # only for actions that change statuses (TUI_EXTRA_REFRESH);
                # 's' (save) changes nothing and must not trigger a re-probe.
                local do_refresh=0
                [ "${#TUI_EXTRA_REFRESH[@]}" -gt "$action" ] && do_refresh="${TUI_EXTRA_REFRESH[$action]:-0}"
                if [ "$do_refresh" = "1" ] && [ -n "$TUI_REFRESH_FN" ]; then
                    # The refresh (connectivity + probes) can take a while and
                    # prints its own lines: announce it, run it, then clear
                    # the screen so the redraw starts from a known state.
                    announce "Refreshing status, please wait..."
                    "$TUI_REFRESH_FN"
                    clear 2>/dev/null || printf '\033[2J\033[H'
                fi
                # The refresh may have added/dropped shortcuts: recompute the
                # redraw height before rendering again.
                extra=${#TUI_EXTRA_KEYS[@]}
                legend_lines=0
                [ -n "${TUI_LEGEND:-}" ] && legend_lines=1
                lines=$((n + 3 + extra + legend_lines))
                _tui_render
                continue
            fi
        fi

        case "$key" in
            $'\x1b[A'|k) _tui_move -1 ;;
            $'\x1b[B'|j) _tui_move 1 ;;
            ' ')
                if [ "${states[$cur]}" = on ]; then states[cur]=off; else states[cur]=on; fi
                changed=1
                ;;
            a)
                # Bulk toggle: "all on" ticks only rows eligible for bulk
                # (TUI_ITEM_BULK=1: missing/yellow components + options that
                # are currently on); green/broken rows stay as they are so a
                # bulk key never triggers mass reinstalls. "All off" clears
                # every row, as before. Without TUI_ITEM_BULK, behaves as
                # today (toggles everything).
                local bulk_mode=0
                [ "${#TUI_ITEM_BULK[@]}" -gt 0 ] && bulk_mode=1
                local all_on=1
                for ((i = 0; i < n; i++)); do
                    [ "${kinds[$i]}" = item ] || continue
                    if [ "$bulk_mode" -eq 1 ] && [ "${TUI_ITEM_BULK[$i]:-1}" != "1" ]; then continue; fi
                    [ "${states[$i]}" = on ] || all_on=0
                done
                local target=on
                [ "$all_on" -eq 1 ] && target=off
                for ((i = 0; i < n; i++)); do
                    [ "${kinds[$i]}" = item ] || continue
                    if [ "$target" = "on" ] && [ "$bulk_mode" -eq 1 ] \
                        && [ "${TUI_ITEM_BULK[$i]:-1}" != "1" ]; then continue; fi
                    states[i]="$target"
                done
                changed=1
                ;;
            ''|$'\n') break ;;
            q|Q) tput cnorm 2>/dev/null || true; _tui_clear; return 1 ;;
        esac
        if [ "$changed" -eq 1 ]; then
            _tui_clear
            _tui_render
        fi
    done

    tput cnorm 2>/dev/null || true
    _tui_clear

    local selected=""
    for ((i = 0; i < n; i++)); do
        [ "${kinds[$i]}" = item ] || continue
        [ "${states[$i]}" = on ] && selected+="${tags[$i]} "
    done
    printf -v "$result_var" '%s' "${selected% }"
    return 0
}

# Action for the 's' shortcut shown in the menu. Uses the default path:
# the shortcut takes no arguments, so --save-kilo=PATH still needs the CLI.
menu_save_kilo() { save_kilo "$DEFAULT_KILO_BACKUP"; }

# Action for the 'u' shortcut: refresh what is already installed. The pkg tools
# are covered by a single `pkg update && pkg upgrade`, so their individual
# toggles are irrelevant; each selected 3rd-party tool is updated only when it
# is actually present.
menu_update_tools() {
    export TERM="${TERM:-xterm-256color}"

    local -A on=()
    local c
    for c in ${TUI_ON_TAGS:-}; do on[$c]=1; done

    step "Updating pkg packages (pkg update && pkg upgrade)"
    pkg_noninteractive pkg update -y || warn "pkg update reported errors; continuing"
    pkg_noninteractive pkg upgrade -y \
        || warn "pkg upgrade reported errors; continuing"
    ok "pkg packages updated"

    step "Updating selected 3rd-party tools"
    local any=0

    if [ -n "${on[copyparty]:-}" ] && tp_installed copyparty; then
        any=1
        if python -m pip install --user -U copyparty >/dev/null; then
            ok "copyparty updated"
        else
            warn "copyparty update failed"
        fi
    fi

    if [ -n "${on[ytdlp]:-}" ] && tp_installed ytdlp; then
        any=1
        if python -m pip install --user -U yt-dlp >/dev/null; then
            ok "yt-dlp updated"
        else
            warn "yt-dlp update failed"
        fi
    fi

    if [ -n "${on[pydf]:-}" ] && tp_installed pydf; then
        any=1
        if pip3 install -U pydf >/dev/null; then
            ok "pydf updated"
        else
            warn "pydf update failed"
        fi
    fi

    if [ -n "${on[shizuku]:-}" ] && tp_installed shizuku; then
        any=1
        if git -C "$SHIZUKU_DIR" pull --ff-only \
           && ( cd "$SHIZUKU_DIR" && CARGO_BUILD_JOBS=1 bash setup.sh ); then
            ok "termux-shizuku-tools updated"
        else
            warn "termux-shizuku-tools update reported errors"
        fi
    fi

    if [ -n "${on[rish]:-}" ] && tp_installed rish; then
        any=1
        local tmp
        tmp=$(mktemp) || tmp=""
        [ -n "$tmp" ] && register_temp "$tmp"
        # Force the non-interactive path: the output is captured below this menu.
        if [ -n "$tmp" ] && curl -fsSL --max-time "$DOWNLOAD_TIMEOUT" --connect-timeout "$NET_CONNECT_TIMEOUT" "$REPO_RISH_INSTALL" -o "$tmp" \
           && bash "$tmp" --reinstall --silent --source default; then
            ok "rish updated"
        else
            warn "rish update failed"
        fi
        [ -n "$tmp" ] && rm -f "$tmp"
    fi

    if [ -n "${on[core]:-}" ] && tp_installed core; then
        any=1
        if core update core; then
            ok "core-termux updated"
        else
            warn "core update reported errors"
        fi
    fi

    if [ -n "${on[kilocode]:-}" ] && tp_installed kilocode; then
        any=1
        if core update ai --kilocode-cli; then
            ok "kilocode-cli updated"
        else
            warn "kilocode update reported errors"
        fi
    fi

    [ "$any" -eq 1 ] || info "No installed 3rd-party tools among the selected ones."
}

# ------------------------------------------------------------- menu (TUI) ----
# Rebuild TUI_ITEM_COLOR after a status change (e.g. after the 'u' update
# action): one entry per menu row, in the same order the rows were built.
# Unified rule for both groups: green = installed+latest, yellow =
# installed+upgradable, red = broken source, default = not installed.
# Menu option rows (tag|description), single source of truth for show_menu
# (item building) and refresh_menu_colors (one empty color entry each).
# Option on/off state lives in APT_UPGRADE / SETUP_STORAGE / KILOCODE_NATIVE /
# CLEANUP and is read when the items are built.
menu_option_state() {
    case "$1" in
        apt_upgrade)     [ "$APT_UPGRADE" -eq 1 ] && echo on || echo off ;;
        no_storage)      [ "$SETUP_STORAGE" -eq 0 ] && echo on || echo off ;;
        kilocode_native) [ "$KILOCODE_NATIVE" -eq 1 ] && echo on || echo off ;;
        cleanup)         [ "$CLEANUP" -eq 1 ] && echo on || echo off ;;
    esac
}
MENU_OPTIONS=(
    "apt_upgrade|OPTION: apt update & upgrade before installing (recommended)"
    "no_storage|OPTION: skip termux-setup-storage (shared storage)"
    "kilocode_native|OPTION: kilocode - pick recommended native method (no prompt)"
    "cleanup|OPTION: cleanup install stubs + caches after installing"
)

# Bulk-key eligibility, one rule for both menus: components qualify when
# menu_default_state is on (missing/yellow); options qualify when currently
# on. Green/broken rows never qualify, so `a` cannot mass-reinstall.
menu_bulk_eligible() {
    case " ${ALL_COMPONENTS[*]} " in
        *" $1 "*) [ "$(menu_default_state "$1")" = "on" ] ;;
        *)        [ "$(menu_option_state "$1")" = "on" ] ;;
    esac
}

refresh_menu_colors() {
    local i=0
    TUI_ITEM_COLOR=()
    TUI_ITEM_BULK=()
    TUI_ITEM_COLOR[i]=""; TUI_ITEM_BULK[i]=""; ((i++)) || true                 # sep: 3rd-party tools
    for _c in "${THIRD_PARTY_COMPONENTS[@]}"; do
        TUI_ITEM_COLOR[i]="$(menu_item_color "$_c")"
        TUI_ITEM_BULK[i]="$(menu_bulk_eligible "$_c" && echo 1 || echo 0)"
        ((i++)) || true
    done
    TUI_ITEM_COLOR[i]=""; TUI_ITEM_BULK[i]=""; ((i++)) || true                 # sep: pkg tools
    for _c in "${PKG_TOOL_COMPONENTS[@]}"; do
        TUI_ITEM_COLOR[i]="$(menu_item_color "$_c")"
        TUI_ITEM_BULK[i]="$(menu_bulk_eligible "$_c" && echo 1 || echo 0)"
        ((i++)) || true
    done
    TUI_ITEM_COLOR[i]=""; TUI_ITEM_BULK[i]=""; ((i++)) || true                 # sep: options
    local _o _tag
    for _o in "${MENU_OPTIONS[@]}"; do
        _tag="${_o%%|*}"
        TUI_ITEM_COLOR[i]=""
        TUI_ITEM_BULK[i]="$(menu_bulk_eligible "$_tag" && echo 1 || echo 0)"
        ((i++)) || true
    done
}

# Re-probe all statuses and rebuild row colors, suffixes, and toggles. Wired
# as TUI_REFRESH_FN so the menu refreshes right after an action without
# leaving it. A row is forced OFF only when its status CHANGED into current
# or broken; rows whose status didn't change keep the user's toggle (a green
# row ticked on purpose for a reinstall stays ticked).
# Refresh-hook contract (see the TUI_EXTRA_STREAM comment): this runs in
# tui_checklist's scope and may read/write n, kinds, tags, descs, states,
# plus the TUI_EXTRA_* arrays; tui_checklist recomputes extra/lines after.
# shellcheck disable=SC2329  # invoked via TUI_REFRESH_FN
refresh_menu_status() {
    # Snapshot statuses so only real changes force toggles off.
    local -A before=()
    local i st
    for ((i = 0; i < n; i++)); do
        [ "${kinds[$i]}" = item ] || continue
        case " ${ALL_COMPONENTS[*]} " in
            *" ${tags[i]} "*) before[${tags[i]}]="$(comp_status "${tags[i]}")" ;;
        esac
    done
    check_connectivity
    probe_pkg_status
    probe_tp_status
    refresh_menu_colors
    # Prerequisites now present: drop the 'p' shortcut (it did its job).
    if ! prereqs_missing; then
        local ni nk=() nd=() nb=() nf=() ns=() nt=() nr=()
        for ((ni = 0; ni < ${#TUI_EXTRA_KEYS[@]}; ni++)); do
            [ "${TUI_EXTRA_KEYS[$ni]}" = "p" ] && continue
            nk+=("${TUI_EXTRA_KEYS[$ni]}"); nd+=("${TUI_EXTRA_DESCS[$ni]}")
            nb+=("${TUI_EXTRA_BUSY[$ni]}"); nf+=("${TUI_EXTRA_FNS[$ni]}")
            ns+=("${TUI_EXTRA_STYLE[$ni]}"); nt+=("${TUI_EXTRA_STREAM[$ni]:-0}")
            nr+=("${TUI_EXTRA_REFRESH[$ni]:-0}")
        done
        TUI_EXTRA_KEYS=("${nk[@]}"); TUI_EXTRA_DESCS=("${nd[@]}")
        TUI_EXTRA_BUSY=("${nb[@]}"); TUI_EXTRA_FNS=("${nf[@]}")
        TUI_EXTRA_STYLE=("${ns[@]}"); TUI_EXTRA_STREAM=("${nt[@]}")
        TUI_EXTRA_REFRESH=("${nr[@]}")
    fi
    for ((i = 0; i < n; i++)); do
        [ "${kinds[$i]}" = item ] || continue
        case " ${ALL_COMPONENTS[*]} " in
            *" ${tags[i]} "*)
                descs[i]="${COMP_DESC[${tags[i]}]}$(comp_suffix "${tags[i]}")"
                st="$(comp_status "${tags[i]}")"
                if [ "$st" = "current" ] || [ "$st" = "broken" ]; then
                    # Only force off when the status actually changed into
                    # this state; an unchanged row keeps the user's toggle.
                    if [ "${before[${tags[i]}]:-}" != "$st" ]; then
                        states[i]="off"
                    fi
                fi
                ;;
        esac
    done
}

show_menu() {
    export TERM="${TERM:-xterm-256color}"

    # Loop so the text fallback can reload the full menu after 'p' installs
    # the prerequisites: items are rebuilt and re-probed every pass, and the
    # TUI is retried (it usually fits now that tput/ncurses-utils exists).
    # NOTE: never re-exec "$0" here — under `bash <(curl ...)` $0 is a dead
    # /dev/fd pipe, so exec would run an empty script and exit silently.
    while true; do
        local -a items=()
        local c
        items+=("sep|3rd-party tools")
        # Connectivity first: without it, offline verdicts would paint false reds.
        # Purple announce — the parallel network probes take a few seconds.
        announce "Checking connectivity, please wait..."
        check_connectivity
        announce "Checking 3rd-party tools (network check, please wait)..."
        probe_tp_status
        for c in "${THIRD_PARTY_COMPONENTS[@]}"; do
            # Green (installed+latest) and broken (dead source) default to off:
            # re-installing green is pointless, installing broken is impossible.
            # A ticked green row forces a reinstall at install time.
            items+=("$c|${COMP_DESC[$c]}$(comp_suffix "$c")|$(menu_default_state "$c")")
        done
        items+=("sep|pkg tools")
        progress "Checking installed pkg tools..."
        probe_pkg_status
        for c in "${PKG_TOOL_COMPONENTS[@]}"; do
            items+=("$c|${COMP_DESC[$c]}$(comp_suffix "$c")|$(menu_default_state "$c")")
        done
        items+=("sep|options")
        local _o _tag _desc
        for _o in "${MENU_OPTIONS[@]}"; do
            _tag="${_o%%|*}"; _desc="${_o#*|}"
            items+=("$_tag|$_desc|$(menu_option_state "$_tag")")
        done

        # Shortcut keys: 's' saves a Kilo backup, 'u' updates what is installed,
        # 'p' installs prerequisites on demand (fresh Termux) and reloads the menu.
        TUI_EXTRA_KEYS=("s" "u")
        TUI_EXTRA_DESCS=("save kilocode backup" "update installed tools")
        TUI_EXTRA_BUSY=("Saving Kilo settings and tokens, please wait..."
                        "Updating installed tools; this can take several minutes...")
        TUI_EXTRA_FNS=("menu_save_kilo" "menu_update_tools")
        TUI_EXTRA_STYLE=("" "")
        TUI_EXTRA_STREAM=(0 1)
        TUI_EXTRA_REFRESH=(0 1)
        if prereqs_missing; then
            TUI_EXTRA_KEYS+=("p")
            TUI_EXTRA_DESCS+=("install prerequisites (recommended on fresh Termux)")
            TUI_EXTRA_BUSY+=("Installing prerequisites; this can take several minutes...")
            TUI_EXTRA_FNS+=("menu_install_prereqs")
            # The prerequisites shortcut is the important one on a fresh Termux:
            # render the whole line in bold white so it stands out.
            TUI_EXTRA_STYLE+=("$C_KEY")
            TUI_EXTRA_STREAM+=(1)
            TUI_EXTRA_REFRESH+=(1)
        fi
        # Status colors for pkg rows (green = installed+latest, yellow =
        # installed+upgradable, default = missing); refreshed after 'u'.
        refresh_menu_colors
        TUI_REFRESH_FN="refresh_menu_status"
        TUI_LEGEND="status"

        # Vertical fit: the redraw moves the cursor up one line per rendered line,
        # so if the block is taller than the screen the display corrupts. Fall back
        # to a plain numbered menu (no cursor movement, no tput) instead of
        # skipping straight into installing everything.
        local rows est legend_extra=0 text_rc=0
        rows=$(tput lines 2>/dev/null) || rows=""
        case "$rows" in ''|*[!0-9]*) rows="${LINES:-24}" ;; esac
        [ -n "$TUI_LEGEND" ] && legend_extra=1
        est=$(( ${#items[@]} + 3 + ${#TUI_EXTRA_KEYS[@]} + legend_extra ))   # title + 2 help lines + legend + extra keys
        if [ "$est" -ge "$rows" ]; then
            warn "Menu needs $est rows, terminal has $rows"
            info "Falling back to a plain text menu"
            info "Tip: zoom out / rotate to landscape for more rows, then press 'r' to reload the full menu"
            TUI_EXTRA_KEYS=(); TUI_EXTRA_DESCS=(); TUI_EXTRA_BUSY=(); TUI_EXTRA_FNS=()
            TUI_EXTRA_STYLE=(); TUI_EXTRA_STREAM=(); TUI_EXTRA_REFRESH=()
            TUI_ITEM_COLOR=(); TUI_REFRESH_FN=""; TUI_LEGEND=""
            show_text_menu "${items[@]}"
            text_rc=$?
            # 42 = 'p' installed the prerequisites, 43 = 'r' reload after zoom:
            # loop back, rebuild items with fresh probes, and retry the TUI.
            if [ "$text_rc" -eq 42 ] || [ "$text_rc" -eq 43 ]; then
                continue
            fi
            return "$text_rc"
        fi

        local result
        if ! tui_checklist "tmx2tm.sh v$SCRIPT_VERSION - select components" result "${items[@]}"; then
            echo
            info "Cancelled."
            exit 130
        fi

        TUI_EXTRA_KEYS=()
        TUI_EXTRA_DESCS=()
        TUI_EXTRA_BUSY=()
        TUI_EXTRA_FNS=()
        TUI_EXTRA_STYLE=()
        TUI_EXTRA_STREAM=()
        TUI_EXTRA_REFRESH=()
        TUI_ITEM_COLOR=()
        TUI_REFRESH_FN=""
        TUI_LEGEND=""

        apply_menu_result "$result"
        return 0
    done
}

# Plain numbered fallback menu for terminals too short for the interactive
# TUI (needs no cursor movement, no tput — just echo + read). Takes the same
# "tag|description|on|off" items, honors separators, and produces the same
# space-separated tag result for apply_menu_result. Empty input confirms,
# 'q' quits, 'a' toggles all, otherwise the typed numbers toggle.
show_text_menu() {
    local -a tags=() descs=() states=() nums=()
    local e rest n=0 i
    for e in "$@"; do
        if [ "${e%%|*}" = "sep" ]; then
            tags+=(""); descs+=("${e#*|}"); states+=("")
        else
            tags+=("${e%%|*}")
            rest="${e#*|}"
            descs+=("${rest%%|*}")
            states+=("${rest##*|}")
            n=$((n + 1))
            nums+=("$n")
        fi
    done

    echo
    echo "tmx2tm.sh v$SCRIPT_VERSION - select components"
    echo "green = installed, yellow = update+, red = source gone"
    echo
    n=0
    for ((i = 0; i < ${#tags[@]}; i++)); do
        if [ -z "${tags[$i]}" ]; then
            echo "-- ${descs[$i]} --"
            continue
        fi
        n=$((n + 1))
        if [ "${states[$i]}" = on ]; then
            printf '  %2d. [x] %s\n' "$n" "${descs[$i]}"
        else
            printf '  %2d. [ ] %s\n' "$n" "${descs[$i]}"
        fi
    done
    echo
    # Recommended actions go last, each on its own full line so they stand
    # out: 'p' installs the prerequisites (bold white, only when actually
    # offered, i.e. base prerequisites missing on a fresh Termux), 'r'
    # reloads after zoom-out/rotate (always offered in the fallback, where
    # the TUI is retried when the terminal is tall enough again).
    echo "Commands: <numbers> toggle | a = toggle all (skips installed) | s = save kilo backup | u = update installed | <Enter> = confirm | q = quit"
    if prereqs_missing; then
        printf '%s%s%s\n' "$C_KEY" "p = install prerequisites (recommended on fresh Termux)" "$C_RESET"
    fi
    echo "r = zoom out and reload"

    local line t idx
    _text_reprint() {
        n=0
        local j
        for ((j = 0; j < ${#tags[@]}; j++)); do
            if [ -z "${tags[$j]}" ]; then
                echo "-- ${descs[$j]} --"
                continue
            fi
            n=$((n + 1))
            if [ "${states[$j]}" = on ]; then
                printf '  %2d. [x] %s\n' "$n" "${descs[$j]}"
            else
                printf '  %2d. [ ] %s\n' "$n" "${descs[$j]}"
            fi
        done
    }
    while true; do
        printf '> '
        IFS= read -r line || { echo; info "Cancelled."; exit 130; }
        case "$line" in
            '') break ;;
            q|Q) info "Cancelled."; exit 130 ;;
            a|A)
                # Same bulk rule as the TUI (menu_bulk_eligible): "all on"
                # ticks only eligible rows (missing/yellow + options on);
                # green/broken stay as they are. "All off" clears every row.
                local all_on=1
                for ((i = 0; i < ${#tags[@]}; i++)); do
                    [ -n "${tags[$i]}" ] || continue
                    menu_bulk_eligible "${tags[$i]}" || continue
                    [ "${states[$i]}" = on ] || all_on=0
                done
                for ((i = 0; i < ${#tags[@]}; i++)); do
                    [ -n "${tags[$i]}" ] || continue
                    if [ "$all_on" -eq 1 ]; then
                        states[i]="off"
                        continue
                    fi
                    menu_bulk_eligible "${tags[$i]}" || continue
                    states[i]="on"
                done
                ;;
            s|S) menu_save_kilo ;;
            u|U)
                menu_update_tools_no_tui
                # Refresh suffixes + toggles with the same rules as
                # refresh_menu_status: notice first, snapshot statuses, then
                # force off only rows whose status CHANGED into current/broken.
                announce "Refreshing status, please wait..."
                local -A _before=()
                local ri st
                for ((ri = 0; ri < ${#tags[@]}; ri++)); do
                    [ -n "${tags[$ri]}" ] || continue
                    case " ${ALL_COMPONENTS[*]} " in
                        *" ${tags[$ri]} "*) _before[${tags[$ri]}]="$(comp_status "${tags[$ri]}")" ;;
                    esac
                done
                check_connectivity
                probe_pkg_status
                probe_tp_status
                for ((ri = 0; ri < ${#tags[@]}; ri++)); do
                    [ -n "${tags[$ri]}" ] || continue
                    case " ${ALL_COMPONENTS[*]} " in
                        *" ${tags[$ri]} "*)
                            descs[ri]="${COMP_DESC[${tags[$ri]}]}$(comp_suffix "${tags[$ri]}")"
                            st="$(comp_status "${tags[$ri]}")"
                            if [ "$st" = "current" ] || [ "$st" = "broken" ]; then
                                if [ "${_before[${tags[$ri]}]:-}" != "$st" ]; then
                                    states[ri]="off"
                                fi
                            fi ;;
                    esac
                done
                refresh_menu_colors
                ;;
            p|P)
                # Already installed (p hidden this pass): don't reinstall in
                # a loop, just stay in the menu.
                if ! prereqs_missing; then
                    warn "Prerequisites are already installed"
                    continue
                fi
                menu_install_prereqs
                # Signal the show_menu loop (rc 42) to rebuild items with
                # fresh probes and reopen the menu with full checks. No exec:
                # under `bash <(curl ...)` $0 is a dead fd pipe, so exec
                # would run an empty script and exit silently.
                progress "Prerequisites installed — reloading the menu..."
                return 42
                ;;
            r|R)
                # Zoomed out / rotated since the fallback opened: signal the
                # show_menu loop (rc 43) to rebuild with fresh probes and
                # retry the TUI. A reload is a fresh look (re-probed defaults),
                # not a resume of the toggles picked here.
                progress "Reloading the menu..."
                return 43
                ;;
            *)
                for t in $line; do
                    case "$t" in
                        ''|*[!0-9]*) warn "Ignoring '$t' (not a number)"; continue ;;
                    esac
                    idx=-1; n=0
                    for ((i = 0; i < ${#tags[@]}; i++)); do
                        [ -n "${tags[$i]}" ] || continue
                        n=$((n + 1))
                        if [ "$n" -eq "$t" ]; then idx=$i; break; fi
                    done
                    if [ "$idx" -lt 0 ]; then warn "Ignoring '$t' (out of range)"; continue; fi
                    if [ "${states[$idx]}" = on ]; then states[idx]="off"; else states[idx]="on"; fi
                done
                ;;
        esac
        # Re-print the list with the new toggles.
        _text_reprint
    done

    local result=""
    for ((i = 0; i < ${#tags[@]}; i++)); do
        [ -n "${tags[$i]}" ] || continue
        [ "${states[$i]}" = on ] && result+="${tags[$i]} "
    done
    apply_menu_result "${result% }"
}

# Update action variant for the text menu: same updates as the TUI 'u' key,
# but built from the text menu's toggles (tags/states) instead of the TUI's
# TUI_ON_TAGS.
menu_update_tools_no_tui() {
    local TUI_ON_TAGS="" i
    for ((i = 0; i < ${#tags[@]}; i++)); do
        [ -n "${tags[$i]}" ] || continue
        [ "${states[$i]}" = on ] && TUI_ON_TAGS+="${tags[$i]} "
    done
    TUI_ON_TAGS="${TUI_ON_TAGS% }"
    menu_update_tools
}

# Apply a confirmed menu result (space-separated tags): reset, apply toggles
# and options, auto-enable dependencies, and validate the selection.
# Shared by the interactive TUI and the text fallback menu.
apply_menu_result() {
    local result="$1"

    # Reset then apply component selections.
    for c in "${ALL_COMPONENTS[@]}"; do SELECTED[$c]=0; done
    SETUP_STORAGE=1
    KILOCODE_NATIVE=0
    APT_UPGRADE=0
    CLEANUP=0

    local tag
    for tag in $result; do
        case "$tag" in
            no_storage)      SETUP_STORAGE=0 ;;
            kilocode_native) KILOCODE_NATIVE=1 ;;
            apt_upgrade)     APT_UPGRADE=1 ;;
            cleanup)         CLEANUP=1 ;;
            *) [ -n "${SELECTED[$tag]:-}" ] && SELECTED[$tag]=1 ;;
        esac
    done

    # kilocode depends on core — but only auto-enable when core is not
    # already current (green): a current core must not be force-reinstalled.
    if is_selected kilocode && ! is_selected core; then
        if [ "$(comp_status core)" = "current" ]; then
            info "kilocode needs core; core already installed, using it"
        else
            SELECTED[core]=1
            warn "kilocode needs core; enabling core automatically"
        fi
    fi

    # termux-shizuku-tools builds Rust Python extensions (jiter, pydantic-core);
    # without the rust toolchain that pip step aborts the whole setup.
    # Same rule: never force-reinstall a green rust (~640 MB).
    if is_selected shizuku && ! is_selected rust; then
        if [ "$(comp_status rust)" = "current" ]; then
            info "termux-shizuku-tools needs rust; rust already installed, using it"
        else
            SELECTED[rust]=1
            warn "termux-shizuku-tools needs rust; enabling rust automatically"
        fi
    fi

    local any=0
    for c in "${ALL_COMPONENTS[@]}"; do is_selected "$c" && any=1; done
    if [ "$any" -eq 0 ] && [ "$CLEANUP" -eq 0 ]; then
        echo
        info "Nothing selected."
        exit 0
    fi

    MENU_CONFIRMED=1
    clear 2>/dev/null || true
}

# ---------------------------------------------------------------- stages ----
# A fresh Termux has no mirror chosen yet (no chosen_mirrors symlink) and
# pkg/apt cannot reach a repository until one is selected. Prefer the normal
# termux-change-repo picker when interactive; otherwise fall back to the
# bundled default mirror so unattended runs still work.
ensure_termux_mirror() {
    local chosen="$PREFIX/etc/termux/chosen_mirrors"
    [ -e "$chosen" ] && return 0

    warn "No Termux repository mirror is selected yet"
    if is_interactive_out && command -v termux-change-repo >/dev/null 2>&1; then
        progress "Running termux-change-repo (pick a mirror group)"
        termux-change-repo || warn "termux-change-repo did not complete; continuing"
    fi

    if [ ! -e "$chosen" ] && [ -e "$PREFIX/etc/termux/mirrors/default" ]; then
        progress "Falling back to the bundled default mirror"
        ln -sfn "$PREFIX/etc/termux/mirrors/default" "$chosen" \
            || warn "Could not select the default mirror automatically"
    fi
}

# apt update + full upgrade before the pkg stages, so curl and the rest of the
# base dependencies install cleanly (a stale index or missing repo otherwise
# makes the pkg install fail). On by default; disable with --no-apt-upgrade or
# the menu toggle.
update_apt() {
    [ "$APT_UPGRADE" -eq 1 ] || return 0

    ensure_termux_mirror

    step "Running apt update & full upgrade"
    DEBIAN_FRONTEND=noninteractive apt update -y \
        || warn "apt update reported errors; continuing anyway"
    # full-upgrade (like pkg upgrade): plain upgrade holds back packages
    # whose dependencies changed, leaving the base image half-updated.
    pkg_noninteractive apt full-upgrade -y \
        || warn "apt full-upgrade reported errors; continuing anyway"
    ok "apt update & full upgrade finished"
}

install_base_deps() {
    step "Installing base pkg dependencies"
    progress "pkg install: ${BASE_PKG_DEPS[*]}"
    pkg_noninteractive pkg install -y "${BASE_PKG_DEPS[@]}" || die "Failed to install base pkg dependencies"
    ok "Base dependencies installed"
}

# True when the base prerequisites are incomplete (fresh Termux): at least one
# BASE_PKG_DEPS package is not installed. Fast local dpkg checks only, no
# network. Used to offer the 'p' (install prerequisites) shortcut in the menus.
prereqs_missing() {
    local p
    for p in "${BASE_PKG_DEPS[@]}"; do
        dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q "ok installed" || return 0
    done
    return 1
}

# Action for the 'p' shortcut: install prerequisites on demand (apt update &
# upgrade plus the base pkg dependencies), e.g. on a fresh Termux where the
# status probes run degraded without git/pip/tput. Idempotent — a rerun is a
# quick no-op. Forces APT_UPGRADE locally so 'p' works even when the
# apt_upgrade option is toggled off. After it finishes, the menu refresh hook
# re-probes, so the menu reloads with full status colors and checks.
menu_install_prereqs() {
    local APT_UPGRADE=1
    update_apt
    install_base_deps
}

# Go keeps user-built binaries in $GOPATH/bin (default ~/go/bin) and the locale
# cache in ~/.cache/go-build. Persist GOPATH and put $GOPATH/bin on PATH in
# ~/.bashrc so `go install`ed tools are found in new shells.
setup_golang_path() {
    # shellcheck disable=SC2016  # literal lines for ~/.bashrc, must not expand
    ensure_bashrc_line 'export GOPATH="$HOME/go"'
    # shellcheck disable=SC2016
    ensure_bashrc_line 'export PATH="$GOPATH/bin:$PATH"'

    export GOPATH="$HOME/go"
    export PATH="$GOPATH/bin:$PATH"
    ok "go -> $(command -v go || echo missing)  (GOPATH=$GOPATH)"
    info "Added GOPATH and \$GOPATH/bin to ~/.bashrc"
}

# Starship prompt init, kept in sync in ~/.bash_profile AND ~/.bashrc on every
# run (not just when starship is selected): zellij sources ~/.bashrc for its
# panes even inside a login shell, so the snippet must live in both files.
# The snippet inits once per shell: the guard checks `declare -F
# starship_precmd` (the function exists only after init in THIS shell and is
# never inherited by children), so a later `source ~/.bashrc` is a no-op
# instead of a double-rendered prompt with double-registered keybindings.
# Filter: drop one starship snippet block (marker + its exact body lines).
# Reads the file on stdin, writes the result on stdout.
# After a marker, expected body lines are consumed ONE AT A TIME and only on
# exact match; at the first non-matching line, consumption stops and that line
# (plus everything after) prints unchanged — user lines after an edited
# snippet always survive. A partial block (marker + some matched lines but no
# `fi`) drops just the matched lines: the marker proves the installer wrote
# them, and a lone `if` without its `fi` can never be user code worth keeping.
# A blank line immediately before a dropped marker goes with it, so add/remove
# cycles do not accumulate blank lines.
# shellcheck disable=SC2329  # invoked via rc_rewrite
_starship_strip_filter() {
    awk '
        function is_body(line) {
            return (line == "if ! declare -F starship_precmd >/dev/null 2>&1 && command -v starship >/dev/null 2>&1; then" \
                || line == "if [ -z \"$STARSHIP_START_TIME\" ] && command -v starship >/dev/null 2>&1; then" \
                || line == "if command -v starship >/dev/null 2>&1; then" \
                || line == "    eval \"$(starship init bash)\"" \
                || line == "fi")
        }
        function flush_blanks(all,   i, upto) {
            # Print pending blank lines verbatim. With all=0 (a marker line
            # follows), drop only the LAST pending blank — the separator the
            # installer wrote before the marker; earlier blanks are user
            # content and survive byte-for-byte.
            upto = nb
            if (!all && upto > 0) upto--
            for (i = 0; i < upto; i++) print blanks[i]
            nb = 0
        }
        $0 == "# Initialize Starship only once, if installed" || $0 == "# Initialize Starship only if installed" {
            flush_blanks(0)
            inb=1; n=0; next
        }
        inb {
            if (is_body($0)) {
                if ($0 == "fi") { inb=0; n=0; next }
                next
            }
            # Non-body line: partial block ends here — matched lines already
            # dropped, so just print this line and resume normal output.
            inb=0; n=0
            print
            next
        }
        /^[[:space:]]*$/ { blanks[nb++]=$0; next }
        { flush_blanks(1); print }
        END { flush_blanks(1) }
    '
}

setup_starship_init() {
    if [ -z "${BASH_VERSION:-}" ]; then
        warn "Installer is not running under bash; skipping starship shell init sync"
        return 0
    fi

    local marker='# Initialize Starship only once, if installed'
    local old_marker='# Initialize Starship only if installed'
    # shellcheck disable=SC2016  # literal snippet line, must not expand
    local new_guard='if ! declare -F starship_precmd >/dev/null 2>&1 && command -v starship >/dev/null 2>&1; then'
    local f
    for f in "$BASH_PROFILE" "$BASHRC"; do
        # Drop the legacy unguarded snippet block so it is replaced by the
        # guarded form below (block match only; user `fi`s are untouched).
        if [ -f "$f" ] && grep -qxF "$old_marker" "$f" 2>/dev/null; then
            rc_rewrite "$f" _starship_strip_filter \
                && { info "Upgraded legacy starship snippet in $f"; RC_CHANGED=1; }
        fi
    done

    if ! command -v starship >/dev/null 2>&1; then
        # User uninstalled starship: remove the snippet from both files so the
        # eval (and its guard) does not linger in new shells.
        local removed=0
        for f in "$BASH_PROFILE" "$BASHRC"; do
            if [ -f "$f" ] && grep -qxF "$marker" "$f" 2>/dev/null; then
                rc_rewrite "$f" _starship_strip_filter \
                    && { info "Removed starship init from $f (starship not installed)"; RC_CHANGED=1; }
                removed=1
            fi
        done
        if [ "$removed" -eq 0 ]; then
            info "Starship not installed; nothing to clean up"
        fi
        return 0
    fi

    for f in "$BASH_PROFILE" "$BASHRC"; do
        if [ -f "$f" ] && grep -qxF "$marker" "$f" 2>/dev/null; then
            if grep -qxF "$new_guard" "$f" 2>/dev/null; then
                info "Starship init already present in $f"
                continue
            fi
            # Marker present but the body is an older guard form
            # (STARSHIP_START_TIME): strip it and re-add the current form.
            if rc_rewrite "$f" _starship_strip_filter; then
                info "Upgraded starship guard in $f"; RC_CHANGED=1
            else
                warn "Could not upgrade starship guard in $f; leaving it"
                continue
            fi
        fi
        rc_backup "$f"
        {
            printf '\n%s\n' "$marker"
            # shellcheck disable=SC2016  # literal snippet for the rc files, must not expand
            printf '%s\n' "$new_guard"
            # shellcheck disable=SC2016  # literal snippet for the rc files, must not expand
            printf '%s\n' '    eval "$(starship init bash)"'
            printf '%s\n' 'fi'
        } >>"$f"
        info "Added starship init to $f"; RC_CHANGED=1
    done
    ok "starship -> $(command -v starship)"
}

# Neofetch auto-run snippet, kept in sync in ~/.bash_profile ONLY (not
# ~/.bashrc: zellij sources .bashrc for every pane/tab, so a .bashrc copy
# would re-run neofetch on each new tab; .bash_profile runs once per login
# shell, which is exactly the desired frequency — no guard variable needed).
# Same pattern as setup_starship_init otherwise: binary present -> snippet
# ensured; binary missing -> snippet removed (from .bash_profile AND any
# stale copy in .bashrc). Also repairs the legacy variant found in the wild,
# which lacks the closing `fi`.
# Filter: drop the neofetch block as one unit whenever start AND end markers
# match (body length up to NEOFETCH_BLOCK_CAP lines, to avoid swallowing a
# file where the end marker belongs to something far away; beyond the cap the
# file is left untouched). Only when NO end marker follows does the legacy
# fallback apply: drop the start marker plus known snippet lines
# (if/neofetch/fi/NEOFETCH_SHOWN), stopping at the first unrelated line.
# shellcheck disable=SC2329  # invoked via rc_rewrite
_neofetch_strip_filter() {
    awk -v s='# >>> neofetch on Termux start >>>' -v e='# <<< neofetch on Termux start <<<' -v cap="$NEOFETCH_BLOCK_CAP" '
        function is_snippet(line) {
            return (line ~ /^if .*neofetch/ || line ~ /neofetch --off/ \
                || line == "fi" || line ~ /NEOFETCH_SHOWN/ || line == "neofetch")
        }
        function flush_legacy(   i, start) {
            start = 0
            while (start < n && is_snippet(buf[start])) start++
            for (i=start;i<n;i++) print buf[i]
            inb=0; n=0
        }
        function flush_far(   i) {
            # End marker too far: not our block — keep everything.
            print s; for (i=0;i<n;i++) print buf[i]; inb=0; n=0
        }
        $0 == s {
            # A second start marker while a block is open (legacy unclosed
            # block followed by a proper one): flush the open buffer with
            # the same rule as at end of file, then start the new block.
            if (inb) flush_legacy()
            inb=1; n=0; next
        }
        inb {
            buf[n++]=$0
            if ($0 == e) {
                # Closed block within the cap: drop it (n counts the end
                # marker line, so the cap on body lines is cap + 1).
                if (n <= cap + 1) { inb=0; n=0; next }
                flush_far(); next
            }
            if (n > cap + 1) { flush_far(); next }
            next
        }
        { print }
        END { if (inb) flush_legacy() }
    '
}
_neofetch_has_closed_block() {
    awk -v s='# >>> neofetch on Termux start >>>' -v e='# <<< neofetch on Termux start <<<' -v cap="$NEOFETCH_BLOCK_CAP" '
        $0==s{inb=1; n=0; next} inb{n++; if($0==e){if(n<=cap+1)ok=1; inb=0}} END{exit !ok}' \
        "$1" 2>/dev/null
}
setup_neofetch_init() {
    if [ -z "${BASH_VERSION:-}" ]; then
        warn "Installer is not running under bash; skipping neofetch shell init sync"
        return 0
    fi

    local start_marker='# >>> neofetch on Termux start >>>'
    local end_marker='# <<< neofetch on Termux start <<<'
    local f removed=0

    if ! command -v neofetch >/dev/null 2>&1; then
        for f in "$BASH_PROFILE" "$BASHRC"; do
            if [ -f "$f" ] && grep -qxF "$start_marker" "$f" 2>/dev/null; then
                rc_rewrite "$f" _neofetch_strip_filter \
                    && { info "Removed neofetch init from $f (neofetch not installed)"; RC_CHANGED=1; }
                removed=1
            fi
        done
        if [ "$removed" -eq 0 ]; then
            info "Neofetch not installed; nothing to clean up"
        fi
        return 0
    fi

    # Drop any stale copy in .bashrc: profile-only from now on.
    if [ -f "$BASHRC" ] && grep -qxF "$start_marker" "$BASHRC" 2>/dev/null; then
        rc_rewrite "$BASHRC" _neofetch_strip_filter \
            && { info "Removed stale neofetch init from $BASHRC (profile-only now)"; RC_CHANGED=1; }
    fi

    f="$BASH_PROFILE"
    if _neofetch_has_closed_block "$f"; then
        info "Neofetch init already present in $f"
    else
        if [ -f "$f" ] && grep -qxF "$start_marker" "$f" 2>/dev/null; then
            # An unclosed/legacy block: try to clean it first. If the rewrite
            # is refused (filter output failed bash -n), leave the file as it
            # was — appending would stack a second block on the broken one.
            if ! rc_rewrite "$f" _neofetch_strip_filter; then
                warn "Could not clean the existing neofetch block in $f; leaving it untouched"
                return 0
            fi
        else
            rc_backup "$f"
        fi
        [ -e "$f" ] || : >"$f"
        {
            printf '\n%s\n' "$start_marker"
            # shellcheck disable=SC2016  # literal snippet for the rc files, must not expand
            printf '%s\n' 'if [[ $- == *i* ]] && command -v neofetch >/dev/null 2>&1; then'
            # shellcheck disable=SC2016
            printf '%s\n' '  neofetch --off'
            printf '%s\n' 'fi'
            printf '%s\n' "$end_marker"
        } >>"$f"
        info "Added neofetch init to $f"; RC_CHANGED=1
    fi
    ok "neofetch -> $(command -v neofetch)"
}

install_pkg_tools() {
    # The probe runs before the menu; for non-menu runs (-y / no TTY /
    # short terminal) PKG_STATUS is empty, so probe here to know the state.
    # update_apt runs first and refreshes the index, so probe AFTER it to avoid
    # trusting a stale "latest". A fresh probe costs ~0.2s for all pkg tools.
    if [ "${#PKG_STATUS[@]}" -eq 0 ]; then
        probe_pkg_status
    fi

    local pkgs=()
    local reinstall_pkgs=()
    local skipped=()
    local c p bin
    for c in "${PKG_TOOL_COMPONENTS[@]}"; do
        is_selected "$c" || continue
        if [ "$(comp_status "$c")" = "current" ]; then
            if [ "$MENU_CONFIRMED" -eq 1 ]; then
                # Explicitly ticked green tool: the user wants a reinstall.
                for p in ${PKG_COMPONENT[$c]}; do reinstall_pkgs+=("$p"); done
            else
                # -y / fallback run: everything is selected by default, so a
                # green tool means skip, not reinstall.
                skipped+=("$c")
            fi
            continue
        fi
        for p in ${PKG_COMPONENT[$c]}; do pkgs+=("$p"); done
    done

    if [ "${#skipped[@]}" -gt 0 ]; then
        info "Already installed (latest), skipping: ${skipped[*]}"
        for c in "${skipped[@]}"; do
            record_result "$c" skipped "already installed (latest)"
        done
    fi
    # Batch install first; on failure retry each package alone so one bad
    # package does not block the rest (S2). Failures record + warn, never die.
    if [ "${#pkgs[@]}" -gt 0 ]; then
        step "Installing pkg tools"
        progress "pkg install: ${pkgs[*]}"
        if pkg_noninteractive pkg install -y "${pkgs[@]}"; then
            ok "pkg tools installed"
        else
            warn "Batch install failed; retrying each package alone"
            local p
            for p in "${pkgs[@]}"; do
                if pkg_noninteractive pkg install -y "$p"; then
                    ok "$p installed"
                else
                    warn "$p failed to install; continuing"
                fi
            done
        fi
    fi
    if [ "${#reinstall_pkgs[@]}" -gt 0 ]; then
        step "Reinstalling explicitly selected pkg tools"
        progress "pkg reinstall: ${reinstall_pkgs[*]}"
        local p
        for p in "${reinstall_pkgs[@]}"; do
            if pkg_noninteractive pkg reinstall -y "$p"; then
                ok "$p reinstalled"
            else
                warn "$p failed to reinstall; continuing"
            fi
        done
    fi
    if [ "${#pkgs[@]}" -eq 0 ] && [ "${#reinstall_pkgs[@]}" -eq 0 ]; then
        info "All selected pkg tools are already installed at the latest version"
    fi

    # Verify each selected tool by its binary and record the outcome.
    for c in "${PKG_TOOL_COMPONENTS[@]}"; do
        is_selected "$c" || continue
        bin="${PKG_COMPONENT_CMD[$c]:-$c}"
        if command -v "$bin" >/dev/null 2>&1; then
            ok "$c -> $(command -v "$bin")"
            if [ "$MENU_CONFIRMED" -eq 1 ] && [ "$(comp_status "$c")" = "current" ]; then
                record_result "$c" updated "$(command -v "$bin")"
            elif [ -z "${RESULT[$c]:-}" ]; then
                record_result "$c" installed "$(command -v "$bin")"
            fi
        else
            warn "$c not found after install"
            record_result "$c" failed "binary '$bin' missing after install"
        fi
    done

    if is_selected golang; then
        setup_golang_path
    fi
}

install_pip_tools() {
    is_selected copyparty || is_selected ytdlp || is_selected pydf || return 0

    step "Installing Python-based tools"

    if is_selected copyparty; then
        if tp_gate copyparty; then
            # TP_FORCE=1 after an explicit menu tick on a green tool.
            local force_flag=()
            [ "$TP_FORCE" -eq 1 ] && force_flag=(--force-reinstall)
            if python -m pip install --user "${force_flag[@]}" -U copyparty; then
                ok "copyparty -> $(command -v copyparty || echo "$HOME/.local/bin/copyparty")"
                record_result copyparty installed "$(command -v copyparty 2>/dev/null || echo "$HOME/.local/bin/copyparty")"
            else
                warn "pip install copyparty failed; continuing"
                record_result copyparty failed "pip install failed"
            fi
        fi
    fi

    if is_selected ytdlp; then
        if tp_gate ytdlp; then
            local force_flag=()
            [ "$TP_FORCE" -eq 1 ] && force_flag=(--force-reinstall)
            if python -m pip install --user "${force_flag[@]}" -U yt-dlp; then
                ok "yt-dlp -> $(command -v yt-dlp || echo "$HOME/.local/bin/yt-dlp")"
                record_result ytdlp installed "$(command -v yt-dlp 2>/dev/null || echo "$HOME/.local/bin/yt-dlp")"
            else
                warn "pip install yt-dlp failed; continuing"
                record_result ytdlp failed "pip install failed"
            fi
        fi
    fi

    if is_selected pydf; then
        if tp_gate pydf; then
            local force_flag=()
            [ "$TP_FORCE" -eq 1 ] && force_flag=(--force-reinstall)
            if pip3 install "${force_flag[@]}" -U pydf; then
                ok "pydf -> $(command -v pydf || echo missing)"
                record_result pydf installed "$(command -v pydf 2>/dev/null || echo installed)"
            else
                warn "pip3 install pydf failed; continuing"
                record_result pydf failed "pip install failed"
            fi
        fi
    fi

    if is_selected copyparty || is_selected ytdlp; then
        # shellcheck disable=SC2016  # literal line for ~/.bashrc, must not expand
        ensure_bashrc_line 'PATH="$HOME/.local/bin:$PATH"'
        export PATH="$HOME/.local/bin:$PATH"
    fi
}

install_copyparty_storage() {
    is_selected copyparty || return 0
    if [ "$SETUP_STORAGE" -eq 1 ] && [ ! -d "$HOME/storage" ]; then
        progress "Requesting shared-storage access (termux-setup-storage)"
        termux-setup-storage >/dev/null 2>&1 \
            || warn "termux-setup-storage skipped or denied; run it manually later"
    fi
}

install_shizuku_tools() {
    is_selected shizuku || return 0
    tp_gate shizuku || return 0
    # TP_FORCE=1 after an explicit menu tick on a green tool: pull + setup.sh
    # rerun is the reinstall path (both are idempotent).

    step "Installing termux-shizuku-tools"

    if [ -d "$SHIZUKU_DIR/.git" ]; then
        progress "Existing checkout found; updating"
        git -C "$SHIZUKU_DIR" pull --ff-only || warn "git pull failed; using existing checkout"
    else
        progress "Cloning $REPO_SHIZUKU"
        if ! git clone --depth=1 "$REPO_SHIZUKU" "$SHIZUKU_DIR"; then
            warn "Failed to clone termux-shizuku-tools; continuing"
            record_result shizuku failed "git clone failed"
            return 0
        fi
    fi

    chmod +x "$SHIZUKU_DIR/setup.sh"
    progress "Running setup.sh (installs rish, symlinks, AI-tool helpers)"

    # setup.sh runs `pip install anthropic google-genai requests`. Neither jiter
    # nor pydantic-core ships an Android wheel, so pip compiles them from source
    # with the rust toolchain. CARGO_BUILD_JOBS=1 avoids the Android "Text file
    # busy" race when cargo runs freshly written build scripts (seen with
    # pydantic-core under parallel builds).
    if [ ! "$(command -v rustc 2>/dev/null)" ]; then
        warn "rustc not found; the AI-tool pip step may fail (select the rust tool)"
    fi
    if ( cd "$SHIZUKU_DIR" && CARGO_BUILD_JOBS=1 bash setup.sh ); then
        ok "setup.sh completed"
    else
        warn "termux-shizuku-tools setup.sh reported errors (rish/env/symlinks may still be usable)"
    fi

    # shellcheck disable=SC2016  # literal line for ~/.bashrc, must not expand
    ensure_bashrc_line 'export PATH=$PATH:~/bin'
    ensure_bashrc_line '[ -f ~/.shizuku_env ] && source ~/.shizuku_env'

    ok "termux-shizuku-tools installed at $SHIZUKU_DIR"
    if [ "$TP_FORCE" -eq 1 ]; then
        record_result shizuku updated "$SHIZUKU_DIR"
    else
        record_result shizuku installed "$SHIZUKU_DIR"
    fi
}

install_rish() {
    is_selected rish || return 0
    tp_gate rish || return 0

    step "Installing rish (merbah3266/rish_installer)"

    command -v curl >/dev/null 2>&1 || die "curl is required to install rish"
    command -v bash >/dev/null 2>&1 || die "bash is required to install rish"

    # Run after termux-shizuku-tools so this installer's rish wins if both
    # components are selected; it extracts the real rish from the Shizuku APK
    # and patches it for this terminal's Android package.
    local -a flags=()
    # TP_FORCE=1 after an explicit menu tick on a green tool.
    if [ "$TP_FORCE" -eq 1 ] || [ -e "$PREFIX/bin/rish" ] || [ -e "$HOME/rish" ]; then
        progress "Passing --reinstall to the rish installer"
        flags+=(--reinstall)
    fi

    local tmp
    tmp=$(mktemp) || die "mktemp failed"
    register_temp "$tmp"
    if ! curl -fsSL --max-time "$DOWNLOAD_TIMEOUT" --connect-timeout "$NET_CONNECT_TIMEOUT" "$REPO_RISH_INSTALL" -o "$tmp"; then
        rm -f "$tmp"
        warn "Failed to download rish_installer.sh; continuing"
        record_result rish failed "download failed"
        return 0
    fi

    # Interactive menu picks the APK source; silent mode uses the recommended
    # default (extract from the installed Shizuku app, else latest GitHub
    # release). -y also forces silent: an unattended run must not prompt.
    if ! is_interactive; then
        progress "Running rish installer silently (source: default)"
        flags+=(--silent --source default)
    else
        info "Follow the rish installer menu to choose a source (offline is recommended)"
    fi

    if ! bash "$tmp" "${flags[@]}"; then
        rm -f "$tmp"
        warn "rish installer failed; continuing"
        record_result rish failed "upstream installer failed"
        return 0
    fi
    rm -f "$tmp"

    if [ -e "$PREFIX/bin/rish" ]; then
        ok "rish installed -> $PREFIX/bin/rish"
        record_result rish installed "$PREFIX/bin/rish"
    elif [ -e "$HOME/rish" ]; then
        ok "rish installed -> $HOME/rish"
        record_result rish installed "$HOME/rish"
    else
        warn "rish not found after install; check the installer output above"
        record_result rish failed "rish binary missing after install"
    fi
    info "Requires the Shizuku app running and this terminal authorized in it"
}

install_core() {
    is_selected core || return 0
    tp_gate core || return 0

    step "Installing core (core-termux)"

    # A dangling symlink (link present, target gone — e.g. pointing into a
    # deleted clone) explains a red [link target missing] row: say so, then
    # fall through to the official installer, which re-links correctly.
    if dangling_link "$PREFIX/bin/core"; then
        warn "Removing stale core link (target missing: $(readlink "$PREFIX/bin/core"))"
        rm -f "$PREFIX/bin/core"
    fi

    # TP_FORCE=1 after an explicit menu tick on a green tool: rerun the
    # upstream installer instead of taking the already-installed shortcut.
    # install_core needs the -x check (not just tp_installed): the binary must
    # be executable for the `core install` calls below to work.
    if [ "$TP_FORCE" -eq 0 ] && [ -x "$PREFIX/bin/core" ]; then
        ok "core already installed: $PREFIX/bin/core"
        return
    fi

    command -v curl >/dev/null 2>&1 || die "curl is required to install core-termux"
    progress "Downloading official core-termux installer"
    local tmp
    tmp=$(mktemp) || die "mktemp failed"
    register_temp "$tmp"
    if ! curl -fsSL --max-time "$DOWNLOAD_TIMEOUT" --connect-timeout "$NET_CONNECT_TIMEOUT" "$REPO_CORE_INSTALL" -o "$tmp" \
        || [ ! -s "$tmp" ]; then
        rm -f "$tmp"
        warn "Failed to download core-termux installer; continuing"
        record_result core failed "download failed"
        return 0
    fi
    progress "Running official core-termux installer"
    if ! bash "$tmp"; then
        rm -f "$tmp"
        warn "core-termux installer failed; continuing"
        record_result core failed "upstream installer failed"
        return 0
    fi
    rm -f "$tmp"

    if [ -e "$PREFIX/bin/core" ]; then
        ok "core installed (run: core)"
        record_result core installed "$PREFIX/bin/core"
    else
        warn "core command not found after install; check the installer output above"
        record_result core failed "core binary missing after install"
    fi
}

install_kilocode() {
    is_selected kilocode || return 0
    tp_gate kilocode || return 0

    step "Installing kilocode-cli via core (core install ai --kilocode-cli)"

    # TP_FORCE=1 after an explicit menu tick on a green tool: rerun the core
    # installer instead of taking the already-installed shortcut.
    if [ "$TP_FORCE" -eq 0 ] && command -v kilocode >/dev/null 2>&1; then
        ok "kilocode already installed -> $(command -v kilocode)"
        return
    fi

    # kilocode depends on core: if core failed, skip instead of attempting.
    if [ -n "${RESULT[core]:-}" ]; then
        case "${RESULT[core]}" in
            failed*)
                warn "kilocode skipped (needs core, which failed)"
                record_result kilocode skipped "needs core"
                return 0 ;;
        esac
    fi
    if ! command -v core >/dev/null 2>&1; then
        warn "core is required to install kilocode-cli; skipping"
        record_result kilocode skipped "needs core"
        return 0
    fi

    # core's installer shows an interactive menu (native / native+proot / proot-distro).
    # Option 0 ("glibc (recommended)") is the default; an empty keypress (Enter) selects it.
    if [ "$KILOCODE_NATIVE" -eq 1 ] || ! is_interactive; then
        progress "Selecting recommended 'glibc (recommended)' method non-interactively"
        if ! printf '\n' | TERM="${TERM:-xterm-256color}" core install ai --kilocode-cli; then
            warn "core install ai --kilocode-cli failed; continuing"
            record_result kilocode failed "core install failed"
            return 0
        fi
    else
        info "Follow the on-screen prompt to choose an install method"
        if ! core install ai --kilocode-cli; then
            warn "core install ai --kilocode-cli failed; continuing"
            record_result kilocode failed "core install failed"
            return 0
        fi
    fi

    if command -v kilocode >/dev/null 2>&1; then
        ok "kilocode-cli installed (commands: kilocode, kilo)"
        record_result kilocode installed "$(command -v kilocode)"
    else
        warn "kilocode command not found after install; check output above"
        record_result kilocode failed "kilocode binary missing after install"
    fi
}

# Human-readable size for byte counts (B/KB/MB/GB with one decimal).
human_size() {
    local b="${1:-0}"
    case "$b" in ''|*[!0-9]*) b=0 ;; esac
    if [ "$b" -ge 1073741824 ]; then
        awk -v b="$b" 'BEGIN{printf "%.1f GB", b/1073741824}'
    elif [ "$b" -ge 1048576 ]; then
        awk -v b="$b" 'BEGIN{printf "%.1f MB", b/1048576}'
    elif [ "$b" -ge 1024 ]; then
        awk -v b="$b" 'BEGIN{printf "%.1f KB", b/1024}'
    else
        printf '%s B' "$b"
    fi
}

# Remove install stubs + caches left behind by the 3rd-party stages. Exactly
# what goes: pip/uv caches, pip temp build dirs, apt archives (apt clean),
# cargo registry + rustup tmp, go build/test cache, npm cache + ~/.npm,
# tool-owned temp stubs (core-*, rish*), and __pycache__/*.pyc inside the
# tool lib dirs. Never touches installed tools, other programs' temp files,
# or the go module cache (re-downloading modules is expensive on mobile).
# Size of exactly what the cleanup's pyc step deletes: __pycache__ dirs plus
# stray *.pyc files outside them, under the two lib trees. One helper for the
# before/after figures so they cannot drift apart. Grand total via du -cb;
# empty input prints nothing, so default to 0 (never du's cwd size).
pyc_size() {
    local out
    out=$(find "$HOME/.local/lib" "$SHIZUKU_DIR" \
        \( -type d -name '__pycache__' -print \) -o \
        \( -type f -name '*.pyc' -print \) 2>/dev/null \
        | tr '\n' '\0' | du -cb --files0-from=- 2>/dev/null | tail -1 | awk '{print $1}')
    case "$out" in ''|*[!0-9]*) out=0 ;; esac
    printf '%s' "$out"
}

cleanup_stubs() {
    [ "$CLEANUP" -eq 1 ] || return 0

    step "Cleaning up install stubs + caches"

    # Measure the reclaimable size in advance: du over exactly the paths the
    # pass removes (existing ones only), so the figure is the cleanup's own
    # footprint. The two lib trees contribute only their pyc portion.
    local tmpd="${TMPDIR:-$PREFIX/tmp}"
    local -a _cl=()
    local _p _pipdir
    for _p in "$HOME/.cache/pip" "$HOME/.cache/uv" "$HOME/.npm" \
              "$HOME/.cache/go-build" "$HOME/.cargo/registry" \
              "$HOME/.rustup/tmp" "$PREFIX/var/cache/apt/archives"; do
        if [ -n "$_p" ] && [ -e "$_p" ]; then _cl+=("$_p"); fi
    done
    if [ -n "${CARGO_HOME:-}" ] && [ -e "$CARGO_HOME/registry" ]; then
        _cl+=("$CARGO_HOME/registry")
    fi
    for _p in "$tmpd"/pip-* "$tmpd"/pip_build_* \
              "$tmpd"/core-* "$tmpd"/rish*; do
        # Globs that match nothing stay literal: keep only existing paths.
        if [ -e "$_p" ]; then _cl+=("$_p"); fi
    done
    # Registered temp paths from this run (task 6 registry).
    local _rp
    for _rp in "${TEMP_PATHS[@]}"; do
        if [ -e "$_rp" ]; then _cl+=("$_rp"); fi
    done
    if command -v pip >/dev/null 2>&1; then
        _pipdir=$(pip cache dir 2>/dev/null)
        if [ -n "$_pipdir" ] && [ -e "$_pipdir" ]; then _cl+=("$_pipdir"); fi
    fi
    local reclaim=0 _sz
    if [ "${#_cl[@]}" -gt 0 ]; then
        _sz=$(du -cb "${_cl[@]}" 2>/dev/null | tail -1 | awk '{print $1}')
        case "$_sz" in ''|*[!0-9]*) _sz=0 ;; esac
        reclaim=$((reclaim + _sz))
    fi
    reclaim=$((reclaim + $(pyc_size)))

    if [ "$reclaim" -gt 0 ]; then
        progress "Reclaimable: $(human_size "$reclaim") — removing now..."
    else
        progress "Nothing reclaimable found — verifying..."
    fi

    if command -v pip >/dev/null 2>&1; then
        pip cache purge >/dev/null 2>&1 || info "pip cache: nothing to purge"
    fi
    if command -v pip3 >/dev/null 2>&1; then
        pip3 cache purge >/dev/null 2>&1 || true
    fi
    # pip build dirs outside the cache (wheels, isolated-build envs, uv cache).
    rm -rf "$HOME/.cache/pip" "$HOME/.cache/uv" \
        "$tmpd"/pip-* "$tmpd"/pip_build_* 2>/dev/null || true
    info "pip/uv caches cleared"

    if command -v apt >/dev/null 2>&1; then
        if DEBIAN_FRONTEND=noninteractive apt clean -y >/dev/null 2>&1; then
            info "apt archives cleared"
        else
            warn "apt clean reported errors"
        fi
    fi

    # Compiler caches from source-built extensions (jiter/pydantic-core via shizuku).
    # ~/.cargo/registry (cache + src + index) is fully re-downloadable: cargo
    # re-fetches it on the next build, so wiping it only costs a re-download.
    rm -rf "$HOME/.cache/pip" "$HOME/.cargo/registry" "$HOME/.rustup/tmp" 2>/dev/null || true
    if [ -n "${CARGO_HOME:-}" ]; then
        rm -rf "$CARGO_HOME/registry" 2>/dev/null || true
    fi
    if command -v cargo >/dev/null 2>&1; then
        cargo cache -a >/dev/null 2>&1 || true
    fi
    # Build + test cache only: keep the module cache (no -modcache).
    if command -v go >/dev/null 2>&1; then
        go clean -cache -testcache >/dev/null 2>&1 \
            || rm -rf "$HOME/.cache/go-build" 2>/dev/null || true
    else
        rm -rf "$HOME/.cache/go-build" 2>/dev/null || true
    fi
    info "cargo/go build caches cleared"

    # Node/npm (core installer) and core-termux temp clones.
    if command -v npm >/dev/null 2>&1; then
        npm cache clean --force >/dev/null 2>&1 || true
    fi
    rm -rf "$HOME/.npm" "$tmpd"/core-* "$tmpd"/rish* 2>/dev/null || true
    info "npm/core temp stubs cleared"

    # Stale .pyc / __pycache__ shipped inside the tool dirs (regenerated on use).
    find "$HOME/.local/lib" "$SHIZUKU_DIR" -type d -name '__pycache__' -prune -exec rm -rf {} + 2>/dev/null || true
    find "$HOME/.local/lib" "$SHIZUKU_DIR" -type f -name '*.pyc' -delete 2>/dev/null || true
    info "compile caches (__pycache__/*.pyc) cleared"

    local freed_after=0 _left _pyc_left
    if [ "${#_cl[@]}" -gt 0 ]; then
        _left=$(du -cb "${_cl[@]}" 2>/dev/null | tail -1 | awk '{print $1}')
        case "$_left" in ''|*[!0-9]*) _left=0 ;; esac
    else
        _left=0
    fi
    _pyc_left=$(pyc_size)
    freed_after=$((reclaim > _left + _pyc_left ? reclaim - _left - _pyc_left : 0))
    if [ "$reclaim" -gt 0 ]; then
        ok "cleanup freed $(human_size "$freed_after") (estimated $(human_size "$reclaim"))"
    else
        ok "cleanup finished — nothing to remove"
    fi
}

print_summary() {
    done_step "Installation complete (tmx2tm.sh v$SCRIPT_VERSION)"
    local c st detail
    echo
    printf '  %sInstalled tools%s\n' "$C_OK" "$C_RESET"
    for c in "${ALL_COMPONENTS[@]}"; do
        [ -n "${RESULT[$c]:-}" ] || continue
        st="${RESULT[$c]%%|*}"
        case "$st" in
            installed|updated)
                printf '    %-14s %s\n' "$c" "${COMP_HINT[$c]}" ;;
        esac
    done

    echo
    printf '  %sSkipped%s\n' "$C_YELLOW" "$C_RESET"
    local any_skip=0
    for c in "${ALL_COMPONENTS[@]}"; do
        [ -n "${RESULT[$c]:-}" ] || continue
        st="${RESULT[$c]%%|*}"; detail="${RESULT[$c]#*|}"
        case "$st" in
            skipped|broken)
                printf '    %-14s %s\n' "$c" "$detail"
                any_skip=1 ;;
        esac
    done
    [ "$any_skip" -eq 0 ] && printf '    %s(none)%s\n' "$C_DIM" "$C_RESET"

    echo
    printf '  %sFailed%s\n' "$C_ERR" "$C_RESET"
    local any_fail=0
    for c in "${ALL_COMPONENTS[@]}"; do
        [ -n "${RESULT[$c]:-}" ] || continue
        st="${RESULT[$c]%%|*}"; detail="${RESULT[$c]#*|}"
        if [ "$st" = "failed" ]; then
            printf '    %-14s %s\n' "$c" "$detail"
            any_fail=1
        fi
    done
    [ "$any_fail" -eq 0 ] && printf '    %s(none)%s\n' "$C_DIM" "$C_RESET"

    echo
    printf '  %sNext steps%s\n' "$C_OK" "$C_RESET"
    local n=1
    printf '    %d. Reload your shell:  %ssource ~/.bashrc%s\n' "$n" "$C_DIM" "$C_RESET"
    n=$((n + 1))
    case "${RESULT[shizuku]:-}" in
        installed*|updated*)
            printf '    %d. Start Shizuku on the device, then test: %sshizuku-status%s\n' "$n" "$C_DIM" "$C_RESET"
            n=$((n + 1)) ;;
    esac
    case "${RESULT[core]:-}" in
        installed*|updated*)
            printf '    %d. Explore core modules: %score list%s\n' "$n" "$C_DIM" "$C_RESET"
            n=$((n + 1)) ;;
    esac
    echo
}

# ------------------------------------------------- kilo settings backup ----
# Snapshot of the current Kilo / kilocode settings, login tokens, and chat
# sessions. Kept OUT of the script so the installer never embeds live
# credentials. kilo-rc.db (message history, ~28MB live SQLite db) is
# deliberately excluded: it is rebuilt on the new device, and copying a live
# database across devices risks lock/version issues.
kilo_backup_files() {
    local -a files=()
    [ -f "$KILO_CONFIG_DIR/kilo.jsonc" ] && files+=(".config/kilo/kilo.jsonc")
    [ -f "$KILO_DATA_DIR/auth.json" ]    && files+=(".local/share/kilo/auth.json")
    [ -f "$KILO_STATE_DIR/model.json" ]  && files+=(".local/state/kilo/model.json")
    # Chat sessions: per-session diff/share payloads plus the active-session
    # pointer and prompt history (~75KB total).
    [ -d "$KILO_DATA_DIR/storage" ]              && files+=(".local/share/kilo/storage")
    [ -f "$KILO_STATE_DIR/session.json" ]        && files+=(".local/state/kilo/session.json")
    [ -f "$KILO_STATE_DIR/prompt-history.jsonl" ] && files+=(".local/state/kilo/prompt-history.jsonl")
    [ "${#files[@]}" -gt 0 ] || return 0
    printf '%s\n' "${files[@]}"
}

save_kilo() {
    local out="${1:-$DEFAULT_KILO_BACKUP}"
    local -a files
    mapfile -t files < <(kilo_backup_files)

    if [ "${#files[@]}" -eq 0 ]; then
        warn "No Kilo settings found (looked in $KILO_CONFIG_DIR, $KILO_DATA_DIR, $KILO_STATE_DIR)"
        return 1
    fi

    step "Backing up Kilo settings and login tokens"
    if ! ( umask 077; tar -czf "$out" -C "$HOME" "${files[@]}" ); then
        warn "Failed to write backup: $out"
        return 1
    fi
    chmod 600 "$out"

    ok "Backup written: $out"
    info "Included: ${files[*]}"
    warn "This archive contains live login tokens - keep it private and out of git."
    return 0
}

restore_kilo() {
    local in="${1:-$DEFAULT_KILO_BACKUP}"
    [ -f "$in" ] || die "Kilo backup not found: $in (create one with --save-kilo)"

    # Defense against a wrong or hostile archive: only the exact members we
    # produce are allowed, so nothing can be written outside the kilo dirs.
    # The storage/ directory matches by prefix (it contains per-session files).
    # Additionally refuse any non-regular/non-directory entry (symlinks, hard
    # links, devices): a symlink member followed by a file written through it
    # is a known extraction trick.
    tar -tzf "$in" >/dev/null 2>&1 || die "Not a valid tar.gz backup: $in"
    local member bad_members="" typ
    while IFS= read -r member; do
        case "$member" in
            .config/kilo/kilo.jsonc|.local/share/kilo/auth.json|.local/state/kilo/model.json|.local/state/kilo/session.json|.local/state/kilo/prompt-history.jsonl|.local/share/kilo/storage|.local/share/kilo/storage/*) ;;
            *) bad_members+="$member " ;;
        esac
    done < <(tar -tzf "$in")
    if [ -n "$bad_members" ]; then
        die "Refusing to restore: unexpected archive entries: $bad_members"
    fi
    while read -r typ _; do
        case "$typ" in
            -|d) ;;
            *) die "Refusing to restore: archive contains a non-regular/non-directory entry (type '$typ')" ;;
        esac
    done < <(tar -tvzf "$in" 2>/dev/null | awk '{print $1}')

    step "Restoring Kilo settings from $in"
    mkdir -p "$KILO_CONFIG_DIR" "$KILO_DATA_DIR" "$KILO_STATE_DIR"
    tar --no-same-owner -xzf "$in" -C "$HOME" || die "Failed to extract backup: $in"

    # Re-assert owner-only permissions on the secrets we just restored.
    [ -f "$KILO_DATA_DIR/auth.json" ]    && chmod 600 "$KILO_DATA_DIR/auth.json"
    [ -f "$KILO_CONFIG_DIR/kilo.jsonc" ] && chmod 600 "$KILO_CONFIG_DIR/kilo.jsonc"
    [ -f "$KILO_STATE_DIR/model.json" ]  && chmod 600 "$KILO_STATE_DIR/model.json"

    ok "Kilo settings restored -> $KILO_CONFIG_DIR, $KILO_DATA_DIR, $KILO_STATE_DIR"
}

# ------------------------------------------------------------------ main ----
main() {
    require_termux

    # Backup is a standalone action.
    if [ "$SAVE_KILO" -eq 1 ]; then
        if [ "$RESTORE_KILO" -eq 1 ]; then
            warn "Both --save-kilo and --restore-kilo given; the backup wins and the restore is skipped."
        fi
        save_kilo "$KILO_SAVE_PATH"
        exit $?
    fi

    # Restore early, then continue into the normal install flow.
    if [ "$RESTORE_KILO" -eq 1 ]; then
        restore_kilo "$KILO_RESTORE_PATH"
    fi

    if [ "$SHOW_MENU" = force ] \
       || { [ "$SHOW_MENU" = auto ] && [ -t 0 ] && [ -t 1 ]; }; then
        show_menu
    fi

    announce "Starting installation - packages are downloaded and some are built from source; the display can pause for a while. Please wait..."
    # Shell snippet sync, unconditional on every run including cleanup-only:
    # binary present -> snippet ensured; binary absent -> snippet removed so
    # uninstalled tools leave no trace. Starship syncs both rc files; neofetch
    # is profile-only. The syncs set RC_CHANGED=1 when they add or remove
    # anything, so main can mark the moment with a step header only when
    # needed. (A second pass after the install stages re-adds snippets for
    # tools installed during this run.)
    RC_CHANGED=0
    setup_starship_init
    setup_neofetch_init
    if [ "$RC_CHANGED" -eq 1 ]; then
        sync_step "Shell snippets synced"
        RC_CHANGED=0
    fi
    local any_tool=0 c
    for c in "${ALL_COMPONENTS[@]}"; do is_selected "$c" && any_tool=1; done
    if [ "$any_tool" -eq 0 ]; then
        # Cleanup-only run (user ticked just the cleanup option): skip all
        # install stages and go straight to the cleanup pass.
        info "No tools selected — running cleanup only"
        cleanup_stubs
        exit 0
    fi
    update_apt
    install_base_deps
    # Non-menu runs never opened the menu, so no probe has run yet: probe both
    # groups now (after apt update, so "latest" is judged on a fresh index).
    # Menu runs reuse the pre-menu probe, refreshed by the 'u' action.
    if [ "$MENU_CONFIRMED" -eq 0 ]; then
        announce "Probing installed tools, please wait..."
        check_connectivity
        probe_pkg_status
        probe_tp_status
    fi
    install_pkg_tools
    install_pip_tools
    install_copyparty_storage
    install_shizuku_tools
    install_rish
    install_core
    install_kilocode
    # Post-install sync: tools just installed now have binaries, so ensure
    # their snippets (the early sync only handled removals + pre-installed).
    RC_CHANGED=0
    setup_starship_init
    setup_neofetch_init
    if [ "$RC_CHANGED" -eq 1 ]; then
        sync_step "Shell snippets synced"
    fi
    cleanup_stubs
    print_summary
    # Exit code for scripted -y runs: 0 when everything succeeded or was
    # skipped, 2 when any selected tool failed (others still ran).
    local tag st
    for tag in "${ALL_COMPONENTS[@]}"; do
        st="${RESULT[$tag]:-}"
        st="${st%%|*}"
        if [ "$st" = "failed" ]; then
            exit 2
        fi
    done
    exit 0
}

main

# =============================================================================
# See README.md for full documentation (usage, components, stages, workflows).
# =============================================================================
