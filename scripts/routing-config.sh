#!/bin/bash
# Routing options configuration module

# Ask a yes/no question, set the named variable to "y" or "n"
_ask_yn() {
    local question="$1"
    local varname="$2"
    local answer=""
    while true; do
        read -r -p "  ${question} [y/n]: " -n 1 answer
        echo
        case "${answer}" in
            y|Y) eval "${varname}=y"; return 0 ;;
            n|N) eval "${varname}=n"; return 0 ;;
            *)   msg_warn "Please enter y or n." ;;
        esac
    done
}

configure_routing_options() {
    msg_inf "Step 4/14: Configuring routing options..."
    echo

    # Adblock — block ads and trackers via routing rules
    if [[ "${ENABLE_ADBLOCK:-ask}" == "ask" ]]; then
        msg_inf "  Block ads and trackers (recommended for clean traffic)?"
        _ask_yn "Enable ad/tracker blocking" ENABLE_ADBLOCK
    fi

    # RU routing — send Russian sites directly, bypassing the tunnel
    if [[ "${ENABLE_RU_ROUTING:-ask}" == "ask" ]]; then
        msg_inf "  Route Russian sites directly without VPN (faster access to RU resources)?"
        _ask_yn "Enable direct routing for Russian sites" ENABLE_RU_ROUTING
    fi

    # QUIC block — block QUIC/HTTP3 for non-RU IPs (improves VPN stability)
    if [[ "${ENABLE_QUIC_BLOCK:-ask}" == "ask" ]]; then
        msg_inf "  Block QUIC protocol for non-RU IPs (reduces connection drops)?"
        _ask_yn "Block QUIC for non-RU IPs" ENABLE_QUIC_BLOCK
    fi

    echo
    msg_inf "  Routing settings:"
    msg_inf "    Adblock:              ${ENABLE_ADBLOCK}"
    msg_inf "    Direct RU routing:    ${ENABLE_RU_ROUTING}"
    msg_inf "    QUIC block (non-RU):  ${ENABLE_QUIC_BLOCK}"
    msg_ok "Routing options configured"
    echo
}
