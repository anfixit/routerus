#!/usr/bin/env bash
# =============================================================================
# deploy-remnanode.sh v3.0
# VLESS + Reality + XHTTP + steal_oneself
#
# Разворачивает remnawave-node на чистом Ubuntu 24.04
# Один домен на ноду. Xray на 443 напрямую. nginx — только fallback.
#
# Запуск:
#   bash <(wget -qO- https://raw.githubusercontent.com/anfixit/routerus/main/deploy-remnanode.sh)
#
# Архитектура:
#   Клиент → Xray:443 (Reality + XHTTP)
#     Reality-клиент → VPN-туннель
#     Не-Reality (DPI/проббер) → nginx:8443 (наш сайт, настоящий SSL)
#
# Фазы:
#    0  Проверки (root, Ubuntu 24)
#    1  Интерактивный ввод (домен, SSH-ключ)
#    2  Системные зависимости + Docker
#    3  Пользователь admin + SSH hardening (порт 2810, key-only)
#    4  fail2ban
#    5  Kernel tuning (sysctl BBR, TCP buffers, conntrack)
#    6  SSL-сертификат (certbot standalone)
#    7  nginx — HTTPS fallback-сайт (порт 8443)
#    8  Фейковый сайт
#    9  x25519 keygen + Config Profile JSON
#   10  Пауза: создание Config Profile + Node в панели
#   11  remnawave-node (docker compose, network_mode: host)
#   12  Geo-файлы + cron автообновления
#   13  Docker log rotation + unattended-upgrades
#   14  Watchdog cron
#   15  UFW
#   16  Beszel agent (интерактивно)
#   17  Итог + чеклист для панели
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# ── Цвета ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

ok()    { echo -e "${GREEN}  ✔ $1${NC}"; }
info()  { echo -e "${CYAN}  ℹ $1${NC}"; }
warn()  { echo -e "${YELLOW}  ⚠ $1${NC}"; }
die()   { echo -e "${RED}  ✖ $1${NC}"; exit 1; }
title() { echo -e "\n${BLUE}━━━ $1 ━━━${NC}"; }
ask()   { echo -ne "${YELLOW}  ▸ $1: ${NC}"; }

SCRIPT_VERSION="3.0"
LOG_FILE="/var/log/deploy-remnanode.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# =============================================================================
# ФАЗА 0: Проверки
# =============================================================================
phase0_checks() {
    title "Фаза 0 / Проверки"

    [[ $EUID -ne 0 ]] && die "Запусти от root: sudo bash $0" || true
    ok "root"

    source /etc/os-release 2>/dev/null || die "Не могу прочитать /etc/os-release"
    [[ "$ID" == "ubuntu" && "${VERSION_ID%%.*}" -ge 24 ]] \
        || die "Нужна Ubuntu 24.04+, у тебя $PRETTY_NAME"
    ok "Ubuntu $VERSION_ID"

    # Проверка DNS
    ping -c1 -W3 google.com &>/dev/null || die "Нет интернета"
    ok "Интернет доступен"

    echo ""
    echo -e "${GREEN}  deploy-remnanode.sh v${SCRIPT_VERSION}${NC}"
    echo -e "${GREEN}  VLESS + Reality + XHTTP + steal_oneself${NC}"
    echo ""
}

# =============================================================================
# ФАЗА 1: Интерактивный ввод
# =============================================================================
phase1_input() {
    title "Фаза 1 / Параметры"

    # ── Домен ─────────────────────────────────────────────────────────────────
    echo ""
    info "При steal_oneself нужен ОДИН домен на ноду."
    info "Домен должен резолвиться на IP этого сервера."
    info "Пример: studio-web.ru, dev-console.ru"
    echo ""

    ask "Домен для этой ноды"
    read -r DOMAIN </dev/tty
    [[ -z "$DOMAIN" ]] && die "Домен не может быть пустым" || true

    # Проверяем DNS
    RESOLVED_IP=$(dig +short "$DOMAIN" A 2>/dev/null | head -1)
    SERVER_IP=$(curl -s4 ifconfig.me 2>/dev/null || curl -s4 icanhazip.com 2>/dev/null)

    if [[ -n "$RESOLVED_IP" && "$RESOLVED_IP" == "$SERVER_IP" ]]; then
        ok "DNS: $DOMAIN → $RESOLVED_IP (совпадает с IP сервера)"
    elif [[ -n "$RESOLVED_IP" ]]; then
        warn "DNS: $DOMAIN → $RESOLVED_IP, но IP сервера = $SERVER_IP"
        warn "Если домен только что создан — DNS может ещё не обновиться"
        ask "Продолжить? (y/n)"
        read -r CONT </dev/tty
        [[ "$CONT" != "y" ]] && die "Прервано. Подожди DNS-делегирование и запусти заново" || true
    else
        warn "Не удалось резолвнуть $DOMAIN — проверь DNS A-запись"
        ask "Продолжить? (y/n)"
        read -r CONT </dev/tty
        [[ "$CONT" != "y" ]] && die "Прервано" || true
    fi

    # ── SSH-ключ ──────────────────────────────────────────────────────────────
    echo ""
    info "SSH-ключ для пользователя admin (ed25519 или rsa)."
    info "На маке: cat ~/.ssh/id_ed25519.pub"
    echo ""
    ask "Вставь публичный SSH-ключ"
    read -r SSH_PUB_KEY </dev/tty
    [[ -z "$SSH_PUB_KEY" ]] && die "SSH-ключ не может быть пустым" || true
    [[ "$SSH_PUB_KEY" != ssh-* ]] && die "Неверный формат SSH-ключа (должен начинаться с ssh-)" || true
    ok "SSH-ключ принят"

    # ── Имя ноды ──────────────────────────────────────────────────────────────
    echo ""
    ask "Имя ноды (для тегов, например DE_natty_narwhal)"
    read -r NODE_NAME </dev/tty
    [[ -z "$NODE_NAME" ]] && NODE_NAME=$(echo "$DOMAIN" | tr '.-' '_')
    ok "Имя ноды: $NODE_NAME"

    echo ""
    info "Параметры:"
    info "  Домен:    $DOMAIN"
    info "  IP:       $SERVER_IP"
    info "  Нода:     $NODE_NAME"
    info "  SSH-ключ: ${SSH_PUB_KEY:0:40}..."
    echo ""
    ask "Всё верно? (y/n)"
    read -r CONFIRM </dev/tty
    [[ "$CONFIRM" != "y" ]] && die "Прервано. Запусти заново" || true
}

# =============================================================================
# ФАЗА 2: Зависимости + Docker
# =============================================================================
phase2_deps() {
    title "Фаза 2 / Системные зависимости"

    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get upgrade -y -qq
    apt-get install -y -qq \
        curl wget git jq openssl cron dnsutils \
        nginx-full certbot fail2ban \
        unattended-upgrades apt-listchanges \
        ca-certificates gnupg lsb-release \
        2>/dev/null
    ok "Пакеты установлены"

    # Docker
    if ! command -v docker &>/dev/null; then
        info "Устанавливаю Docker..."
        curl -fsSL https://get.docker.com | sh
        systemctl enable --now docker
        ok "Docker установлен"
    else
        ok "Docker уже есть: $(docker --version | cut -d' ' -f3)"
    fi

    # Сброс ошибок Docker (Ubuntu 24.04 quirk)
    systemctl reset-failed docker 2>/dev/null || true
}

# =============================================================================
# ФАЗА 3: Пользователь admin + SSH hardening
# =============================================================================
phase3_ssh() {
    title "Фаза 3 / SSH hardening"

    SSH_PORT=2810

    # Создаём пользователя admin
    if id "admin" &>/dev/null; then
        ok "Пользователь admin уже существует"
    else
        groupadd -f admin
        useradd -m -s /bin/bash -g admin -G sudo,docker admin 2>/dev/null \
            || useradd -m -s /bin/bash -G sudo,docker admin 2>/dev/null
        ok "Пользователь admin создан"
    fi

    # SSH-ключ
    mkdir -p /home/admin/.ssh
    echo "$SSH_PUB_KEY" > /home/admin/.ssh/authorized_keys
    chmod 700 /home/admin/.ssh
    chmod 600 /home/admin/.ssh/authorized_keys
    chown -R admin:$(id -gn admin) /home/admin/.ssh
    ok "SSH-ключ установлен"

    # Passwordless sudo
    echo "admin ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/admin
    chmod 440 /etc/sudoers.d/admin
    ok "sudo без пароля"

    # SSH config
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%s)

    cat > /etc/ssh/sshd_config.d/hardening.conf << SSHEOF
Port $SSH_PORT
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
X11Forwarding no
AllowUsers admin
SSHEOF

    # Ubuntu 24.04: ssh.socket конфликтует с ssh.service
    systemctl disable ssh.socket 2>/dev/null || true
    systemctl stop ssh.socket 2>/dev/null || true

    # Перезапуск SSH (на Ubuntu 24 сервис называется ssh, не sshd)
    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
    ok "SSH: порт $SSH_PORT, key-only, root запрещён"

    warn "ВАЖНО: Проверь подключение из ДРУГОГО терминала:"
    warn "  ssh -p $SSH_PORT admin@$SERVER_IP"
    warn "  Потом: sudo su -"
}

# =============================================================================
# ФАЗА 4: fail2ban
# =============================================================================
phase4_fail2ban() {
    title "Фаза 4 / fail2ban"

    cat > /etc/fail2ban/jail.local << 'F2BEOF'
[sshd]
enabled  = true
port     = 2810
filter   = sshd
logpath  = /var/log/auth.log
maxretry = 3
bantime  = 3600
findtime = 600
F2BEOF

    systemctl enable fail2ban
    systemctl restart fail2ban
    ok "fail2ban: SSH на порту 2810, бан после 3 попыток"
}

# =============================================================================
# ФАЗА 5: Kernel tuning
# =============================================================================
phase5_sysctl() {
    title "Фаза 5 / Kernel tuning"

    cat > /etc/sysctl.d/99-remnanode.conf << 'SYSEOF'
# ── BBR ──
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# ── TCP buffers ──
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# ── Conntrack ──
net.netfilter.nf_conntrack_max = 131072

# ── TCP keepalive ──
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5

# ── SYN flood protection ──
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_syn_retries = 3

# ── Disable ICMP redirects ──
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# ── Disable source routing ──
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0

# ── File descriptors ──
fs.file-max = 1048576
fs.nr_open = 1048576
SYSEOF

    sysctl -p /etc/sysctl.d/99-remnanode.conf >/dev/null 2>&1
    ok "BBR, TCP buffers, conntrack, SYN flood protection"
}

# =============================================================================
# ФАЗА 6: SSL-сертификат
# =============================================================================
phase6_ssl() {
    title "Фаза 6 / SSL-сертификат"

    # Останавливаем nginx и освобождаем порт 80
    systemctl stop nginx 2>/dev/null || true
    fuser -k 80/tcp 2>/dev/null || true
    sleep 1

    if [[ -d "/etc/letsencrypt/live/${DOMAIN}" ]]; then
        ok "SSL для $DOMAIN уже есть"
    else
        info "Получаю SSL для $DOMAIN..."
        certbot certonly --standalone --non-interactive \
            --agree-tos --register-unsafely-without-email \
            -d "$DOMAIN" \
            || die "Не удалось получить SSL для $DOMAIN. Проверь: dig $DOMAIN A +short"
        ok "SSL $DOMAIN получен"
    fi

    # Автопродление certbot (не через systemd — порт 80 будет занят)
    # Используем webroot или pre/post hooks
    cat > /etc/letsencrypt/cli.ini << CERTEOF
# Certbot renewal config
# При продлении останавливаем nginx, получаем сертификат, запускаем
pre-hook = systemctl stop nginx || true; fuser -k 80/tcp || true
post-hook = systemctl start nginx || true
CERTEOF

    # Таймер certbot (если не создан)
    systemctl enable certbot.timer 2>/dev/null || true
    ok "Автопродление SSL настроено"
}

# =============================================================================
# ФАЗА 7: nginx — HTTPS fallback (порт 8443)
# =============================================================================
phase7_nginx() {
    title "Фаза 7 / nginx fallback"

    info "nginx = fallback-сайт с настоящим SSL на порту 8443"
    info "Reality dest → 127.0.0.1:8443 (DPI/пробберы видят реальный сайт)"

    # Убираем дефолтный сайт
    rm -f /etc/nginx/sites-enabled/default

    # Основной сайт с SSL (порт 8443)
    # xver: 1 в Reality → nginx получает PROXY protocol
    cat > /etc/nginx/sites-available/${DOMAIN}.conf << NGXEOF
server {
    listen 8443 ssl http2 proxy_protocol;
    listen [::]:8443 ssl http2 proxy_protocol;
    server_name ${DOMAIN};

    set_real_ip_from 127.0.0.1;
    real_ip_header proxy_protocol;
    server_tokens off;

    ssl_certificate     /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    root /var/www/html;
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
NGXEOF

    # Редирект HTTP → HTTPS (порт 80 — для общего использования)
    cat > /etc/nginx/sites-available/redirect.conf << 'RDEOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    return 301 https://$host$request_uri;
}
RDEOF

    ln -sf /etc/nginx/sites-available/${DOMAIN}.conf /etc/nginx/sites-enabled/
    ln -sf /etc/nginx/sites-available/redirect.conf /etc/nginx/sites-enabled/

    # nginx НЕ нужен stream модуль (в отличие от v2.2)
    # Убираем stream если был от старого деплоя
    rm -f /etc/nginx/stream-enabled/*.conf 2>/dev/null || true
    sed -i '/stream {/,/}/d' /etc/nginx/nginx.conf 2>/dev/null || true

    nginx -t || die "nginx конфиг невалиден"
    systemctl enable nginx
    systemctl start nginx
    ok "nginx: HTTPS fallback на порту 8443"
}

# =============================================================================
# ФАЗА 8: Фейковый сайт
# =============================================================================
phase8_fakesite() {
    title "Фаза 8 / Фейковый сайт"

    mkdir -p /var/www/html
    bash <(wget -qO- https://raw.githubusercontent.com/mozaroc/x-ui-pro/refs/heads/master/randomfakehtml.sh) 2>/dev/null \
        || {
            # Fallback если скрипт недоступен
            cat > /var/www/html/index.html << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Welcome</title>
    <style>
        body { font-family: -apple-system, sans-serif; margin: 40px auto; max-width: 650px; line-height: 1.6; color: #444; padding: 0 10px; }
        h1 { line-height: 1.2; }
    </style>
</head>
<body>
    <h1>Welcome to our site</h1>
    <p>This server is running normally. Thank you for visiting.</p>
    <p><small>&copy; 2024-2026</small></p>
</body>
</html>
HTMLEOF
        }
    ok "Фейковый сайт развёрнут в /var/www/html"
}

# =============================================================================
# ФАЗА 9: x25519 keygen + Config Profile JSON
# =============================================================================
phase9_keygen() {
    title "Фаза 9 / x25519 ключи + Config Profile"

    mkdir -p /opt/remnanode

    # Генерируем x25519 ключи через Docker (Xray)
    info "Генерирую x25519 ключи..."
    KEY_OUTPUT=$(docker run --rm ghcr.io/xtls/xray-core:latest xray x25519 2>/dev/null) \
        || KEY_OUTPUT=$(docker run --rm teddysun/xray:latest xray x25519 2>/dev/null) \
        || KEY_OUTPUT=$(docker run --rm ghcr.io/xtls/xray-core x25519 2>/dev/null) \
        || die "Не удалось сгенерировать x25519 ключи"

    PRIVATE_KEY=$(echo "$KEY_OUTPUT" | grep -i "private" | awk '{print $NF}')
    PUBLIC_KEY=$(echo "$KEY_OUTPUT" | grep -i "public" | awk '{print $NF}')

    [[ -z "$PRIVATE_KEY" || -z "$PUBLIC_KEY" ]] && die "Не удалось извлечь ключи" || true

    # Сохраняем ключи
    cat > /opt/remnanode/keys.txt << KEYSEOF
# x25519 keys generated $(date +%Y-%m-%d)
PRIVATE_KEY=$PRIVATE_KEY
PUBLIC_KEY=$PUBLIC_KEY
KEYSEOF
    chmod 600 /opt/remnanode/keys.txt

    ok "Ключи сгенерированы"
    echo ""
    echo -e "${GREEN}  Private Key: $PRIVATE_KEY${NC}"
    echo -e "${GREEN}  Public Key:  $PUBLIC_KEY${NC}"
    echo ""

    # Генерируем shortIds
    SHORT_IDS=$(openssl rand -hex 8)

    # Выводим готовый Config Profile JSON
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  ГОТОВЫЙ JSON ДЛЯ CONFIG PROFILE В REMNAWAVE              ║${NC}"
    echo -e "${CYAN}║  Скопируй и вставь в: Config Profiles → Create            ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    cat << JSONEOF
{
  "log": {
    "loglevel": "warning"
  },
  "dns": {
    "servers": [
      {
        "address": "https://94.140.14.14/dns-query",
        "domains": [],
        "skipFallback": false
      },
      "localhost"
    ]
  },
  "inbounds": [
    {
      "tag": "${NODE_NAME}_xhttp",
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none"
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "reality",
        "xhttpSettings": {
          "mode": "auto",
          "path": "/xhp",
          "extra": {
            "noSSEHeader": true,
            "xPaddingBytes": "100-1000",
            "scMaxBufferedPosts": 30,
            "scMaxEachPostBytes": 1000000,
            "scStreamUpServerSecs": "20-80"
          }
        },
        "realitySettings": {
          "dest": "127.0.0.1:8443",
          "show": false,
          "xver": 1,
          "shortIds": ["", "a1", "bc23", "def456", "${SHORT_IDS}"],
          "privateKey": "${PRIVATE_KEY}",
          "serverNames": ["${DOMAIN}"]
        }
      }
    }
  ],
  "outbounds": [
    {"tag": "DIRECT", "protocol": "freedom"},
    {"tag": "BLOCK", "protocol": "blackhole"}
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "network": "udp",
        "port": "443",
        "outboundTag": "BLOCK"
      },
      {
        "type": "field",
        "protocol": ["bittorrent"],
        "outboundTag": "DIRECT"
      },
      {
        "type": "field",
        "domain": [
          "geosite:category-ads-all",
          "geosite:win-spy",
          "domain:doubleclick.net",
          "domain:googlesyndication.com",
          "domain:googleadservices.com",
          "domain:google-analytics.com",
          "domain:analytics.yandex.ru",
          "domain:mc.yandex.ru",
          "domain:crashlytics.com",
          "domain:app-measurement.com",
          "domain:appcenter.ms"
        ],
        "outboundTag": "BLOCK"
      },
      {
        "type": "field",
        "network": "udp",
        "port": "135,137,138,139",
        "outboundTag": "BLOCK"
      },
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "DIRECT"
      }
    ]
  }
}
JSONEOF

    echo ""
    info "Сохрани этот JSON — он понадобится для шага 10"
    echo ""
}

# =============================================================================
# ФАЗА 10: Пауза — создание в панели Remnawave
# =============================================================================
phase10_panel() {
    title "Фаза 10 / Настройка в панели Remnawave"

    echo ""
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  СЕЙЧАС ПЕРЕКЛЮЧИСЬ В ПАНЕЛЬ REMNAWAVE И СДЕЛАЙ:           ║${NC}"
    echo -e "${YELLOW}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${YELLOW}║                                                            ║${NC}"
    echo -e "${YELLOW}║  1. Config Profiles → Create                               ║${NC}"
    echo -e "${YELLOW}║     Имя: ${NODE_NAME}_xhttp                                ║${NC}"
    echo -e "${YELLOW}║     Вставь JSON из фазы 9 (выше)                           ║${NC}"
    echo -e "${YELLOW}║                                                            ║${NC}"
    echo -e "${YELLOW}║  2. Nodes → Create                                         ║${NC}"
    echo -e "${YELLOW}║     Name: ${NODE_NAME}                                     ║${NC}"
    echo -e "${YELLOW}║     Address: ${SERVER_IP}                                  ║${NC}"
    echo -e "${YELLOW}║     Port: 2222                                             ║${NC}"
    echo -e "${YELLOW}║     Привязать Config Profile: ${NODE_NAME}_xhttp           ║${NC}"
    echo -e "${YELLOW}║     → Скопируй SECRET_KEY после создания!                  ║${NC}"
    echo -e "${YELLOW}║                                                            ║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    ask "Вставь SECRET_KEY из панели"
    read -r SECRET_KEY </dev/tty
    [[ -z "$SECRET_KEY" ]] && die "SECRET_KEY не может быть пустым" || true
    ok "SECRET_KEY принят"
}

# =============================================================================
# ФАЗА 11: remnawave-node (Docker Compose)
# =============================================================================
phase11_docker() {
    title "Фаза 11 / remnawave-node"

    mkdir -p /opt/remnanode/geodata

    cat > /opt/remnanode/.env << ENVEOF
# remnawave-node v3.0
SSL_CERT=/etc/letsencrypt/live/${DOMAIN}/fullchain.pem
SSL_KEY=/etc/letsencrypt/live/${DOMAIN}/privkey.pem
NODE_SECRET=${SECRET_KEY}
ENVEOF
    chmod 600 /opt/remnanode/.env

    cat > /opt/remnanode/docker-compose.yml << DCEOF
services:
  remnawave-node:
    image: remnawave/node:latest
    container_name: remnawave-node
    restart: unless-stopped
    network_mode: host
    env_file: .env
    cap_add:
      - NET_ADMIN
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    volumes:
      - /etc/letsencrypt/live/${DOMAIN}/fullchain.pem:/etc/letsencrypt/live/${DOMAIN}/fullchain.pem:ro
      - /etc/letsencrypt/live/${DOMAIN}/privkey.pem:/etc/letsencrypt/live/${DOMAIN}/privkey.pem:ro
      - /etc/letsencrypt/archive/${DOMAIN}:/etc/letsencrypt/archive/${DOMAIN}:ro
      - /opt/remnanode/geodata/geosite.dat:/usr/local/share/xray/geosite.dat:ro
      - /opt/remnanode/geodata/geoip.dat:/usr/local/share/xray/geoip.dat:ro
DCEOF

    cd /opt/remnanode
    docker compose pull
    docker compose up -d
    ok "remnawave-node запущен (network_mode: host, Xray на порту 443)"

    # Ждём запуска
    sleep 5
    if docker ps | grep -q remnawave-node; then
        ok "Контейнер remnawave-node работает"
    else
        warn "Контейнер не запустился. Проверь: docker logs remnawave-node"
    fi
}

# =============================================================================
# ФАЗА 12: Geo-файлы + cron
# =============================================================================
phase12_geo() {
    title "Фаза 12 / Geo-файлы"

    local GEO_DIR="/opt/remnanode/geodata"

    # Скачиваем (jsDelivr блокирует файлы >50MB, используем raw.githubusercontent.com)
    info "Скачиваю geosite.dat и geoip.dat (runetfreedom)..."
    wget -q --timeout=30 --tries=3 \
        "https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/geosite.dat" \
        -O "${GEO_DIR}/geosite.dat" \
        || warn "Не удалось скачать geosite.dat"

    wget -q --timeout=30 --tries=3 \
        "https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/geoip.dat" \
        -O "${GEO_DIR}/geoip.dat" \
        || warn "Не удалось скачать geoip.dat"

    [[ -f "${GEO_DIR}/geosite.dat" ]] && ok "geosite.dat: $(du -h ${GEO_DIR}/geosite.dat | cut -f1)"
    [[ -f "${GEO_DIR}/geoip.dat" ]] && ok "geoip.dat: $(du -h ${GEO_DIR}/geoip.dat | cut -f1)"

    # Скрипт автообновления
    cat > /opt/remnanode/update-geo.sh << 'GEOEOF'
#!/bin/bash
GEO_DIR="/opt/remnanode/geodata"
LOG="/var/log/geo-update.log"

wget -q --timeout=30 --tries=3 \
    "https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/geosite.dat" \
    -O "${GEO_DIR}/geosite.dat.tmp" && \
    mv "${GEO_DIR}/geosite.dat.tmp" "${GEO_DIR}/geosite.dat"

wget -q --timeout=30 --tries=3 \
    "https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/geoip.dat" \
    -O "${GEO_DIR}/geoip.dat.tmp" && \
    mv "${GEO_DIR}/geoip.dat.tmp" "${GEO_DIR}/geoip.dat"

cd /opt/remnanode && docker compose restart
echo "$(date '+%Y-%m-%d %H:%M:%S') geo updated" >> "$LOG"
GEOEOF
    chmod +x /opt/remnanode/update-geo.sh

    # Cron: обновление каждую ночь в 03:00
    CRON_LINE="0 3 * * * /opt/remnanode/update-geo.sh"
    (crontab -l 2>/dev/null || true) | grep -v "update-geo" | { cat; echo "$CRON_LINE"; } | crontab -
    ok "Cron: автообновление geo в 03:00"
}

# =============================================================================
# ФАЗА 13: Docker log rotation + unattended-upgrades
# =============================================================================
phase13_maintenance() {
    title "Фаза 13 / Docker log rotation + auto-updates"

    # Docker log rotation
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json << 'DKEOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
DKEOF
    systemctl restart docker 2>/dev/null || true
    ok "Docker: log rotation 10MB × 3"

    # Unattended upgrades
    cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'UUEOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::Automatic-Reboot "false";
UUEOF
    systemctl enable unattended-upgrades
    ok "Автообновления безопасности включены"
}

# =============================================================================
# ФАЗА 14: Watchdog cron
# =============================================================================
phase14_watchdog() {
    title "Фаза 14 / Watchdog"

    cat > /opt/remnanode/watchdog.sh << 'WDEOF'
#!/bin/bash
if ! docker ps | grep -q remnawave-node; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') watchdog: restarting remnawave-node" >> /var/log/watchdog.log
    cd /opt/remnanode && docker compose up -d
fi
WDEOF
    chmod +x /opt/remnanode/watchdog.sh

    CRON_WD="*/5 * * * * /opt/remnanode/watchdog.sh"
    (crontab -l 2>/dev/null || true) | grep -v "watchdog" | { cat; echo "$CRON_WD"; } | crontab -
    ok "Watchdog: проверка контейнера каждые 5 минут"
}

# =============================================================================
# ФАЗА 15: UFW
# =============================================================================
phase15_ufw() {
    title "Фаза 15 / UFW"

    ufw --force reset >/dev/null 2>&1
    ufw default deny incoming
    ufw default allow outgoing

    ufw allow 2810/tcp comment "SSH"
    ufw allow 443/tcp  comment "Xray Reality XHTTP"
    ufw allow 80/tcp   comment "HTTP redirect + certbot"
    ufw allow 8443/tcp comment "nginx fallback"
    ufw allow 2222/tcp comment "Remnawave node API"

    ufw --force enable
    ok "UFW: 2810(SSH) 443(Xray) 80(HTTP) 8443(nginx) 2222(API)"
}

# =============================================================================
# ФАЗА 16: Beszel agent (интерактивно)
# =============================================================================
phase16_beszel() {
    title "Фаза 16 / Beszel agent"

    echo ""
    ask "Установить Beszel agent? (y/n)"
    read -r INSTALL_BESZEL </dev/tty

    if [[ "$INSTALL_BESZEL" == "y" ]]; then
        echo ""
        info "Beszel hub: http://23.88.3.239:51068"
        info "Чтобы добавить ноду в Beszel:"
        info "  1. Зайди в Beszel UI → Systems → Add System"
        info "  2. Name: ${NODE_NAME}"
        info "  3. Host: ${SERVER_IP}"
        info "  4. Port: 45876"
        info "  5. Скопируй Token и Key из Beszel"
        echo ""

        ask "Вставь Beszel TOKEN"
        read -r BESZEL_TOKEN </dev/tty

        ask "Вставь Beszel KEY (ssh-ed25519 ...)"
        read -r BESZEL_KEY </dev/tty

        if [[ -n "$BESZEL_TOKEN" && -n "$BESZEL_KEY" ]]; then
            # Открываем порт для Beszel
            ufw allow 45876/tcp comment "Beszel agent"

            # Удаляем старый агент и volume если есть
            docker stop beszel-agent 2>/dev/null || true
            docker rm beszel-agent 2>/dev/null || true
            docker volume rm beszel_agent_data 2>/dev/null || true

            docker run -d \
                --name beszel-agent \
                --restart unless-stopped \
                --network host \
                -e LISTEN=:45876 \
                -e KEY="$BESZEL_KEY" \
                -v /var/run/docker.sock:/var/run/docker.sock:ro \
                henrygd/beszel-agent:latest

            if docker ps | grep -q beszel-agent; then
                ok "Beszel agent запущен на порту 45876"
            else
                warn "Beszel agent не запустился. Проверь: docker logs beszel-agent"
            fi
        else
            warn "Token или Key не указаны, пропускаю Beszel"
        fi
    else
        info "Beszel пропущен. Можно установить позже"
    fi
}

# =============================================================================
# ФАЗА 17: Итог
# =============================================================================
phase17_summary() {
    title "Фаза 17 / Готово!"

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  DEPLOY v3.0 ЗАВЕРШЁН                                      ║${NC}"
    echo -e "${GREEN}║  VLESS + Reality + XHTTP + steal_oneself                    ║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║                                                            ║${NC}"
    echo -e "${GREEN}║  Домен:       ${DOMAIN}${NC}"
    echo -e "${GREEN}║  IP:          ${SERVER_IP}${NC}"
    echo -e "${GREEN}║  Нода:        ${NODE_NAME}${NC}"
    echo -e "${GREEN}║  SSH:         ssh -p 2810 admin@${SERVER_IP}${NC}"
    echo -e "${GREEN}║  Private Key: ${PRIVATE_KEY}${NC}"
    echo -e "${GREEN}║  Public Key:  ${PUBLIC_KEY}${NC}"
    echo -e "${GREEN}║                                                            ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  ⚠ ОБЯЗАТЕЛЬНО СДЕЛАЙ В ПАНЕЛИ REMNAWAVE:                 ║${NC}"
    echo -e "${YELLOW}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${YELLOW}║                                                            ║${NC}"
    echo -e "${YELLOW}║  3. Hosts → Create                                         ║${NC}"
    echo -e "${YELLOW}║     Inbound tag: ${NODE_NAME}_xhttp                        ║${NC}"
    echo -e "${YELLOW}║     Address:     ${DOMAIN}                                 ║${NC}"
    echo -e "${YELLOW}║     Port:        443                                       ║${NC}"
    echo -e "${YELLOW}║     SNI:         ${DOMAIN}   (тот же — steal_oneself!)     ║${NC}"
    echo -e "${YELLOW}║     Fingerprint: chrome                                    ║${NC}"
    echo -e "${YELLOW}║     ALPN:        h2                                        ║${NC}"
    echo -e "${YELLOW}║                                                            ║${NC}"
    echo -e "${YELLOW}║  4. Internal Squads → Default-Squad                        ║${NC}"
    echo -e "${YELLOW}║     → Добавь inbound ${NODE_NAME}_xhttp                   ║${NC}"
    echo -e "${YELLOW}║     ⚠ БЕЗ ЭТОГО НОДА НЕ ПОПАДЁТ В ПОДПИСКУ!              ║${NC}"
    echo -e "${YELLOW}║                                                            ║${NC}"
    echo -e "${YELLOW}║  5. Проверь: Nodes → нода должна быть зелёная              ║${NC}"
    echo -e "${YELLOW}║     Happ → обнови подписку → пинг есть → работает!         ║${NC}"
    echo -e "${YELLOW}║                                                            ║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    info "Ключи сохранены в /opt/remnanode/keys.txt"
    info "Лог деплоя: $LOG_FILE"
    echo ""
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    phase0_checks
    phase1_input
    phase2_deps
    phase3_ssh
    phase4_fail2ban
    phase5_sysctl
    phase6_ssl
    phase7_nginx
    phase8_fakesite
    phase9_keygen
    phase10_panel
    phase11_docker
    phase12_geo
    phase13_maintenance
    phase14_watchdog
    phase15_ufw
    phase16_beszel
    phase17_summary
}

main "$@"
