load helpers

setup() {
    load_functions ensure_bashrc_line rc_backup register_temp info warn
    setup_stubs
    rm -rf "$BATS_TMPDIR/t"; mkdir -p "$BATS_TMPDIR/t"
    BASHRC="$BATS_TMPDIR/t/rc"
}

@test "ensure_bashrc_line: present line creates no backup, no change" {
    printf 'export X=1\n' >"$BASHRC"
    ensure_bashrc_line 'export X=1'
    [ "$(cat "$BASHRC")" = "export X=1" ]
    [ ! -e "$BASHRC.tmx2tm.bak" ]
}

@test "ensure_bashrc_line: missing line backed up and appended once" {
    printf 'export X=1\n' >"$BASHRC"
    ensure_bashrc_line 'export Y=2'
    [ "$(cat "$BASHRC.tmx2tm.bak")" = "export X=1" ]
    grep -q 'export Y=2' "$BASHRC"
    # Second run: line now present, backup must NOT be overwritten.
    printf 'export Z=9\n' >>"$BASHRC.tmx2tm.bak"
    ensure_bashrc_line 'export Y=2'
    grep -q 'export Z=9' "$BASHRC.tmx2tm.bak"
}
