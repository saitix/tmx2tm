load helpers

setup() {
    load_functions tp_gate
    setup_stubs
    # Stubs for tp_gate's dependencies.
    ensure_tp_status() { return 0; }
    info() { :; }
    warn() { :; }
    record_result() { :; }
    # comp_status / comp_broken_why read the maps directly (as the real ones
    # do); the tests set the maps below.
    comp_status() { printf '%s' "${TP_STATUS[$1]:-missing}"; }
    comp_broken_why() { printf '%s' "${TP_BROKEN_WHY[$1]:-source gone}"; }
    MENU_CONFIRMED=0
    TP_FORCE=0
}

@test "tp_gate: broken dangling link proceeds" {
    declare -gA TP_STATUS=([core]=broken)
    declare -gA TP_BROKEN_WHY=([core]="link target missing")
    TP_WHY_DANGLING="link target missing"
    tp_gate core
    [ "$?" -eq 0 ]
    [ "$TP_FORCE" -eq 0 ]
}

@test "tp_gate: broken archived skips and records" {
    declare -gA TP_STATUS=([core]=broken)
    declare -gA TP_BROKEN_WHY=([core]="archived")
    TP_WHY_DANGLING="link target missing"
    recorded=""
    record_result() { recorded="$1 $2 $3"; }
    tp_gate core || rc=$?
    [ "$rc" -eq 1 ]
    [ "$recorded" = "core broken archived" ]
}

@test "tp_gate: current with menu confirmed forces reinstall" {
    declare -gA TP_STATUS=([core]=current)
    declare -gA TP_BROKEN_WHY=()
    TP_WHY_DANGLING="link target missing"
    MENU_CONFIRMED=1
    tp_gate core
    [ "$?" -eq 0 ]
    [ "$TP_FORCE" -eq 1 ]
}

@test "tp_gate: current unattended skips and records" {
    declare -gA TP_STATUS=([core]=current)
    declare -gA TP_BROKEN_WHY=()
    TP_WHY_DANGLING="link target missing"
    MENU_CONFIRMED=0
    recorded=""
    record_result() { recorded="$1 $2"; }
    tp_gate core || rc=$?
    [ "$rc" -eq 1 ]
    [ "$recorded" = "core skipped" ]
}
