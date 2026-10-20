load helpers

setup() {
    rm -rf "$BATS_TMPDIR/t"; mkdir -p "$BATS_TMPDIR/t"
    load_functions _starship_strip_filter _neofetch_strip_filter \
        _neofetch_has_closed_block rc_backup rc_rewrite register_temp \
        info warn
    setup_stubs
}

filter() { printf '%s' "$1" | "$2"; }

assert_syntax() { bash -n "$1"; }

# ---------------- starship ----------------

@test "starship: current snippet only is removed" {
    input='# Initialize Starship only once, if installed
if [ -z "$STARSHIP_START_TIME" ] && command -v starship >/dev/null 2>&1; then
    eval "$(starship init bash)"
fi
'
    run filter "$input" _starship_strip_filter
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "starship: legacy snippet only is removed" {
    input='# Initialize Starship only if installed
if command -v starship >/dev/null 2>&1; then
    eval "$(starship init bash)"
fi
'
    run filter "$input" _starship_strip_filter
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "starship: user if-blocks before and after survive" {
    input='if [ -f ~/a ]; then
  echo a
fi
# Initialize Starship only once, if installed
if [ -z "$STARSHIP_START_TIME" ] && command -v starship >/dev/null 2>&1; then
    eval "$(starship init bash)"
fi
if [ -f ~/b ]; then
  echo b
fi
'
    run filter "$input" _starship_strip_filter
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" >"$BATS_TMPDIR/t/out"
    bash -n "$BATS_TMPDIR/t/out"
    cat >"$BATS_TMPDIR/t/expected" <<'EXPECTED'
if [ -f ~/a ]; then
  echo a
fi
if [ -f ~/b ]; then
  echo b
fi
EXPECTED
    diff "$BATS_TMPDIR/t/expected" "$BATS_TMPDIR/t/out"
}

@test "starship: blank runs and whitespace lines kept verbatim" {
    input='echo one


echo two

echo three
# Initialize Starship only once, if installed
if [ -z "$STARSHIP_START_TIME" ] && command -v starship >/dev/null 2>&1; then
    eval "$(starship init bash)"
fi
echo four

   
echo five
'
    run filter "$input" _starship_strip_filter
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" >"$BATS_TMPDIR/t/out"
    bash -n "$BATS_TMPDIR/t/out"
    cat >"$BATS_TMPDIR/t/expected" <<'EXPECTED'
echo one


echo two

echo three
echo four

   
echo five
EXPECTED
    diff "$BATS_TMPDIR/t/expected" "$BATS_TMPDIR/t/out"
}

@test "starship: edited body keeps user lines" {
    input='# Initialize Starship only once, if installed
    eval "$(starship init bash)"
alias ll="ls -l"
export EDITOR=vim
echo after
'
    result=$(filter "$input" _starship_strip_filter)
    printf '%s\n' "$result" >"$BATS_TMPDIR/t/out"
    grep -q 'alias ll=' "$BATS_TMPDIR/t/out"
    grep -q 'EDITOR=vim' "$BATS_TMPDIR/t/out"
    bash -n "$BATS_TMPDIR/t/out"
}

@test "starship: incomplete body drops matched lines, keeps rest" {
    input='# Initialize Starship only once, if installed
if [ -z "$STARSHIP_START_TIME" ] && command -v starship >/dev/null 2>&1; then
    eval "$(starship init bash)"
echo still-here
'
    run filter "$input" _starship_strip_filter
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" >"$BATS_TMPDIR/t/out"
    ! grep -q 'Initialize Starship' "$BATS_TMPDIR/t/out"
    grep -q 'still-here' "$BATS_TMPDIR/t/out"
    bash -n "$BATS_TMPDIR/t/out"
}

@test "starship: no marker passes through" {
    input='echo hello
alias ll="ls -l"
'
    run filter "$input" _starship_strip_filter
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '%s' "$input")" ]
}

@test "starship: idempotent" {
    input='echo top
# Initialize Starship only once, if installed
if [ -z "$STARSHIP_START_TIME" ] && command -v starship >/dev/null 2>&1; then
    eval "$(starship init bash)"
fi
echo bottom
'
    once=$(filter "$input" _starship_strip_filter)
    twice=$(filter "$once" _starship_strip_filter)
    [ "$once" = "$twice" ]
}

# ---------------- neofetch ----------------

NEO_START='# >>> neofetch on Termux start >>>'
NEO_END='# <<< neofetch on Termux start <<<'

@test "neofetch: closed installer block is removed" {
    input="$NEO_START
if [[ \$- == *i* ]] && command -v neofetch >/dev/null 2>&1; then
  neofetch --off
fi
$NEO_END
"
    printf '%s' "$input" >"$BATS_TMPDIR/t/in"
    run _neofetch_has_closed_block "$BATS_TMPDIR/t/in"
    [ "$status" -eq 0 ]
    run filter "$input" _neofetch_strip_filter
    [ "$status" -eq 0 ]
    ! printf '%s' "$output" | grep -q 'neofetch on Termux'
    printf '%s' "$output" >"$BATS_TMPDIR/t/out"
    run _neofetch_has_closed_block "$BATS_TMPDIR/t/out"
    [ "$status" -ne 0 ]
    bash -n "$BATS_TMPDIR/t/out"
}

@test "neofetch: long edited closed block is removed whole" {
    input="echo before
$NEO_START
if [[ \$- == *i* ]] && command -v neofetch >/dev/null 2>&1; then
  neofetch --off
  echo custom1
  echo custom2
  if [ -n \"\$X\" ]; then
    echo nested
  fi
fi
$NEO_END
echo after
"
    run filter "$input" _neofetch_strip_filter
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" >"$BATS_TMPDIR/t/out"
    grep -q 'echo before' "$BATS_TMPDIR/t/out"
    grep -q 'echo after' "$BATS_TMPDIR/t/out"
    ! grep -q 'neofetch on Termux' "$BATS_TMPDIR/t/out"
    ! grep -q 'custom1' "$BATS_TMPDIR/t/out"
    bash -n "$BATS_TMPDIR/t/out"
}

@test "neofetch: legacy unclosed block keeps user if-block" {
    input="$NEO_START
if [[ \$- == *i* && -z \"\$NEOFETCH_SHOWN\" ]] && command -v neofetch >/dev/null 2>&1; then
  neofetch --off
  export NEOFETCH_SHOWN=1
if [ -f ~/u ]; then
  echo user
fi
"
    run filter "$input" _neofetch_strip_filter
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" >"$BATS_TMPDIR/t/out"
    grep -q 'echo user' "$BATS_TMPDIR/t/out"
    ! grep -q 'neofetch on Termux' "$BATS_TMPDIR/t/out"
    bash -n "$BATS_TMPDIR/t/out"
}

@test "neofetch: unrelated lines after bare marker survive" {
    input="$NEO_START
alias ll=\"ls -l\"
export EDITOR=vim
"
    run filter "$input" _neofetch_strip_filter
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" >"$BATS_TMPDIR/t/out"
    grep -q 'alias ll=' "$BATS_TMPDIR/t/out"
    grep -q 'EDITOR=vim' "$BATS_TMPDIR/t/out"
    bash -n "$BATS_TMPDIR/t/out"
}

@test "neofetch: end marker beyond cap leaves file untouched" {
    input="$NEO_START
$(for i in $(seq 1 30); do echo "echo filler$i"; done)
$NEO_END
"
    run filter "$input" _neofetch_strip_filter
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '%s' "$input")" ]
}

@test "neofetch: no markers passes through" {
    input='echo hello
'
    run filter "$input" _neofetch_strip_filter
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '%s' "$input")" ]
}

@test "neofetch: idempotent" {
    input="echo top
$NEO_START
if [[ \$- == *i* ]] && command -v neofetch >/dev/null 2>&1; then
  neofetch --off
fi
$NEO_END
echo bottom
"
    once=$(filter "$input" _neofetch_strip_filter)
    twice=$(filter "$once" _neofetch_strip_filter)
    [ "$once" = "$twice" ]
}

@test "neofetch: legacy block then closed block keeps user lines" {
    input="$NEO_START
if [[ \$- == *i* ]] && command -v neofetch >/dev/null 2>&1; then
  neofetch --off
export USERVAR=1
alias keep=me
$NEO_START
if [[ \$- == *i* ]] && command -v neofetch >/dev/null 2>&1; then
  neofetch --off
fi
$NEO_END
"
    run filter "$input" _neofetch_strip_filter
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" >"$BATS_TMPDIR/t/out"
    grep -q 'USERVAR=1' "$BATS_TMPDIR/t/out"
    grep -q 'alias keep=me' "$BATS_TMPDIR/t/out"
    ! grep -q 'neofetch on Termux' "$BATS_TMPDIR/t/out"
    ! grep -q 'neofetch --off' "$BATS_TMPDIR/t/out"
    bash -n "$BATS_TMPDIR/t/out"
}

@test "neofetch: two closed blocks back to back both removed" {
    input="echo before
$NEO_START
if [[ \$- == *i* ]] && command -v neofetch >/dev/null 2>&1; then
  neofetch --off
fi
$NEO_END
$NEO_START
if [[ \$- == *i* ]] && command -v neofetch >/dev/null 2>&1; then
  neofetch --off
fi
$NEO_END
echo after
"
    run filter "$input" _neofetch_strip_filter
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" >"$BATS_TMPDIR/t/out"
    grep -q 'echo before' "$BATS_TMPDIR/t/out"
    grep -q 'echo after' "$BATS_TMPDIR/t/out"
    ! grep -q 'neofetch on Termux' "$BATS_TMPDIR/t/out"
    bash -n "$BATS_TMPDIR/t/out"
}

# ---------------- rc_rewrite ----------------

@test "rc_rewrite: bad filter output leaves file untouched" {
    printf 'echo ok\n' >"$BATS_TMPDIR/t/rc"
    bad_filter() { printf 'if broken {{{\n'; }
    run rc_rewrite "$BATS_TMPDIR/t/rc" bad_filter
    [ "$status" -ne 0 ]
    [ "$(cat "$BATS_TMPDIR/t/rc")" = "echo ok" ]
}

@test "rc_rewrite: symlink stays a symlink" {
    printf 'echo orig\n' >"$BATS_TMPDIR/t/real"
    ln -s "$BATS_TMPDIR/t/real" "$BATS_TMPDIR/t/link"
    add_line() { cat; printf 'echo added\n'; }
    run rc_rewrite "$BATS_TMPDIR/t/link" add_line
    [ "$status" -eq 0 ]
    [ -L "$BATS_TMPDIR/t/link" ]
    grep -q 'echo added' "$BATS_TMPDIR/t/real"
}

@test "rc_rewrite: backup created once with original content" {
    printf 'echo v1\n' >"$BATS_TMPDIR/t/rc2"
    add_a() { cat; printf 'echo a\n'; }
    add_b() { cat; printf 'echo b\n'; }
    rc_rewrite "$BATS_TMPDIR/t/rc2" add_a
    rc_rewrite "$BATS_TMPDIR/t/rc2" add_b
    [ "$(cat "$BATS_TMPDIR/t/rc2.tmx2tm.bak")" = "echo v1" ]
    grep -q 'echo b' "$BATS_TMPDIR/t/rc2"
}
