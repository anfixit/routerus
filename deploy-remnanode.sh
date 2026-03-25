#!/usr/bin/env bash
# =============================================================================
# deploy-remnanode.sh
# Разворачивает remnawave-node на чистом Ubuntu 24.04
#
# Запуск:
#   bash <(wget -qO- https://raw.githubusercontent.com/ТВОЙ_НИК/РЕПО/main/deploy-remnanode.sh)
#
# Фазы:
#   0  Проверки (root, Ubuntu 24)
#   1  Интерактивный ввод (SECRET_KEY, домены, порты)
#   2  Зависимости (docker, ufw, nginx, certbot)
#   3  SSH-порт
#   4  SSL-сертификаты (certbot standalone)
#   5  nginx (stream SNI: 443 → 8443 / 7443 / 9443)
#   6  remnawave-node (docker compose)
#   7  geosite/geoip dat + cron-автообновление
#   8  Node Exporter для Prometheus
#   9  Fake site (randomfakehtml.sh)
#  10  UFW (финальные правила)
#  11  Итоговый вывод с инструкцией
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# ── Цвета ─────────────────────────────────────────────────────────────────────
R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m' C='\033[0;36m' B='\033[1m' NC='\033[0m'

ok()    { echo -e "${G}  ✓${NC} $*"; }
info()  { echo -e "${C}  →${NC} $*"; }
warn()  { echo -e "${Y}  !${NC} $*"; }
die()   { echo -e "${R}  ✗ ОШИБКА:${NC} $*" >&2; exit 1; }
title() { echo -e "\n${B}══ $* ══${NC}"; }

# ── Глобальные переменные (заполняются в phase1) ──────────────────────────────
SECRET_KEY=""
CONNECTION_DOMAIN=""
SNI_DOMAIN=""
NODE_PORT="2222"
SSH_PORT="22"
MASTER_IP="151.244.72.28"
SERVER_IP=""
NODE_DIR="/opt/remnanode"
XRAY_SHARE="/usr/local/share/xray"
NODE_EXPORTER_VER="1.9.1"

# =============================================================================
# ФАЗА 0: Проверки
# =============================================================================
phase0_checks() {
    title "Фаза 0 / Проверки"

    [[ $EUID -eq 0 ]] || die "Запускай от root: sudo su - && bash ..."

    local ver
    ver=$(grep -oP '(?<=VERSION_ID=")[^"]+' /etc/os-release 2>/dev/null || echo "unknown")
    [[ "$ver" != "24.04" ]] && warn "Скрипт тестировался на Ubuntu 24.04. Обнаружено: $ver"

    SERVER_IP=$(ip route get 8.8.8.8 2>/dev/null | grep -Po 'src \K\S+' | head -1 \
                || curl -s4 ifconfig.me | tr -d '[:space:]')

    ok "IP сервера: $SERVER_IP"
    ok "Проверки пройдены"
}

# =============================================================================
# ФАЗА 1: Интерактивный ввод параметров
# =============================================================================
phase1_input() {
    title "Фаза 1 / Параметры"

    # ── SECRET_KEY ────────────────────────────────────────────────────────────
    echo ""
    echo -e "${B}  Шаг 1: SECRET KEY из Remnawave панели${NC}"
    echo "  ┌──────────────────────────────────────────────────────────────┐"
    echo "  │  1. Открой панель Remnawave                                  │"
    echo "  │  2. Перейди: Nodes → Add node                                │"
    echo "  │  3. Заполни имя ноды и порт (по умолчанию: 2222)            │"
    echo "  │  4. Нажми кнопку «Important information»                     │"
    echo "  │  5. Скопируй SECRET KEY (длинная строка eyJ...)              │"
    echo "  └──────────────────────────────────────────────────────────────┘"
    echo ""
    while [[ -z "$SECRET_KEY" ]]; do
        read -rp "  SECRET KEY: " SECRET_KEY
        [[ -z "$SECRET_KEY" ]] && warn "Ключ не может быть пустым"
    done

    # ── Домены ────────────────────────────────────────────────────────────────
    echo ""
    echo -e "${B}  Шаг 2: Домены${NC}"
    echo "  Нужно два домена/поддомена → оба должны быть направлены на IP: $SERVER_IP"
    echo ""
    echo "  Где взять бесплатно:"
    echo -e "    ${G}★${NC} duckdns.org   — вход через GitHub или Google, до 5 поддоменов"
    echo "       Пример: mynode.duckdns.org, mynode-sni.duckdns.org"
    echo "    • dynu.com      — поддерживает IPv6, свои домены"
    echo "    • afraid.org    — 5 поддоменов, 55 000+ доменных зон"
    echo "    • noip.com      — 3 хоста, нужно подтверждать раз в 30 дней"
    echo ""
    echo "  Домен 1 — connection domain (для подключения клиентов)"
    echo "  Пример: mynode.duckdns.org"
    while [[ -z "$CONNECTION_DOMAIN" ]]; do
        read -rp "  Connection domain: " CONNECTION_DOMAIN
        [[ -z "$CONNECTION_DOMAIN" ]] && warn "Домен не может быть пустым"
    done

    echo ""
    echo "  Домен 2 — SNI domain (для маскировки Reality, должен отличаться от первого)"
    echo "  Пример: mynode-sni.duckdns.org"
    while [[ -z "$SNI_DOMAIN" ]]; do
        read -rp "  SNI domain: " SNI_DOMAIN
        [[ -z "$SNI_DOMAIN" ]] && warn "Домен не может быть пустым"
        [[ "$SNI_DOMAIN" == "$CONNECTION_DOMAIN" ]] && \
            warn "SNI domain должен отличаться от connection domain" && SNI_DOMAIN=""
    done

    # ── Порт ноды ─────────────────────────────────────────────────────────────
    echo ""
    read -rp "  Порт remnawave-node [${NODE_PORT}]: " _port
    [[ -n "$_port" ]] && NODE_PORT="$_port"

    # ── SSH-порт ──────────────────────────────────────────────────────────────
    echo ""
    echo "  SSH-порт: рекомендуется сменить с 22 для защиты от сканеров"
    read -rp "  Новый SSH-порт [Enter — оставить 22]: " _ssh
    [[ -n "$_ssh" ]] && SSH_PORT="$_ssh"

    # ── IP мастера ────────────────────────────────────────────────────────────
    echo ""
    read -rp "  IP мастер-сервера для Node Exporter [${MASTER_IP}]: " _master
    [[ -n "$_master" ]] && MASTER_IP="$_master"

    # ── Итог ─────────────────────────────────────────────────────────────────
    echo ""
    echo -e "${B}  Итоговые параметры:${NC}"
    echo "  ─────────────────────────────────────────────"
    printf "  %-24s %s\n" "Connection domain:"  "$CONNECTION_DOMAIN"
    printf "  %-24s %s\n" "SNI domain:"         "$SNI_DOMAIN"
    printf "  %-24s %s\n" "Node port:"          "$NODE_PORT"
    printf "  %-24s %s\n" "SSH port:"           "$SSH_PORT"
    printf "  %-24s %s\n" "Master IP:"          "$MASTER_IP"
    printf "  %-24s %s...\n" "SECRET_KEY:"      "${SECRET_KEY:0:20}"
    echo "  ─────────────────────────────────────────────"
    echo ""
    read -rp "  Всё верно? [Y/n]: " _confirm
    [[ "${_confirm,,}" == "n" ]] && die "Отменено. Запусти скрипт заново."

    ok "Параметры приняты"
}

# =============================================================================
# ФАЗА 2: Зависимости
# =============================================================================
phase2_deps() {
    title "Фаза 2 / Зависимости"

    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq \
        curl wget ufw nginx certbot \
        jq ca-certificates gnupg lsb-release

    if ! command -v docker &>/dev/null; then
        info "Устанавливаю Docker..."
        curl -fsSL https://get.docker.com | sh
        systemctl enable --now docker
    else
        ok "Docker уже установлен"
    fi

    docker compose version &>/dev/null \
        || die "docker compose plugin не найден — переустанови Docker через get.docker.com"

    ok "Зависимости установлены"
}

# =============================================================================
# ФАЗА 3: SSH-порт
# =============================================================================
phase3_ssh() {
    title "Фаза 3 / SSH"

    if [[ "$SSH_PORT" == "22" ]]; then
        ok "SSH-порт оставлен 22"
        return
    fi

    sed -i "s/^#*Port .*/Port ${SSH_PORT}/" /etc/ssh/sshd_config
    grep -q "^Port ${SSH_PORT}" /etc/ssh/sshd_config \
        || echo "Port ${SSH_PORT}" >> /etc/ssh/sshd_config

    systemctl restart sshd
    ok "SSH переведён на порт $SSH_PORT"
    warn "Следующее подключение: ssh root@${SERVER_IP} -p ${SSH_PORT}"
}

# =============================================================================
# ФАЗА 4: SSL
# =============================================================================
phase4_ssl() {
    title "Фаза 4 / SSL-сертификаты"

    systemctl stop nginx 2>/dev/null || true
    fuser -k 80/tcp 2>/dev/null || true
    sleep 1

    for domain in "$CONNECTION_DOMAIN" "$SNI_DOMAIN"; do
        if [[ -d "/etc/letsencrypt/live/${domain}" ]]; then
            ok "SSL для $domain уже есть"
            continue
        fi
        info "Получаю SSL для $domain..."
        certbot certonly --standalone --non-interactive --agree-tos \
            --register-unsafely-without-email -d "$domain" \
            || die "SSL для $domain не получен. Убедись что $domain → $SERVER_IP"
        ok "SSL для $domain получен"
    done

    systemctl start nginx
}

# =============================================================================
# ФАЗА 5: nginx
# =============================================================================
phase5_nginx() {
    title "Фаза 5 / nginx (stream SNI routing)"

    mkdir -p /etc/nginx/stream-enabled

    # Stream module
    grep -qF "load_module modules/ngx_stream_module.so;" /etc/nginx/nginx.conf \
        || sed -i '1s|^|load_module /usr/lib/nginx/modules/ngx_stream_module.so;\n|' \
               /etc/nginx/nginx.conf

    grep -qF "stream { include /etc/nginx/stream-enabled/*.conf; }" /etc/nginx/nginx.conf \
        || echo "stream { include /etc/nginx/stream-enabled/*.conf; }" \
               >> /etc/nginx/nginx.conf

    grep -qF "worker_rlimit_nofile" /etc/nginx/nginx.conf \
        || echo "worker_rlimit_nofile 16384;" >> /etc/nginx/nginx.conf

    sed -i "/worker_connections/c\\        worker_connections 4096;" /etc/nginx/nginx.conf

    # Stream: 443 → по SNI
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
    listen       443;
    proxy_pass   \$sni_upstream;
    ssl_preread  on;
    proxy_protocol on;
}
EOF

    # HTTP → HTTPS
    cat > /etc/nginx/sites-available/80.conf << EOF
server {
    listen 80;
    server_name ${CONNECTION_DOMAIN} ${SNI_DOMAIN};
    return 301 https://\$host\$request_uri;
}
EOF

    # HTTPS vhost для connection domain (fake site)
    cat > "/etc/nginx/sites-available/${CONNECTION_DOMAIN}.conf" << EOF
server {
    server_tokens off;
    server_name   ${CONNECTION_DOMAIN};
    listen        7443 ssl http2 proxy_protocol;
    listen        [::]:7443 ssl http2 proxy_protocol;
    ssl_certificate     /etc/letsencrypt/live/${CONNECTION_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${CONNECTION_DOMAIN}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers   HIGH:!aNULL:!eNULL:!MD5:!DES:!RC4;
    root  /var/www/html/;
    index index.html;
    location / { try_files \$uri \$uri/ =404; }
}
EOF

    # HTTPS vhost для SNI domain (Reality fallback 9443)
    cat > "/etc/nginx/sites-available/${SNI_DOMAIN}.conf" << EOF
server {
    server_tokens off;
    server_name   ${SNI_DOMAIN};
    listen        9443 ssl http2;
    listen        [::]:9443 ssl http2;
    ssl_certificate     /etc/letsencrypt/live/${SNI_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${SNI_DOMAIN}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers   HIGH:!aNULL:!eNULL:!MD5:!DES:!RC4;
    root  /var/www/html/;
    index index.html;
    location / { try_files \$uri \$uri/ =404; }
}
EOF

    rm -f /etc/nginx/sites-enabled/default
    ln -sf /etc/nginx/sites-available/80.conf \
           /etc/nginx/sites-enabled/
    ln -sf "/etc/nginx/sites-available/${CONNECTION_DOMAIN}.conf" \
           /etc/nginx/sites-enabled/
    ln -sf "/etc/nginx/sites-available/${SNI_DOMAIN}.conf" \
           /etc/nginx/sites-enabled/

    nginx -t || die "nginx config test failed"
    systemctl restart nginx
    ok "nginx настроен (443 → 8443/7443, Reality fallback → 9443)"
}

# =============================================================================
# ФАЗА 6: remnawave-node
# =============================================================================
phase6_node() {
    title "Фаза 6 / remnawave-node"

    mkdir -p "$NODE_DIR" /var/log/remnanode "$XRAY_SHARE"

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
      - /var/log/remnanode:/var/log/remnanode
      - ${XRAY_SHARE}:/usr/local/share/xray
EOF

    systemctl reset-failed docker 2>/dev/null || true

    cd "$NODE_DIR"
    docker compose pull -q
    docker compose up -d

    sleep 5
    if docker compose ps | grep -qiE "running|up"; then
        ok "remnawave-node запущен на порту ${NODE_PORT}"
    else
        warn "Контейнер возможно ещё стартует. Проверь: docker compose -C $NODE_DIR logs -f"
    fi
}

# =============================================================================
# ФАЗА 7: geosite/geoip dat
# =============================================================================
phase7_geo() {
    title "Фаза 7 / geosite + geoip dat"

    local base="https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download"

    wget -qO "${XRAY_SHARE}/geosite.dat" "${base}/geosite.dat" \
        || die "Не удалось скачать geosite.dat"
    wget -qO "${XRAY_SHARE}/geoip.dat"   "${base}/geoip.dat"   \
        || die "Не удалось скачать geoip.dat"

    ok "geosite.dat и geoip.dat загружены → $XRAY_SHARE"

    cat > /usr/local/bin/update-geo-dat.sh << 'GEOEOF'
#!/usr/bin/env bash
set -euo pipefail
XRAY_SHARE="/usr/local/share/xray"
BASE="https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download"
LOG="/var/log/remnanode/geo-update.log"
wget -qO "${XRAY_SHARE}/geosite.dat.new" "${BASE}/geosite.dat"
wget -qO "${XRAY_SHARE}/geoip.dat.new"   "${BASE}/geoip.dat"
mv "${XRAY_SHARE}/geosite.dat.new" "${XRAY_SHARE}/geosite.dat"
mv "${XRAY_SHARE}/geoip.dat.new"   "${XRAY_SHARE}/geoip.dat"
cd /opt/remnanode && docker compose restart remnanode
echo "$(date '+%Y-%m-%d %H:%M:%S') geo dat updated" >> "$LOG"
GEOEOF

    chmod +x /usr/local/bin/update-geo-dat.sh

    (crontab -l 2>/dev/null | grep -v "update-geo-dat"; \
     echo "0 3 * * * /usr/local/bin/update-geo-dat.sh") | crontab -

    ok "Автообновление dat: каждый день в 03:00"
}

# =============================================================================
# ФАЗА 8: Node Exporter
# =============================================================================
phase8_node_exporter() {
    title "Фаза 8 / Node Exporter"

    if command -v node_exporter &>/dev/null; then
        ok "Node Exporter уже установлен"
        return
    fi

    local arch="amd64"
    local tarball="node_exporter-${NODE_EXPORTER_VER}.linux-${arch}.tar.gz"
    wget -qO "/tmp/${tarball}" \
        "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VER}/${tarball}"
    tar -xzf "/tmp/${tarball}" -C /tmp
    mv "/tmp/node_exporter-${NODE_EXPORTER_VER}.linux-${arch}/node_exporter" /usr/local/bin/
    rm -rf "/tmp/node_exporter-${NODE_EXPORTER_VER}.linux-${arch}" "/tmp/${tarball}"

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

    systemctl daemon-reload
    systemctl enable --now node_exporter
    ok "Node Exporter v${NODE_EXPORTER_VER} запущен"
}

# =============================================================================
# ФАЗА 9: Fake site
# =============================================================================
phase9_fakesite() {
    title "Фаза 9 / Fake site"
    bash <(wget -qO- \
        https://raw.githubusercontent.com/mozaroc/x-ui-pro/refs/heads/master/randomfakehtml.sh \
    ) || warn "randomfakehtml.sh вернул ошибку (не критично)"
    ok "Fake site установлен"
}

# =============================================================================
# ФАЗА 10: UFW
# =============================================================================
phase10_ufw() {
    title "Фаза 10 / UFW"

    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing

    ufw allow "${SSH_PORT}/tcp"   comment "SSH"
    ufw allow 80/tcp              comment "HTTP"
    ufw allow 443/tcp             comment "HTTPS / Xray"
    ufw allow "${NODE_PORT}/tcp"  comment "remnawave-node API"
    ufw allow from "${MASTER_IP}" to any port 9100 proto tcp \
        comment "Node Exporter → master"

    ufw --force enable
    ok "UFW активирован"
}

# =============================================================================
# ФАЗА 11: Итоговый вывод
# =============================================================================
phase11_summary() {
    echo ""
    echo -e "${G}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${G}║                  Развёртывание завершено!                    ║${NC}"
    echo -e "${G}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    printf "  %-26s ${C}%s${NC}\n" "Сервер IP:"          "$SERVER_IP"
    printf "  %-26s %s\n" "Connection domain:"  "$CONNECTION_DOMAIN"
    printf "  %-26s %s\n" "SNI domain:"         "$SNI_DOMAIN"
    printf "  %-26s %s\n" "Node port:"          "$NODE_PORT"
    if [[ "$SSH_PORT" != "22" ]]; then
        printf "  %-26s ${Y}%s  ← НОВЫЙ SSH-ПОРТ, запомни!${NC}\n" "SSH port:" "$SSH_PORT"
    fi
    echo ""
    echo -e "${B}  Что сделать в панели Remnawave:${NC}"
    echo "  1. Nodes → найди ноду → статус должен быть Online"
    echo "     Если не Online: docker compose -C $NODE_DIR logs -f"
    echo "  2. Включи «Host visibility» (чтобы нода попала в подписки)"
    echo "  3. Привяжи нужный Config Profile к ноде"
    echo ""
    echo -e "${B}  Полезные команды:${NC}"
    echo "  docker compose -C $NODE_DIR logs -f        # логи ноды"
    echo "  docker compose -C $NODE_DIR restart        # перезапуск"
    echo "  /usr/local/bin/update-geo-dat.sh           # обновить dat вручную"
    echo ""
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    clear
    echo -e "${C}"
    echo "  ┌─────────────────────────────────────────────────┐"
    echo "  │       remnawave-node  •  deploy script v1.0     │"
    echo "  │       Ubuntu 24.04   •  Xray  •  nginx  •  ufw  │"
    echo "  └─────────────────────────────────────────────────┘"
    echo -e "${NC}"

    phase0_checks
    phase1_input
    phase2_deps
    phase3_ssh
    phase4_ssl
    phase5_nginx
    phase6_node
    phase7_geo
    phase8_node_exporter
    phase9_fakesite
    phase10_ufw
    phase11_summary
}

main "$@"
