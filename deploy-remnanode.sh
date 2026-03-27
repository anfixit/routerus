#!/usr/bin/env bash
# =============================================================================
# deploy-remnanode.sh — Развёртывание remnawave-node на Ubuntu 24.04
# github.com/anfixit/routerus
#
# Запуск:
#   bash <(wget -qO- https://raw.githubusercontent.com/anfixit/routerus/main/deploy-remnanode.sh)
#
# Фазы:
#   0  Проверки (root, Ubuntu 24)
#   1  Интерактивный ввод параметров
#   2  Обновление системы + зависимости
#   3  Docker
#   4  SSH-порт (опционально)
#   5  SSL-сертификаты (certbot standalone)
#   6  nginx (stream SNI: 443 → 8443/7443, Reality fallback → 9443)
#   7  Генерация Reality ключей + пауза для создания Config Profile
#   8  remnawave-node (docker compose)
#   9  geosite.dat + geoip.dat (runetfreedom) + cron автообновление
#  10  Node Exporter для Prometheus
#  11  Fake site (randomfakehtml.sh)
#  12  UFW
#  13  Итоговый вывод
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

# ── Переменные ────────────────────────────────────────────────────────────────
SECRET_KEY=""
CONNECTION_DOMAIN=""
SNI_DOMAIN=""
NODE_PORT="2222"
SSH_PORT="22"
MASTER_IP="151.244.72.28"
SERVER_IP=""
NODE_DIR="/opt/remnanode"
XRAY_SHARE="/usr/local/share/xray"
GEO_BASE="https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download"
NODE_EXPORTER_VER="1.9.1"

# =============================================================================
# ФАЗА 0: Проверки
# =============================================================================
phase0_checks() {
    title "Фаза 0 / Проверки"

    [[ $EUID -eq 0 ]] || die "Запускай от root: sudo su -"

    local ver
    ver=$(grep -oP '(?<=VERSION_ID=")[^"]+' /etc/os-release 2>/dev/null || echo "unknown")
    [[ "$ver" != "24.04" ]] && warn "Скрипт тестировался на Ubuntu 24.04. Обнаружено: $ver"

    SERVER_IP=$(ip route get 8.8.8.8 2>/dev/null | grep -Po 'src \K\S+' | head -1 \
                || curl -s4 ifconfig.me | tr -d '[:space:]')
    ok "IP сервера: $SERVER_IP"
}

# =============================================================================
# ФАЗА 1: Интерактивный ввод
# =============================================================================
phase1_input() {
    title "Фаза 1 / Параметры"

    # SECRET KEY
    echo ""
    echo -e "${B}  Шаг 1: SECRET KEY из Remnawave панели${NC}"
    echo "  ┌──────────────────────────────────────────────────────────────┐"
    echo "  │  1. Открой панель Remnawave                                  │"
    echo "  │  2. Nodes → Add node                                         │"
    echo "  │  3. Заполни имя ноды (формат: СТРАНА_название)              │"
    echo "  │     Например: DE_mynode, NL_amsterdam, AT_vienna             │"
    echo "  │  4. Порт ноды: 2222 (или свой)                              │"
    echo "  │  5. Нажми «Important information» → скопируй SECRET KEY     │"
    echo "  └──────────────────────────────────────────────────────────────┘"
    echo ""
    while [[ -z "$SECRET_KEY" ]]; do
        read -rp "  SECRET KEY (eyJ...): " SECRET_KEY
        [[ -z "$SECRET_KEY" ]] && warn "Ключ не может быть пустым"
    done

    # Домены
    echo ""
    echo -e "${B}  Шаг 2: Домены${NC}"
    echo "  Нужно 2 домена/поддомена → оба направить на IP: $SERVER_IP"
    echo ""
    echo "  Бесплатные DNS-сервисы:"
    echo -e "    ${G}★${NC} duckdns.org   — вход через GitHub/Google, до 5 поддоменов"
    echo "       Пример: mynode.duckdns.org и mynode-sni.duckdns.org"
    echo "    • dynu.com      — IPv6, поддержка своих доменов"
    echo "    • afraid.org    — 5 поддоменов, 55 000+ зон"
    echo "    • noip.com      — 3 хоста, подтверждение раз в 30 дней"
    echo ""
    echo "  Домен 1 — connection domain (адрес для подключения клиентов)"
    while [[ -z "$CONNECTION_DOMAIN" ]]; do
        read -rp "  Connection domain: " CONNECTION_DOMAIN
        [[ -z "$CONNECTION_DOMAIN" ]] && warn "Домен не может быть пустым"
    done

    echo ""
    echo "  Домен 2 — SNI domain (маскировка Reality, должен отличаться)"
    while [[ -z "$SNI_DOMAIN" ]]; do
        read -rp "  SNI domain: " SNI_DOMAIN
        [[ -z "$SNI_DOMAIN" ]] && warn "Домен не может быть пустым"
        [[ "$SNI_DOMAIN" == "$CONNECTION_DOMAIN" ]] && \
            warn "SNI domain должен отличаться от connection domain" && SNI_DOMAIN=""
    done

    # Порт ноды
    echo ""
    read -rp "  Порт remnawave-node [${NODE_PORT}]: " _port
    [[ -n "$_port" ]] && NODE_PORT="$_port"

    # SSH порт
    echo ""
    echo "  SSH-порт: рекомендуется сменить с 22 для защиты от сканеров"
    read -rp "  Новый SSH-порт [Enter — оставить 22]: " _ssh
    [[ -n "$_ssh" ]] && SSH_PORT="$_ssh"

    # IP мастера
    echo ""
    read -rp "  IP мастер-сервера для Node Exporter [${MASTER_IP}]: " _master
    [[ -n "$_master" ]] && MASTER_IP="$_master"

    # Подтверждение
    echo ""
    echo -e "${B}  Параметры:${NC}"
    echo "  ──────────────────────────────────────────────"
    printf "  %-24s %s\n" "Connection domain:"  "$CONNECTION_DOMAIN"
    printf "  %-24s %s\n" "SNI domain:"         "$SNI_DOMAIN"
    printf "  %-24s %s\n" "Node port:"          "$NODE_PORT"
    printf "  %-24s %s\n" "SSH port:"           "$SSH_PORT"
    printf "  %-24s %s\n" "Master IP:"          "$MASTER_IP"
    printf "  %-24s %s...\n" "SECRET KEY:"      "${SECRET_KEY:0:20}"
    echo "  ──────────────────────────────────────────────"
    echo ""
    read -rp "  Всё верно? [Y/n]: " _confirm
    [[ "${_confirm,,}" == "n" ]] && die "Отменено. Запусти скрипт заново."
    ok "Параметры приняты"
}

# =============================================================================
# ФАЗА 2: Обновление системы + зависимости
# =============================================================================
phase2_deps() {
    title "Фаза 2 / Зависимости"

    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get upgrade -y -qq
    apt-get install -y -qq \
        curl wget ufw nginx-full certbot \
        libnginx-mod-stream \
        ca-certificates gnupg lsb-release

    ok "Зависимости установлены"
}

# =============================================================================
# ФАЗА 3: Docker
# =============================================================================
phase3_docker() {
    title "Фаза 3 / Docker"

    if command -v docker &>/dev/null; then
        ok "Docker уже установлен: $(docker --version | grep -oP '[\d.]+' | head -1)"
    else
        info "Устанавливаю Docker..."
        curl -fsSL https://get.docker.com | sh
        systemctl enable --now docker
        ok "Docker установлен"
    fi

    docker compose version &>/dev/null \
        || die "docker compose plugin не найден. Переустанови Docker через get.docker.com"

    # Сброс возможного failed-state
    systemctl reset-failed docker 2>/dev/null || true
}

# =============================================================================
# ФАЗА 4: SSH-порт
# =============================================================================
phase4_ssh() {
    title "Фаза 4 / SSH"

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
# ФАЗА 5: SSL
# =============================================================================
phase5_ssl() {
    title "Фаза 5 / SSL-сертификаты"

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
# ФАЗА 6: nginx
# =============================================================================
phase6_nginx() {
    title "Фаза 6 / nginx (stream SNI routing)"

    mkdir -p /etc/nginx/stream-enabled

    # Stream module — подключаем только если не подключён через modules-enabled
    if [[ ! -f /etc/nginx/modules-enabled/50-mod-stream.conf ]]; then
        grep -qF "load_module modules/ngx_stream_module.so;" /etc/nginx/nginx.conf \
            || sed -i '1s|^|load_module /usr/lib/nginx/modules/ngx_stream_module.so;\n|' \
                   /etc/nginx/nginx.conf
    else
        # Убираем ручную строку если она вдруг попала туда раньше
        sed -i '/load_module.*ngx_stream_module/d' /etc/nginx/nginx.conf
    fi

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

    # HTTP → HTTPS redirect
    cat > /etc/nginx/sites-available/80.conf << EOF
server {
    listen 80;
    server_name ${CONNECTION_DOMAIN} ${SNI_DOMAIN};
    return 301 https://\$host\$request_uri;
}
EOF

    # HTTPS для connection domain (fake site)
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

    # HTTPS для SNI domain (Reality fallback)
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
    ok "nginx настроен"
}

# =============================================================================
# ФАЗА 7: Генерация Reality ключей
# =============================================================================
XRAY_PRIVATE_KEY=""
XRAY_PUBLIC_KEY=""

phase7_keygen() {
    title "Фаза 7 / Генерация Reality ключей"

    info "Генерирую ключевую пару x25519..."
    local output
    output=$(docker run --rm remnawave/node:latest xray x25519 2>/dev/null) \
        || die "Не удалось запустить xray x25519. Проверь Docker."

    XRAY_PRIVATE_KEY=$(echo "$output" | grep "^PrivateKey:" | awk '{print $2}')
    XRAY_PUBLIC_KEY=$(echo "$output"  | grep "^Password:"   | awk '{print $2}')

    [[ -z "$XRAY_PRIVATE_KEY" ]] && die "Не удалось получить PrivateKey"

    echo ""
    echo -e "${G}  ╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${G}  ║              Ключи для Config Profile в панели              ║${NC}"
    echo -e "${G}  ╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${B}PrivateKey${NC} (вставить в privateKey Config Profile):"
    echo -e "  ${Y}${XRAY_PRIVATE_KEY}${NC}"
    echo ""
    echo -e "  ${B}PublicKey${NC}  (для справки / клиентских конфигов):"
    echo -e "  ${C}${XRAY_PUBLIC_KEY}${NC}"
    echo ""
    echo -e "  ${B}SNI domain${NC} (вставить в serverNames Config Profile):"
    echo -e "  ${C}${SNI_DOMAIN}${NC}"
    echo ""
    echo "  ┌──────────────────────────────────────────────────────────────┐"
    echo "  │  Сейчас открой панель Remnawave и создай Config Profile:     │"
    echo "  │                                                              │"
    echo "  │  1. Config Profiles → Add profile                           │"
    echo "  │  2. Вставь шаблон из README                                 │"
    echo "  │  3. Замени privateKey на ключ выше                          │"
    echo "  │  4. Замени serverNames на: ${SNI_DOMAIN}         │"
    echo "  │  5. Сохрани профиль                                         │"
    echo "  │                                                              │"
    echo "  │  После этого нажми Enter чтобы продолжить установку         │"
    echo "  └──────────────────────────────────────────────────────────────┘"
    echo ""
    read -rp "  Нажми Enter когда Config Profile создан..." _
    ok "Продолжаем установку"
}

# =============================================================================
# ФАЗА 8: remnawave-node
# =============================================================================
phase7_node() {
    title "Фаза 7 / remnawave-node"

    mkdir -p "$NODE_DIR" "$NODE_DIR/geodata" /var/log/remnanode "$XRAY_SHARE"

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
      - ${NODE_DIR}/geodata/geosite.dat:/usr/local/share/xray/geosite.dat:ro
      - ${NODE_DIR}/geodata/geoip.dat:/usr/local/share/xray/geoip.dat:ro
      - /var/log/remnanode:/var/log/remnanode
EOF

    cd "$NODE_DIR"
    docker compose pull -q
    docker compose up -d

    sleep 5
    docker compose ps | grep -qiE "running|up" \
        && ok "remnawave-node запущен (порт ${NODE_PORT})" \
        || warn "Контейнер возможно ещё стартует. Проверь: docker compose -C $NODE_DIR logs -f"
}

# =============================================================================
# ФАЗА 9: geosite/geoip + автообновление
# =============================================================================
phase8_geo() {
    title "Фаза 8 / geosite + geoip (runetfreedom)"

    info "Скачиваю geosite.dat..."
    curl -fsSLo "${NODE_DIR}/geodata/geosite.dat" "${GEO_BASE}/geosite.dat" \
        || die "Не удалось скачать geosite.dat"

    info "Скачиваю geoip.dat..."
    curl -fsSLo "${NODE_DIR}/geodata/geoip.dat" "${GEO_BASE}/geoip.dat" \
        || die "Не удалось скачать geoip.dat"

    # Перезапуск ноды чтобы подхватила свежие файлы
    cd "$NODE_DIR" && docker compose restart remnanode
    ok "Геофайлы загружены (geosite: $(du -sh ${NODE_DIR}/geodata/geosite.dat | cut -f1), geoip: $(du -sh ${NODE_DIR}/geodata/geoip.dat | cut -f1))"

    # Скрипт автообновления
    cat > /usr/local/bin/update-geo-dat.sh << GEOEOF
#!/usr/bin/env bash
set -euo pipefail
BASE="https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download"
DIR="${NODE_DIR}/geodata"
LOG="/var/log/remnanode/geo-update.log"
curl -fsSLo "\${DIR}/geosite.dat.new" "\${BASE}/geosite.dat"
curl -fsSLo "\${DIR}/geoip.dat.new"   "\${BASE}/geoip.dat"
mv "\${DIR}/geosite.dat.new" "\${DIR}/geosite.dat"
mv "\${DIR}/geoip.dat.new"   "\${DIR}/geoip.dat"
cd ${NODE_DIR} && docker compose restart remnanode
echo "\$(date "+%Y-%m-%d %H:%M:%S") updated" >> "\$LOG"
GEOEOF

    chmod +x /usr/local/bin/update-geo-dat.sh

    # Cron: каждую ночь в 03:00
    (crontab -l 2>/dev/null | grep -v "update-geo-dat"; \
     echo "0 3 * * * /usr/local/bin/update-geo-dat.sh") | crontab -

    ok "Автообновление dat настроено (cron: 0 3 * * *)"
}

# =============================================================================
# ФАЗА 9: Node Exporter
# =============================================================================
phase9_node_exporter() {
    title "Фаза 9 / Node Exporter"

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
# ФАЗА 10: Fake site
# =============================================================================
phase10_fakesite() {
    title "Фаза 10 / Fake site"

    bash <(wget -qO- \
        https://raw.githubusercontent.com/mozaroc/x-ui-pro/refs/heads/master/randomfakehtml.sh \
    ) || warn "randomfakehtml.sh вернул ошибку (не критично)"

    ok "Fake site установлен"
}

# =============================================================================
# ФАЗА 11: UFW
# =============================================================================
phase11_ufw() {
    title "Фаза 11 / UFW"

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
# ФАЗА 12: Итоговый вывод
# =============================================================================
phase12_summary() {
    echo ""
    echo -e "${G}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${G}║                  Развёртывание завершено!                    ║${NC}"
    echo -e "${G}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    printf "  %-26s ${C}%s${NC}\n" "Сервер IP:"          "$SERVER_IP"
    printf "  %-26s %s\n" "Connection domain:"  "$CONNECTION_DOMAIN"
    printf "  %-26s %s\n" "SNI domain:"         "$SNI_DOMAIN"
    printf "  %-26s %s\n" "Node port:"          "$NODE_PORT"
    [[ "$SSH_PORT" != "22" ]] && \
        printf "  %-26s ${Y}%s  ← НОВЫЙ SSH-ПОРТ!${NC}\n" "SSH port:" "$SSH_PORT"
    echo ""
    echo -e "${B}  Что сделать в панели Remnawave:${NC}"
    echo "  1. Nodes → убедись что нода Online"
    echo "     Если нет: docker compose -C $NODE_DIR logs -f"
    echo "  2. Включи Host visibility (чтобы нода попала в подписки)"
    echo "  3. Привяжи Config Profile к ноде"
    echo ""
    echo -e "${B}  Полезные команды:${NC}"
    echo "  docker compose -C $NODE_DIR logs -f       # логи ноды"
    echo "  docker compose -C $NODE_DIR restart       # перезапуск"
    echo "  /usr/local/bin/update-geo-dat.sh          # обновить dat вручную"
    echo "  cat /var/log/remnanode/geo-update.log     # лог обновлений"
    echo ""
    echo -e "${B}  Автообновление dat:${NC} каждую ночь в 03:00"
    echo ""
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    clear
    echo -e "${C}"
    echo "  ┌─────────────────────────────────────────────────────┐"
    echo "  │        remnawave-node  •  deploy script  v1.3       │"
    echo "  │        Ubuntu 24.04  •  Xray  •  nginx  •  ufw      │"
    echo "  │        github.com/anfixit/routerus                  │"
    echo "  └─────────────────────────────────────────────────────┘"
    echo -e "${NC}"

    phase0_checks
    phase1_input
    phase2_deps
    phase3_docker
    phase4_ssh
    phase5_ssl
    phase6_nginx
    phase7_keygen
    phase7_node
    phase8_geo
    phase9_node_exporter
    phase10_fakesite
    phase11_ufw
    phase12_summary
}

main "$@"
