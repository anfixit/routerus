#!/usr/bin/env bash
# =============================================================================
# deploy-remnanode.sh v1.4 — Развёртывание remnawave-node на Ubuntu 24.04
# github.com/anfixit/routerus
#
# Запуск:
#   bash <(wget -qO- https://raw.githubusercontent.com/anfixit/routerus/main/deploy-remnanode.sh)
#
# Flow v1.4:
#   0  Проверки (root, Ubuntu 24)
#   1  Интерактивный ввод (домены, порты, имя профиля)
#   2  Зависимости (apt, nginx-full, certbot)
#   3  Docker
#   4  SSH-порт (опционально)
#   5  SSL-сертификаты (certbot standalone)
#   6  nginx (stream SNI: 443 → 8443/7443/9443)
#   7  Генерация x25519 ключей → JSON для Config Profile → пауза
#   8  SECRET_KEY (пользователь создаёт ноду в панели)
#   9  geosite + geoip (ДО запуска контейнера)
#  10  remnawave-node (docker compose)
#  11  Автообновление geo (cron)
#  12  Node Exporter
#  13  Fake site
#  14  UFW
#  15  Итог
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m' C='\033[0;36m' B='\033[1m' NC='\033[0m'

ok()    { echo -e "${G}  ✓${NC} $*"; }
info()  { echo -e "${C}  →${NC} $*"; }
warn()  { echo -e "${Y}  !${NC} $*"; }
die()   { echo -e "${R}  ✗ ОШИБКА:${NC} $*" >&2; exit 1; }
title() { echo -e "\n${B}══ $* ══${NC}"; }

SECRET_KEY="" CONNECTION_DOMAIN="" SNI_DOMAIN="" PROFILE_NAME=""
NODE_PORT="2222" SSH_PORT="22" MASTER_IP="151.244.72.28" SERVER_IP=""
NODE_DIR="/opt/remnanode" GEO_DIR="${NODE_DIR}/geodata"
GEO_SITE_URL="https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/geosite.dat"
GEO_IP_URL="https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/geoip.dat"
NODE_EXPORTER_VER="1.9.1" XRAY_PRIVATE_KEY="" XRAY_PUBLIC_KEY=""

phase0_checks() {
    title "Фаза 0 / Проверки"
    [[ $EUID -eq 0 ]] || die "Запускай от root: sudo su -"
    local ver; ver=$(grep -oP '(?<=VERSION_ID=")[^"]+' /etc/os-release 2>/dev/null || echo "unknown")
    [[ "$ver" != "24.04" ]] && warn "Скрипт тестировался на Ubuntu 24.04. Обнаружено: $ver"
    SERVER_IP=$(ip route get 8.8.8.8 2>/dev/null | grep -Po 'src \K\S+' | head -1 || curl -s4 ifconfig.me | tr -d '[:space:]')
    ok "IP сервера: $SERVER_IP"
}

phase1_input() {
    title "Фаза 1 / Параметры"
    echo ""
    echo -e "${B}  Шаг 1: Домены${NC}"
    echo "  Нужно 2 домена → оба направить A-записью на IP: $SERVER_IP"
    echo ""
    echo "  Бесплатные DNS:"
    echo -e "    ${G}★${NC} duckdns.org — до 5 поддоменов, вход через GitHub/Google"
    echo "    • dynu.com • afraid.org • noip.com • или свой домен"
    echo ""
    echo "  Домен 1 — connection domain (подключение клиентов, SSL)"
    while [[ -z "$CONNECTION_DOMAIN" ]]; do
        read -rp "  Connection domain: " CONNECTION_DOMAIN
        [[ -z "$CONNECTION_DOMAIN" ]] && warn "Не может быть пустым"
    done
    echo "  Домен 2 — SNI domain (маскировка Reality, должен отличаться)"
    while [[ -z "$SNI_DOMAIN" ]]; do
        read -rp "  SNI domain: " SNI_DOMAIN
        [[ -z "$SNI_DOMAIN" ]] && warn "Не может быть пустым"
        [[ "$SNI_DOMAIN" == "$CONNECTION_DOMAIN" ]] && warn "Должен отличаться!" && SNI_DOMAIN=""
    done
    echo ""
    echo -e "${B}  Шаг 2: Имя профиля${NC} (формат: СТРАНА_название)"
    while [[ -z "$PROFILE_NAME" ]]; do
        read -rp "  Имя профиля: " PROFILE_NAME
        [[ -z "$PROFILE_NAME" ]] && warn "Не может быть пустым"
    done
    echo ""
    read -rp "  Порт remnawave-node [${NODE_PORT}]: " _p; [[ -n "$_p" ]] && NODE_PORT="$_p"
    echo "  SSH-порт: рекомендуется сменить с 22"
    read -rp "  Новый SSH-порт [Enter = оставить 22]: " _s; [[ -n "$_s" ]] && SSH_PORT="$_s"
    read -rp "  IP мастер-сервера [${MASTER_IP}]: " _m; [[ -n "$_m" ]] && MASTER_IP="$_m"
    echo ""
    echo -e "${B}  Параметры:${NC}"
    echo "  ──────────────────────────────────────"
    printf "  %-22s %s\n" "Connection:" "$CONNECTION_DOMAIN"
    printf "  %-22s %s\n" "SNI:" "$SNI_DOMAIN"
    printf "  %-22s %s\n" "Profile:" "$PROFILE_NAME"
    printf "  %-22s %s\n" "Node port:" "$NODE_PORT"
    printf "  %-22s %s\n" "SSH port:" "$SSH_PORT"
    printf "  %-22s %s\n" "Master IP:" "$MASTER_IP"
    echo "  ──────────────────────────────────────"
    read -rp "  Всё верно? [Y/n]: " _c; [[ "${_c,,}" == "n" ]] && die "Отменено."
    ok "Параметры приняты"
}

phase2_deps() {
    title "Фаза 2 / Зависимости"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get upgrade -y -qq
    apt-get install -y -qq curl wget ufw nginx-full certbot libnginx-mod-stream ca-certificates gnupg lsb-release jq
    ok "Пакеты установлены"
}

phase3_docker() {
    title "Фаза 3 / Docker"
    if command -v docker &>/dev/null; then
        ok "Docker: $(docker --version | grep -oP '[\d.]+' | head -1)"
    else
        info "Устанавливаю Docker..."
        curl -fsSL https://get.docker.com | sh
        systemctl enable --now docker
        ok "Docker установлен"
    fi
    docker compose version &>/dev/null || die "docker compose plugin не найден"
    systemctl reset-failed docker 2>/dev/null || true
}

phase4_ssh() {
    title "Фаза 4 / SSH"
    if [[ "$SSH_PORT" == "22" ]]; then ok "SSH-порт оставлен 22"; return; fi
    sed -i "s/^#*Port .*/Port ${SSH_PORT}/" /etc/ssh/sshd_config
    grep -q "^Port ${SSH_PORT}" /etc/ssh/sshd_config || echo "Port ${SSH_PORT}" >> /etc/ssh/sshd_config
    systemctl restart sshd
    ok "SSH → порт $SSH_PORT"
    warn "Новое подключение: ssh root@${SERVER_IP} -p ${SSH_PORT}"
}

phase5_ssl() {
    title "Фаза 5 / SSL"
    systemctl stop nginx 2>/dev/null || true
    fuser -k 80/tcp 2>/dev/null || true; sleep 1
    for d in "$CONNECTION_DOMAIN" "$SNI_DOMAIN"; do
        if [[ -d "/etc/letsencrypt/live/${d}" ]]; then ok "SSL $d уже есть"; continue; fi
        info "Получаю SSL для $d..."
        certbot certonly --standalone --non-interactive --agree-tos --register-unsafely-without-email -d "$d" \
            || die "SSL для $d не получен. Проверь A-запись → $SERVER_IP"
        ok "SSL $d получен"
    done
    systemctl start nginx 2>/dev/null || true
}

phase6_nginx() {
    title "Фаза 6 / nginx"
    mkdir -p /etc/nginx/stream-enabled
    sed -i '/load_module.*ngx_stream_module/d' /etc/nginx/nginx.conf
    grep -qF "stream { include /etc/nginx/stream-enabled/*.conf; }" /etc/nginx/nginx.conf \
        || echo "stream { include /etc/nginx/stream-enabled/*.conf; }" >> /etc/nginx/nginx.conf

    cat > /etc/nginx/stream-enabled/stream.conf << EOF
map \$ssl_preread_server_name \$sni_upstream {
    hostnames;
    ${SNI_DOMAIN}          xray_backend;
    ${CONNECTION_DOMAIN}   https_backend;
    default                xray_backend;
}
upstream xray_backend  { server 127.0.0.1:8443; }
upstream https_backend { server 127.0.0.1:7443; }
server {
    listen 443; listen [::]:443;
    proxy_pass \$sni_upstream; ssl_preread on; proxy_protocol on;
}
EOF
    cat > /etc/nginx/sites-available/80.conf << EOF
server { listen 80; server_name ${CONNECTION_DOMAIN} ${SNI_DOMAIN}; return 301 https://\$host\$request_uri; }
EOF
    cat > "/etc/nginx/sites-available/${CONNECTION_DOMAIN}.conf" << EOF
server {
    server_tokens off; server_name ${CONNECTION_DOMAIN};
    listen 7443 ssl http2 proxy_protocol; listen [::]:7443 ssl http2 proxy_protocol;
    ssl_certificate /etc/letsencrypt/live/${CONNECTION_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${CONNECTION_DOMAIN}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    root /var/www/html/; index index.html;
    location / { try_files \$uri \$uri/ =404; }
}
EOF
    cat > "/etc/nginx/sites-available/${SNI_DOMAIN}.conf" << EOF
server {
    server_tokens off; server_name ${SNI_DOMAIN};
    listen 9443 ssl http2; listen [::]:9443 ssl http2;
    ssl_certificate /etc/letsencrypt/live/${SNI_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${SNI_DOMAIN}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    root /var/www/html/; index index.html;
    location / { try_files \$uri \$uri/ =404; }
}
EOF
    rm -f /etc/nginx/sites-enabled/default
    ln -sf /etc/nginx/sites-available/80.conf /etc/nginx/sites-enabled/
    ln -sf "/etc/nginx/sites-available/${CONNECTION_DOMAIN}.conf" /etc/nginx/sites-enabled/
    ln -sf "/etc/nginx/sites-available/${SNI_DOMAIN}.conf" /etc/nginx/sites-enabled/
    nginx -t || die "nginx config test failed"
    systemctl restart nginx
    ok "nginx: 443→SNI, 7443→HTTPS, 9443→Reality fallback"
}

phase7_keygen() {
    title "Фаза 7 / Генерация Reality ключей"
    info "Загружаю образ remnawave/node..."
    docker pull remnawave/node:latest -q 2>/dev/null || docker pull remnawave/node:latest
    info "Генерирую x25519..."
    local output
    output=$(docker run --rm remnawave/node:latest xray x25519 2>/dev/null) || die "xray x25519 не сработал"
    XRAY_PRIVATE_KEY=$(echo "$output" | grep -i "private" | awk '{print $NF}')
    XRAY_PUBLIC_KEY=$(echo "$output" | grep -i "public" | awk '{print $NF}')
    [[ -z "$XRAY_PUBLIC_KEY" ]] && XRAY_PUBLIC_KEY=$(echo "$output" | grep -i "password" | awk '{print $NF}')
    [[ -z "$XRAY_PRIVATE_KEY" ]] && die "Не удалось получить PrivateKey"

    echo ""
    echo -e "${G}  ╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${G}  ║${NC}  ${B}Private Key:${NC} ${Y}${XRAY_PRIVATE_KEY}${NC}"
    echo -e "${G}  ║${NC}  ${B}Public Key:${NC}  ${C}${XRAY_PUBLIC_KEY}${NC}"
    echo -e "${G}  ╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    read -rp "  Config Profile '${PROFILE_NAME}' уже создан в панели? [y/N]: " _hp
    if [[ "${_hp,,}" == "y" ]]; then
        info "Обнови privateKey → ${XRAY_PRIVATE_KEY}"
        info "Обнови serverNames → [\"${SNI_DOMAIN}\"]"
        read -rp "  Обнови профиль, затем Enter... " _
    else
        info "Вот готовый JSON для Config Profile:"
        echo ""
        echo -e "${B}  ─── СКОПИРУЙ ОТСЮДА ───${NC}"
        cat <<ENDJSON
{
  "log": {"loglevel": "warning"},
  "dns": {
    "servers": [
      {"address": "https://94.140.14.14/dns-query", "domains": [], "skipFallback": false},
      "localhost"
    ]
  },
  "inbounds": [
    {
      "tag": "${PROFILE_NAME}",
      "port": 8443,
      "protocol": "vless",
      "settings": {"clients": [], "decryption": "none"},
      "sniffing": {"enabled": true, "destOverride": ["http", "tls", "quic"]},
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "tcpSettings": {"acceptProxyProtocol": true},
        "realitySettings": {
          "dest": "127.0.0.1:9443", "show": false, "xver": 0,
          "shortIds": ["", "a1", "bc23", "def456", "1234abcd", "ab1234567890", "abcd12345678abcd"],
          "privateKey": "${XRAY_PRIVATE_KEY}",
          "serverNames": ["${SNI_DOMAIN}"]
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
      {"type": "field", "outboundTag": "BLOCK", "network": "udp", "port": "135,137,138,139"},
      {"type": "field", "outboundTag": "BLOCK", "domain": [
        "geosite:category-ads-all", "geosite:win-spy",
        "domain:google-analytics.com", "domain:analytics.yandex.ru", "domain:mc.yandex.ru",
        "domain:appcenter.ms", "domain:app-measurement.com", "domain:firebase.io",
        "domain:crashlytics.com", "domain:doubleclick.net", "domain:googlesyndication.com",
        "domain:googleadservices.com", "domain:googletagmanager.com",
        "domain:googletagservices.com", "domain:scorecardresearch.com",
        "domain:quantserve.com", "domain:adnxs.com", "domain:moatads.com"
      ]},
      {"type": "field", "outboundTag": "BLOCK", "network": "udp", "port": "443"},
      {"type": "field", "outboundTag": "DIRECT", "protocol": ["bittorrent"]},
      {"type": "field", "outboundTag": "DIRECT", "ip": ["geoip:private"]}
    ]
  }
}
ENDJSON
        echo -e "${B}  ─── ДО СЮДА ───${NC}"
        echo ""
        echo "  1. Панель → Config Profiles → + → имя: ${PROFILE_NAME}"
        echo "  2. Вставь JSON → Сохрани"
        read -rp "  Создай профиль, затем Enter... " _
    fi
    ok "Ключи готовы, профиль настроен"
}

phase8_secret() {
    title "Фаза 8 / SECRET_KEY"
    echo ""
    info "Создай ноду в панели:"
    echo "  1. Nodes → + (добавить)"
    echo "  2. Имя: ${PROFILE_NAME}, IP: ${SERVER_IP}, Порт: ${NODE_PORT}"
    echo "  3. Привяжи профиль: ${PROFILE_NAME}"
    echo "  4. Скопируй SECRET_KEY (eyJ...)"
    echo -e "  ${Y}Нода будет Offline — это нормально.${NC}"
    echo ""
    while [[ -z "$SECRET_KEY" ]]; do
        read -rp "  SECRET_KEY: " SECRET_KEY
        [[ -z "$SECRET_KEY" ]] && warn "Не может быть пустым"
    done
    ok "SECRET_KEY (${#SECRET_KEY} символов)"
}

phase9_geo() {
    title "Фаза 9 / Geo-файлы"
    mkdir -p "$GEO_DIR"
    info "geosite.dat..."
    wget -q -O "${GEO_DIR}/geosite.dat" "$GEO_SITE_URL" || die "Не скачался geosite.dat"
    info "geoip.dat..."
    wget -q -O "${GEO_DIR}/geoip.dat" "$GEO_IP_URL" || die "Не скачался geoip.dat"
    ok "geosite $(du -sh "${GEO_DIR}/geosite.dat" | cut -f1) + geoip $(du -sh "${GEO_DIR}/geoip.dat" | cut -f1)"
}

phase10_node() {
    title "Фаза 10 / remnawave-node"
    mkdir -p "$NODE_DIR" /var/log/remnanode
    cat > "${NODE_DIR}/docker-compose.yml" << EOF
services:
  remnanode:
    container_name: remnanode
    hostname: remnanode
    image: remnawave/node:latest
    restart: always
    network_mode: host
    cap_add:
      - NET_ADMIN
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    environment:
      - NODE_PORT=${NODE_PORT}
      - SECRET_KEY=${SECRET_KEY}
    volumes:
      - ${GEO_DIR}/geosite.dat:/usr/local/share/xray/geosite.dat:ro
      - ${GEO_DIR}/geoip.dat:/usr/local/share/xray/geoip.dat:ro
      - /var/log/remnanode:/var/log/remnanode
EOF
    cd "$NODE_DIR"
    docker compose up -d
    sleep 5
    if docker ps --format '{{.Names}}' | grep -q remnanode; then
        ok "remnawave-node запущен (порт ${NODE_PORT})"
    else
        warn "Проверь: docker compose -C $NODE_DIR logs -f"
    fi
}

phase11_geocron() {
    title "Фаза 11 / Автообновление geo"
    cat > /usr/local/bin/update-geo-dat.sh << 'GEOEOF'
#!/usr/bin/env bash
set -euo pipefail
GEO="/opt/remnanode/geodata"
LOG="/var/log/remnanode/geo-update.log"
S="https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/geosite.dat"
I="https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/geoip.dat"
wget -q -O "${GEO}/geosite.dat.new" "$S" && mv "${GEO}/geosite.dat.new" "${GEO}/geosite.dat"
wget -q -O "${GEO}/geoip.dat.new" "$I" && mv "${GEO}/geoip.dat.new" "${GEO}/geoip.dat"
cd /opt/remnanode && docker compose restart remnanode
echo "$(date '+%Y-%m-%d %H:%M:%S') updated" >> "$LOG"
GEOEOF
    chmod +x /usr/local/bin/update-geo-dat.sh
    (crontab -l 2>/dev/null | grep -v "update-geo-dat"; echo "0 3 * * * /usr/local/bin/update-geo-dat.sh") | crontab -
    ok "Cron: geo обновление каждую ночь в 03:00"
}

phase12_node_exporter() {
    title "Фаза 12 / Node Exporter"
    if command -v node_exporter &>/dev/null; then ok "Уже установлен"; return; fi
    local arch="amd64" tb="node_exporter-${NODE_EXPORTER_VER}.linux-amd64.tar.gz"
    wget -qO "/tmp/${tb}" "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VER}/${tb}"
    tar -xzf "/tmp/${tb}" -C /tmp
    mv "/tmp/node_exporter-${NODE_EXPORTER_VER}.linux-amd64/node_exporter" /usr/local/bin/
    rm -rf "/tmp/node_exporter-${NODE_EXPORTER_VER}.linux-amd64" "/tmp/${tb}"
    useradd -rs /bin/false node_exporter 2>/dev/null || true
    cat > /etc/systemd/system/node_exporter.service << EOF
[Unit]
Description=Prometheus Node Exporter
After=network.target
[Service]
User=node_exporter
ExecStart=/usr/local/bin/node_exporter --web.listen-address=0.0.0.0:9100
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload; systemctl enable --now node_exporter
    ok "Node Exporter v${NODE_EXPORTER_VER} на :9100"
}

phase13_fakesite() {
    title "Фаза 13 / Fake site"
    mkdir -p /var/www/html
    if bash <(wget -qO- https://raw.githubusercontent.com/mozaroc/x-ui-pro/refs/heads/master/randomfakehtml.sh) 2>/dev/null; then
        ok "Fake site (randomfakehtml)"
    else
        echo '<html><head><title>Welcome</title><style>body{font-family:Arial,sans-serif;margin:40px;background:#f5f5f5}.c{max-width:800px;margin:0 auto;background:#fff;padding:30px;border-radius:8px;box-shadow:0 2px 4px rgba(0,0,0,.1)}</style></head><body><div class="c"><h1>Welcome</h1><p>Site under construction.</p></div></body></html>' > /var/www/html/index.html
        ok "Fake site (fallback)"
    fi
}

phase14_ufw() {
    title "Фаза 14 / UFW"
    ufw --force reset
    ufw default deny incoming; ufw default allow outgoing
    ufw allow "${SSH_PORT}/tcp" comment "SSH"
    ufw allow 80/tcp comment "HTTP"
    ufw allow 443/tcp comment "HTTPS/Xray"
    ufw allow from "${MASTER_IP}" to any port 9100 proto tcp comment "Node Exporter"
    ufw --force enable
    ok "UFW: SSH(${SSH_PORT}), 80, 443, 9100(${MASTER_IP})"
}

phase15_summary() {
    echo ""
    echo -e "${G}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${G}║           remnawave-node v1.4 — развёрнут!                    ║${NC}"
    echo -e "${G}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    printf "  %-22s ${C}%s${NC}\n" "Server IP:" "$SERVER_IP"
    printf "  %-22s %s\n" "Connection:" "$CONNECTION_DOMAIN"
    printf "  %-22s %s\n" "SNI:" "$SNI_DOMAIN"
    printf "  %-22s %s\n" "Profile:" "$PROFILE_NAME"
    printf "  %-22s %s\n" "Private Key:" "$XRAY_PRIVATE_KEY"
    printf "  %-22s %s\n" "Public Key:" "$XRAY_PUBLIC_KEY"
    [[ "$SSH_PORT" != "22" ]] && printf "  %-22s ${Y}%s ← НОВЫЙ!${NC}\n" "SSH:" "$SSH_PORT"
    echo ""
    echo -e "${B}  В панели:${NC}"
    echo "  1. Nodes → нода Online?"
    echo "  2. Включи Host visibility"
    echo "  3. Профиль ${PROFILE_NAME} привязан?"
    echo ""
    echo -e "${B}  Команды:${NC}"
    echo "  docker compose -C $NODE_DIR logs -f"
    echo "  docker compose -C $NODE_DIR restart"
    echo "  /usr/local/bin/update-geo-dat.sh"
    echo ""
}

main() {
    clear
    echo -e "${C}"
    echo "  ┌──────────────────────────────────────────────────────┐"
    echo "  │        remnawave-node  •  deploy script  v1.4       │"
    echo "  │        github.com/anfixit/routerus                  │"
    echo "  └──────────────────────────────────────────────────────┘"
    echo -e "${NC}"
    phase0_checks; phase1_input; phase2_deps; phase3_docker; phase4_ssh
    phase5_ssl; phase6_nginx; phase7_keygen; phase8_secret; phase9_geo
    phase10_node; phase11_geocron; phase12_node_exporter; phase13_fakesite
    phase14_ufw; phase15_summary
}
main "$@"
