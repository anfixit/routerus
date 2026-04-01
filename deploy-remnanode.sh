#!/usr/bin/env bash
# =============================================================================
# deploy-remnanode.sh v1.6 — Развёртывание remnawave-node на Ubuntu 24.04
# github.com/anfixit/routerus
#
# Запуск:
#   bash <(wget -qO- https://raw.githubusercontent.com/anfixit/routerus/main/deploy-remnanode.sh)
#
# Changelog v1.6:
#   - fix: SSH restart — sshd || ssh (совместимость с Ubuntu 24.04)
#   - fix: UFW — добавлен NODE_PORT (2222) для связи панели с нодой
#   - fix: crontab pipefail-safe (не падает на пустом crontab)
#   - fix: wget geo-файлов с --timeout и --tries
#   - fix: docker pull без -q (некоторые версии не поддерживают)
#   - add: проверка Master IP != Server IP
#   - add: подробные объяснения к каждой фазе
#   - add: чеклист из 5 шагов в финале (включая Internal Squads)
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

# =============================================================================
# ФАЗА 0
# =============================================================================
phase0_checks() {
    title "Фаза 0 / Проверки"
    echo "  Проверяем что скрипт запущен от root на Ubuntu 24.04."
    echo ""
    [[ $EUID -eq 0 ]] || die "Запускай от root: sudo su -"
    local ver; ver=$(grep -oP '(?<=VERSION_ID=")[^"]+' /etc/os-release 2>/dev/null || echo "unknown")
    [[ "$ver" != "24.04" ]] && warn "Скрипт тестировался на Ubuntu 24.04. Обнаружено: $ver"
    SERVER_IP=$(ip route get 8.8.8.8 2>/dev/null | grep -Po 'src \K\S+' | head -1 || curl -s4 ifconfig.me | tr -d '[:space:]')
    ok "IP сервера: $SERVER_IP"
}

# =============================================================================
# ФАЗА 1
# =============================================================================
phase1_input() {
    title "Фаза 1 / Параметры"

    echo ""
    echo -e "${B}  ┌──────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${B}  │  Шаг 1: Домены                                              │${NC}"
    echo -e "${B}  └──────────────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo "  Для работы ноды нужно 2 домена, каждый направленный на IP: $SERVER_IP"
    echo ""
    echo "  • CONNECTION DOMAIN — адрес, который клиенты используют для"
    echo "    подключения к VPN. На него выпускается SSL-сертификат."
    echo "    Пример: mynode.duckdns.org"
    echo ""
    echo "  • SNI DOMAIN — домен для маскировки под обычный сайт (Reality)."
    echo "    При проверке трафика DPI видит этот домен, а не VPN."
    echo "    На нём будет фейковый сайт. Должен отличаться от connection."
    echo "    Пример: mynode-sni.duckdns.org"
    echo ""
    echo "  Бесплатные DNS-сервисы:"
    echo -e "    ${G}★${NC} duckdns.org   — до 5 поддоменов, вход через GitHub/Google"
    echo "    • dynu.com      — IPv6, поддержка своих доменов"
    echo "    • afraid.org    — 5 поддоменов, 55 000+ зон"
    echo "    • noip.com      — 3 хоста, подтверждение раз в 30 дней"
    echo "    • Или свой домен (reg.ru, Cloudflare, ...)"
    echo ""

    while [[ -z "$CONNECTION_DOMAIN" ]]; do
        read -rp "  Connection domain: " CONNECTION_DOMAIN
        [[ -z "$CONNECTION_DOMAIN" ]] && warn "Не может быть пустым"
    done
    while [[ -z "$SNI_DOMAIN" ]]; do
        read -rp "  SNI domain: " SNI_DOMAIN
        [[ -z "$SNI_DOMAIN" ]] && warn "Не может быть пустым"
        [[ "$SNI_DOMAIN" == "$CONNECTION_DOMAIN" ]] && warn "Должен отличаться от connection!" && SNI_DOMAIN=""
    done

    echo ""
    echo -e "${B}  ┌──────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${B}  │  Шаг 2: Имя профиля                                         │${NC}"
    echo -e "${B}  └──────────────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo "  Уникальное имя для Config Profile и ноды в панели Remnawave."
    echo "  Формат: СТРАНА_название. Примеры: DE_berlin, NL_amsterdam, SE_stockholm"
    echo "  Это имя будет видно в списке серверов у клиентов."
    echo ""
    while [[ -z "$PROFILE_NAME" ]]; do
        read -rp "  Имя профиля: " PROFILE_NAME
        [[ -z "$PROFILE_NAME" ]] && warn "Не может быть пустым"
    done

    echo ""
    echo -e "${B}  ┌──────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${B}  │  Шаг 3: Порты и мониторинг                                  │${NC}"
    echo -e "${B}  └──────────────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo "  Node port — порт, на котором remnawave-node общается с панелью."
    echo "  По умолчанию 2222. Должен совпадать с тем, что указан в панели."
    read -rp "  Порт remnawave-node [${NODE_PORT}]: " _p; [[ -n "$_p" ]] && NODE_PORT="$_p"

    echo ""
    echo "  SSH-порт — рекомендуется сменить с 22, чтобы снизить количество"
    echo "  брутфорс-атак. Популярные варианты: 2222, 2810, 22022."
    read -rp "  Новый SSH-порт [Enter = оставить 22]: " _s; [[ -n "$_s" ]] && SSH_PORT="$_s"

    echo ""
    echo "  Master IP — IP сервера с панелью Remnawave + Prometheus + Grafana."
    echo "  Нужен чтобы UFW разрешил доступ к метрикам Node Exporter (порт 9100)"
    echo "  только с мастер-сервера. Это НЕ IP текущего сервера."
    read -rp "  IP мастер-сервера [${MASTER_IP}]: " _m; [[ -n "$_m" ]] && MASTER_IP="$_m"

    if [[ "$MASTER_IP" == "$SERVER_IP" ]]; then
        warn "Master IP совпадает с IP этого сервера ($SERVER_IP)."
        warn "Master IP — это IP сервера с панелью Remnawave, не текущего."
        read -rp "  Точно верно? [y/N]: " _mc
        [[ "${_mc,,}" != "y" ]] && read -rp "  Введи правильный Master IP: " MASTER_IP
    fi

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

# =============================================================================
# ФАЗА 2
# =============================================================================
phase2_deps() {
    title "Фаза 2 / Зависимости"
    echo "  Устанавливаем системные пакеты: nginx, certbot, jq и др."
    echo ""
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get upgrade -y -qq
    apt-get install -y -qq curl wget ufw nginx-full certbot libnginx-mod-stream ca-certificates gnupg lsb-release jq
    ok "Пакеты установлены"
}

# =============================================================================
# ФАЗА 3
# =============================================================================
phase3_docker() {
    title "Фаза 3 / Docker"
    echo "  Docker нужен для запуска контейнера remnawave-node."
    echo ""
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

# =============================================================================
# ФАЗА 4 — FIX v1.6: sshd || ssh
# =============================================================================
phase4_ssh() {
    title "Фаза 4 / SSH"
    if [[ "$SSH_PORT" == "22" ]]; then ok "SSH-порт оставлен 22"; return; fi

    echo "  Меняем SSH-порт и сразу разрешаем его в UFW (страховка от обрыва)."
    echo ""

    sed -i "s/^#*Port .*/Port ${SSH_PORT}/" /etc/ssh/sshd_config
    grep -q "^Port ${SSH_PORT}" /etc/ssh/sshd_config || echo "Port ${SSH_PORT}" >> /etc/ssh/sshd_config

    # Разрешаем новый порт ДО перезапуска — страховка от потери доступа
    ufw allow "${SSH_PORT}/tcp" comment "SSH" 2>/dev/null || true

    # FIX v1.6: на Ubuntu 24.04 сервис может называться ssh или sshd
    systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || warn "Не удалось перезапустить SSH"

    ok "SSH → порт $SSH_PORT"
    warn "Новое подключение: ssh root@${SERVER_IP} -p ${SSH_PORT}"
}

# =============================================================================
# ФАЗА 5
# =============================================================================
phase5_ssl() {
    title "Фаза 5 / SSL"
    echo "  Let's Encrypt сертификаты для обоих доменов."
    echo "  certbot использует standalone-режим (временно слушает порт 80)."
    echo ""
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

# =============================================================================
# ФАЗА 6
# =============================================================================
phase6_nginx() {
    title "Фаза 6 / nginx"
    echo "  nginx слушает порт 443 и по SNI (имени домена в TLS) решает"
    echo "  куда направить трафик:"
    echo "    SNI domain  → 8443 (Xray Reality)"
    echo "    Conn domain → 7443 (HTTPS, fake site)"
    echo "    Reality fallback → 9443"
    echo ""

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

# =============================================================================
# ФАЗА 7
# =============================================================================
phase7_keygen() {
    title "Фаза 7 / Генерация Reality ключей"
    echo "  Reality (XTLS) использует ключи x25519 для шифрования."
    echo "  Private Key вставляется в Config Profile на сервере."
    echo "  Public Key используется клиентами (подставляется автоматически)."
    echo ""

    info "Загружаю образ remnawave/node..."
    docker pull remnawave/node:latest 2>/dev/null || docker pull remnawave/node:latest
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
        echo ""
        info "Обнови в существующем профиле:"
        echo "    privateKey  → ${XRAY_PRIVATE_KEY}"
        echo "    serverNames → [\"${SNI_DOMAIN}\"]"
        read -rp "  Обнови профиль, затем Enter... " _
    else
        echo ""
        echo -e "${B}  Создай Config Profile в панели Remnawave.${NC}"
        echo "  Панель → Config Profiles → + (добавить) → имя: ${PROFILE_NAME}"
        echo "  Вставь этот JSON в поле «Конфиг. Xray»:"
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
        read -rp "  Создай профиль в панели, затем Enter... " _
    fi
    ok "Ключи готовы, профиль настроен"
}

# =============================================================================
# ФАЗА 8
# =============================================================================
phase8_secret() {
    title "Фаза 8 / SECRET_KEY"
    echo ""
    echo "  Теперь создай ноду в панели Remnawave."
    echo "  SECRET_KEY — уникальный токен, который связывает контейнер"
    echo "  на этом сервере с нодой в панели. Генерируется панелью."
    echo ""
    echo -e "${B}  Шаги в панели:${NC}"
    echo "  1. Nodes → + (добавить ноду)"
    echo "  2. Имя: ${PROFILE_NAME}"
    echo "  3. IP: ${SERVER_IP}"
    echo "  4. Порт: ${NODE_PORT}"
    echo "  5. Привяжи профиль: ${PROFILE_NAME}"
    echo "  6. Создай ноду → скопируй SECRET_KEY (длинная строка eyJ...)"
    echo ""
    echo -e "  ${Y}Нода будет Offline — это нормально, мы её ещё не запустили.${NC}"
    echo ""
    while [[ -z "$SECRET_KEY" ]]; do
        read -rp "  SECRET_KEY: " SECRET_KEY
        [[ -z "$SECRET_KEY" ]] && warn "Не может быть пустым"
    done
    ok "SECRET_KEY (${#SECRET_KEY} символов)"
}

# =============================================================================
# ФАЗА 9 — geo ДО контейнера + timeout/tries
# =============================================================================
phase9_geo() {
    title "Фаза 9 / Geo-файлы"
    echo "  Скачиваем geosite.dat и geoip.dat от runetfreedom."
    echo "  Содержат категории доменов и IP для маршрутизации и блокировки рекламы."
    echo "  Монтируются в контейнер. Скачиваем ДО запуска — иначе Docker"
    echo "  создаст пустые директории вместо файлов."
    echo "  Файлы большие (~80MB суммарно), может занять несколько минут."
    echo ""
    mkdir -p "$GEO_DIR"
    info "geosite.dat (~62MB)..."
    wget --timeout=120 --tries=3 -q -O "${GEO_DIR}/geosite.dat" "$GEO_SITE_URL" \
        || die "Не скачался geosite.dat. Попробуй вручную: wget -O ${GEO_DIR}/geosite.dat $GEO_SITE_URL"
    info "geoip.dat (~21MB)..."
    wget --timeout=120 --tries=3 -q -O "${GEO_DIR}/geoip.dat" "$GEO_IP_URL" \
        || die "Не скачался geoip.dat. Попробуй вручную: wget -O ${GEO_DIR}/geoip.dat $GEO_IP_URL"
    ok "geosite $(du -sh "${GEO_DIR}/geosite.dat" | cut -f1) + geoip $(du -sh "${GEO_DIR}/geoip.dat" | cut -f1)"
}

# =============================================================================
# ФАЗА 10
# =============================================================================
phase10_node() {
    title "Фаза 10 / remnawave-node"
    echo "  Запускаем контейнер с Xray-core, который подключится к панели."
    echo ""
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
        warn "Проверь логи: docker logs remnanode --tail=20"
    fi
}

# =============================================================================
# ФАЗА 11 — crontab pipefail-safe
# =============================================================================
phase11_geocron() {
    title "Фаза 11 / Автообновление geo"
    echo "  Geo-файлы обновляются каждые 6 часов в источнике."
    echo "  Настраиваем cron на обновление каждую ночь в 03:00."
    echo ""
    cat > /usr/local/bin/update-geo-dat.sh << 'GEOEOF'
#!/usr/bin/env bash
set -euo pipefail
GEO="/opt/remnanode/geodata"
LOG="/var/log/remnanode/geo-update.log"
S="https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/geosite.dat"
I="https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/geoip.dat"
wget --timeout=120 --tries=3 -q -O "${GEO}/geosite.dat.new" "$S" && mv "${GEO}/geosite.dat.new" "${GEO}/geosite.dat"
wget --timeout=120 --tries=3 -q -O "${GEO}/geoip.dat.new" "$I" && mv "${GEO}/geoip.dat.new" "${GEO}/geoip.dat"
cd /opt/remnanode && docker compose restart remnanode
echo "$(date '+%Y-%m-%d %H:%M:%S') updated" >> "$LOG"
GEOEOF
    chmod +x /usr/local/bin/update-geo-dat.sh

    # FIX v1.6: pipefail-safe crontab
    local existing_cron=""
    existing_cron=$(crontab -l 2>/dev/null || true)
    local new_cron
    new_cron=$(echo "$existing_cron" | grep -v "update-geo-dat" || true)
    printf '%s\n' "${new_cron}" "0 3 * * * /usr/local/bin/update-geo-dat.sh" | sed '/^$/d' | crontab -

    ok "Cron: geo обновление каждую ночь в 03:00"
}

# =============================================================================
# ФАЗА 12
# =============================================================================
phase12_node_exporter() {
    title "Фаза 12 / Node Exporter"
    echo "  Prometheus Node Exporter собирает метрики сервера (CPU, RAM, диск)."
    echo "  Grafana на мастер-сервере отображает их в дашборде."
    echo "  Доступ ограничен UFW — только с IP мастера ($MASTER_IP)."
    echo ""
    if command -v node_exporter &>/dev/null; then ok "Уже установлен"; return; fi
    local tb="node_exporter-${NODE_EXPORTER_VER}.linux-amd64.tar.gz"
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

# =============================================================================
# ФАЗА 13
# =============================================================================
phase13_fakesite() {
    title "Фаза 13 / Fake site"
    echo "  Фейковый сайт показывается при проверке SNI-домена браузером."
    echo "  Если кто-то зайдёт на SNI-домен — увидит обычный сайт, не VPN."
    echo ""
    mkdir -p /var/www/html
    if bash <(wget -qO- https://raw.githubusercontent.com/mozaroc/x-ui-pro/refs/heads/master/randomfakehtml.sh) 2>/dev/null; then
        ok "Fake site (randomfakehtml)"
    else
        echo '<html><head><title>Welcome</title><style>body{font-family:Arial,sans-serif;margin:40px;background:#f5f5f5}.c{max-width:800px;margin:0 auto;background:#fff;padding:30px;border-radius:8px;box-shadow:0 2px 4px rgba(0,0,0,.1)}</style></head><body><div class="c"><h1>Welcome</h1><p>Site under construction.</p></div></body></html>' > /var/www/html/index.html
        ok "Fake site (fallback)"
    fi
}

# =============================================================================
# ФАЗА 14 — FIX v1.6: добавлен NODE_PORT
# =============================================================================
phase14_ufw() {
    title "Фаза 14 / UFW"
    echo "  Файрвол разрешает только необходимые порты:"
    echo "    SSH(${SSH_PORT}), HTTP(80), HTTPS/Xray(443),"
    echo "    Node API(${NODE_PORT}) — для связи панели с нодой,"
    echo "    Node Exporter(9100) — только с ${MASTER_IP}"
    echo ""
    ufw --force reset
    ufw default deny incoming; ufw default allow outgoing
    ufw allow "${SSH_PORT}/tcp" comment "SSH"
    ufw allow 80/tcp comment "HTTP"
    ufw allow 443/tcp comment "HTTPS/Xray"
    ufw allow "${NODE_PORT}/tcp" comment "remnawave-node API"
    ufw allow from "${MASTER_IP}" to any port 9100 proto tcp comment "Node Exporter"
    ufw --force enable
    ok "UFW: SSH(${SSH_PORT}), 80, 443, ${NODE_PORT}, 9100(${MASTER_IP})"
}

# =============================================================================
# ФАЗА 15
# =============================================================================
phase15_summary() {
    echo ""
    echo -e "${G}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${G}║           remnawave-node v1.6 — развёрнут!                    ║${NC}"
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
    echo -e "${B}  ┌──────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${B}  │          ЧЕКЛИСТ В ПАНЕЛИ (5 шагов, все обязательные)        │${NC}"
    echo -e "${B}  └──────────────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo "  1. ${B}Nodes${NC} → убедись что нода ${G}Online${NC} (зелёный статус)"
    echo "     Если Offline: docker logs remnanode --tail=20"
    echo ""
    echo "  2. ${B}Nodes${NC} → ${PROFILE_NAME} → включи ${Y}Host visibility${NC}"
    echo "     Без этого нода не попадёт в подписки клиентов."
    echo ""
    echo "  3. ${B}Hosts${NC} → создай хост для ноды:"
    echo "     • Инбаунд: ${PROFILE_NAME}"
    echo "     • Адрес: ${CONNECTION_DOMAIN}"
    echo "     • Port: ${Y}443${NC} (не 8443!)"
    echo "     • SNI: ${SNI_DOMAIN}"
    echo ""
    echo "  4. ${B}Internal Squads${NC} → Default-Squad → добавь инбаунд ${PROFILE_NAME}"
    echo "     ${R}⚠ БЕЗ ЭТОГО ШАГА НОДА НЕ ПОЯВИТСЯ В ПОДПИСКАХ!${NC}"
    echo ""
    echo "  5. ${B}На клиенте${NC} (Happ/v2rayNG) → обнови подписку вручную"
    echo ""
    echo -e "${B}  Команды:${NC}"
    echo "  docker logs remnanode --tail=20             # логи"
    echo "  cd /opt/remnanode && docker compose restart  # перезапуск"
    echo "  /usr/local/bin/update-geo-dat.sh            # обновить geo"
    echo ""
}

# =============================================================================
main() {
    clear
    echo -e "${C}"
    echo "  ┌──────────────────────────────────────────────────────┐"
    echo "  │        remnawave-node  •  deploy script  v1.6       │"
    echo "  │        github.com/anfixit/routerus                  │"
    echo "  └──────────────────────────────────────────────────────┘"
    echo -e "${NC}"
    phase0_checks; phase1_input; phase2_deps; phase3_docker; phase4_ssh
    phase5_ssl; phase6_nginx; phase7_keygen; phase8_secret; phase9_geo
    phase10_node; phase11_geocron; phase12_node_exporter; phase13_fakesite
    phase14_ufw; phase15_summary
}
main "$@"
