#!/bin/bash
# System update module

update_system() {
    msg_inf "Step 1/14: Updating system packages..."

    export DEBIAN_FRONTEND=noninteractive

    # Refresh package index first
    apt-get update -qq

    # Install baseline tools required before any other step runs.
    # These are safe to install on any Debian/Ubuntu server and are needed
    # by subsequent steps (wget for downloads, ca-certificates for TLS, etc.)
    apt-get install -y -qq \
        ca-certificates \
        curl \
        wget \
        gnupg \
        lsb-release \
        software-properties-common \
        apt-transport-https \
        net-tools \
        htop \
        nano \
        tzdata

    # Full system upgrade
    apt-get upgrade -y -qq
    apt-get dist-upgrade -y -qq
    apt-get autoremove -y -qq
    apt-get autoclean -qq

    msg_ok "System updated successfully"
    echo
}
