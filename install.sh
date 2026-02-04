#!/bin/bash
#################### RouteRus v1.0.0 - 3X-UI Pro Installation Script ##################
# GitHub: https://github.com/anfixit/routerus
# Based on x-ui-pro by @crazy_day_admin (https://t.me/crazy_day_admin)
# Routing by @Corvus-Malus (https://github.com/Corvus-Malus)
# Integrated and enhanced by RouteRus Team
########################################################################################

set -e

# Check root
[[ $EUID -ne 0 ]] && echo "❌ This script must be run as root!" && exit 1

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_URL="https://raw.githubusercontent.com/anfixit/routerus/main"

# Source helper functions
source "${SCRIPT_DIR}/scripts/helpers.sh" 2>/dev/null || {
    wget -qO /tmp/helpers.sh "${REPO_URL}/scripts/helpers.sh"
    source /tmp/helpers.sh
}

# Banner
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

show_banner

# Variables
INSTALL_MODE="interactive"
DOMAIN=""
REALITY_DOMAIN=""
ENABLE_ADBLOCK="ask"
ENABLE_RU_ROUTING="ask"
ENABLE_QUIC_BLOCK="ask"

# Parse arguments
while [ "$#" -gt 0 ]; do
    case "$1" in
        -install) INSTALL_MODE="$2"; shift 2;;
        -subdomain) DOMAIN="$2"; shift 2;;
        -reality_domain) REALITY_DOMAIN="$2"; shift 2;;
        -enable_adblock) ENABLE_ADBLOCK="$2"; shift 2;;
        -enable_ru_routing) ENABLE_RU_ROUTING="$2"; shift 2;;
        -enable_quic_block) ENABLE_QUIC_BLOCK="$2"; shift 2;;
        -uninstall)
            source "${SCRIPT_DIR}/scripts/uninstall.sh"
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

# Main installation steps
main() {
    msg_inf "🚀 Starting RouteRus Installation..."
    echo
    
    # Step 1: System Update
    source "${SCRIPT_DIR}/scripts/system-update.sh" || download_and_source "system-update.sh"
    update_system
    
    # Step 2: Cleanup old installations
    source "${SCRIPT_DIR}/scripts/cleanup.sh" || download_and_source "cleanup.sh"
    cleanup_old_installations
    
    # Step 3: Get domains
    source "${SCRIPT_DIR}/scripts/domain-setup.sh" || download_and_source "domain-setup.sh"
    setup_domains
    
    # Step 4: Configure routing options
    source "${SCRIPT_DIR}/scripts/routing-config.sh" || download_and_source "routing-config.sh"
    configure_routing_options
    
    # Step 5: Install packages
    source "${SCRIPT_DIR}/scripts/install-packages.sh" || download_and_source "install-packages.sh"
    install_required_packages
    
    # Step 6: Install 3X-UI
    source "${SCRIPT_DIR}/scripts/install-xui.sh" || download_and_source "install-xui.sh"
    install_3xui
    
    # Step 7: Configure SSL
    source "${SCRIPT_DIR}/scripts/ssl-setup.sh" || download_and_source "ssl-setup.sh"
    setup_ssl_certificates
    
    # Step 8: Configure database
    source "${SCRIPT_DIR}/scripts/db-config.sh" || download_and_source "db-config.sh"
    configure_database
    
    # Step 9: Setup routing
    source "${SCRIPT_DIR}/scripts/setup-routing.sh" || download_and_source "setup-routing.sh"
    setup_routing_rules
    
    # Step 10: Configure Nginx
    source "${SCRIPT_DIR}/scripts/nginx-config.sh" || download_and_source "nginx-config.sh"
    configure_nginx
    
    # Step 11: Create inbounds
    source "${SCRIPT_DIR}/scripts/create-inbounds.sh" || download_and_source "create-inbounds.sh"
    create_default_inbounds
    
    # Step 12: Optimize system
    source "${SCRIPT_DIR}/scripts/optimize.sh" || download_and_source "optimize.sh"
    optimize_system
    
    # Step 13: Setup firewall
    source "${SCRIPT_DIR}/scripts/firewall.sh" || download_and_source "firewall.sh"
    configure_firewall
    
    # Step 14: Setup cron jobs
    source "${SCRIPT_DIR}/scripts/cron-setup.sh" || download_and_source "cron-setup.sh"
    setup_cron_jobs
    
    # Final step: Show results
    source "${SCRIPT_DIR}/scripts/show-results.sh" || download_and_source "show-results.sh"
    show_installation_results
}

# Helper function to download and source scripts
download_and_source() {
    local script_name="$1"
    wget -qO "/tmp/${script_name}" "${REPO_URL}/scripts/${script_name}"
    source "/tmp/${script_name}"
}

# Help function
show_help() {
    cat << EOF
RouteRus - 3X-UI Pro Installation Script

Usage:
  ./install.sh [OPTIONS]

Options:
  -install yes|no              Installation mode (default: interactive)
  -subdomain DOMAIN            Panel domain (e.g., panel.duckdns.org)
  -reality_domain DOMAIN       REALITY domain (e.g., reality.duckdns.org)
  -enable_adblock y|n          Enable ad/tracker blocking
  -enable_ru_routing y|n       Enable direct routing for Russian sites
  -enable_quic_block y|n       Block QUIC for non-RU IPs
  -uninstall                   Uninstall RouteRus
  -h, --help                   Show this help message

Examples:
  # Interactive installation
  ./install.sh

  # Automated installation
  ./install.sh -install yes -subdomain panel.duckdns.org \\
    -reality_domain reality.duckdns.org -enable_adblock y \\
    -enable_ru_routing y -enable_quic_block y

  # Uninstall
  ./install.sh -uninstall

More info: https://github.com/anfixit/routerus
EOF
}

# Run main installation
main

exit 0
