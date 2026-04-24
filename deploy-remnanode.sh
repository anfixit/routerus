#!/usr/bin/env bash
# =============================================================================
# deploy-remnanode.sh v3.1
# VLESS + Reality + XHTTP + steal_oneself
#
# Разворачивает remnawave-node на чистом Ubuntu 24.04
# Один домен на ноду. Xray на 443 напрямую. nginx — только fallback.
#
# Запуск:
#   wget -O deploy.sh https://raw.githubusercontent.com/anfixit/routerus/main/deploy-remnanode.sh
#   bash deploy.sh
#
# Changelog v3.1:
#   - FIX: NODE_PORT=2222 в .env (Required)
#   - FIX: geo-файлы скачиваются ДО docker compose up
#   - FIX: daemon.json ДО запуска контейнера
#   - FIX: все read из /dev/tty
#   - FIX: все условия через if/then (безопасно для set -e)
#   - FIX: psmisc в списке пакетов (fuser)
#   - FIX: sysctl conntrack с обработкой ошибок
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

ok()    { echo -e "${GREEN}  ✔ $1${NC}"; }
info()  { echo -e "${CYAN}  ℹ $1${NC}"; }
warn()  { echo -e "${YELLOW}  ⚠ $1${NC}"; }
die()   { echo -e "${RED}  ✖ $1${NC}"; exit 1; }
title() { echo -e "\n${BLUE}━━━ $1 ━━━${NC}"; }
ask()   { echo -ne "${YELLOW}  ▸ $1: ${NC}"; }

SCRIPT_VERSION="3.2"
LOG_FILE="/var/log/deploy-remnanode.log"
exec > >(tee -a "$LOG_FILE") 2>&1

phase0_checks() {
    title "Фаза 0 / Проверки"
    if [[ $EUID -ne 0 ]]; then die "Запусти от root: sudo bash $0"; fi
    ok "root"
    source /etc/os-release 2>/dev/null || die "Не могу прочитать /etc/os-release"
    if [[ "$ID" != "ubuntu" || "${VERSION_ID%%.*}" -lt 24 ]]; then
        die "Нужна Ubuntu 24.04+, у тебя $PRETTY_NAME"
    fi
    ok "Ubuntu $VERSION_ID"
    ping -c1 -W3 google.com &>/dev/null || die "Нет интернета"
    ok "Интернет доступен"
    echo ""
    echo -e "${GREEN}  deploy-remnanode.sh v${SCRIPT_VERSION}${NC}"
    echo -e "${GREEN}  VLESS + Reality + XHTTP + steal_oneself${NC}"
    echo ""
}

phase1_input() {
    title "Фаза 1 / Параметры"
    echo ""
    info "При steal_oneself нужен ОДИН домен на ноду."
    info "Домен должен резолвиться на IP этого сервера."
    info "Пример: studio-web.ru, dev-console.ru"
    echo ""
    ask "Домен для этой ноды"
    read -r DOMAIN </dev/tty
    if [[ -z "$DOMAIN" ]]; then die "Домен не может быть пустым"; fi

    RESOLVED_IP=$(dig +short "$DOMAIN" A 2>/dev/null | head -1) || true
    SERVER_IP=$(curl -s4 ifconfig.me 2>/dev/null || curl -s4 icanhazip.com 2>/dev/null) || true

    if [[ -n "$RESOLVED_IP" && "$RESOLVED_IP" == "$SERVER_IP" ]]; then
        ok "DNS: $DOMAIN → $RESOLVED_IP (совпадает с IP сервера)"
    elif [[ -n "$RESOLVED_IP" ]]; then
        warn "DNS: $DOMAIN → $RESOLVED_IP, но IP сервера = $SERVER_IP"
        ask "Продолжить? (y/n)"
        read -r CONT </dev/tty
        if [[ "$CONT" != "y" ]]; then die "Прервано"; fi
    else
        warn "Не удалось резолвнуть $DOMAIN — проверь DNS A-запись"
        ask "Продолжить? (y/n)"
        read -r CONT </dev/tty
        if [[ "$CONT" != "y" ]]; then die "Прервано"; fi
    fi

    echo ""
    info "SSH-ключ для пользователя admin (ed25519 или rsa)."
    info "На маке: cat ~/.ssh/id_ed25519.pub"
    echo ""
    ask "Вставь публичный SSH-ключ"
    read -r SSH_PUB_KEY </dev/tty
    if [[ -z "$SSH_PUB_KEY" ]]; then die "SSH-ключ не может быть пустым"; fi
    if [[ "$SSH_PUB_KEY" != ssh-* ]]; then die "Неверный формат (должен начинаться с ssh-)"; fi
    ok "SSH-ключ принят"

    echo ""
    ask "Имя ноды (для тегов, например DE_natty_narwhal)"
    read -r NODE_NAME </dev/tty
    if [[ -z "$NODE_NAME" ]]; then
        NODE_NAME=$(echo "$DOMAIN" | tr '.-' '_')
    fi
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
    if [[ "$CONFIRM" != "y" ]]; then die "Прервано. Запусти заново"; fi
}

phase2_deps() {
    title "Фаза 2 / Системные зависимости"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get upgrade -y -qq
    apt-get install -y -qq \
        curl wget git jq openssl cron dnsutils psmisc \
        nginx-full certbot fail2ban \
        unattended-upgrades apt-listchanges \
        ca-certificates gnupg lsb-release \
        2>/dev/null
    ok "Пакеты установлены"

    if ! command -v docker &>/dev/null; then
        info "Устанавливаю Docker..."
        curl -fsSL https://get.docker.com | sh
        systemctl enable --now docker
        ok "Docker установлен"
    else
        ok "Docker уже есть: $(docker --version | cut -d' ' -f3)"
    fi
    systemctl reset-failed docker 2>/dev/null || true

    # Docker log rotation (ДО запуска контейнеров!)
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json << 'DKEOF'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
DKEOF
    systemctl restart docker 2>/dev/null || true
    ok "Docker: log rotation 10MB × 3"
}

phase3_ssh() {
    title "Фаза 3 / SSH hardening"
    SSH_PORT=2810
    if id "admin" &>/dev/null; then
        ok "Пользователь admin уже существует"
    else
        groupadd -f admin
        useradd -m -s /bin/bash -g admin -G sudo,docker admin 2>/dev/null \
            || useradd -m -s /bin/bash -G sudo,docker admin 2>/dev/null
        ok "Пользователь admin создан"
    fi
    mkdir -p /home/admin/.ssh
    echo "$SSH_PUB_KEY" > /home/admin/.ssh/authorized_keys
    chmod 700 /home/admin/.ssh
    chmod 600 /home/admin/.ssh/authorized_keys
    chown -R admin:$(id -gn admin) /home/admin/.ssh
    ok "SSH-ключ установлен"
    echo "admin ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/admin
    chmod 440 /etc/sudoers.d/admin
    ok "sudo без пароля"

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
    systemctl disable ssh.socket 2>/dev/null || true
    systemctl stop ssh.socket 2>/dev/null || true
    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
    ok "SSH: порт $SSH_PORT, key-only, root запрещён"
    warn "ВАЖНО: Проверь подключение из ДРУГОГО терминала:"
    warn "  ssh -p $SSH_PORT admin@$SERVER_IP"
}

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

phase5_sysctl() {
    title "Фаза 5 / Kernel tuning"
    cat > /etc/sysctl.d/99-remnanode.conf << 'SYSEOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_syn_retries = 3
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
fs.file-max = 1048576
fs.nr_open = 1048576
SYSEOF
    sysctl -p /etc/sysctl.d/99-remnanode.conf >/dev/null 2>&1 || true
    modprobe nf_conntrack 2>/dev/null || true
    sysctl -w net.netfilter.nf_conntrack_max=131072 >/dev/null 2>&1 || true
    ok "BBR, TCP buffers, SYN flood protection"
}

phase6_ssl() {
    title "Фаза 6 / SSL-сертификат"
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
    cat > /etc/letsencrypt/cli.ini << CERTEOF
pre-hook = systemctl stop nginx || true; fuser -k 80/tcp || true
post-hook = systemctl start nginx || true
CERTEOF
    systemctl enable certbot.timer 2>/dev/null || true
    ok "Автопродление SSL настроено"
}

phase7_nginx() {
    title "Фаза 7 / nginx fallback"
    info "Reality dest → 127.0.0.1:8443 (DPI/пробберы видят реальный сайт)"
    rm -f /etc/nginx/sites-enabled/default
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
    cat > /etc/nginx/sites-available/redirect.conf << 'RDEOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    return 301 https://$host$request_uri;
}
RDEOF
    ln -sf /etc/nginx/sites-available/${DOMAIN}.conf /etc/nginx/sites-enabled/
    ln -sf /etc/nginx/sites-available/redirect.conf /etc/nginx/sites-enabled/
    rm -f /etc/nginx/stream-enabled/*.conf 2>/dev/null || true
    sed -i '/stream {/,/}/d' /etc/nginx/nginx.conf 2>/dev/null || true
    nginx -t || die "nginx конфиг невалиден"
    systemctl enable nginx
    systemctl start nginx
    ok "nginx: HTTPS fallback на порту 8443"
}

phase8_fakesite() {
    title "Фаза 8 / Фейковый сайт"
    mkdir -p /var/www/html

    # Встроенный генератор рандомных бизнес-сайтов
    # Без внешних скачиваний, без палёных шаблонов
    local THEMES=(
        "Web Development Studio|We build modern web applications|Web Development,Cloud Solutions,API Integration,DevOps Consulting"
        "Digital Marketing Agency|Data-driven marketing for growing brands|SEO Optimization,Content Strategy,PPC Management,Social Media"
        "Cloud Infrastructure|Enterprise-grade cloud hosting solutions|Managed Hosting,Auto Scaling,24/7 Monitoring,CDN Services"
        "Design Bureau|Creative solutions for digital products|UI/UX Design,Brand Identity,Motion Graphics,Print Design"
        "IT Consulting|Technology solutions for modern business|Infrastructure Audit,Security Assessment,Migration Planning,Team Training"
        "Software Solutions|Custom software for complex problems|Enterprise Apps,Mobile Development,Data Analytics,System Integration"
        "Network Services|Reliable connectivity for your business|Network Design,VoIP Solutions,Fiber Optics,Managed WiFi"
        "Data Analytics|Turn your data into actionable insights|Business Intelligence,Data Warehousing,ML Models,Dashboards"
    )

    local COLORS=(
        "#2563eb|#1e40af|#eff6ff"
        "#059669|#047857|#ecfdf5"
        "#7c3aed|#6d28d9|#f5f3ff"
        "#dc2626|#b91c1c|#fef2f2"
        "#0891b2|#0e7490|#ecfeff"
        "#d97706|#b45309|#fffbeb"
        "#4f46e5|#4338ca|#eef2ff"
        "#0d9488|#0f766e|#f0fdfa"
    )

    local IDX=$((RANDOM % ${#THEMES[@]}))
    local CIDX=$((RANDOM % ${#COLORS[@]}))

    IFS='|' read -r BIZ_NAME BIZ_DESC BIZ_SERVICES <<< "${THEMES[$IDX]}"
    IFS='|' read -r COLOR1 COLOR2 BG_COLOR <<< "${COLORS[$CIDX]}"

    # Извлекаем красивое имя из домена
    local SITE_NAME
    SITE_NAME=$(echo "$DOMAIN" | sed 's/\.[^.]*$//' | sed 's/[-_]/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2))}1')

    local YEAR
    YEAR=$(date +%Y)

    cat > /var/www/html/index.html << SITEEOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${SITE_NAME} — ${BIZ_NAME}</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; color: #1f2937; background: #fff; }
        .hero { background: linear-gradient(135deg, ${COLOR1}, ${COLOR2}); color: #fff; padding: 80px 20px; text-align: center; }
        .hero h1 { font-size: 2.5rem; font-weight: 700; margin-bottom: 1rem; }
        .hero p { font-size: 1.2rem; opacity: 0.9; max-width: 600px; margin: 0 auto; }
        .container { max-width: 960px; margin: 0 auto; padding: 60px 20px; }
        .services { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 24px; margin-top: 40px; }
        .card { background: ${BG_COLOR}; border-radius: 12px; padding: 24px; text-align: center; }
        .card h3 { color: ${COLOR1}; margin-bottom: 8px; font-size: 1.1rem; }
        .card p { color: #6b7280; font-size: 0.9rem; line-height: 1.5; }
        .about { margin-top: 60px; line-height: 1.8; color: #4b5563; }
        footer { text-align: center; padding: 40px 20px; color: #9ca3af; font-size: 0.85rem; border-top: 1px solid #f3f4f6; margin-top: 60px; }
        a { color: ${COLOR1}; }
    </style>
</head>
<body>
    <div class="hero">
        <h1>${SITE_NAME}</h1>
        <p>${BIZ_DESC}</p>
    </div>
    <div class="container">
        <h2 style="text-align:center;font-size:1.8rem;">Our Services</h2>
        <div class="services">
SITEEOF

    # Генерируем карточки из списка услуг
    IFS=',' read -ra SVCS <<< "$BIZ_SERVICES"
    for svc in "${SVCS[@]}"; do
        cat >> /var/www/html/index.html << CARDEOF
            <div class="card">
                <h3>${svc}</h3>
                <p>Professional ${svc,,} services tailored to your business needs and goals.</p>
            </div>
CARDEOF
    done

    cat >> /var/www/html/index.html << FOOTEOF
        </div>
        <div class="about">
            <h2 style="margin-bottom:16px;">About Us</h2>
            <p>${SITE_NAME} is a team of experienced professionals delivering ${BIZ_NAME,,} services since 2019. We work with clients across Europe, helping them achieve their technology goals with modern, scalable solutions.</p>
            <p style="margin-top:12px;">Based in Europe. Available worldwide. <a href="mailto:info@${DOMAIN}">Get in touch</a>.</p>
        </div>
    </div>
    <footer>
        &copy; 2019-${YEAR} ${SITE_NAME}. All rights reserved. | <a href="mailto:info@${DOMAIN}">info@${DOMAIN}</a>
    </footer>
</body>
</html>
FOOTEOF

    ok "Фейковый сайт: ${SITE_NAME} — ${BIZ_NAME}"
}

phase9_keygen() {
    title "Фаза 9 / x25519 ключи + Config Profile"
    mkdir -p /opt/remnanode
    info "Генерирую x25519 ключи..."
    KEY_OUTPUT=$(docker run --rm ghcr.io/xtls/xray-core:latest xray x25519 2>/dev/null) \
        || KEY_OUTPUT=$(docker run --rm teddysun/xray:latest xray x25519 2>/dev/null) \
        || KEY_OUTPUT=$(docker run --rm ghcr.io/xtls/xray-core x25519 2>/dev/null) \
        || die "Не удалось сгенерировать x25519 ключи"
    PRIVATE_KEY=$(echo "$KEY_OUTPUT" | grep -i "private" | awk '{print $NF}')
    PUBLIC_KEY=$(echo "$KEY_OUTPUT" | grep -i "public" | awk '{print $NF}')
    if [[ -z "$PRIVATE_KEY" || -z "$PUBLIC_KEY" ]]; then
        die "Не удалось извлечь ключи"
    fi
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
    SHORT_IDS=$(openssl rand -hex 8)
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  ГОТОВЫЙ JSON ДЛЯ CONFIG PROFILE В REMNAWAVE              ║${NC}"
    echo -e "${CYAN}║  Скопируй и вставь в: Config Profiles → Create            ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    cat << JSONEOF
{
  "log": { "loglevel": "warning" },
  "dns": { "servers": [{"address":"https://94.140.14.14/dns-query","domains":[],"skipFallback":false},"localhost"] },
  "inbounds": [{
    "tag": "${NODE_NAME}_xhttp",
    "port": 443,
    "protocol": "vless",
    "settings": { "clients": [], "decryption": "none" },
    "sniffing": { "enabled": true, "destOverride": ["http","tls","quic"] },
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
        "shortIds": ["","a1","bc23","def456","${SHORT_IDS}"],
        "privateKey": "${PRIVATE_KEY}",
        "serverNames": ["${DOMAIN}"]
      }
    }
  }],
  "outbounds": [
    {"tag":"DIRECT","protocol":"freedom"},
    {"tag":"BLOCK","protocol":"blackhole"}
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {"type":"field","network":"udp","port":"443","outboundTag":"BLOCK"},
      {"type":"field","protocol":["bittorrent"],"outboundTag":"DIRECT"},
      {"type":"field","domain":["geosite:category-ads-all","geosite:win-spy","domain:doubleclick.net","domain:googlesyndication.com","domain:googleadservices.com","domain:google-analytics.com","domain:analytics.yandex.ru","domain:mc.yandex.ru","domain:crashlytics.com","domain:app-measurement.com","domain:appcenter.ms"],"outboundTag":"BLOCK"},
      {"type":"field","network":"udp","port":"135,137,138,139","outboundTag":"BLOCK"},
      {"type":"field","ip":["geoip:private"],"outboundTag":"DIRECT"}
    ]
  }
}
JSONEOF
    echo ""
    info "Сохрани этот JSON — он понадобится для шага 10"
    echo ""
}

phase10_panel() {
    title "Фаза 10 / Настройка в панели Remnawave"
    echo ""
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  СЕЙЧАС ПЕРЕКЛЮЧИСЬ В ПАНЕЛЬ REMNAWAVE И СДЕЛАЙ:           ║${NC}"
    echo -e "${YELLOW}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${YELLOW}║  1. Config Profiles → Create                               ║${NC}"
    echo -e "${YELLOW}║     Имя: ${NODE_NAME}_xhttp                                ║${NC}"
    echo -e "${YELLOW}║     Вставь JSON из фазы 9 (выше)                           ║${NC}"
    echo -e "${YELLOW}║  2. Nodes → Create                                         ║${NC}"
    echo -e "${YELLOW}║     Name: ${NODE_NAME}                                     ║${NC}"
    echo -e "${YELLOW}║     Address: ${SERVER_IP}                                  ║${NC}"
    echo -e "${YELLOW}║     Port: 2222                                             ║${NC}"
    echo -e "${YELLOW}║     Привязать Config Profile: ${NODE_NAME}_xhttp           ║${NC}"
    echo -e "${YELLOW}║     → Скопируй SECRET_KEY после создания!                  ║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    ask "Вставь SECRET_KEY из панели"
    read -r SECRET_KEY </dev/tty
    if [[ -z "$SECRET_KEY" ]]; then die "SECRET_KEY не может быть пустым"; fi
    ok "SECRET_KEY принят"
}

phase11_geo() {
    title "Фаза 11 / Geo-файлы (ДО запуска контейнера!)"
    local GEO_DIR="/opt/remnanode/geodata"
    mkdir -p "$GEO_DIR"
    info "Скачиваю geosite.dat и geoip.dat..."
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/geosite.dat" \
        -O "${GEO_DIR}/geosite.dat" || warn "Не удалось скачать geosite.dat"
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/geoip.dat" \
        -O "${GEO_DIR}/geoip.dat" || warn "Не удалось скачать geoip.dat"
    if [[ -f "${GEO_DIR}/geosite.dat" && -s "${GEO_DIR}/geosite.dat" ]]; then
        ok "geosite.dat: $(du -h "${GEO_DIR}/geosite.dat" | cut -f1)"
    else
        warn "geosite.dat отсутствует или пуст"
    fi
    if [[ -f "${GEO_DIR}/geoip.dat" && -s "${GEO_DIR}/geoip.dat" ]]; then
        ok "geoip.dat: $(du -h "${GEO_DIR}/geoip.dat" | cut -f1)"
    else
        warn "geoip.dat отсутствует или пуст"
    fi
}

phase12_docker() {
    title "Фаза 12 / remnawave-node"
    cat > /opt/remnanode/.env << ENVEOF
SSL_CERT=/etc/letsencrypt/live/${DOMAIN}/fullchain.pem
SSL_KEY=/etc/letsencrypt/live/${DOMAIN}/privkey.pem
SECRET_KEY=${SECRET_KEY}
NODE_PORT=2222
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
    ok "remnawave-node запущен (network_mode: host, Xray :443)"
    sleep 5
    if docker ps | grep -q remnawave-node; then
        ok "Контейнер remnawave-node работает"
    else
        warn "Контейнер не запустился! Логи:"
        docker logs remnawave-node --tail 15 2>&1 || true
    fi
}

phase13_maintenance() {
    title "Фаза 13 / Автообслуживание"
    cat > /opt/remnanode/update-geo.sh << 'GEOEOF'
#!/bin/bash
GEO_DIR="/opt/remnanode/geodata"
LOG="/var/log/geo-update.log"
wget -q --timeout=30 --tries=3 \
    "https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/geosite.dat" \
    -O "${GEO_DIR}/geosite.dat.tmp" && mv "${GEO_DIR}/geosite.dat.tmp" "${GEO_DIR}/geosite.dat"
wget -q --timeout=30 --tries=3 \
    "https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/geoip.dat" \
    -O "${GEO_DIR}/geoip.dat.tmp" && mv "${GEO_DIR}/geoip.dat.tmp" "${GEO_DIR}/geoip.dat"
cd /opt/remnanode && docker compose restart
echo "$(date '+%Y-%m-%d %H:%M:%S') geo updated" >> "$LOG"
GEOEOF
    chmod +x /opt/remnanode/update-geo.sh
    CRON_LINE="0 3 * * * /opt/remnanode/update-geo.sh"
    EXISTING_CRON=$(crontab -l 2>/dev/null || true)
    FILTERED_CRON=$(echo "$EXISTING_CRON" | grep -v "update-geo" || true)
    printf '%s\n%s\n' "$FILTERED_CRON" "$CRON_LINE" | crontab -
    ok "Cron: автообновление geo в 03:00"
    cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'UUEOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::Automatic-Reboot "false";
UUEOF
    systemctl enable unattended-upgrades
    ok "Автообновления безопасности включены"
}

phase14_watchdog() {
    title "Фаза 14 / Watchdog"
    cat > /opt/remnanode/watchdog.sh << 'WDEOF'
#!/bin/bash
if ! docker ps | grep -q remnawave-node; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') watchdog: restarting" >> /var/log/watchdog.log
    cd /opt/remnanode && docker compose up -d
fi
WDEOF
    chmod +x /opt/remnanode/watchdog.sh
    CRON_WD="*/5 * * * * /opt/remnanode/watchdog.sh"
    EXISTING_CRON=$(crontab -l 2>/dev/null || true)
    FILTERED_CRON=$(echo "$EXISTING_CRON" | grep -v "watchdog" || true)
    printf '%s\n%s\n' "$FILTERED_CRON" "$CRON_WD" | crontab -
    ok "Watchdog: проверка каждые 5 минут"
}

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

phase16_beszel() {
    title "Фаза 16 / Beszel agent"
    echo ""
    ask "Установить Beszel agent? (y/n)"
    read -r INSTALL_BESZEL </dev/tty
    if [[ "$INSTALL_BESZEL" == "y" ]]; then
        echo ""
        info "Beszel hub: http://23.88.3.239:51068"
        info "  1. Зайди в Beszel UI → Systems → Add System"
        info "  2. Name: ${NODE_NAME} | Host: ${SERVER_IP} | Port: 45876"
        info "  3. Скопируй Token и Key"
        echo ""
        ask "Вставь Beszel TOKEN"
        read -r BESZEL_TOKEN </dev/tty
        ask "Вставь Beszel KEY (ssh-ed25519 ...)"
        read -r BESZEL_KEY </dev/tty
        if [[ -n "$BESZEL_TOKEN" && -n "$BESZEL_KEY" ]]; then
            ufw allow 45876/tcp comment "Beszel agent"
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
            warn "Token или Key не указаны, пропускаю"
        fi
    else
        info "Beszel пропущен. Можно установить позже"
    fi
}

phase17_summary() {
    title "Фаза 17 / Готово!"
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  DEPLOY v${SCRIPT_VERSION} ЗАВЕРШЁН                                      ║${NC}"
    echo -e "${GREEN}║  VLESS + Reality + XHTTP + steal_oneself                    ║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║  Домен:       ${DOMAIN}${NC}"
    echo -e "${GREEN}║  IP:          ${SERVER_IP}${NC}"
    echo -e "${GREEN}║  Нода:        ${NODE_NAME}${NC}"
    echo -e "${GREEN}║  SSH:         ssh -p 2810 admin@${SERVER_IP}${NC}"
    echo -e "${GREEN}║  Private Key: ${PRIVATE_KEY}${NC}"
    echo -e "${GREEN}║  Public Key:  ${PUBLIC_KEY}${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  ⚠ ОБЯЗАТЕЛЬНО СДЕЛАЙ В ПАНЕЛИ REMNAWAVE:                 ║${NC}"
    echo -e "${YELLOW}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${YELLOW}║  3. Hosts → Create                                         ║${NC}"
    echo -e "${YELLOW}║     Inbound tag: ${NODE_NAME}_xhttp                        ║${NC}"
    echo -e "${YELLOW}║     Address:     ${DOMAIN}                                 ║${NC}"
    echo -e "${YELLOW}║     Port:        443                                       ║${NC}"
    echo -e "${YELLOW}║     SNI:         ${DOMAIN}   (steal_oneself!)              ║${NC}"
    echo -e "${YELLOW}║     Fingerprint: chrome                                    ║${NC}"
    echo -e "${YELLOW}║     ALPN:        h2                                        ║${NC}"
    echo -e "${YELLOW}║  4. Internal Squads → Default-Squad                        ║${NC}"
    echo -e "${YELLOW}║     → Добавь inbound ${NODE_NAME}_xhttp                   ║${NC}"
    echo -e "${YELLOW}║     ⚠ БЕЗ ЭТОГО НОДА НЕ ПОПАДЁТ В ПОДПИСКУ!              ║${NC}"
    echo -e "${YELLOW}║  5. Nodes → нода зелёная? Happ → обнови → пинг?           ║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    info "Ключи: /opt/remnanode/keys.txt"
    info "Лог:   $LOG_FILE"
    echo ""
}

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
    phase11_geo
    phase12_docker
    phase13_maintenance
    phase14_watchdog
    phase15_ufw
    phase16_beszel
    phase17_summary
}

main "$@"
