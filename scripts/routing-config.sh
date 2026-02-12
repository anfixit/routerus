#!/bin/bash
# Routing options configuration module

# Prompt for a y/n option if its current value is "ask".
# Usage: _prompt_yn "VARNAME" "Question text" "default"
_prompt_yn() {
    local var_name="$1"
    local question="$2"
    local default="${3:-y}"
    local current_value="${!var_name:-ask}"

    if [[ "${current_value}" == "y" || "${current_value}" == "n" ]]; then
        msg_inf "  ${question}: ${current_value} (from args/env)"
        return 0
    fi

    local hint="Y/n"
    [[ "${default}" == "n" ]] && hint="y/N"

    while true; do
        read -rp "  ${question} [${hint}]: " answer
        answer="${answer:-${default}}"
        answer="${answer,,}"  # lowercase
        case "${answer}" in
            y|yes) printf -v "${var_name}" 'y'; break ;;
            n|no)  printf -v "${var_name}" 'n'; break ;;
            *)     msg_err "Please answer y or n" ;;
        esac
    done
}

configure_routing_options() {
    msg_inf "Step 4/14: Configuring routing options..."
    echo
    msg_inf "Select routing features:"

    _prompt_yn "ENABLE_ADBLOCK" "Enable ad/tracker blocking?" "y"
    _prompt_yn "ENABLE_RU_ROUTING" "Enable direct routing for Russian sites/IPs?" "y"
    _prompt_yn "ENABLE_QUIC_BLOCK" "Block QUIC/HTTP3 for non-RU IPs?" "y"

    echo
    msg_ok "Routing: adblock=${ENABLE_ADBLOCK}, ru_routing=${ENABLE_RU_ROUTING}, quic_block=${ENABLE_QUIC_BLOCK}"
    echo
}
