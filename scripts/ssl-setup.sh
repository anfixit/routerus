#!/bin/bash
# SSL certificate setup module

setup_ssl_certificates() {
    msg_inf "Step 7/14: Setting up SSL certificates..."

    if [[ -z "${DOMAIN:-}" ]]; then
        msg_warn "Panel domain not set — skipping SSL setup"
        msg_inf "SSL can be configured later with: certbot certonly --standalone -d YOUR_DOMAIN"
        echo
        return 0
    fi

    # Ensure port 80 is free for certbot standalone verification
    systemctl stop nginx 2>/dev/null || true

    local certbot_email=""
    if [[ -n "${CLOUDFLARE_EMAIL:-}" ]]; then
        certbot_email="${CLOUDFLARE_EMAIL}"
    fi

    # Issue certificate for panel domain
    local cert_args=(
        certonly
        --standalone
        --non-interactive
        --agree-tos
        --preferred-challenges http
        -d "${DOMAIN}"
    )

    if [[ -n "${certbot_email}" ]]; then
        cert_args+=(--email "${certbot_email}")
    else
        cert_args+=(--register-unsafely-without-email)
    fi

    msg_inf "Requesting SSL certificate for ${DOMAIN}..."
    if ! certbot "${cert_args[@]}"; then
        msg_err "Failed to obtain SSL certificate for ${DOMAIN}"
        msg_inf "Make sure the domain points to this server's IP and port 80 is reachable"
        return 1
    fi

    # Store cert paths as globals for db-config.sh
    CERT_PATH="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
    KEY_PATH="/etc/letsencrypt/live/${DOMAIN}/privkey.pem"

    if [[ ! -f "${CERT_PATH}" || ! -f "${KEY_PATH}" ]]; then
        msg_err "SSL certificate files not found after certbot"
        return 1
    fi

    # Issue certificate for REALITY domain if different from panel domain
    if [[ -n "${REALITY_DOMAIN:-}" && "${REALITY_DOMAIN}" != "${DOMAIN}" ]]; then
        local reality_cert_args=(
            certonly
            --standalone
            --non-interactive
            --agree-tos
            --preferred-challenges http
            -d "${REALITY_DOMAIN}"
        )

        if [[ -n "${certbot_email}" ]]; then
            reality_cert_args+=(--email "${certbot_email}")
        else
            reality_cert_args+=(--register-unsafely-without-email)
        fi

        msg_inf "Requesting SSL certificate for ${REALITY_DOMAIN}..."
        if ! certbot "${reality_cert_args[@]}"; then
            msg_warn "Failed to obtain SSL for ${REALITY_DOMAIN} — REALITY may still work without it"
        fi
    fi

    msg_ok "SSL certificates configured"
    echo
}
