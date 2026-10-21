load helpers

setup() {
    load_functions setup_fastfetch_init _block_strip_filter _block_has_closed \
        rc_backup rc_rewrite register_temp info warn
    setup_stubs
    ok() { :; }
    RC_CHANGED=0
    rm -rf "$BATS_TMPDIR/ff"; mkdir -p "$BATS_TMPDIR/ff/bin"
    BASH_PROFILE="$BATS_TMPDIR/ff/profile"
    BASHRC="$BATS_TMPDIR/ff/rc"
    NO_FF_PATH=$(path_without_fastfetch)
}

# A PATH directory holding symlinks to only the basic tools the functions use,
# and no fastfetch: `command -v fastfetch` fails even on a machine where it is
# installed, without hiding the rest of the system tools.
path_without_fastfetch() {
    local dir="$BATS_TMPDIR/ff/nobin" t p
    mkdir -p "$dir"
    for t in awk grep sed cat cp mv rm mktemp cmp chmod bash dirname; do
        p=$(command -v "$t") && ln -sf "$p" "$dir/$t"
    done
    printf '%s' "$dir"
}

use_fastfetch() {
    printf '#!/bin/sh\nexit 0\n' >"$BATS_TMPDIR/ff/bin/fastfetch"
    chmod +x "$BATS_TMPDIR/ff/bin/fastfetch"
    PATH="$BATS_TMPDIR/ff/bin:$NO_FF_PATH"
}

no_fastfetch() {
    PATH="$NO_FF_PATH"
}

@test "present: v0.9 neofetch block is replaced by the fastfetch block, profile only" {
    use_fastfetch
    cat >"$BASH_PROFILE" <<EOF
echo top
$NEOFETCH_LEGACY_START
if [[ \$- == *i* ]] && command -v neofetch >/dev/null 2>&1; then
  neofetch --off
fi
$NEOFETCH_LEGACY_END
echo bottom
EOF
    cat >"$BASHRC" <<EOF
echo rc
$NEOFETCH_LEGACY_START
if [[ \$- == *i* ]] && command -v neofetch >/dev/null 2>&1; then
  neofetch --off
fi
$NEOFETCH_LEGACY_END
EOF
    setup_fastfetch_init
    grep -qxF "$FASTFETCH_START" "$BASH_PROFILE"
    grep -qxF "$FASTFETCH_END" "$BASH_PROFILE"
    grep -q 'fastfetch -l none' "$BASH_PROFILE"
    ! grep -q 'neofetch' "$BASH_PROFILE"
    grep -q 'echo top' "$BASH_PROFILE"
    grep -q 'echo bottom' "$BASH_PROFILE"
    ! grep -q 'neofetch' "$BASHRC"
    ! grep -qxF "$FASTFETCH_START" "$BASHRC"
    grep -q 'echo rc' "$BASHRC"
    bash -n "$BASH_PROFILE"
    bash -n "$BASHRC"
    [ "$RC_CHANGED" -eq 1 ]
}

@test "present: second run is a no-op" {
    use_fastfetch
    printf 'echo top\n' >"$BASH_PROFILE"
    setup_fastfetch_init
    cp "$BASH_PROFILE" "$BATS_TMPDIR/ff/first"
    RC_CHANGED=0
    setup_fastfetch_init
    cmp -s "$BASH_PROFILE" "$BATS_TMPDIR/ff/first"
    [ "$RC_CHANGED" -eq 0 ]
}

@test "absent: fastfetch and v0.9 neofetch blocks are removed from both files" {
    no_fastfetch
    cat >"$BASH_PROFILE" <<EOF
echo top
$FASTFETCH_START
if [[ \$- == *i* ]] && command -v fastfetch >/dev/null 2>&1; then
  fastfetch -l none
fi
$FASTFETCH_END
echo bottom
EOF
    cat >"$BASHRC" <<EOF
echo rc
$NEOFETCH_LEGACY_START
if [[ \$- == *i* ]] && command -v neofetch >/dev/null 2>&1; then
  neofetch --off
fi
$NEOFETCH_LEGACY_END
EOF
    setup_fastfetch_init
    ! grep -q 'fastfetch' "$BASH_PROFILE"
    ! grep -q 'neofetch' "$BASHRC"
    grep -q 'echo top' "$BASH_PROFILE"
    grep -q 'echo bottom' "$BASH_PROFILE"
    grep -q 'echo rc' "$BASHRC"
    [ "$RC_CHANGED" -eq 1 ]
}

@test "present: refused cleanup of a legacy block does not stack fastfetch on top" {
    use_fastfetch
    cat >"$BASH_PROFILE" <<EOF
$NEOFETCH_LEGACY_START
if [[ \$- == *i* && -z "\$NEOFETCH_SHOWN" ]] && command -v neofetch >/dev/null 2>&1; then
  neofetch --off
if [ -f ~/u ]; then
  echo hi
EOF
    cp "$BASH_PROFILE" "$BATS_TMPDIR/ff/before"
    setup_fastfetch_init
    cmp -s "$BASH_PROFILE" "$BATS_TMPDIR/ff/before"
    ! grep -qxF "$FASTFETCH_START" "$BASH_PROFILE"
    [ "$RC_CHANGED" -eq 0 ]
}
