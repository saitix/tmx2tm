load helpers

setup() {
    rm -rf "$BATS_TMPDIR/t"; mkdir -p "$BATS_TMPDIR/t"
    load_functions _starship_strip_filter _block_strip_filter _block_has_closed \
        rc_backup rc_rewrite register_temp info warn
    setup_stubs
}

# filter <input> <function> [args...]: run a filter on the input text.
filter() { local in="$1"; shift; printf '%s' "$in" | "$@"; }

assert_syntax() { bash -n "$1"; }

# ---------------- starship ----------------

@test "starship: current snippet only is removed" {
    input='# Initialize Starship only once, if installed
if ! declare -F starship_precmd >/dev/null 2>&1 && command -v starship >/dev/null 2>&1; then
    eval "$(starship init bash)"
fi
'
    run filter "$input" _starship_strip_filter
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "starship: older STARSHIP_START_TIME form is removed" {
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

# ---------------- fastfetch block ----------------

ff_filter() { filter "$1" _block_strip_filter "$FASTFETCH_START" "$FASTFETCH_END" "$FASTFETCH_BLOCK_CAP" "$FASTFETCH_SNIPPET_RE"; }

@test "fastfetch: closed block is removed" {
    input=$(cat <<EOF
echo before
$FASTFETCH_START
if [[ \$- == *i* ]] && command -v fastfetch >/dev/null 2>&1; then
  fastfetch -l none
fi
$FASTFETCH_END
echo after
EOF
)
    printf '%s\n' "$input" >"$BATS_TMPDIR/t/in"
    run _block_has_closed "$FASTFETCH_START" "$FASTFETCH_END" "$FASTFETCH_BLOCK_CAP" "$BATS_TMPDIR/t/in"
    [ "$status" -eq 0 ]
    run ff_filter "$input"
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" >"$BATS_TMPDIR/t/out"
    grep -q 'echo before' "$BATS_TMPDIR/t/out"
    grep -q 'echo after' "$BATS_TMPDIR/t/out"
    ! grep -q 'fastfetch' "$BATS_TMPDIR/t/out"
    bash -n "$BATS_TMPDIR/t/out"
    run _block_has_closed "$FASTFETCH_START" "$FASTFETCH_END" "$FASTFETCH_BLOCK_CAP" "$BATS_TMPDIR/t/out"
    [ "$status" -ne 0 ]
}

@test "fastfetch: long edited closed block is removed whole" {
    input=$(cat <<EOF
echo before
$FASTFETCH_START
if [[ \$- == *i* ]] && command -v fastfetch >/dev/null 2>&1; then
  fastfetch -l none
  echo custom1
  echo custom2
  if [ -n "\$X" ]; then
    echo nested
  fi
fi
$FASTFETCH_END
echo after
EOF
)
    run ff_filter "$input"
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" >"$BATS_TMPDIR/t/out"
    grep -q 'echo before' "$BATS_TMPDIR/t/out"
    grep -q 'echo after' "$BATS_TMPDIR/t/out"
    ! grep -q 'custom1' "$BATS_TMPDIR/t/out"
    ! grep -q 'fastfetch on Termux' "$BATS_TMPDIR/t/out"
    bash -n "$BATS_TMPDIR/t/out"
}

@test "fastfetch: two closed blocks back to back both removed" {
    input=$(cat <<EOF
echo before
$FASTFETCH_START
if [[ \$- == *i* ]] && command -v fastfetch >/dev/null 2>&1; then
  fastfetch -l none
fi
$FASTFETCH_END
$FASTFETCH_START
if [[ \$- == *i* ]] && command -v fastfetch >/dev/null 2>&1; then
  fastfetch -l none
fi
$FASTFETCH_END
echo after
EOF
)
    run ff_filter "$input"
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" >"$BATS_TMPDIR/t/out"
    grep -q 'echo before' "$BATS_TMPDIR/t/out"
    grep -q 'echo after' "$BATS_TMPDIR/t/out"
    ! grep -q 'fastfetch on Termux' "$BATS_TMPDIR/t/out"
    bash -n "$BATS_TMPDIR/t/out"
}

@test "fastfetch: end marker beyond cap leaves file untouched" {
    input="$FASTFETCH_START
$(for i in $(seq 1 30); do echo "echo filler$i"; done)
$FASTFETCH_END
"
    run ff_filter "$input"
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '%s' "$input")" ]
}

@test "fastfetch: no markers passes through" {
    input='echo hello
alias ll="ls -l"
'
    run ff_filter "$input"
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '%s' "$input")" ]
}

@test "fastfetch: idempotent" {
    input=$(cat <<EOF
echo top
$FASTFETCH_START
if [[ \$- == *i* ]] && command -v fastfetch >/dev/null 2>&1; then
  fastfetch -l none
fi
$FASTFETCH_END
echo bottom
EOF
)
    once=$(ff_filter "$input")
    twice=$(ff_filter "$once")
    [ "$once" = "$twice" ]
}

@test "fastfetch: filter leaves a v0.9 neofetch block alone" {
    input=$(cat <<EOF
$NEOFETCH_LEGACY_START
if [[ \$- == *i* ]] && command -v neofetch >/dev/null 2>&1; then
  neofetch --off
fi
$NEOFETCH_LEGACY_END
EOF
)
    run ff_filter "$input"
    [ "$status" -eq 0 ]
    [ "$output" = "$input" ]
}

# ---------------- legacy v0.9 neofetch block (migration) ----------------

nf_filter() { filter "$1" _block_strip_filter "$NEOFETCH_LEGACY_START" "$NEOFETCH_LEGACY_END" "$FASTFETCH_BLOCK_CAP" "$NEOFETCH_SNIPPET_RE"; }

@test "legacy neofetch: closed v0.9 block is removed" {
    input=$(cat <<EOF
echo before
$NEOFETCH_LEGACY_START
if [[ \$- == *i* ]] && command -v neofetch >/dev/null 2>&1; then
  neofetch --off
fi
$NEOFETCH_LEGACY_END
echo after
EOF
)
    run nf_filter "$input"
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" >"$BATS_TMPDIR/t/out"
    grep -q 'echo before' "$BATS_TMPDIR/t/out"
    grep -q 'echo after' "$BATS_TMPDIR/t/out"
    ! grep -q 'neofetch' "$BATS_TMPDIR/t/out"
    bash -n "$BATS_TMPDIR/t/out"
}

@test "legacy neofetch: unclosed block keeps user if-block" {
    input=$(cat <<EOF
$NEOFETCH_LEGACY_START
if [[ \$- == *i* && -z "\$NEOFETCH_SHOWN" ]] && command -v neofetch >/dev/null 2>&1; then
  neofetch --off
  export NEOFETCH_SHOWN=1
if [ -f ~/u ]; then
  echo user
fi
EOF
)
    run nf_filter "$input"
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" >"$BATS_TMPDIR/t/out"
    grep -q 'echo user' "$BATS_TMPDIR/t/out"
    ! grep -q 'neofetch' "$BATS_TMPDIR/t/out"
    bash -n "$BATS_TMPDIR/t/out"
}

@test "legacy neofetch: unrelated lines after bare marker survive" {
    input="$NEOFETCH_LEGACY_START
alias ll=\"ls -l\"
export EDITOR=vim
"
    run nf_filter "$input"
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" >"$BATS_TMPDIR/t/out"
    grep -q 'alias ll=' "$BATS_TMPDIR/t/out"
    grep -q 'EDITOR=vim' "$BATS_TMPDIR/t/out"
    bash -n "$BATS_TMPDIR/t/out"
}

@test "legacy neofetch: unclosed block then closed block keeps user lines" {
    input=$(cat <<EOF
$NEOFETCH_LEGACY_START
if [[ \$- == *i* ]] && command -v neofetch >/dev/null 2>&1; then
  neofetch --off
export USERVAR=1
alias keep=me
$NEOFETCH_LEGACY_START
if [[ \$- == *i* ]] && command -v neofetch >/dev/null 2>&1; then
  neofetch --off
fi
$NEOFETCH_LEGACY_END
EOF
)
    run nf_filter "$input"
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" >"$BATS_TMPDIR/t/out"
    grep -q 'USERVAR=1' "$BATS_TMPDIR/t/out"
    grep -q 'alias keep=me' "$BATS_TMPDIR/t/out"
    ! grep -q 'neofetch' "$BATS_TMPDIR/t/out"
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
