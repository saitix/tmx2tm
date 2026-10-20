# helpers.bash — loads installer functions into bats without running it.
# tmx2tm.sh executes arg parsing and main() at top level, so it must never be
# sourced directly. Instead, extract named functions (from `^name() {` to the
# next `^}`) into a temp file and source that.
#
# Usage in a .bats file:
#   load helpers
#   setup() { load_functions _starship_strip_filter ...; }

TMX2TM_SH="${BATS_TEST_DIRNAME}/../tmx2tm.sh"

load_functions() {
    local name start end dest="$BATS_TMPDIR/funcs.$$.bash"
    : >"$dest"
    for name in "$@"; do
        start=$(grep -n "^${name}() {" "$TMX2TM_SH" | cut -d: -f1 | head -1)
        if [ -z "$start" ]; then
            echo "load_functions: function '$name' not found in tmx2tm.sh" >&2
            return 1
        fi
        end=$(awk -v s="$start" 'NR>s && /^\}/{print NR; exit}' "$TMX2TM_SH")
        if [ -z "$end" ]; then
            echo "load_functions: end of '$name' not found" >&2
            return 1
        fi
        sed -n "${start},${end}p" "$TMX2TM_SH" >>"$dest"
    done
    # shellcheck disable=SC1090
    source "$dest"
}

# Stubs so the extracted functions run outside the installer.
setup_stubs() {
    C_RESET=""; C_BLUE=""; C_DIM=""; C_OK=""; C_WARN=""
    C_HL=""; C_KEY=""; C_ERR=""; C_PURPLE=""; C_YELLOW=""
    TEMP_PATHS=()
    declare -gA RC_BACKED_UP=()
    # Config constants the functions reference: read the real values from
    # tmx2tm.sh so tests always match the script instead of a copy.
    local line
    line=$(grep '^NEOFETCH_BLOCK_CAP=' "$TMX2TM_SH" | head -1)
    # shellcheck disable=SC2163
    [ -n "$line" ] && eval "export $line"
    TP_WHY_DANGLING=$(grep '^TP_WHY_DANGLING=' "$TMX2TM_SH" | head -1 | cut -d= -f2- | tr -d '"')
    export TP_WHY_DANGLING
}
