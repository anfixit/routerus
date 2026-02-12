#!/bin/bash
#################### RouteRus v1.0.0 ##################################
# GitHub: https://github.com/anfixit/routerus
# Based on x-ui-pro by @crazy_day_admin (https://t.me/crazy_day_admin)
# Routing by @Corvus-Malus (https://github.com/Corvus-Malus)
########################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_URL="https://raw.githubusercontent.com/anfixit/routerus/main"

# --- Helper: download and source a script module ---

load_module() {
    local script_name="$1"
    local local_path="${SCRIPT_DIR}/scripts/${script_name}"

    if [[ -f "${local_path}" ]]; then
        # shellcheck source=/dev/null
        source "${local_path}"
    else
        wget -qO "/tmp/${script_name}" "${REPO_URL}/scripts/${script_name}"
        # shellcheck source=/dev/null
        source "/tmp/${script_name}"
    fi
}

# --- Load helpers first ---

load_module "helpers.sh"

# --- Help (defined early so it's available during arg parsing) ---

show_help() {
    cat << 'EOF'
RouteRus - 3X-UI Pro Installation Script

Usage:
  ./install.sh [OPTIONS]

Options:
  --install yes|no             Installation mode (default: interactive)
  --subdomain DOMAIN           Panel domain (e.g., panel.duckdns.org)
  --reality-domain DOMAIN      REALITY domain (e.g., reality.duckdns.org)
  --enable-adblock y|n         Enable ad/tracker blocking
  --enable-ru-routing y|n      Enable direct routing for Russian sites
  --enable-quic-block y|n      Block QUIC for non-RU IPs
  --uninstall                  Uninstall RouteRus
  -h, --help                   Show this help message

Legacy single-dash options (-install, -subdomain, etc.) are also supported.

Examples:
  # Interactive installation
  ./install.sh

  # Automated installation
  ./install.sh --install yes --subdomain panel.duckdns.org \
    --reality-domain reality.duckdns.org --enable-adblock y \
    --enable-ru-routing y --enable-quic-block y

  # Uninstall
  ./install.sh --uninstall

More info: https://github.com/anfixit/routerus
EOF
}

# --- Root check ---

if [[ ${EUID} -ne 0 ]]; then
    msg_err "This script must be run as root!"
    exit 1
fi

# --- Banner ---

show_banner() {
    clear
    msg_inf '  ____              _       ____            '
    msg_inf ' |  _ \ ___  _   _| |_ ___|  _ \ _   _ ___ '
    msg_inf ' | |_) / _ \| | | | __/ _ \ |_) | | | / __|'
    msg_inf ' |  _ < (_) | |_| | ||  __/  _ <| |_| \__ \'
    msg_inf ' |_| \_\___/ \__,_|\__\___|_| \_\\__,_|___/'
    msg_inf '                                            '
    msg_inf ' 3X-UI Pro with Advanced Routing & REALITY '
    msg_inf ' Version: 1.0.0                             '
    echo
}

# --- Parse arguments ---

INSTALL_MODE="interactive"
DOMAIN=""
REALITY_DOMAIN=""
ENABLE_ADBLOCK="ask"
ENABLE_RU_ROUTING="ask"
ENABLE_QUIC_BLOCK="ask"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --install|-install)
            INSTALL_MODE="$2"; shift 2 ;;
        --subdomain|-subdomain)
            DOMAIN="$2"; shift 2 ;;
        --reality-domain|-reality_domain)
            REALITY_DOMAIN="$2"; shift 2 ;;
        --enable-adblock|-enable_adblock)
            ENABLE_ADBLOCK="$2"; shift 2 ;;
        --enable-ru-routing|-enable_ru_routing)
            ENABLE_RU_ROUTING="$2"; shift 2 ;;
        --enable-quic-block|-enable_quic_block)
            ENABLE_QUIC_BLOCK="$2"; shift 2 ;;
        --uninstall|-uninstall)
            load_module "uninstall.sh"
            uninstall_routerus
            exit 0
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            msg_err "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# --- Main installation ---

main() {
    show_banner
    msg_inf "Starting RouteRus Installation..."
    echo

    local -a steps=(
        "system-update.sh:update_system"
        "cleanup.sh:cleanup_old_installations"
        "domain-setup.sh:setup_domains"
        "routing-config.sh:configure_routing_options"
        "install-packages.sh:install_required_packages"
        "install-xui.sh:install_3xui"
        "ssl-setup.sh:setup_ssl_certificates"
        "db-config.sh:configure_database"
        "setup-routing.sh:setup_routing_rules"
        "nginx-config.sh:configure_nginx"
        "create-inbounds.sh:create_default_inbounds"
        "optimize.sh:optimize_system"
        "firewall.sh:configure_firewall"
        "cron-setup.sh:setup_cron_jobs"
        "show-results.sh:show_installation_results"
    )

    for step in "${steps[@]}"; do
        local module="${step%%:*}"
        local func="${step##*:}"
        load_module "${module}"
        "${func}"
    done
}

main
