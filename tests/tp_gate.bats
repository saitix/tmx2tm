load helpers

setup() {
    load_functions tp_gate
    setup_stubs
    # Stubs for tp_gate's dependencies.
    ensure_tp_status() { return 0; }
    info() { :; }
    warn() { :; }
    record_result() { :; }
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
