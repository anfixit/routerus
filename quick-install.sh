#!/bin/bash
##########################################################################################
# RouteRus Quick Install Script
# Usage: bash <(wget -qO- https://raw.githubusercontent.com/anfixit/routerus/main/quick-install.sh)
##########################################################################################

set -e

echo "🚀 RouteRus Quick Installer"
echo "=============================="
echo

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root" 
   exit 1
fi

# Detect OS
if [ ! -f /etc/os-release ]; then
    echo "❌ Cannot detect OS version"
    exit 1
fi

source /etc/os-release

if [[ "$ID" != "ubuntu" ]] || [[ "${VERSION_ID}" != "24.04" ]]; then
    echo "⚠️  Warning: This script is designed for Ubuntu 24.04"
    echo "   Your OS: $PRETTY_NAME"
    read -p "   Continue anyway? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Download and run main installer
REPO_URL="https://raw.githubusercontent.com/anfixit/routerus/main"
TEMP_DIR="/tmp/routerus-install"

echo "📥 Downloading RouteRus..."
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

# Download main script
wget -q --show-progress -O install.sh "${REPO_URL}/install.sh" || {
    echo "❌ Failed to download installer"
    exit 1
}

chmod +x install.sh

echo
echo "✅ Downloaded successfully!"
echo "🚀 Starting installation..."
echo

# Run installer with all arguments passed to this script
./install.sh "$@"

# Cleanup
cd /
rm -rf "$TEMP_DIR"

exit 0
