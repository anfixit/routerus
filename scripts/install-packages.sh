#!/bin/bash
# Package installation module

install_required_packages() {
    msg_inf "Step 5/14: Installing required packages..."

    export DEBIAN_FRONTEND=noninteractive

    local -a packages=(
        nginx
        certbot
        python3-certbot-nginx
        sqlite3
        jq
        ufw
        wget
        curl
        openssl
        cron
        lsof
        unzip
    )

    # Install all packages in one apt call
    if ! apt-get install -y -qq "${packages[@]}"; then
        msg_err "Failed to install required packages"
        return 1
    fi

    # Verify critical binaries are available
    local -a required_cmds=(nginx certbot sqlite3 jq openssl)
    for cmd in "${required_cmds[@]}"; do
        if ! command_exists "${cmd}"; then
            msg_err "Required command not found after install: ${cmd}"
            return 1
        fi
    done

    # Stop and disable nginx for now — it will be configured in step 10
    systemctl stop nginx 2>/dev/null || true
    systemctl disable nginx 2>/dev/null || true

    msg_ok "All required packages installed"
    echo
}
