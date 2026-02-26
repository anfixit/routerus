#!/bin/bash
# Firewall configuration module

configure_firewall() {
    msg_inf "Step 13/14: Configuring firewall..."

    if ! command_exists ufw; then
        msg_warn "ufw not installed — skipping firewall configuration"
        return 0
    fi

    # Use custom SSH port if defined in .env, otherwise default to 22
    local ssh_port="${CUSTOM_SSH_PORT:-22}"

    # Reset to clean defaults without prompting
    ufw --force reset

    ufw default deny incoming
    ufw default allow outgoing

    # SSH — must always be first to avoid locking ourselves out
    ufw allow "${ssh_port}/tcp" comment "SSH"

    # HTTP — required for Let's Encrypt challenge and HTTP→HTTPS redirect
    ufw allow 80/tcp comment "HTTP"

    # HTTPS — main traffic
    ufw allow 443/tcp comment "HTTPS TCP"
    ufw allow 443/udp comment "HTTPS QUIC"

    # 3X-UI panel port (randomised during install)
    if [[ -n "${PANEL_PORT:-}" ]]; then
        ufw allow "${PANEL_PORT}/tcp" comment "3X-UI panel"
    fi

    ufw --force enable

    msg_ok "Firewall configured"
    echo
}
