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
# Version: 0.6
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

step() { printf '\n%s==>%s %s%s%s\n' "$C_BLUE" "$C_RESET" "$C_HL" "$1" "$C_RESET"; }
announce() { printf '\n%s%s%s\n' "$C_PURPLE" "$1" "$C_RESET"; }
info() { printf '    %s%s%s\n' "$C_DIM" "$1" "$C_RESET"; }
ok()   { printf '    %s[ok]%s %s\n' "$C_OK" "$C_RESET" "$1"; }
warn() { printf '    %s[!]%s %s\n' "$C_WARN" "$C_RESET" "$1"; }
die()  { printf '\n%s[ERROR]%s %s\n' "$C_ERR" "$C_RESET" "$1" >&2; exit 1; }

# ---------------------------------------------------------------- config ----
SCRIPT_VERSION="0.6"
REPO_SHIZUKU="https://github.com/jecis-repos/termux-shizuku-tools.git"
REPO_CORE_INSTALL="https://raw.githubusercontent.com/DevCoreXOfficial/core-termux/main/install.sh"
REPO_RISH_INSTALL="https://raw.githubusercontent.com/merbah3266/rish_installer/main/rish_installer.sh"

SHIZUKU_DIR="$HOME/termux-shizuku-tools"
BASHRC="$HOME/.bashrc"

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
PKG_TOOL_COMPONENTS=(bat dig elinks golang mc neofetch ranger rust shellcheck sqlite ssh telnet uv zellij)
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
    [telnet]="telnet <host> <port>"
    [uv]="uv --version"
    [zellij]="zellij"
)

# Runtime state / options.
declare -A SELECTED=()
for _c in "${ALL_COMPONENTS[@]}"; do SELECTED[$_c]=1; done

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
TUI_EXTRA_KEYS=()
TUI_EXTRA_DESCS=()
TUI_EXTRA_BUSY=()
TUI_EXTRA_FNS=()

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
    local lines=$((n + 3 + extra))   # title + items + 2 help lines (+ one per extra key)
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
            local mark="[ ]" line
            [ "${states[$i]}" = on ] && mark="[x]"
            if [ "$i" -eq "$cur" ]; then
                line="> $mark ${descs[$i]}"
                _tui_fit line
                printf '%s%s%s\033[K\n' "$C_BLUE" "$line" "$C_RESET"
            else
                line="  $mark ${descs[$i]}"
                _tui_fit line
                printf '%s%s%s\033[K\n' "$C_DIM" "$line" "$C_RESET"
            fi
        done
        _tui_line "$C_KEY" 'Up' "$C_DIM" '/' "$C_KEY" 'Down' "$C_DIM" ' move  ' "$C_KEY" 'Space' "$C_DIM" ' toggle'
        _tui_line "$C_KEY" 'a' "$C_DIM" ' all  ' "$C_KEY" 'Enter' "$C_DIM" ' confirm  ' "$C_KEY" 'q' "$C_DIM" ' quit'
        local ei
        for ((ei = 0; ei < extra; ei++)); do
            _tui_line "$C_KEY" "${TUI_EXTRA_KEYS[$ei]}" "$C_DIM" " ${TUI_EXTRA_DESCS[$ei]}"
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
show_menu() {
    export TERM="${TERM:-xterm-256color}"

    local -a items=()
    local c
    items+=("sep|3rd-party tools")
    for c in "${THIRD_PARTY_COMPONENTS[@]}"; do
        items+=("$c|${COMP_DESC[$c]}|on")
    done
    items+=("sep|pkg tools")
    for c in "${PKG_TOOL_COMPONENTS[@]}"; do
        items+=("$c|${COMP_DESC[$c]}|on")
    done
    items+=("apt_upgrade|OPTION: apt update & upgrade before installing (recommended)|$([ "$APT_UPGRADE" -eq 1 ] && echo on || echo off)")
    items+=("no_storage|OPTION: skip termux-setup-storage (shared storage)|$([ "$SETUP_STORAGE" -eq 0 ] && echo on || echo off)")
    items+=("kilocode_native|OPTION: kilocode - pick recommended native method (no prompt)|$([ "$KILOCODE_NATIVE" -eq 1 ] && echo on || echo off)")

    # Shortcut keys: 's' saves a Kilo backup, 'u' updates what is installed.
    TUI_EXTRA_KEYS=("s" "u")
    TUI_EXTRA_DESCS=("save kilocode backup" "update installed tools")
    TUI_EXTRA_BUSY=("Saving Kilo settings and tokens, please wait..."
                    "Updating installed tools; this can take several minutes...")
    TUI_EXTRA_FNS=("menu_save_kilo" "menu_update_tools")

    # Vertical fit: the redraw moves the cursor up one line per rendered line,
    # so if the block is taller than the screen the display corrupts. Fall
    # back to installing everything instead of drawing a broken menu.
    local rows est
    rows=$(tput lines 2>/dev/null) || rows=""
    case "$rows" in ''|*[!0-9]*) rows="${LINES:-24}" ;; esac
    est=$(( ${#items[@]} + 3 + ${#TUI_EXTRA_KEYS[@]} ))   # title + 2 help lines + extra keys
    if [ "$est" -ge "$rows" ]; then
        warn "Menu needs $est rows, terminal has $rows"
        info "Skipping the menu; all components will be installed. Use -y for a quiet run."
        TUI_EXTRA_KEYS=(); TUI_EXTRA_DESCS=(); TUI_EXTRA_BUSY=(); TUI_EXTRA_FNS=()
        return 0
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
        info "Running termux-change-repo (pick a mirror group)"
        termux-change-repo || warn "termux-change-repo did not complete; continuing"
    fi

    if [ ! -e "$chosen" ] && [ -e "$PREFIX/etc/termux/mirrors/default" ]; then
        info "Falling back to the bundled default mirror"
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
    info "pkg install: ${BASE_PKG_DEPS[*]}"
    pkg install -y "${BASE_PKG_DEPS[@]}" || die "Failed to install base pkg dependencies"
    ok "Base dependencies installed"
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

install_pkg_tools() {
    local pkgs=()
    local c p bin
    for c in "${PKG_TOOL_COMPONENTS[@]}"; do
        is_selected "$c" || continue
        for p in ${PKG_COMPONENT[$c]}; do pkgs+=("$p"); done
    done
    [ "${#pkgs[@]}" -gt 0 ] || return 0

    step "Installing pkg tools"
    info "pkg install: ${pkgs[*]}"
    pkg install -y "${pkgs[@]}" || die "Failed to install pkg tools"
    ok "pkg tools installed"

    for c in "${PKG_TOOL_COMPONENTS[@]}"; do
        is_selected "$c" || continue
        bin="${PKG_COMPONENT_CMD[$c]:-$c}"
        ok "$c -> $(command -v "$bin" || echo missing)"
    done

    if is_selected golang; then
        setup_golang_path
    fi
}

install_pip_tools() {
    is_selected copyparty || is_selected ytdlp || is_selected pydf || return 0

    step "Installing Python-based tools"

    python -m ensurepip --upgrade >/dev/null 2>&1 || warn "ensurepip reported issues; continuing"

    if is_selected copyparty; then
        python -m pip install --user -U copyparty || die "pip install copyparty failed"
        ok "copyparty -> $(command -v copyparty || echo "$HOME/.local/bin/copyparty")"
    fi

    if is_selected ytdlp; then
        python -m pip install --user -U yt-dlp || die "pip install yt-dlp failed"
        ok "yt-dlp -> $(command -v yt-dlp || echo "$HOME/.local/bin/yt-dlp")"
    fi

    if is_selected pydf; then
        pip3 install -U pydf || die "pip3 install pydf failed"
        ok "pydf -> $(command -v pydf || echo missing)"
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
        info "Requesting shared-storage access (termux-setup-storage)"
        termux-setup-storage >/dev/null 2>&1 \
            || warn "termux-setup-storage skipped or denied; run it manually later"
    fi
}

install_shizuku_tools() {
    is_selected shizuku || return 0

    step "Installing termux-shizuku-tools"

    if [ -d "$SHIZUKU_DIR/.git" ]; then
        info "Existing checkout found; updating"
        git -C "$SHIZUKU_DIR" pull --ff-only || warn "git pull failed; using existing checkout"
    else
        info "Cloning $REPO_SHIZUKU"
        git clone --depth=1 "$REPO_SHIZUKU" "$SHIZUKU_DIR" \
            || die "Failed to clone termux-shizuku-tools"
    fi

    chmod +x "$SHIZUKU_DIR/setup.sh"
    info "Running setup.sh (installs rish, symlinks, AI-tool helpers)"

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

    step "Installing rish (merbah3266/rish_installer)"

    command -v curl >/dev/null 2>&1 || die "curl is required to install rish"
    command -v bash >/dev/null 2>&1 || die "bash is required to install rish"

    # Run after termux-shizuku-tools so this installer's rish wins if both
    # components are selected; it extracts the real rish from the Shizuku APK
    # and patches it for this terminal's Android package.
    local -a flags=()
    if [ -e "$PREFIX/bin/rish" ] || [ -e "$HOME/rish" ]; then
        info "An existing rish was found; passing --reinstall"
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
        info "Running rish installer silently (source: default)"
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

    step "Installing core (core-termux)"

    if [ -x "$PREFIX/bin/core" ]; then
        ok "core already installed: $PREFIX/bin/core"
        return
    fi

    command -v curl >/dev/null 2>&1 || die "curl is required to install core-termux"
    info "Running official core-termux installer"
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

    step "Installing kilocode-cli via core (core install ai --kilocode-cli)"

    if command -v kilocode >/dev/null 2>&1; then
        ok "kilocode already installed -> $(command -v kilocode)"
        return
    fi

    command -v core >/dev/null 2>&1 || die "core is required to install kilocode-cli"

    # core's installer shows an interactive menu (native / native+proot / proot-distro).
    # Option 0 ("glibc (recommended)") is the default; an empty keypress (Enter) selects it.
    if [ "$KILOCODE_NATIVE" -eq 1 ] || [ ! -t 0 ]; then
        info "Selecting recommended 'glibc (recommended)' method non-interactively"
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
    step "Installation complete (tmx2tm.sh v$SCRIPT_VERSION)"
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
# Snapshot of the current Kilo / kilocode settings and login tokens.
# Kept OUT of the script so the installer never embeds live credentials.
kilo_backup_files() {
    local -a files=()
    [ -f "$KILO_CONFIG_DIR/kilo.jsonc" ] && files+=(".config/kilo/kilo.jsonc")
    [ -f "$KILO_DATA_DIR/auth.json" ]    && files+=(".local/share/kilo/auth.json")
    [ -f "$KILO_STATE_DIR/model.json" ]  && files+=(".local/state/kilo/model.json")
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
    tar -tzf "$in" >/dev/null 2>&1 || die "Not a valid tar.gz backup: $in"
    local member bad_members=""
    while IFS= read -r member; do
        case "$member" in
            .config/kilo/kilo.jsonc|.local/share/kilo/auth.json|.local/state/kilo/model.json) ;;
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
# README has moved to ./README.md (single source of truth).
# See README.md for full documentation (usage, components, stages, workflows).
# =============================================================================
