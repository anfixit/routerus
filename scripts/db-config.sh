#!/bin/bash
# Database configuration module

# 3X-UI settings keys reference:
#   webPort       — panel listen port
#   webBasePath   — URL base path (e.g. /xT8nQ4vLp9/)
#   webCertFile   — path to SSL fullchain.pem
#   webKeyFile    — path to SSL privkey.pem
#   tgBotToken    — Telegram bot token
#   tgBotChatId   — Telegram admin chat ID
#   tgBotEnable   — enable Telegram notifications (true/false)

configure_database() {
    msg_inf "Step 8/14: Configuring database..."

    local db_path="${XUI_DB_PATH:-/etc/x-ui/x-ui.db}"

    if [[ ! -f "${db_path}" ]]; then
        msg_err "3X-UI database not found at ${db_path}"
        msg_inf "Make sure 3X-UI was installed successfully (step 6)"
        return 1
    fi

    backup_file "${db_path}"

    # Helper to upsert a setting in the 3X-UI settings table
    _db_set() {
        local key="$1"
        local value="$2"
        local exists
        exists="$(sqlite3 "${db_path}" \
            "SELECT COUNT(*) FROM settings WHERE key='${key}';")"
        if [[ "${exists}" -gt 0 ]]; then
            sqlite3 "${db_path}" \
                "UPDATE settings SET value='${value}' WHERE key='${key}';"
        else
            sqlite3 "${db_path}" \
                "INSERT INTO settings (key, value) VALUES ('${key}', '${value}');"
        fi
    }

    # Apply panel port and path
    if [[ -n "${PANEL_PORT:-}" ]]; then
        _db_set "webPort" "${PANEL_PORT}"
        msg_inf "Panel port: ${PANEL_PORT}"
    fi

    if [[ -n "${PANEL_PATH:-}" ]]; then
        _db_set "webBasePath" "${PANEL_PATH}"
        msg_inf "Panel path: ${PANEL_PATH}"
    fi

    # Apply SSL certificate paths
    if [[ -n "${CERT_PATH:-}" && -f "${CERT_PATH}" ]]; then
        _db_set "webCertFile" "${CERT_PATH}"
        _db_set "webKeyFile" "${KEY_PATH}"
        msg_inf "SSL certificates linked"
    fi

    # Apply panel credentials
    if [[ -n "${PANEL_USERNAME:-}" && -n "${PANEL_PASSWORD:-}" ]]; then
        local user_count
        user_count="$(sqlite3 "${db_path}" "SELECT COUNT(*) FROM users;" 2>/dev/null || echo 0)"
        if [[ "${user_count}" -gt 0 ]]; then
            sqlite3 "${db_path}" \
                "UPDATE users SET username='${PANEL_USERNAME}', password='${PANEL_PASSWORD}' WHERE id=1;"
        else
            sqlite3 "${db_path}" \
                "INSERT INTO users (username, password) VALUES ('${PANEL_USERNAME}', '${PANEL_PASSWORD}');"
        fi
        msg_inf "Panel credentials configured"
    fi

    # Telegram bot settings (optional)
    if [[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "${TELEGRAM_ADMIN_ID:-}" ]]; then
        _db_set "tgBotToken" "${TELEGRAM_BOT_TOKEN}"
        _db_set "tgBotChatId" "${TELEGRAM_ADMIN_ID}"
        _db_set "tgBotEnable" "true"
        msg_inf "Telegram bot configured"
    fi

    # Restart x-ui to apply new settings
    systemctl restart x-ui

    if ! wait_for_service "x-ui" 15; then
        msg_err "3X-UI failed to restart after database configuration"
        return 1
    fi

    unset -f _db_set

    msg_ok "Database configured and 3X-UI restarted"
    echo
}
