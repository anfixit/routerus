#!/bin/bash
# Routing rules setup module

GEOFILES_DIR="/usr/local/x-ui/bin"
GEOFILES_REPO="Loyalsoldier/v2ray-rules-dat"

setup_routing_rules() {
    msg_inf "Step 9/14: Setting up routing rules..."

    local configs_dir="${SCRIPT_DIR}/configs/routing"
    local base_config="${configs_dir}/base-routing.json"

    if [[ ! -f "${base_config}" ]]; then
        msg_err "Base routing config not found: ${base_config}"
        return 1
    fi

    # Start with base routing template
    local routing_json
    routing_json="$(cat "${base_config}")"

    # Add adblock rules
    if [[ "${ENABLE_ADBLOCK}" == "y" ]]; then
        local adblock_file="${configs_dir}/adblock-rule.json"
        if [[ -f "${adblock_file}" ]]; then
            routing_json="$(echo "${routing_json}" | jq \
                --slurpfile rule "${adblock_file}" \
                '.routing.rules += [$rule[0]]')"
            msg_inf "  Added: ad/tracker blocking rules"
        fi
    fi

    # Add Russian routing rules (domains, IPs, bittorrent)
    if [[ "${ENABLE_RU_ROUTING}" == "y" ]]; then
        local ru_file="${configs_dir}/ru-direct-rule.json"
        if [[ -f "${ru_file}" ]]; then
            routing_json="$(echo "${routing_json}" | jq \
                --slurpfile rules "${ru_file}" \
                '.routing.rules += [$rules[0].ru_domains, $rules[0].ru_ips, $rules[0].bittorrent]')"
            msg_inf "  Added: Russian domain/IP direct routing"
        fi
    fi

    # Add QUIC/NetBIOS blocking rules
    if [[ "${ENABLE_QUIC_BLOCK}" == "y" ]]; then
        local quic_file="${configs_dir}/quic-block-rule.json"
        if [[ -f "${quic_file}" ]]; then
            routing_json="$(echo "${routing_json}" | jq \
                --slurpfile rules "${quic_file}" \
                '.routing.rules += [$rules[0].quic_block, $rules[0].netbios_block]')"
            msg_inf "  Added: QUIC/HTTP3 + NetBIOS blocking"
        fi
    fi

    # Validate assembled JSON
    if ! echo "${routing_json}" | jq empty 2>/dev/null; then
        msg_err "Assembled routing JSON is invalid"
        return 1
    fi

    local rule_count
    rule_count="$(echo "${routing_json}" | jq '.routing.rules | length')"
    msg_inf "  Total routing rules: ${rule_count}"

    # Store routing config in 3X-UI database as xray template routing
    local db_path="${XUI_DB_PATH:-/etc/x-ui/x-ui.db}"
    if [[ -f "${db_path}" ]]; then
        # Build a minimal Xray template with just the routing section
        local xray_template
        xray_template="$(jq -n --argjson routing "${routing_json}" '$routing')"

        local exists
        exists="$(sqlite3 "${db_path}" \
            "SELECT COUNT(*) FROM settings WHERE key='xrayTemplateConfig';")"
        if [[ "${exists}" -gt 0 ]]; then
            sqlite3 "${db_path}" \
                "UPDATE settings SET value='${xray_template//\'/\'\'}' WHERE key='xrayTemplateConfig';"
        else
            sqlite3 "${db_path}" \
                "INSERT INTO settings (key, value) VALUES ('xrayTemplateConfig', '${xray_template//\'/\'\'}');"
        fi
    fi

    # Download/update GeoIP and GeoSite files
    if [[ "${UPDATE_GEOFILES:-y}" == "y" ]]; then
        msg_inf "  Updating GeoIP/GeoSite databases..."
        mkdir -p "${GEOFILES_DIR}"

        local -a geofiles=(geoip.dat geosite.dat)
        for file in "${geofiles[@]}"; do
            local url="https://github.com/${GEOFILES_REPO}/releases/latest/download/${file}"
            if wget -qO "${GEOFILES_DIR}/${file}" "${url}"; then
                msg_inf "  Updated: ${file}"
            else
                msg_warn "  Failed to download ${file} — using existing version"
            fi
        done
    fi

    # Restart x-ui to apply routing changes
    systemctl restart x-ui 2>/dev/null || true

    msg_ok "Routing rules applied (${rule_count} rules)"
    echo
}
