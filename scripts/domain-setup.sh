#!/bin/bash
# Domain setup module

# Validate basic domain/hostname format (letters, digits, dots, hyphens)
_domain_valid() {
    local d="$1"
    [[ "${d}" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]]
}

# Prompt user to enter a valid domain. Echoes the validated value to stdout.
_prompt_domain() {
    local prompt="$1"
    local input=""
    while true; do
        read -r -p "  ${prompt}: " input
        input="${input// /}"   # strip accidental spaces
        if [[ -z "${input}" ]]; then
            msg_warn "Domain cannot be empty — please try again."
            continue
        fi
        if _domain_valid "${input}"; then
            echo "${input}"
            return 0
        else
            msg_err "Invalid format: '${input}'"
            msg_inf "  Use only letters, digits, dots (.) and hyphens (-)."
        fi
    done
}

setup_domains() {
    msg_inf "Step 3/14: Domain configuration..."

    # Skip interactive prompts when both domains are already provided
    # (e.g. via --subdomain / --reality-domain flags or .env file)
    if [[ -n "${DOMAIN:-}" && -n "${REALITY_DOMAIN:-}" ]]; then
        if ! _domain_valid "${DOMAIN}"; then
            msg_err "Panel domain is invalid: '${DOMAIN}'"
            return 1
        fi
        if ! _domain_valid "${REALITY_DOMAIN}"; then
            msg_err "REALITY domain is invalid: '${REALITY_DOMAIN}'"
            return 1
        fi
        msg_inf "  Panel domain:   ${DOMAIN}"
        msg_inf "  REALITY domain: ${REALITY_DOMAIN}"
        msg_ok "Domains configured"
        echo
        return 0
    fi

    echo
    msg_warn "You need TWO domains/subdomains:"
    msg_inf "  1. Panel domain  — for the 3X-UI web management interface"
    msg_inf "  2. REALITY domain — for VLESS+REALITY protocol (SNI masking)"
    echo
    msg_inf "  Tip: get FREE subdomains at https://www.duckdns.org"
    msg_inf "  Both must point to this server's IP address before you run this script."
    echo

    # Panel domain
    if [[ -z "${DOMAIN:-}" ]]; then
        DOMAIN="$(_prompt_domain "Enter panel domain   (e.g. panel.yourname.duckdns.org)")"
    fi

    # REALITY domain
    if [[ -z "${REALITY_DOMAIN:-}" ]]; then
        REALITY_DOMAIN="$(_prompt_domain "Enter REALITY domain (e.g. reality.yourname.duckdns.org)")"
    fi

    if [[ "${DOMAIN}" == "${REALITY_DOMAIN}" ]]; then
        msg_warn "Warning: panel and REALITY domains are identical. Allowed, but not recommended."
    fi

    echo
    msg_inf "  Panel domain:   ${DOMAIN}"
    msg_inf "  REALITY domain: ${REALITY_DOMAIN}"
    msg_ok "Domains configured"
    echo
}
