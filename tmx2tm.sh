#!/data/data/com.termux/files/usr/bin/bash
#
# tmx2tm.sh
# Fresh-install installer for a new Termux instance.
#
# Run directly from git (downloads the script to a temp file, then runs it
# with your own shell, so all flags work and stdin stays usable):
#
#   curl -fsSL https://raw.githubusercontent.com/saitix/tmx2tm/main/tmx2tm.sh -o /tmp/tmx2tm.sh && bash /tmp/tmx2tm.sh
#   curl -fsSL https://raw.githubusercontent.com/saitix/tmx2tm/main/tmx2tm.sh -o /tmp/tmx2tm.sh && bash /tmp/tmx2tm.sh -y
#
# (Do NOT pipe curl into bash: the script reads stdin for its interactive
# menu, so `curl ... | bash` would break the TUI.)
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

# ---------------------------------------------------------------- config ----
SCRIPT_VERSION="0.9"
REPO_SHIZUKU="https://github.com/jecis-repos/termux-shizuku-tools.git"
REPO_CORE_INSTALL="https://raw.githubusercontent.com/DevCoreXOfficial/core-termux/main/install.sh"
REPO_RISH_INSTALL="https://raw.githubusercontent.com/merbah3266/rish_installer/main/rish_installer.sh"

SHIZUKU_DIR="$HOME/termux-shizuku-tools"
BASHRC="$HOME/.bashrc"
BASH_PROFILE="$HOME/.bash_profile"

# pkg dependencies shared by the complex tools (always installed).
BASE_PKG_DEPS=(
    python termux-api
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
SHOW_MENU=auto   # auto | force | never
SAVE_KILO=0
RESTORE_KILO=0
KILO_SAVE_PATH="$DEFAULT_KILO_BACKUP"
KILO_RESTORE_PATH="$DEFAULT_KILO_BACKUP"

for arg in "$@"; do
    case "$arg" in
        --no-storage)       SETUP_STORAGE=0 ;;
        --no-apt-upgrade)   APT_UPGRADE=0 ;;
        --kilocode-native)  KILOCODE_NATIVE=1 ;;
        --menu)             SHOW_MENU=force ;;
        -y|--yes|--no-menu) SHOW_MENU=never ;;
        --save-kilo)        SAVE_KILO=1 ;;
        --save-kilo=*)      SAVE_KILO=1; KILO_SAVE_PATH="${arg#*=}" ;;
        --restore-kilo)     RESTORE_KILO=1 ;;
        --restore-kilo=*)   RESTORE_KILO=1; KILO_RESTORE_PATH="${arg#*=}" ;;
        -h|--help)
            sed -n '2,/^set -uo pipefail/{/^set -uo pipefail/d;p;}' "$0"
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
            why="${TP_BROKEN_WHY[$1]:-source gone}"
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
# every network call carries a short --max-time and failures fall back to a
# safe verdict instead of hanging. Results land in TP_STATUS (tag -> state)
# with reasons in TP_BROKEN_WHY (tag -> e.g. "source unreachable").
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
# mirror (pkg index freshness). Each curl is capped at 5s; the three run in
# parallel so the worst case is ~5s, and offline fails fast (no route).
check_connectivity() {
    NET_GITHUB=0; NET_PYPI=0; NET_PKG=0
    local tmpnet mirror
    tmpnet=$(mktemp -d 2>/dev/null) || return 0
    ( curl -fsSL --max-time 5 -o /dev/null https://github.com >/dev/null 2>&1 \
        && echo 1 >"$tmpnet/gh" || echo 0 >"$tmpnet/gh" ) &
    ( curl -fsSL --max-time 5 -o /dev/null https://pypi.org/simple/ >/dev/null 2>&1 \
        && echo 1 >"$tmpnet/pypi" || echo 0 >"$tmpnet/pypi" ) &
    mirror=$(apt-cache policy 2>/dev/null | grep -o 'http[^ ]*' | head -1)
    ( [ -n "$mirror" ] && curl -fsSL --max-time 5 -o /dev/null "$mirror" >/dev/null 2>&1 \
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
        pydf)      command -v pydf >/dev/null 2>&1 ;;
        shizuku)   [ -d "$SHIZUKU_DIR/.git" ] ;;
        rish)      [ -e "$PREFIX/bin/rish" ] || [ -e "$HOME/rish" ] ;;
        core)      command -v core >/dev/null 2>&1 ;;
        kilocode)  command -v kilocode >/dev/null 2>&1 ;;
    esac
}

# Upstream git state for owner/repo: ok | unreachable | archived.
# Unreachable = `git ls-remote` failed (repo gone, network down, host down).
# Archived is read from the GitHub API; an API failure (rate limit, offline)
# skips the archived check instead of crying wolf — reachability already
# covered the offline case.
tp_git_repo_state() {
    git ls-remote "https://github.com/$1.git" HEAD >/dev/null 2>&1 \
        || { echo unreachable; return; }
    local archived
    archived=$(curl -fsSL --max-time 8 "https://api.github.com/repos/$1" 2>/dev/null \
        | grep -o '"archived": *[a-z]*' | awk '{print $2}')
    if [ "$archived" = "true" ]; then echo archived; else echo ok; fi
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
    latest=$(pip index versions "$pkg" 2>/dev/null \
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
    if curl -fsSL --max-time 8 "https://pypi.org/simple/$pkg/" >/dev/null 2>&1; then
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
        remote_head=$(git ls-remote "https://github.com/$repo.git" HEAD 2>/dev/null | awk '{print $1}')
        if [ -z "$remote_head" ]; then
            printf 'broken\nsource unreachable\n'
            return
        fi
        local_head=$(git -C "$SHIZUKU_DIR" rev-parse HEAD 2>/dev/null)
        state="$(tp_git_repo_state "$repo")"
        if [ "$state" = "archived" ]; then
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
                printf 'broken\nlink target missing\n'
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
# by the per-call --max-time flags inside the probes.
probe_tp_status() {
    TP_STATUS=()
    TP_BROKEN_WHY=()
    local tmpdir c
    tmpdir=$(mktemp -d 2>/dev/null) || { warn "Cannot create temp dir for probe"; return 1; }
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

# Gate for a 3rd-party install stage. Sets TP_FORCE (0/1). Returns 0 = proceed
# (fresh install, update, or forced reinstall of a green tool after an explicit
# menu tick), 1 = skip (green tool in a non-menu run, or broken source).
# Broken + selected never dies mid-run: warn and skip instead.
TP_FORCE=0
tp_gate() {
    local tag="$1"
    TP_FORCE=0
    ensure_tp_status
    case "${TP_STATUS[$tag]:-missing}" in
        current)
            if [ "$MENU_CONFIRMED" -eq 1 ]; then TP_FORCE=1; return 0; fi
            info "'$tag' already installed (latest), skipping"
            return 1 ;;
        broken)
            warn "'$tag' skipped (${TP_BROKEN_WHY[$tag]:-source gone})"
            return 1 ;;
        *) return 0 ;;
    esac
}

# Append a line to ~/.bashrc only if it is not already present.
ensure_bashrc_line() {
    local line="$1"
    if ! grep -qxF "$line" "$BASHRC" 2>/dev/null; then
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
TUI_EXTRA_KEYS=()
TUI_EXTRA_DESCS=()
TUI_EXTRA_BUSY=()
TUI_EXTRA_FNS=()
TUI_EXTRA_STYLE=()
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
    local legend_lines=0
    [ -n "${TUI_LEGEND:-}" ] && legend_lines=1
    local lines=$((n + 3 + extra + legend_lines))   # title + items + 2 help lines (+ legend + one per extra key)
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
        _tui_line "$C_KEY" 'a' "$C_DIM" ' all  ' "$C_KEY" 'Enter' "$C_DIM" ' confirm  ' "$C_KEY" 'q' "$C_DIM" ' quit'
        if [ -n "${TUI_LEGEND:-}" ]; then
            _tui_line "$C_OK" 'green' "$C_DIM" ' = installed  ' "$C_YELLOW" 'yellow' "$C_DIM" ' = update+  ' "$C_ERR" 'red' "$C_DIM" ' = source gone'
        fi
            local ei estyle=""
            for ((ei = 0; ei < extra; ei++)); do
                [ "${#TUI_EXTRA_STYLE[@]}" -gt "$ei" ] && estyle="${TUI_EXTRA_STYLE[$ei]}"
                if [ -n "$estyle" ]; then
                    _tui_line "$estyle" "${TUI_EXTRA_KEYS[$ei]} ${TUI_EXTRA_DESCS[$ei]}"
                else
                    _tui_line "$C_KEY" "${TUI_EXTRA_KEYS[$ei]}" "$C_DIM" " ${TUI_EXTRA_DESCS[$ei]}"
                fi
            done
    }

    _tui_clear() { printf '\033[%dA\033[J' "$lines"; }

    # Move the cursor by $1 rows, skipping separator headers.
    _tui_move() {
        local d="$1"
        local j=$((cur + d))
        while [ "$j" -ge 0 ] && [ "$j" -lt "$n" ] && [ "${kinds[$j]}" = sep ]; do j=$((j + d)); done
        if [ "$j" -ge 0 ] && [ "$j" -lt "$n" ]; then
            cur=$j
            changed=1
        fi
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
                # Let the caller refresh per-item state (e.g. pkg status colors
                # after the 'u' update action) before the menu redraws.
                if [ -n "$TUI_REFRESH_FN" ]; then
                    "$TUI_REFRESH_FN"
                fi
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
                local all_on=1
                for ((i = 0; i < n; i++)); do
                    [ "${kinds[$i]}" = item ] || continue
                    [ "${states[$i]}" = on ] || all_on=0
                done
                local target=on
                [ "$all_on" -eq 1 ] && target=off
                for ((i = 0; i < n; i++)); do
                    [ "${kinds[$i]}" = item ] || continue
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
# is actually present. Runs in a subshell (the caller captures its output), so
# the SELECTED mutations below do not leak into the menu state.
menu_update_tools() {
    export TERM="${TERM:-xterm-256color}"

    local -A on=()
    local c
    for c in ${TUI_ON_TAGS:-}; do on[$c]=1; done

    step "Updating pkg packages (pkg update && pkg upgrade)"
    pkg update -y  || warn "pkg update reported errors; continuing"
    pkg upgrade -y || warn "pkg upgrade reported errors; continuing"
    ok "pkg packages updated"

    step "Updating selected 3rd-party tools"
    local any=0

    if [ -n "${on[copyparty]:-}" ] \
       && { command -v copyparty >/dev/null 2>&1 || [ -x "$HOME/.local/bin/copyparty" ]; }; then
        any=1
        if python -m pip install --user -U copyparty >/dev/null; then
            ok "copyparty updated"
        else
            warn "copyparty update failed"
        fi
    fi

    if [ -n "${on[ytdlp]:-}" ] \
       && { command -v yt-dlp >/dev/null 2>&1 || [ -x "$HOME/.local/bin/yt-dlp" ]; }; then
        any=1
        if python -m pip install --user -U yt-dlp >/dev/null; then
            ok "yt-dlp updated"
        else
            warn "yt-dlp update failed"
        fi
    fi

    if [ -n "${on[pydf]:-}" ] && command -v pydf >/dev/null 2>&1; then
        any=1
        if pip3 install -U pydf >/dev/null; then
            ok "pydf updated"
        else
            warn "pydf update failed"
        fi
    fi

    if [ -n "${on[shizuku]:-}" ] && [ -d "$SHIZUKU_DIR/.git" ]; then
        any=1
        if git -C "$SHIZUKU_DIR" pull --ff-only \
           && ( cd "$SHIZUKU_DIR" && CARGO_BUILD_JOBS=1 bash setup.sh ); then
            ok "termux-shizuku-tools updated"
        else
            warn "termux-shizuku-tools update reported errors"
        fi
    fi

    if [ -n "${on[rish]:-}" ] && { [ -e "$PREFIX/bin/rish" ] || [ -e "$HOME/rish" ]; }; then
        any=1
        local tmp
        tmp=$(mktemp) || tmp=""
        # Force the non-interactive path: the output is captured below this menu.
        if [ -n "$tmp" ] && curl -fsSL "$REPO_RISH_INSTALL" -o "$tmp" \
           && bash "$tmp" --reinstall --silent --source default; then
            ok "rish updated"
        else
            warn "rish update failed"
        fi
        [ -n "$tmp" ] && rm -f "$tmp"
    fi

    if [ -n "${on[core]:-}" ] && command -v core >/dev/null 2>&1; then
        any=1
        if core update core; then
            ok "core-termux updated"
        else
            warn "core update reported errors"
        fi
    fi

    if [ -n "${on[kilocode]:-}" ] && command -v kilocode >/dev/null 2>&1; then
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
refresh_menu_colors() {
    local i=0
    TUI_ITEM_COLOR=()
    TUI_ITEM_COLOR[i]=""; ((i++)) || true                                   # sep: 3rd-party tools
    for _c in "${THIRD_PARTY_COMPONENTS[@]}"; do TUI_ITEM_COLOR[i]="$(menu_item_color "$_c")"; ((i++)) || true; done
    TUI_ITEM_COLOR[i]=""; ((i++)) || true                                   # sep: pkg tools
    for _c in "${PKG_TOOL_COMPONENTS[@]}"; do TUI_ITEM_COLOR[i]="$(menu_item_color "$_c")"; ((i++)) || true; done
    TUI_ITEM_COLOR[i]=""; ((i++)) || true                                   # sep: options
    TUI_ITEM_COLOR[i]=""; ((i++)) || true                                   # apt_upgrade option
    TUI_ITEM_COLOR[i]=""; ((i++)) || true                                   # no_storage option
    TUI_ITEM_COLOR[i]=""; ((i++)) || true                                   # kilocode_native option
}

# Re-probe all statuses and rebuild row colors, suffixes, and toggles. Wired
# as TUI_REFRESH_FN so the menu refreshes right after the 'u' action without
# leaving it. Green tools go off (nothing to do), broken tools go off
# (nothing can be done); missing/yellow rows keep the user's toggle.
refresh_menu_status() {
    check_connectivity
    probe_pkg_status
    probe_tp_status
    refresh_menu_colors
    local i st
    for ((i = 0; i < n; i++)); do
        [ "${kinds[$i]}" = item ] || continue
        case " ${ALL_COMPONENTS[*]} " in
            *" ${tags[i]} "*)
                descs[i]="${COMP_DESC[${tags[i]}]}$(comp_suffix "${tags[i]}")"
                st="$(comp_status "${tags[i]}")"
                if [ "$st" = "current" ] || [ "$st" = "broken" ]; then
                    states[i]="off"
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
    items+=("apt_upgrade|OPTION: apt update & upgrade before installing (recommended)|$([ "$APT_UPGRADE" -eq 1 ] && echo on || echo off)")
    items+=("no_storage|OPTION: skip termux-setup-storage (shared storage)|$([ "$SETUP_STORAGE" -eq 0 ] && echo on || echo off)")
    items+=("kilocode_native|OPTION: kilocode - pick recommended native method (no prompt)|$([ "$KILOCODE_NATIVE" -eq 1 ] && echo on || echo off)")

    # Shortcut keys: 's' saves a Kilo backup, 'u' updates what is installed,
    # 'p' installs prerequisites on demand (fresh Termux) and reloads the menu.
    TUI_EXTRA_KEYS=("s" "u")
    TUI_EXTRA_DESCS=("save kilocode backup" "update installed tools")
    TUI_EXTRA_BUSY=("Saving Kilo settings and tokens, please wait..."
                    "Updating installed tools; this can take several minutes...")
    TUI_EXTRA_FNS=("menu_save_kilo" "menu_update_tools")
    TUI_EXTRA_STYLE=("" "")
    if prereqs_missing; then
        TUI_EXTRA_KEYS+=("p")
        TUI_EXTRA_DESCS+=("install prerequisites (recommended on fresh Termux)")
        TUI_EXTRA_BUSY+=("Installing prerequisites; this can take several minutes...")
        TUI_EXTRA_FNS+=("menu_install_prereqs")
        # The prerequisites shortcut is the important one on a fresh Termux:
        # render the whole line in bold white so it stands out.
        TUI_EXTRA_STYLE+=("$C_KEY")
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
        TUI_EXTRA_STYLE=()
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
    if ! tui_checklist "tmx2tm.sh v$SCRIPT_VERSION - select components" result "${items[@]}"; then        echo
        info "Cancelled."
        exit 130
    fi

    TUI_EXTRA_KEYS=()
    TUI_EXTRA_DESCS=()
    TUI_EXTRA_BUSY=()
    TUI_EXTRA_FNS=()
    TUI_EXTRA_STYLE=()
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
    echo "Commands: <numbers> toggle | a = toggle all | s = save kilo backup | u = update installed | <Enter> = confirm | q = quit"
    if prereqs_missing; then
        printf '%s%s%s\n' "$C_KEY" "p = install prerequisites (recommended on fresh Termux)" "$C_RESET"
    fi
    echo "r = zoom out and reload"

    local line t idx
    while true; do
        printf '> '
        IFS= read -r line || { echo; info "Cancelled."; exit 130; }
        case "$line" in
            '') break ;;
            q|Q) info "Cancelled."; exit 130 ;;
            a|A)
                local all_on=1
                for ((i = 0; i < ${#tags[@]}; i++)); do
                    [ -n "${tags[$i]}" ] || continue
                    [ "${states[$i]}" = on ] || all_on=0
                done
                for ((i = 0; i < ${#tags[@]}; i++)); do
                    [ -n "${tags[$i]}" ] || continue
                    if [ "$all_on" -eq 1 ]; then states[i]="off"; else states[i]="on"; fi
                done
                ;;
            s|S) menu_save_kilo ;;
            u|U) menu_update_tools_no_tui ;;
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
    done

    local result=""
    for ((i = 0; i < ${#tags[@]}; i++)); do
        [ -n "${tags[$i]}" ] || continue
        [ "${states[$i]}" = on ] && result+="${tags[$i]} "
    done
    apply_menu_result "${result% }"
}

# Update action variant for the text menu: same updates as the TUI 'u' key,
# but without TUI locals (no TUI_ON_TAGS / redraw). Updates everything that
# is installed, then returns to the text menu loop.
menu_update_tools_no_tui() {
    local TUI_ON_TAGS=""
    local c
    for c in "${ALL_COMPONENTS[@]}"; do TUI_ON_TAGS+="$c "; done
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

    local tag
    for tag in $result; do
        case "$tag" in
            no_storage)      SETUP_STORAGE=0 ;;
            kilocode_native) KILOCODE_NATIVE=1 ;;
            apt_upgrade)     APT_UPGRADE=1 ;;
            *) [ -n "${SELECTED[$tag]:-}" ] && SELECTED[$tag]=1 ;;
        esac
    done

    # kilocode depends on core.
    if is_selected kilocode && ! is_selected core; then
        SELECTED[core]=1
        warn "kilocode needs core; enabling core automatically"
    fi

    # termux-shizuku-tools builds Rust Python extensions (jiter, pydantic-core);
    # without the rust toolchain that pip step aborts the whole setup.
    if is_selected shizuku && ! is_selected rust; then
        SELECTED[rust]=1
        warn "termux-shizuku-tools needs rust; enabling rust automatically"
    fi

    local any=0
    for c in "${ALL_COMPONENTS[@]}"; do is_selected "$c" && any=1; done
    if [ "$any" -eq 0 ]; then
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
    if [ -t 0 ] && [ -t 1 ] && command -v termux-change-repo >/dev/null 2>&1; then
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

    step "Running apt update & upgrade"
    DEBIAN_FRONTEND=noninteractive apt update -y \
        || warn "apt update reported errors; continuing anyway"
    DEBIAN_FRONTEND=noninteractive apt upgrade -y -o Dpkg::Options::="--force-confold" \
        || warn "apt upgrade reported errors; continuing anyway"
    ok "apt update & upgrade finished"
}

install_base_deps() {
    step "Installing base pkg dependencies"
    progress "pkg install: ${BASE_PKG_DEPS[*]}"
    pkg install -y "${BASE_PKG_DEPS[@]}" || die "Failed to install base pkg dependencies"
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
# The snippet evals at most once per shell tree: STARSHIP_START_TIME is set by
# starship's own init on first eval, so a second sourcing (e.g. zellij reading
# .bashrc after .bash_profile already ran) is a no-op instead of a
# double-rendered prompt with double-registered keybindings.
# Sync rule: binary present -> snippet ensured in both files (old unguarded
# form upgraded in place); binary missing (user uninstalled) -> snippet
# removed from both files so shells stay clean. Only touches the files when
# the installer itself runs under bash ($BASH_VERSION is set only by bash).
setup_starship_init() {
    if [ -z "${BASH_VERSION:-}" ]; then
        warn "Installer is not running under bash; skipping starship shell init sync"
        return 0
    fi

    local marker='# Initialize Starship only once, if installed'
    local old_marker='# Initialize Starship only if installed'
    local f
    for f in "$BASH_PROFILE" "$BASHRC"; do
        # Drop the legacy unguarded snippet (4 lines: marker, if, eval, fi)
        # wherever it appears so it is replaced by the guarded form below.
        # shellcheck disable=SC2016  # literal snippet lines, must not expand
        if [ -f "$f" ] && grep -qxF "$old_marker" "$f" 2>/dev/null; then
            grep -vxF -e "$old_marker" \
                      -e 'if command -v starship >/dev/null 2>&1; then' \
                      -e '    eval "$(starship init bash)"' \
                      -e 'fi' "$f" >"$f.tmp" 2>/dev/null && mv "$f.tmp" "$f"
            info "Upgraded legacy starship snippet in $f"
        fi
    done

    if ! command -v starship >/dev/null 2>&1; then
        # User uninstalled starship: remove the snippet from both files so the
        # eval (and its guard) does not linger in new shells.
        local removed=0
        for f in "$BASH_PROFILE" "$BASHRC"; do
            # shellcheck disable=SC2016  # literal snippet lines, must not expand
            if [ -f "$f" ] && grep -qxF "$marker" "$f" 2>/dev/null; then
                grep -vxF -e "$marker" \
                          -e 'if [ -z "$STARSHIP_START_TIME" ] && command -v starship >/dev/null 2>&1; then' \
                          -e '    eval "$(starship init bash)"' \
                          -e 'fi' "$f" >"$f.tmp" 2>/dev/null && mv "$f.tmp" "$f"
                info "Removed starship init from $f (starship not installed)"
                removed=1
            fi
        done
        [ "$removed" -eq 0 ] && info "Starship not installed; nothing to clean up"
        return 0
    fi

    for f in "$BASH_PROFILE" "$BASHRC"; do
        if [ -f "$f" ] && grep -qxF "$marker" "$f" 2>/dev/null; then
            info "Starship init already present in $f"
            continue
        fi
        {
            printf '\n%s\n' "$marker"
            # shellcheck disable=SC2016  # literal snippet for the rc files, must not expand
            printf '%s\n' 'if [ -z "$STARSHIP_START_TIME" ] && command -v starship >/dev/null 2>&1; then'
            # shellcheck disable=SC2016  # literal snippet for the rc files, must not expand
            printf '%s\n' '    eval "$(starship init bash)"'
            printf '%s\n' 'fi'
        } >>"$f"
        info "Added starship init to $f"
    done
    ok "starship -> $(command -v starship)"
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
        if [ "${PKG_STATUS[$c]:-missing}" = "current" ]; then
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
    for c in "${PKG_TOOL_COMPONENTS[@]}"; do
        is_selected "$c" && continue
        if [ "${PKG_STATUS[$c]:-missing}" = "current" ]; then
            skipped+=("$c")
        fi
    done

    if [ "${#skipped[@]}" -gt 0 ]; then
        info "Already installed (latest), skipping: ${skipped[*]}"
    fi
    if [ "${#pkgs[@]}" -gt 0 ]; then
        step "Installing pkg tools"
        progress "pkg install: ${pkgs[*]}"
        pkg install -y "${pkgs[@]}" || die "Failed to install pkg tools"
        ok "pkg tools installed"
    fi
    if [ "${#reinstall_pkgs[@]}" -gt 0 ]; then
        step "Reinstalling explicitly selected pkg tools"
        progress "pkg reinstall: ${reinstall_pkgs[*]}"
        pkg reinstall -y "${reinstall_pkgs[@]}" || die "Failed to reinstall pkg tools"
        ok "pkg tools reinstalled"
    fi
    if [ "${#pkgs[@]}" -eq 0 ] && [ "${#reinstall_pkgs[@]}" -eq 0 ]; then
        info "All selected pkg tools are already installed at the latest version"
    fi

    for c in "${PKG_TOOL_COMPONENTS[@]}"; do
        is_selected "$c" || continue
        bin="${PKG_COMPONENT_CMD[$c]:-$c}"
        ok "$c -> $(command -v "$bin" || echo missing)"
    done

    if is_selected golang; then
        setup_golang_path
    fi

    # Starship snippet sync runs unconditionally (not gated on selection): it
    # ensures the snippet in both rc files when installed, and removes it
    # from both when the user uninstalled starship.
    setup_starship_init
}

install_pip_tools() {
    is_selected copyparty || is_selected ytdlp || is_selected pydf || return 0

    step "Installing Python-based tools"

    python -m ensurepip --upgrade >/dev/null 2>&1 || warn "ensurepip reported issues; continuing"

    if is_selected copyparty; then
        if tp_gate copyparty; then
            # TP_FORCE=1 after an explicit menu tick on a green tool.
            local force_flag=()
            [ "$TP_FORCE" -eq 1 ] && force_flag=(--force-reinstall)
            python -m pip install --user "${force_flag[@]}" -U copyparty || die "pip install copyparty failed"
            ok "copyparty -> $(command -v copyparty || echo "$HOME/.local/bin/copyparty")"
        fi
    fi

    if is_selected ytdlp; then
        if tp_gate ytdlp; then
            local force_flag=()
            [ "$TP_FORCE" -eq 1 ] && force_flag=(--force-reinstall)
            python -m pip install --user "${force_flag[@]}" -U yt-dlp || die "pip install yt-dlp failed"
            ok "yt-dlp -> $(command -v yt-dlp || echo "$HOME/.local/bin/yt-dlp")"
        fi
    fi

    if is_selected pydf; then
        if tp_gate pydf; then
            local force_flag=()
            [ "$TP_FORCE" -eq 1 ] && force_flag=(--force-reinstall)
            pip3 install "${force_flag[@]}" -U pydf || die "pip3 install pydf failed"
            ok "pydf -> $(command -v pydf || echo missing)"
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
        git clone --depth=1 "$REPO_SHIZUKU" "$SHIZUKU_DIR" \
            || die "Failed to clone termux-shizuku-tools"
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
    if ! curl -fsSL "$REPO_RISH_INSTALL" -o "$tmp"; then
        rm -f "$tmp"
        die "Failed to download rish_installer.sh"
    fi

    # Interactive menu picks the APK source; silent mode uses the recommended
    # default (extract from the installed Shizuku app, else latest GitHub release).
    if [ ! -t 0 ]; then
        progress "Running rish installer silently (source: default)"
        flags+=(--silent --source default)
    else
        info "Follow the rish installer menu to choose a source (offline is recommended)"
    fi

    if ! bash "$tmp" "${flags[@]}"; then
        rm -f "$tmp"
        die "rish installer failed"
    fi
    rm -f "$tmp"

    if [ -e "$PREFIX/bin/rish" ]; then
        ok "rish installed -> $PREFIX/bin/rish"
    elif [ -e "$HOME/rish" ]; then
        ok "rish installed -> $HOME/rish"
    else
        warn "rish not found after install; check the installer output above"
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
    if [ "$TP_FORCE" -eq 0 ] && [ -x "$PREFIX/bin/core" ]; then
        ok "core already installed: $PREFIX/bin/core"
        return
    fi

    command -v curl >/dev/null 2>&1 || die "curl is required to install core-termux"
    progress "Running official core-termux installer"
    if ! curl -fsSL "$REPO_CORE_INSTALL" | bash; then
        die "core-termux installer failed"
    fi

    if [ -e "$PREFIX/bin/core" ]; then
        ok "core installed (run: core)"
    else
        warn "core command not found after install; check the installer output above"
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

    command -v core >/dev/null 2>&1 || die "core is required to install kilocode-cli"

    # core's installer shows an interactive menu (native / native+proot / proot-distro).
    # Option 0 ("glibc (recommended)") is the default; an empty keypress (Enter) selects it.
    if [ "$KILOCODE_NATIVE" -eq 1 ] || [ ! -t 0 ]; then
        progress "Selecting recommended 'glibc (recommended)' method non-interactively"
        if ! printf '\n' | TERM="${TERM:-xterm-256color}" core install ai --kilocode-cli; then
            die "core install ai --kilocode-cli failed"
        fi
    else
        info "Follow the on-screen prompt to choose an install method"
        core install ai --kilocode-cli || die "core install ai --kilocode-cli failed"
    fi

    if command -v kilocode >/dev/null 2>&1; then
        ok "kilocode-cli installed (commands: kilocode, kilo)"
    else
        warn "kilocode command not found after install; check output above"
    fi
}

print_summary() {
    done_step "Installation complete (tmx2tm.sh v$SCRIPT_VERSION)"
    echo
    printf '  %sInstalled tools%s\n' "$C_BLUE" "$C_RESET"
    local c
    for c in "${ALL_COMPONENTS[@]}"; do
        is_selected "$c" || continue
        printf '    %-14s %s\n' "$c" "${COMP_HINT[$c]}"
    done

    echo
    printf '  %sNext steps%s\n' "$C_BLUE" "$C_RESET"
    printf '    1. Reload your shell:  %ssource ~/.bashrc%s\n' "$C_DIM" "$C_RESET"
    if is_selected shizuku; then
        printf '    2. Start Shizuku on the device, then test: %sshizuku-status%s\n' "$C_DIM" "$C_RESET"
    fi
    if is_selected core; then
        printf '    3. Explore core modules: %score list%s\n' "$C_DIM" "$C_RESET"
    fi
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
    tar -tzf "$in" >/dev/null 2>&1 || die "Not a valid tar.gz backup: $in"
    local member bad_members=""
    while IFS= read -r member; do
        case "$member" in
            .config/kilo/kilo.jsonc|.local/share/kilo/auth.json|.local/state/kilo/model.json|.local/state/kilo/session.json|.local/state/kilo/prompt-history.jsonl|.local/share/kilo/storage|.local/share/kilo/storage/*) ;;
            *) bad_members+="$member " ;;
        esac
    done < <(tar -tzf "$in")
    if [ -n "$bad_members" ]; then
        die "Refusing to restore: unexpected archive entries: $bad_members"
    fi

    step "Restoring Kilo settings from $in"
    mkdir -p "$KILO_CONFIG_DIR" "$KILO_DATA_DIR" "$KILO_STATE_DIR"
    tar -xzf "$in" -C "$HOME" || die "Failed to extract backup: $in"

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
    print_summary
}

main

# =============================================================================
# See README.md for full documentation (usage, components, stages, workflows).
# =============================================================================
