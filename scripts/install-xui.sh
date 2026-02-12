#!/bin/bash
# 3X-UI installation module

XUI_INSTALL_DIR="/usr/local/x-ui"
XUI_DB_PATH="/etc/x-ui/x-ui.db"
XUI_SERVICE="x-ui"
XUI_REPO="MHSanaei/3x-ui"

install_3xui() {
    msg_inf "Step 6/14: Installing 3X-UI..."

    # Generate panel credentials for later use (db-config.sh will apply them)
    PANEL_PORT="$(make_free_port)"
    PANEL_PATH="/$(gen_random_string 10)/"
    if [[ -z "${PANEL_USERNAME:-}" ]]; then
        PANEL_USERNAME="$(gen_random_string 10)"
    fi
    if [[ -z "${PANEL_PASSWORD:-}" ]]; then
        PANEL_PASSWORD="$(gen_random_string 16)"
    fi

    msg_inf "Generated panel port: ${PANEL_PORT}"

    # Get latest release tag from GitHub API
    local latest_version
    latest_version="$(wget -qO- "https://api.github.com/repos/${XUI_REPO}/releases/latest" \
        | jq -r '.tag_name')" || {
        msg_err "Failed to query GitHub API for latest 3X-UI release"
        return 1
    }

    if [[ -z "${latest_version}" || "${latest_version}" == "null" ]]; then
        msg_err "Could not determine latest 3X-UI version"
        return 1
    fi

    msg_inf "Latest 3X-UI version: ${latest_version}"

    # Determine architecture
    local arch
    case "$(uname -m)" in
        x86_64)  arch="amd64" ;;
        aarch64) arch="arm64" ;;
        armv7l)  arch="armv7" ;;
        *)
            msg_err "Unsupported architecture: $(uname -m)"
            return 1
            ;;
    esac

    # Download release archive
    local download_url="https://github.com/${XUI_REPO}/releases/download/${latest_version}/x-ui-linux-${arch}.tar.gz"
    local tmp_archive
    tmp_archive="$(mktemp /tmp/x-ui-XXXXXXXXXX.tar.gz)"

    msg_inf "Downloading 3X-UI ${latest_version} (${arch})..."
    if ! wget -qO "${tmp_archive}" "${download_url}"; then
        rm -f "${tmp_archive}"
        msg_err "Failed to download 3X-UI from ${download_url}"
        return 1
    fi

    if [[ ! -s "${tmp_archive}" ]]; then
        rm -f "${tmp_archive}"
        msg_err "Downloaded 3X-UI archive is empty"
        return 1
    fi

    # Stop existing service if running
    systemctl stop "${XUI_SERVICE}" 2>/dev/null || true

    # Extract to installation directory
    mkdir -p "${XUI_INSTALL_DIR}"
    mkdir -p /etc/x-ui

    if ! tar -xzf "${tmp_archive}" -C "${XUI_INSTALL_DIR}" --strip-components=1; then
        rm -f "${tmp_archive}"
        msg_err "Failed to extract 3X-UI archive"
        return 1
    fi
    rm -f "${tmp_archive}"

    chmod +x "${XUI_INSTALL_DIR}/x-ui"
    chmod +x "${XUI_INSTALL_DIR}/bin/xray-linux-${arch}" 2>/dev/null || true

    # Create systemd service
    cat > /etc/systemd/system/${XUI_SERVICE}.service << 'UNIT'
[Unit]
Description=x-ui Service
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/usr/local/x-ui/
ExecStart=/usr/local/x-ui/x-ui
Restart=on-failure
RestartSec=5s
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
UNIT

    systemctl daemon-reload
    systemctl enable "${XUI_SERVICE}"
    systemctl start "${XUI_SERVICE}"

    # Wait for service to start
    if ! wait_for_service "${XUI_SERVICE}" 15; then
        msg_err "3X-UI service failed to start"
        return 1
    fi

    msg_ok "3X-UI ${latest_version} installed and running"
    echo
}
