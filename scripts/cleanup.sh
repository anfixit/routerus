#!/bin/bash
# Cleanup old installations

cleanup_old_installations() {
    msg_inf "🧹 Step 2/14: Cleaning up old installations..."
    
    systemctl stop x-ui 2>/dev/null || true
    systemctl stop nginx 2>/dev/null || true
    
    rm -rf /etc/systemd/system/x-ui.service
    rm -rf /usr/local/x-ui
    rm -rf /etc/x-ui
    rm -rf /etc/nginx/sites-enabled/*
    rm -rf /etc/nginx/sites-available/*
    rm -rf /etc/nginx/stream-enabled/*
    
    msg_ok "✓ Cleanup completed!"
    echo
}
