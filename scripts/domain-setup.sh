#!/bin/bash
# Domain setup module

# Prompt for a domain value if not already set.
# Usage: _prompt_domain "VARNAME" "Prompt text"
_prompt_domain() {
    local var_name="$1"
    local prompt_text="$2"
    local current_value="${!var_name:-}"

    if [[ -n "${current_value}" ]]; then
        msg_inf "${prompt_text}: ${current_value} (from args/env)"
        return 0
    fi

    while true; do
        read -rp "  ${prompt_text}: " value
        if [[ -z "${value}" ]]; then
            msg_err "Domain cannot be empty"
            continue
        fi
        if [[ ! "${value}" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]]; then
            msg_err "Invalid domain format. Example: panel.duckdns.org"
            continue
        fi
        # Set the global variable
        printf -v "${var_name}" '%s' "${value}"
        break
    done
}

setup_domains() {
    msg_inf "Step 3/14: Domain configuration..."
    msg_warn "You need TWO domains/subdomains:"
    msg_inf "  1. Panel domain (web interface)"
    msg_inf "  2. REALITY domain (protocol masking)"
    echo
    msg_inf "Get FREE subdomains: https://www.duckdns.org"
    echo

    _prompt_domain "DOMAIN" "Panel domain (e.g. panel.duckdns.org)"
    _prompt_domain "REALITY_DOMAIN" "REALITY domain (e.g. reality.duckdns.org)"
    echo

    if [[ "${DOMAIN}" == "${REALITY_DOMAIN}" ]]; then
        msg_err "Panel and REALITY domains must be different!"
        return 1
    fi

    msg_ok "Domains: panel=${DOMAIN}, reality=${REALITY_DOMAIN}"
    echo
}
