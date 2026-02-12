#!/bin/bash
##########################################################################
# RouteRus Quick Install Script
# Usage: bash <(wget -qO- https://raw.githubusercontent.com/anfixit/routerus/main/quick-install.sh)
##########################################################################

set -euo pipefail

REPO_URL="https://raw.githubusercontent.com/anfixit/routerus/main"
TEMP_DIR=""

cleanup() {
    if [[ -n "${TEMP_DIR}" && -d "${TEMP_DIR}" ]]; then
        rm -rf "${TEMP_DIR}"
    fi
}
trap cleanup EXIT INT TERM

echo "RouteRus Quick Installer"
echo "=============================="
echo

if [[ ${EUID} -ne 0 ]]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

if [[ ! -f /etc/os-release ]]; then
    echo "ERROR: Cannot detect OS version"
    exit 1
fi

# shellcheck source=/dev/null
source /etc/os-release

if [[ "${ID}" != "ubuntu" ]] || [[ "${VERSION_ID}" != "24.04" ]]; then
    echo "Warning: This script is designed for Ubuntu 24.04"
    echo "  Your OS: ${PRETTY_NAME}"
    read -r -p "  Continue anyway? (y/n): " -n 1
    echo
    if [[ ! ${REPLY} =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

TEMP_DIR="$(mktemp -d /tmp/routerus-install-XXXXXXXXXX)"

echo "Downloading RouteRus..."

wget -q --show-progress -O "${TEMP_DIR}/install.sh" "${REPO_URL}/install.sh" || {
    echo "ERROR: Failed to download installer"
    exit 1
}

# Verify the download is a shell script
if ! head -1 "${TEMP_DIR}/install.sh" | grep -q '^#!/bin/bash'; then
    echo "ERROR: Downloaded file is not a valid installer"
    exit 1
fi

chmod +x "${TEMP_DIR}/install.sh"

echo
echo "Downloaded successfully!"
echo "Starting installation..."
echo

"${TEMP_DIR}/install.sh" "$@"
