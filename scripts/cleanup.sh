#!/bin/bash
# Cleanup old installations

cleanup_old_installations() {
    msg_inf "Step 2/14: Cleaning up old installations..."

    systemctl stop x-ui 2>/dev/null || true
    systemctl stop nginx 2>/dev/null || true

    local -a paths=(
        /etc/systemd/system/x-ui.service
        /usr/local/x-ui
        /etc/x-ui
    )
    for path in "${paths[@]}"; do
        if [[ -e "${path}" ]]; then
            rm -rf "${path}"
        fi
    done

    # Clean nginx virtual hosts (only files, not the directories themselves)
    local -a nginx_dirs=(
        /etc/nginx/sites-enabled
        /etc/nginx/sites-available
        /etc/nginx/stream-enabled
    )
    for dir in "${nginx_dirs[@]}"; do
        if [[ -d "${dir}" ]]; then
            find "${dir}" -maxdepth 1 -type f -delete
        fi
    done

    msg_ok "Cleanup completed"
    echo
}
