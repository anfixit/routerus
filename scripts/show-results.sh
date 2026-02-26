#!/bin/bash
# Installation results display module

show_installation_results() {
    # Detect public IP for the panel URL fallback
    local server_ip
    server_ip="$(curl -s4 --max-time 5 https://api.ipify.org 2>/dev/null \
        || curl -s4 --max-time 5 https://ifconfig.me 2>/dev/null \
        || echo "YOUR_SERVER_IP")"

    local panel_host="${DOMAIN:-${server_ip}}"
    local protocol="http"
    [[ -n "${DOMAIN:-}" && -f "${CERT_PATH:-}" ]] && protocol="https"

    local panel_url="${protocol}://${panel_host}:${PANEL_PORT:-54321}${PANEL_PATH:-/}"

    echo
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║           RouteRus Installation Complete!                   ║"
    echo "╠══════════════════════════════════════════════════════════════╣"
    echo "║  PANEL ACCESS                                               ║"
    printf "║  URL:      %-49s║\n" "${panel_url}"
    printf "║  Username: %-49s║\n" "${PANEL_USERNAME:-admin}"
    printf "║  Password: %-49s║\n" "${PANEL_PASSWORD:-admin}"
    echo "╠══════════════════════════════════════════════════════════════╣"
    echo "║  DOMAINS                                                    ║"
    printf "║  Panel:    %-49s║\n" "${DOMAIN:-not configured}"
    printf "║  REALITY:  %-49s║\n" "${REALITY_DOMAIN:-not configured}"
    echo "╠══════════════════════════════════════════════════════════════╣"
    echo "║  ROUTING FEATURES                                           ║"
    printf "║  Adblock:            %-39s║\n" "${ENABLE_ADBLOCK:-n}"
    printf "║  Direct RU routing:  %-39s║\n" "${ENABLE_RU_ROUTING:-n}"
    printf "║  QUIC block (non-RU):%-39s║\n" "${ENABLE_QUIC_BLOCK:-n}"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo
    msg_warn "SAVE THE CREDENTIALS ABOVE — they will not be shown again!"
    echo
}
