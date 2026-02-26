#!/bin/bash
# Cron jobs setup module

setup_cron_jobs() {
    msg_inf "Step 14/14: Setting up cron jobs..."

    local cron_file="/etc/cron.d/routerus"
    cat > "${cron_file}" << 'EOF'
# RouteRus cron jobs

# SSL certificate auto-renewal — runs twice daily, reloads nginx on success
0 3,15 * * * root certbot renew --quiet --deploy-hook "systemctl reload nginx 2>/dev/null || true"

# x-ui watchdog — restart the panel if it goes down
* * * * * root systemctl is-active --quiet x-ui || systemctl restart x-ui
EOF

    chmod 644 "${cron_file}"

    # Reload cron daemon to pick up new file
    systemctl reload cron 2>/dev/null || systemctl reload crond 2>/dev/null || true

    msg_ok "Cron jobs configured"
    echo
}
