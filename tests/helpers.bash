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

# Read named config constants from tmx2tm.sh (single source of truth) and
# define them in the test shell. Fails loudly when a constant is missing.
load_constants() {
    local name line
    for name in "$@"; do
        line=$(grep -m1 "^${name}=" "$TMX2TM_SH") || {
            echo "load_constants: '$name' not found in tmx2tm.sh" >&2
            return 1
        }
        eval "$line"
    done
}

# Stubs so the extracted functions run outside the installer.
setup_stubs() {
    C_RESET=""; C_BLUE=""; C_DIM=""; C_OK=""; C_WARN=""
    C_HL=""; C_KEY=""; C_ERR=""; C_PURPLE=""; C_YELLOW=""
    TEMP_PATHS=()
    declare -gA RC_BACKED_UP=()
    load_constants TP_WHY_DANGLING FASTFETCH_START FASTFETCH_END FASTFETCH_BLOCK_CAP \
        FASTFETCH_SNIPPET_RE NEOFETCH_LEGACY_START NEOFETCH_LEGACY_END NEOFETCH_SNIPPET_RE
}
