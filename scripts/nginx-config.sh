#!/bin/bash
# Nginx configuration module

NGINX_SITES="/etc/nginx/sites-available"
NGINX_ENABLED="/etc/nginx/sites-enabled"
NGINX_STREAM="/etc/nginx/stream-enabled"
FAKE_WEB_DIR="/var/www/html"

configure_nginx() {
    msg_inf "Step 10/14: Configuring Nginx..."

    if [[ -z "${DOMAIN:-}" ]]; then
        msg_warn "Panel domain not set — skipping Nginx configuration"
        echo
        return 0
    fi

    local panel_port="${PANEL_PORT:-2053}"
    local cert_file="${CERT_PATH:-/etc/letsencrypt/live/${DOMAIN}/fullchain.pem}"
    local key_file="${KEY_PATH:-/etc/letsencrypt/live/${DOMAIN}/privkey.pem}"

    mkdir -p "${NGINX_SITES}" "${NGINX_ENABLED}" "${NGINX_STREAM}"

    # Remove default site
    rm -f "${NGINX_ENABLED}/default"

    # --- Panel reverse proxy (HTTPS -> x-ui panel) ---
    cat > "${NGINX_SITES}/${DOMAIN}.conf" << VHOST
server {
    listen 80;
    server_name ${DOMAIN};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ${DOMAIN};

    ssl_certificate     ${cert_file};
    ssl_certificate_key ${key_file};
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 10m;

    # Panel proxy
    location ${PANEL_PATH:-/} {
        proxy_pass         http://127.0.0.1:${panel_port};
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
    }

    # WebSocket support for panel
    location ${PANEL_PATH:-/}ws {
        proxy_pass         http://127.0.0.1:${panel_port};
        proxy_http_version 1.1;
        proxy_set_header   Upgrade \$http_upgrade;
        proxy_set_header   Connection "upgrade";
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
    }

    # Fake website — serves static files for masking
    location / {
        root ${FAKE_WEB_DIR};
        index index.html;
    }
}
VHOST

    ln -sf "${NGINX_SITES}/${DOMAIN}.conf" "${NGINX_ENABLED}/"

    # --- Fake website ---
    mkdir -p "${FAKE_WEB_DIR}"
    if [[ ! -f "${FAKE_WEB_DIR}/index.html" ]]; then
        cat > "${FAKE_WEB_DIR}/index.html" << 'HTML'
<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Welcome</title><style>body{font-family:system-ui;display:flex;align-items:center;
justify-content:center;height:100vh;margin:0;background:#f5f5f5}
.c{text-align:center;color:#333}h1{font-size:2em}</style></head>
<body><div class="c"><h1>Welcome</h1><p>This server is under maintenance.</p></div></body>
</html>
HTML
    fi

    # --- Stream SNI routing for REALITY ---
    if [[ -n "${REALITY_DOMAIN:-}" ]]; then
        local nginx_conf="/etc/nginx/nginx.conf"
        if ! grep -q "stream-enabled" "${nginx_conf}" 2>/dev/null; then
            if ! grep -q "^stream" "${nginx_conf}" 2>/dev/null; then
                cat >> "${nginx_conf}" << 'STREAM'

stream {
    include /etc/nginx/stream-enabled/*.conf;
}
STREAM
            fi
        fi

        cat > "${NGINX_STREAM}/sni-routing.conf" << SNI
# SNI-based routing: REALITY domain -> Xray, everything else -> HTTPS backend
map \$ssl_preread_server_name \$backend {
    ${REALITY_DOMAIN}    xray_reality;
    default              https_default;
}

upstream xray_reality {
    server 127.0.0.1:${REALITY_LISTEN_PORT:-10443};
}

upstream https_default {
    server 127.0.0.1:4433;
}

server {
    listen 443;
    proxy_pass \$backend;
    ssl_preread on;
}
SNI
        msg_inf "  SNI routing: ${REALITY_DOMAIN} -> Xray REALITY"
    fi

    # Validate and reload nginx
    if ! nginx -t 2>/dev/null; then
        msg_err "Nginx configuration test failed"
        nginx -t 2>&1
        return 1
    fi

    systemctl enable nginx
    systemctl restart nginx

    if ! wait_for_service "nginx" 10; then
        msg_err "Nginx failed to start"
        return 1
    fi

    msg_ok "Nginx configured: reverse proxy + fake site"
    echo
}
