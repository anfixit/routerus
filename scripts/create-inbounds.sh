#!/bin/bash
# Inbound creation module

# REALITY target domains for TLS camouflage
REALITY_DEST="yahoo.com:443"
REALITY_SERVER_NAMES='["yahoo.com","www.yahoo.com"]'

create_default_inbounds() {
    msg_inf "Step 11/14: Creating default inbounds..."

    local db_path="${XUI_DB_PATH:-/etc/x-ui/x-ui.db}"

    if [[ ! -f "${db_path}" ]]; then
        msg_err "3X-UI database not found: ${db_path}"
        return 1
    fi

    # Determine Xray binary path
    local xray_bin=""
    local arch
    case "$(uname -m)" in
        x86_64)  arch="amd64" ;;
        aarch64) arch="arm64" ;;
        armv7l)  arch="armv7" ;;
        *)       arch="amd64" ;;
    esac
    xray_bin="${XUI_INSTALL_DIR:-/usr/local/x-ui}/bin/xray-linux-${arch}"

    if [[ ! -x "${xray_bin}" ]]; then
        msg_err "Xray binary not found: ${xray_bin}"
        return 1
    fi

    # Generate x25519 keypair for REALITY
    local keypair
    keypair="$("${xray_bin}" x25519 2>/dev/null)" || {
        msg_err "Failed to generate x25519 keypair"
        return 1
    }

    local private_key
    local public_key
    private_key="$(echo "${keypair}" | grep 'Private' | awk '{print $NF}')"
    public_key="$(echo "${keypair}" | grep 'Public' | awk '{print $NF}')"

    if [[ -z "${private_key}" || -z "${public_key}" ]]; then
        msg_err "Failed to parse x25519 keys"
        return 1
    fi

    # Generate short ID (8 hex chars)
    local short_id
    short_id="$(openssl rand -hex 4)"

    # Generate client UUID
    local client_id
    client_id="$("${xray_bin}" uuid 2>/dev/null)" || {
        client_id="$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen)"
    }

    # Pick a listen port for REALITY inbound
    REALITY_LISTEN_PORT="$(make_free_port)"

    local inbound_port="${REALITY_LISTEN_PORT}"
    local remark="VLESS-REALITY"

    # Build inbound settings JSON
    local settings
    settings="$(jq -n \
        --arg id "${client_id}" \
        '{
            clients: [{
                id: $id,
                flow: "xtls-rprx-vision",
                email: "default@routerus",
                limitIp: 0,
                totalGB: 0,
                expiryTime: 0,
                enable: true
            }],
            decryption: "none",
            fallbacks: []
        }')"

    # Build stream settings JSON
    local stream_settings
    stream_settings="$(jq -n \
        --arg pk "${private_key}" \
        --arg dest "${REALITY_DEST}" \
        --arg shortId "${short_id}" \
        --argjson serverNames "${REALITY_SERVER_NAMES}" \
        '{
            network: "tcp",
            security: "reality",
            realitySettings: {
                show: false,
                xver: 0,
                dest: $dest,
                serverNames: $serverNames,
                privateKey: $pk,
                minClient: "",
                maxClient: "",
                maxTimediff: 0,
                shortIds: [$shortId]
            },
            tcpSettings: {
                acceptProxyProtocol: false,
                header: { type: "none" }
            }
        }')"

    # Build sniffing settings
    local sniffing='{"enabled":true,"destOverride":["http","tls","quic","fakedns"],"metadataOnly":false,"routeOnly":false}'

    # Insert inbound into database
    sqlite3 "${db_path}" "INSERT INTO inbounds (
        user_id, up, down, total, remark, enable, expiry_time,
        listen, port, protocol, settings, stream_settings, tag, sniffing
    ) VALUES (
        1, 0, 0, 0,
        '${remark}', 1, 0,
        '', ${inbound_port}, 'vless',
        '${settings//\'/\'\'}',
        '${stream_settings//\'/\'\'}',
        'inbound-${inbound_port}',
        '${sniffing}'
    );"

    # Restart x-ui to load new inbound
    systemctl restart x-ui
    if ! wait_for_service "x-ui" 15; then
        msg_err "3X-UI failed to restart after inbound creation"
        return 1
    fi

    # Store connection info for show-results.sh
    REALITY_PUBLIC_KEY="${public_key}"
    REALITY_SHORT_ID="${short_id}"
    REALITY_CLIENT_ID="${client_id}"

    msg_inf "  VLESS+REALITY inbound on port ${inbound_port}"
    msg_ok "Inbound created: VLESS+REALITY (xtls-rprx-vision)"
    echo
}
