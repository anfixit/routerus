#!/usr/bin/env bash
# =============================================================================
# deploy-remnanode.sh v2.0
# Разворачивает remnawave-node на чистом Ubuntu 24.04 с полным hardening
#
# Использование:
#   bash <(wget -qO- https://raw.githubusercontent.com/anfixit/routerus/main/deploy-remnanode.sh)
#
# Фазы:
#    0  Проверки (root, Ubuntu 24)
#    1  Интерактивный ввод параметров
#    2  Системные зависимости
#    3  Docker
#    4  Создание пользователя admin + SSH-ключ
#    5  SSH hardening (порт 2810, key-only, no root login)
#    6  fail2ban
#    7  Kernel tuning (sysctl)
#    8  SSL-сертификаты (certbot)
#    9  nginx (stream SNI routing)
#   10  x25519 keygen + Config Profile JSON
#   11  remnawave-node (docker compose)
#   12  Geo-файлы + cron-автообновление
#   13  Node Exporter (Prometheus)
#   14  Фейковый сайт
#   15  Certbot auto-renew timer
#   16  Unattended upgrades
#   17  Watchdog-скрипт
#   18  Автоочистка (cron docker prune + logrotate)
#   19  UFW (финальные правила)
#   20  Итоговый вывод
#
# GitHub: github.com/anfixit/routerus
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# ── Цвета ─────────────────────────────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'; B='\033[1m'; NC='\033[0m'

ok()    { echo -e "  ${G}✓${NC} $*"; }
info()  { echo -e "  ${C}→${NC} $*"; }
warn()  { echo -e "  ${Y}!${NC} $*"; }
die()   { echo -e "  ${R}✗ ОШИБКА:${NC} $*" >&2; exit 1; }
title() { echo -e "\n${B}══ $* ══${NC}"; }

# ── Глобальные переменные ─────────────────────────────────────────────────────
SECRET_KEY=""
CONNECTION_DOMAIN=""
SNI_DOMAIN=""
NODE_PORT="2222"
SSH_PORT="2810"
MASTER_IP="151.244.72.28"
NODE_DIR="/opt/remnanode"
ADMIN_USER="admin"
ADMIN_SSH_KEY=""
NODE_EXPORTER_VER="1.9.1"
SERVER_IP=""
PROFILE_NAME=""

# =============================================================================
# ФАЗА 0: Проверки
# =============================================================================
phase0_checks() {
    title "Фаза 0 / Проверки"

    [[ $EUID -eq 0 ]] || die "Запускай от root: sudo su -"

    local ver
    ver=$(grep -oP '(?<=VERSION_ID=")[^"]+' /etc/os-release 2>/dev/null || echo "unknown")
    [[ "$ver" == "24.04" ]] || warn "Тестировалось на Ubuntu 24.04 (у тебя: $ver)"

    SERVER_IP=$(ip -4 addr show scope global | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
    [[ -n "$SERVER_IP" ]] || die "Не могу определить IP сервера"
    ok "Сервер: $SERVER_IP (Ubuntu $ver)"
}

# =============================================================================
# ФАЗА 1: Интерактивный ввод
# =============================================================================
phase1_input() {
    title "Фаза 1 / Параметры"
    echo ""
    echo -e "  ${B}Подготовка${NC}"
    echo "  Перед запуском нужно:"
    echo "  1. Создать Config Profile в панели Remnawave (временные ключи — ок)"
    echo "  2. Создать ноду в панели → скопировать SECRET KEY"
    echo "  3. Направить 2 домена на IP этого сервера ($SERVER_IP)"
    echo ""
    echo -e "  ${B}Бесплатные DNS:${NC}"
    echo "    • duckdns.org (рекомендую) — до 5 поддоменов"
    echo "    • dynu.com / afraid.org / noip.com"
    echo ""

    # ── SECRET_KEY ────────────────────────────────────────────────────────────
    echo -e "  ${Y}Панель → Nodes → нода → Important information → SECRET KEY${NC}"
    while [[ -z "$SECRET_KEY" ]]; do
        read -rp "  SECRET_KEY: " SECRET_KEY
        [[ -z "$SECRET_KEY" ]] && warn "Не может быть пустым"
    done

    # ── Домены ────────────────────────────────────────────────────────────────
    echo ""
    echo "  Домен 1 — адрес подключения клиентов (напр. mynode.duckdns.org)"
    while [[ -z "$CONNECTION_DOMAIN" ]]; do
        read -rp "  Connection domain: " CONNECTION_DOMAIN
        [[ -z "$CONNECTION_DOMAIN" ]] && warn "Не может быть пустым"
    done

    echo ""
    echo "  Домен 2 — SNI для Reality маскировки (напр. mynode-sni.duckdns.org)"
    while [[ -z "$SNI_DOMAIN" ]]; do
        read -rp "  SNI domain: " SNI_DOMAIN
        [[ -z "$SNI_DOMAIN" ]] && warn "Не может быть пустым"
    done

    # ── Имя профиля ───────────────────────────────────────────────────────────
    echo ""
    read -rp "  Имя Config Profile в панели (напр. DE_karmikoala): " PROFILE_NAME
    PROFILE_NAME="${PROFILE_NAME:-NODE_$(hostname)}"

    # ── Порт ноды ─────────────────────────────────────────────────────────────
    echo ""
    read -rp "  Порт remnawave-node [${NODE_PORT}]: " _port
    [[ -n "$_port" ]] && NODE_PORT="$_port"

    # ── SSH-порт ──────────────────────────────────────────────────────────────
    echo ""
    read -rp "  SSH-порт [${SSH_PORT}]: " _ssh
    [[ -n "$_ssh" ]] && SSH_PORT="$_ssh"

    # ── SSH-ключ администратора ───────────────────────────────────────────────
    echo ""
    echo -e "  ${B}SSH-ключ${NC} для пользователя '${ADMIN_USER}'"
    echo "  После деплоя вход будет ТОЛЬКО по этому ключу (пароли отключены)."
    echo ""
    echo "  Как получить ключ на своём компьютере:"
    echo -e "    ${C}cat ~/.ssh/id_ed25519.pub${NC}   (рекомендуемый)"
    echo -e "    ${C}cat ~/.ssh/id_rsa.pub${NC}       (если нет ed25519)"
    echo ""
    echo "  Если ключа нет — сгенерируй:"
    echo -e "    ${C}ssh-keygen -t ed25519 -C \"your@email.com\"${NC}"
    echo ""
    while [[ -z "$ADMIN_SSH_KEY" ]]; do
        read -rp "  Вставь публичный SSH-ключ: " ADMIN_SSH_KEY
        if [[ -z "$ADMIN_SSH_KEY" ]]; then
            warn "Не может быть пустым"
        elif [[ ! "$ADMIN_SSH_KEY" =~ ^ssh-(ed25519|rsa|ecdsa)|^ecdsa-sha2 ]]; then
            warn "Не похоже на публичный ключ. Должен начинаться с ssh-ed25519, ssh-rsa, ssh-ecdsa или ecdsa-sha2"
            ADMIN_SSH_KEY=""
        fi
    done
    ok "SSH-ключ принят"

    # ── Master IP ─────────────────────────────────────────────────────────────
    echo ""
    read -rp "  IP мастер-сервера для мониторинга [${MASTER_IP}]: " _master
    [[ -n "$_master" ]] && MASTER_IP="$_master"

    # Проверка: Master IP не должен совпадать с IP ноды
    if [[ "$MASTER_IP" == "$SERVER_IP" ]]; then
        warn "Master IP = IP этого сервера! Prometheus не достучится."
        read -rp "  Точно верно? [y/N]: " _ok
        [[ "${_ok,,}" != "y" ]] && read -rp "  Правильный Master IP: " MASTER_IP
    fi

    # ── Подтверждение ─────────────────────────────────────────────────────────
    echo ""
    echo -e "  ${B}Параметры:${NC}"
    printf "  %-22s %s\n" "Connection:" "$CONNECTION_DOMAIN"
    printf "  %-22s %s\n" "SNI:" "$SNI_DOMAIN"
    printf "  %-22s %s\n" "Profile:" "$PROFILE_NAME"
    printf "  %-22s %s\n" "Node port:" "$NODE_PORT"
    printf "  %-22s %s\n" "SSH port:" "$SSH_PORT"
    printf "  %-22s %s\n" "SSH-ключ:" "${ADMIN_SSH_KEY:0:40}..."
    printf "  %-22s %s\n" "Master IP:" "$MASTER_IP"
    printf "  %-22s %s...\n" "SECRET_KEY:" "${SECRET_KEY:0:20}"
    echo ""
    read -rp "  Всё верно? [Y/n]: " _c
    [[ "${_c,,}" == "n" ]] && die "Отменено. Запусти заново."
    ok "Параметры приняты"
}

# =============================================================================
# ФАЗА 2: Системные зависимости
# =============================================================================
phase2_deps() {
    title "Фаза 2 / Зависимости"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get upgrade -y -qq
    apt-get install -y -qq \
        curl wget ufw nginx-full certbot libnginx-mod-stream \
        ca-certificates gnupg lsb-release jq fail2ban \
        unattended-upgrades apt-listchanges logrotate
    ok "Системные пакеты установлены"
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
    docker compose version &>/dev/null || die "docker compose plugin не найден"
    systemctl reset-failed docker 2>/dev/null || true
    ok "Docker готов"
}

# =============================================================================
# ФАЗА 4: Пользователь admin
# =============================================================================
phase4_admin_user() {
    title "Фаза 4 / Пользователь admin"
    echo "  Создаём пользователя '${ADMIN_USER}' с sudo и SSH-ключом."
    echo "  Root-логин по SSH будет отключён."
    echo ""

    if id "$ADMIN_USER" &>/dev/null; then
        ok "Пользователь $ADMIN_USER уже существует"
    else
        useradd -m -s /bin/bash -G sudo "$ADMIN_USER"
        ok "Создан пользователь $ADMIN_USER"
    fi

    # Sudo без пароля (для удобства администрирования)
    echo "${ADMIN_USER} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${ADMIN_USER}"
    chmod 440 "/etc/sudoers.d/${ADMIN_USER}"

    # SSH-ключ
    local ssh_dir="/home/${ADMIN_USER}/.ssh"
    mkdir -p "$ssh_dir"
    echo "$ADMIN_SSH_KEY" > "${ssh_dir}/authorized_keys"
    chmod 700 "$ssh_dir"
    chmod 600 "${ssh_dir}/authorized_keys"
    chown -R "${ADMIN_USER}:${ADMIN_USER}" "$ssh_dir"

    # Добавляем admin в группу docker (для управления контейнерами без sudo)
    usermod -aG docker "$ADMIN_USER" 2>/dev/null || true

    ok "SSH-ключ установлен, sudo настроен, docker-группа добавлена"
}

# =============================================================================
# ФАЗА 5: SSH Hardening
# =============================================================================
phase5_ssh_hardening() {
    title "Фаза 5 / SSH Hardening"
    echo "  Порт: ${SSH_PORT}, только ключи, root-логин отключён."
    echo ""

    # Бэкап оригинального конфига
    local SSH_BACKUP="/etc/ssh/sshd_config.bak.$(date +%s)"
    cp /etc/ssh/sshd_config "$SSH_BACKUP"

    # Генерация нового конфига
    cat > /etc/ssh/sshd_config << SSHEOF
# ═══ SSH Hardened Config (deploy-remnanode v2.0) ═══

Port ${SSH_PORT}

# Аутентификация
PermitRootLogin no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes

# Безопасность
MaxAuthTries 3
MaxSessions 3
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2

# Отключаем лишнее
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
PermitTunnel no
PrintMotd no
PrintLastLog yes
TCPKeepAlive yes

# Только admin
AllowUsers ${ADMIN_USER}

# Логирование
SyslogFacility AUTH
LogLevel VERBOSE

# Протокол
Protocol 2
SSHEOF

    # Разрешаем новый порт в UFW ДО перезапуска SSH (страховка)
    ufw allow "${SSH_PORT}/tcp" comment "SSH" 2>/dev/null || true

    # Перезапуск SSH
    systemctl restart sshd 2>/dev/null || systemctl restart ssh

    ok "SSH hardened: порт ${SSH_PORT}, key-only, root отключён"
    echo ""
    warn "══════════════════════════════════════════════════════════════"
    warn "  ВАЖНО! Проверь доступ в НОВОМ терминале прямо сейчас:"
    warn "  ssh ${ADMIN_USER}@${SERVER_IP} -p ${SSH_PORT}"
    warn "  Если не работает — текущая сессия ещё открыта, чиним."
    warn "══════════════════════════════════════════════════════════════"
    echo ""
    read -rp "  Подключился в новом терминале? [Y/n]: " _check
    if [[ "${_check,,}" == "n" ]]; then
        warn "Откатываю SSH на порт 22 с root-доступом..."
        cp "$SSH_BACKUP" /etc/ssh/sshd_config 2>/dev/null
        systemctl restart sshd 2>/dev/null || systemctl restart ssh
        die "SSH откачен. Разберись с ключами и запусти скрипт заново."
    fi
    ok "SSH доступ подтверждён"
}

# =============================================================================
# ФАЗА 6: fail2ban
# =============================================================================
phase6_fail2ban() {
    title "Фаза 6 / fail2ban"

    cat > /etc/fail2ban/jail.local << F2BEOF
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 3
backend  = systemd

[sshd]
enabled  = true
port     = ${SSH_PORT}
filter   = sshd
logpath  = /var/log/auth.log
maxretry = 3
bantime  = 3600

[nginx-botsearch]
enabled  = true
port     = http,https
filter   = nginx-botsearch
logpath  = /var/log/nginx/error.log
maxretry = 5
bantime  = 86400

[nginx-limit-req]
enabled  = true
port     = http,https
filter   = nginx-limit-req
logpath  = /var/log/nginx/error.log
maxretry = 10
bantime  = 3600
F2BEOF

    systemctl enable --now fail2ban
    systemctl restart fail2ban
    ok "fail2ban: SSH (порт ${SSH_PORT}) + nginx"
}

# =============================================================================
# ФАЗА 7: Kernel Tuning (sysctl)
# =============================================================================
phase7_sysctl() {
    title "Фаза 7 / Kernel Tuning"

    cat > /etc/sysctl.d/99-remnanode.conf << 'SYSEOF'
# ═══ Remnawave Node — sysctl tuning ═══

# ── TCP/Network Performance ──
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.ipv4.tcp_rmem = 4096 1048576 16777216
net.ipv4.tcp_wmem = 4096 1048576 16777216
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_max_tw_buckets = 2000000
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.ip_local_port_range = 10000 65535

# ── TCP Fast Open ──
net.ipv4.tcp_fastopen = 3

# ── BBR Congestion Control ──
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# ── Conntrack (для большого числа соединений) ──
net.netfilter.nf_conntrack_max = 262144

# ── Защита от SYN flood ──
net.ipv4.tcp_syncookies = 1

# ── Защита от IP spoofing ──
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# ── Отключаем ICMP redirect (не нужно для VPN-ноды) ──
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# ── Отключаем source routing ──
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0

# ── File descriptors ──
fs.file-max = 1048576
fs.nr_open = 1048576
SYSEOF

    sysctl -p /etc/sysctl.d/99-remnanode.conf >/dev/null 2>&1
    ok "Kernel tuned: BBR, TCP buffers, conntrack, SYN flood protection"
}

# =============================================================================
# ФАЗА 8: SSL
# =============================================================================
phase8_ssl() {
    title "Фаза 8 / SSL-сертификаты"
    systemctl stop nginx 2>/dev/null || true
    fuser -k 80/tcp 2>/dev/null || true
    sleep 1

    for d in "$CONNECTION_DOMAIN" "$SNI_DOMAIN"; do
        if [[ -d "/etc/letsencrypt/live/${d}" ]]; then
            ok "SSL $d — уже есть"
            continue
        fi
        info "Получаю SSL для $d..."
        certbot certonly --standalone --non-interactive \
            --agree-tos --register-unsafely-without-email \
            -d "$d" \
            || die "Не удалось получить SSL для $d. Проверь DNS: nslookup $d"
        ok "SSL $d"
    done
}

# =============================================================================
# ФАЗА 9: nginx (stream SNI routing)
# =============================================================================
phase9_nginx() {
    title "Фаза 9 / nginx"
    echo "  Порт 443 → SNI routing:"
    echo "    ${CONNECTION_DOMAIN} → Xray (8443)"
    echo "    ${SNI_DOMAIN}        → HTTPS (7443) + Reality fallback (9443)"
    echo ""

    # ── stream SNI ────────────────────────────────────────────────────────────
    mkdir -p /etc/nginx/stream-enabled

    cat > /etc/nginx/stream-enabled/stream.conf << STRMEOF
map \$ssl_preread_server_name \$sni_name {
    ${CONNECTION_DOMAIN}    xray;
    ${SNI_DOMAIN}           reality;
    default                 xray;
}

upstream xray {
    server 127.0.0.1:8443;
}

upstream reality {
    server 127.0.0.1:9443;
}

server {
    listen 443;
    listen [::]:443;
    proxy_pass      \$sni_name;
    ssl_preread     on;
    proxy_protocol  on;
}
STRMEOF

    # ── Добавляем stream include в nginx.conf (если нет) ──────────────────────
    if ! grep -q "stream-enabled" /etc/nginx/nginx.conf; then
        echo "stream { include /etc/nginx/stream-enabled/*.conf; }" >> /etc/nginx/nginx.conf
    fi

    # ── HTTPS site (порт 7443) ────────────────────────────────────────────────
    cat > /etc/nginx/sites-available/node-https.conf << HTTPEOF
server {
    listen 7443 ssl proxy_protocol;
    server_name ${CONNECTION_DOMAIN} ${SNI_DOMAIN};

    ssl_certificate     /etc/letsencrypt/live/${CONNECTION_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${CONNECTION_DOMAIN}/privkey.pem;

    set_real_ip_from 127.0.0.1;
    real_ip_header proxy_protocol;

    location / {
        root /var/www/html;
        index index.html;
    }
}
HTTPEOF

    # ── Reality fallback (порт 9443) ──────────────────────────────────────────
    cat > /etc/nginx/sites-available/node-reality.conf << REALEOF
server {
    listen 9443 ssl proxy_protocol;
    server_name ${SNI_DOMAIN};

    ssl_certificate     /etc/letsencrypt/live/${SNI_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${SNI_DOMAIN}/privkey.pem;

    set_real_ip_from 127.0.0.1;
    real_ip_header proxy_protocol;

    location / {
        root /var/www/html;
        index index.html;
    }
}
REALEOF

    # ── HTTP → HTTPS redirect (порт 80) ──────────────────────────────────────
    cat > /etc/nginx/sites-available/redirect-80.conf << R80EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    location /.well-known/acme-challenge/ { root /var/www/html; }
    location / { return 301 https://\$host\$request_uri; }
}
R80EOF

    # Активируем конфиги
    rm -f /etc/nginx/sites-enabled/default
    ln -sf /etc/nginx/sites-available/node-https.conf /etc/nginx/sites-enabled/
    ln -sf /etc/nginx/sites-available/node-reality.conf /etc/nginx/sites-enabled/
    ln -sf /etc/nginx/sites-available/redirect-80.conf /etc/nginx/sites-enabled/

    # Убираем конфликтный load_module (Ubuntu 24.04 грузит через modules-enabled)
    sed -i '/load_module.*ngx_stream_module/d' /etc/nginx/nginx.conf

    nginx -t || die "nginx конфиг невалиден"
    systemctl enable --now nginx
    systemctl restart nginx
    ok "nginx: SNI routing на порту 443"
}

# =============================================================================
# ФАЗА 10: x25519 Keygen
# =============================================================================
phase10_keygen() {
    title "Фаза 10 / Генерация x25519 ключей"

    # Нужен Docker для генерации ключей через Xray
    local keys
    keys=$(docker run --rm ghcr.io/xtls/xray-core:latest xray x25519 2>/dev/null) \
        || die "Не удалось сгенерировать ключи"

    local PRIVATE_KEY PUBLIC_KEY
    PRIVATE_KEY=$(echo "$keys" | grep "Private" | awk '{print $NF}')
    PUBLIC_KEY=$(echo "$keys" | grep "Public" | awk '{print $NF}')

    [[ -n "$PRIVATE_KEY" && -n "$PUBLIC_KEY" ]] || die "Ключи пустые"

    echo ""
    echo -e "  ${G}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "  ${G}║${NC}  ${B}x25519 ключи сгенерированы${NC}"
    echo -e "  ${G}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "  ${G}║${NC}  Private: ${Y}${PRIVATE_KEY}${NC}"
    echo -e "  ${G}║${NC}  Public:  ${Y}${PUBLIC_KEY}${NC}"
    echo -e "  ${G}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "  ${G}║${NC}"
    echo -e "  ${G}║${NC}  Сейчас обнови Config Profile '${PROFILE_NAME}' в панели:"
    echo -e "  ${G}║${NC}  1. Панель → Config Profiles → ${PROFILE_NAME} → Edit"
    echo -e "  ${G}║${NC}  2. Замени privateKey на: ${Y}${PRIVATE_KEY}${NC}"
    echo -e "  ${G}║${NC}  3. Замени shortIds — оставь существующие или сгенерируй"
    echo -e "  ${G}║${NC}  4. serverNames → [\"${SNI_DOMAIN}\"]"
    echo -e "  ${G}║${NC}  5. Dest → ${SNI_DOMAIN}:9443"
    echo -e "  ${G}║${NC}  6. Сохрани"
    echo -e "  ${G}║${NC}"
    echo -e "  ${G}║${NC}  ${B}Host в панели:${NC}"
    echo -e "  ${G}║${NC}  Address: ${CONNECTION_DOMAIN}"
    echo -e "  ${G}║${NC}  Port: 443 (НЕ 8443!)"
    echo -e "  ${G}║${NC}  SNI: ${SNI_DOMAIN}"
    echo -e "  ${G}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Сохраняем ключи для docker-compose
    echo "$PRIVATE_KEY" > "${NODE_DIR}/.private_key"
    echo "$PUBLIC_KEY" > "${NODE_DIR}/.public_key"

    read -rp "  Обновил(а) профиль в панели? Нажми Enter для продолжения..."
    ok "Ключи сгенерированы и сохранены"
}

# =============================================================================
# ФАЗА 11: remnawave-node (docker compose)
# =============================================================================
phase11_node() {
    title "Фаза 11 / remnawave-node"

    mkdir -p "${NODE_DIR}/geodata"

    # Docker log rotation (глобально, до запуска контейнера)
    mkdir -p /etc/docker
    if [[ ! -f /etc/docker/daemon.json ]]; then
        cat > /etc/docker/daemon.json << 'DJEOF'
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    }
}
DJEOF
        systemctl restart docker
        sleep 2
        ok "Docker log rotation: ≤ 10MB × 3 файла"
    fi

    cat > "${NODE_DIR}/docker-compose.yml" << DCEOF
services:
  remnanode:
    container_name: remnanode
    hostname: remnanode
    image: remnawave/node:latest
    network_mode: host
    restart: always
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
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
DCEOF

    ok "docker-compose.yml создан"
}

# =============================================================================
# ФАЗА 12: Geo-файлы + cron
# =============================================================================
phase12_geo() {
    title "Фаза 12 / Geo-файлы"
    echo "  Источник: runetfreedom/russia-v2ray-rules-dat"
    echo "  geosite.dat (~62MB) + geoip.dat (~5MB)"
    echo ""

    local GEO_BASE="https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release"

    info "Скачиваю geosite.dat..."
    wget -q --timeout=120 --tries=3 -O "${NODE_DIR}/geodata/geosite.dat" \
        "${GEO_BASE}/geosite.dat" \
        || die "Не удалось скачать geosite.dat"
    ok "geosite.dat ($(du -h "${NODE_DIR}/geodata/geosite.dat" | cut -f1))"

    info "Скачиваю geoip.dat..."
    wget -q --timeout=120 --tries=3 -O "${NODE_DIR}/geodata/geoip.dat" \
        "${GEO_BASE}/geoip.dat" \
        || die "Не удалось скачать geoip.dat"
    ok "geoip.dat ($(du -h "${NODE_DIR}/geodata/geoip.dat" | cut -f1))"

    # Теперь запускаем контейнер (geo-файлы уже на месте)
    info "Запускаю remnawave-node..."
    cd "${NODE_DIR}"
    docker compose pull
    docker compose up -d
    sleep 5

    if docker ps | grep -q remnanode; then
        ok "remnanode запущен"
    else
        warn "Контейнер не запустился, логи:"
        docker logs remnanode --tail=10
        die "remnanode не стартовал"
    fi

    # ── Cron автообновление ───────────────────────────────────────────────────
    mkdir -p /var/log/remnanode

    cat > /usr/local/bin/update-geo-dat.sh << 'GEOEOF'
#!/bin/bash
set -euo pipefail
LOG="/var/log/remnanode/geo-update.log"
DIR="/opt/remnanode/geodata"
BASE="https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release"
TS=$(date "+%Y-%m-%d %H:%M:%S")

echo "[$TS] Начинаю обновление geo-файлов" >> "$LOG"

for f in geosite.dat geoip.dat; do
    wget -q --timeout=120 --tries=3 -O "${DIR}/${f}.tmp" "${BASE}/${f}" 2>>"$LOG"
    if [[ -s "${DIR}/${f}.tmp" ]]; then
        mv "${DIR}/${f}.tmp" "${DIR}/${f}"
        echo "[$TS] $f обновлён ($(du -h "${DIR}/${f}" | cut -f1))" >> "$LOG"
    else
        rm -f "${DIR}/${f}.tmp"
        echo "[$TS] ОШИБКА: $f пустой" >> "$LOG"
    fi
done

cd /opt/remnanode && docker compose restart >> "$LOG" 2>&1
echo "[$TS] Контейнер перезапущен" >> "$LOG"
GEOEOF

    chmod +x /usr/local/bin/update-geo-dat.sh

    # Cron: ежедневно в 03:00
    local CRON_LINE="0 3 * * * /usr/local/bin/update-geo-dat.sh"
    local CURRENT_CRON=""
    CURRENT_CRON=$(crontab -l 2>/dev/null || true)
    if ! echo "$CURRENT_CRON" | grep -qF "update-geo-dat"; then
        echo "${CURRENT_CRON:+$CURRENT_CRON
}${CRON_LINE}" | crontab -
    fi

    ok "Автообновление geo: cron 0 3 * * *"
}

# =============================================================================
# ФАЗА 13: Node Exporter
# =============================================================================
phase13_node_exporter() {
    title "Фаза 13 / Node Exporter"

    if [[ -f /usr/local/bin/node_exporter ]]; then
        ok "Node Exporter уже установлен"
        return
    fi

    local NE_URL="https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VER}/node_exporter-${NODE_EXPORTER_VER}.linux-amd64.tar.gz"

    wget -q --timeout=60 --tries=3 -O /tmp/ne.tar.gz "$NE_URL" \
        || die "Не удалось скачать Node Exporter"
    tar -xzf /tmp/ne.tar.gz -C /tmp
    mv "/tmp/node_exporter-${NODE_EXPORTER_VER}.linux-amd64/node_exporter" /usr/local/bin/
    rm -rf /tmp/ne.tar.gz "/tmp/node_exporter-${NODE_EXPORTER_VER}.linux-amd64"

    useradd -rs /bin/false node_exporter 2>/dev/null || true

    cat > /etc/systemd/system/node_exporter.service << 'NEEOF'
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
NEEOF

    systemctl daemon-reload
    systemctl enable --now node_exporter
    ok "Node Exporter v${NODE_EXPORTER_VER} на порту 9100"
}

# =============================================================================
# ФАЗА 14: Фейковый сайт
# =============================================================================
phase14_fakesite() {
    title "Фаза 14 / Фейковый сайт"

    local FAKESITE_URL="https://raw.githubusercontent.com/mozaroc/x-ui-pro/master/randomfakehtml.sh"

    if wget -q --timeout=30 --tries=2 -O /tmp/randomfakehtml.sh "$FAKESITE_URL"; then
        bash /tmp/randomfakehtml.sh
        rm -f /tmp/randomfakehtml.sh
        ok "Фейковый сайт установлен"
    else
        # Fallback — минимальный фейк
        mkdir -p /var/www/html
        cat > /var/www/html/index.html << 'FAKEEOF'
<!DOCTYPE html>
<html><head><title>Welcome</title></head>
<body><h1>It works!</h1><p>This server is running.</p></body>
</html>
FAKEEOF
        warn "randomfakehtml недоступен, установлена заглушка"
    fi
}

# =============================================================================
# ФАЗА 15: Certbot auto-renew + проверка
# =============================================================================
phase15_certbot_timer() {
    title "Фаза 15 / Certbot auto-renew"

    # Certbot ставит свой systemd timer, проверяем что он активен
    if systemctl is-enabled certbot.timer &>/dev/null; then
        ok "Certbot timer активен (автопродление SSL)"
    else
        systemctl enable --now certbot.timer 2>/dev/null || true
        ok "Certbot timer включён"
    fi

    # Хук для перезапуска nginx после обновления сертификатов
    mkdir -p /etc/letsencrypt/renewal-hooks/post
    cat > /etc/letsencrypt/renewal-hooks/post/restart-nginx.sh << 'CERTEOF'
#!/bin/bash
systemctl reload nginx
CERTEOF
    chmod +x /etc/letsencrypt/renewal-hooks/post/restart-nginx.sh
    ok "Post-renewal hook: nginx reload"
}

# =============================================================================
# ФАЗА 16: Unattended Upgrades
# =============================================================================
phase16_unattended() {
    title "Фаза 16 / Автообновления безопасности"

    cat > /etc/apt/apt.conf.d/20auto-upgrades << 'UUEOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
UUEOF

    cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'UU2EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
UU2EOF

    ok "Security-патчи ставятся автоматически (без reboot)"
}

# =============================================================================
# ФАЗА 17: Watchdog
# =============================================================================
phase17_watchdog() {
    title "Фаза 17 / Watchdog"

    cat > /usr/local/bin/watchdog-remnanode.sh << 'WDEOF'
#!/bin/bash
# Проверяет что remnanode жив. Если нет — перезапускает.
# Запускается через cron каждые 5 минут.

LOG="/var/log/remnanode/watchdog.log"
TS=$(date "+%Y-%m-%d %H:%M:%S")

if ! docker ps --format '{{.Names}}' | grep -q '^remnanode$'; then
    echo "[$TS] ALERT: remnanode не запущен, перезапускаю..." >> "$LOG"
    cd /opt/remnanode && docker compose up -d >> "$LOG" 2>&1
    echo "[$TS] Перезапуск завершён" >> "$LOG"
fi

# Проверяем nginx
if ! systemctl is-active --quiet nginx; then
    echo "[$TS] ALERT: nginx упал, перезапускаю..." >> "$LOG"
    systemctl restart nginx >> "$LOG" 2>&1
fi
WDEOF

    chmod +x /usr/local/bin/watchdog-remnanode.sh

    local CRON_WD="*/5 * * * * /usr/local/bin/watchdog-remnanode.sh"
    local CURRENT_CRON=""
    CURRENT_CRON=$(crontab -l 2>/dev/null || true)
    if ! echo "$CURRENT_CRON" | grep -qF "watchdog-remnanode"; then
        echo "${CURRENT_CRON:+$CURRENT_CRON
}${CRON_WD}" | crontab -
    fi

    ok "Watchdog: проверка remnanode + nginx каждые 5 мин"
}

# =============================================================================
# ФАЗА 18: Автоочистка
# =============================================================================
phase18_cleanup() {
    title "Фаза 18 / Автоочистка"

    # Docker prune раз в неделю (воскресенье 04:00)
    local CRON_PRUNE="0 4 * * 0 docker system prune -f >> /var/log/remnanode/docker-prune.log 2>&1"
    local CURRENT_CRON=""
    CURRENT_CRON=$(crontab -l 2>/dev/null || true)
    if ! echo "$CURRENT_CRON" | grep -qF "docker system prune"; then
        echo "${CURRENT_CRON:+$CURRENT_CRON
}${CRON_PRUNE}" | crontab -
    fi

    # Logrotate для наших логов
    cat > /etc/logrotate.d/remnanode << 'LREOF'
/var/log/remnanode/*.log {
    weekly
    rotate 4
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root root
}
LREOF

    ok "Docker prune: воскресенье 04:00 | Логи: ротация 4 недели"
}

# =============================================================================
# ФАЗА 19: UFW
# =============================================================================
phase19_ufw() {
    title "Фаза 19 / UFW Firewall"

    ufw --force reset >/dev/null
    ufw default deny incoming
    ufw default allow outgoing

    ufw allow "${SSH_PORT}/tcp" comment "SSH"
    ufw allow 80/tcp comment "HTTP (certbot + redirect)"
    ufw allow 443/tcp comment "HTTPS / Xray"
    ufw allow "${NODE_PORT}/tcp" comment "Remnawave node"
    ufw allow from "${MASTER_IP}" to any port 9100 proto tcp comment "Node Exporter (master only)"

    ufw --force enable
    ok "UFW: SSH=${SSH_PORT}, HTTP=80, HTTPS=443, Node=${NODE_PORT}, Exporter=9100 (master)"
}

# =============================================================================
# ФАЗА 20: Итог
# =============================================================================
phase20_summary() {
    title "Готово!"
    echo ""
    echo -e "  ${G}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "  ${G}║${NC}  ${B}remnawave-node v2.0 — деплой завершён${NC}"
    echo -e "  ${G}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "  ${G}║${NC}  Сервер:       ${SERVER_IP}"
    echo -e "  ${G}║${NC}  Connection:   ${CONNECTION_DOMAIN}"
    echo -e "  ${G}║${NC}  SNI:          ${SNI_DOMAIN}"
    echo -e "  ${G}║${NC}  Profile:      ${PROFILE_NAME}"
    echo -e "  ${G}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "  ${G}║${NC}  ${B}SSH доступ:${NC}"
    echo -e "  ${G}║${NC}  ssh ${ADMIN_USER}@${SERVER_IP} -p ${SSH_PORT}"
    echo -e "  ${G}║${NC}  Пользователь: ${ADMIN_USER} (sudo, docker)"
    echo -e "  ${G}║${NC}  Root-логин: ОТКЛЮЧЁН"
    echo -e "  ${G}║${NC}  Пароли: ОТКЛЮЧЕНЫ (только SSH-ключ)"
    echo -e "  ${G}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "  ${G}║${NC}  ${B}Безопасность:${NC}"
    echo -e "  ${G}║${NC}  fail2ban: SSH + nginx"
    echo -e "  ${G}║${NC}  UFW: deny all, allow SSH/${SSH_PORT}, 80, 443, ${NODE_PORT}"
    echo -e "  ${G}║${NC}  sysctl: BBR, SYN flood protection, TCP tuning"
    echo -e "  ${G}║${NC}  Автопатчи: unattended-upgrades (security)"
    echo -e "  ${G}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "  ${G}║${NC}  ${B}Автоматизация:${NC}"
    echo -e "  ${G}║${NC}  Geo-update:    ежедневно 03:00"
    echo -e "  ${G}║${NC}  Watchdog:      каждые 5 мин (remnanode + nginx)"
    echo -e "  ${G}║${NC}  Docker prune:  воскресенье 04:00"
    echo -e "  ${G}║${NC}  Log rotation:  4 недели"
    echo -e "  ${G}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "  ${G}║${NC}  ${B}Действия в панели Remnawave:${NC}"
    echo -e "  ${G}║${NC}  1. Nodes → нода = ${G}Online${NC}"
    echo -e "  ${G}║${NC}  2. Включи «Host visibility»"
    echo -e "  ${G}║${NC}  3. Проверь профиль ${PROFILE_NAME}"
    echo -e "  ${G}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "  ${G}║${NC}  ${B}Полезные команды:${NC}"
    echo -e "  ${G}║${NC}  docker compose -C ${NODE_DIR} logs -f"
    echo -e "  ${G}║${NC}  docker compose -C ${NODE_DIR} restart"
    echo -e "  ${G}║${NC}  /usr/local/bin/update-geo-dat.sh"
    echo -e "  ${G}║${NC}  /usr/local/bin/watchdog-remnanode.sh"
    echo -e "  ${G}║${NC}  sudo fail2ban-client status sshd"
    echo -e "  ${G}║${NC}  sudo ufw status"
    echo -e "  ${G}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    clear
    echo -e "${C}"
    echo "  ┌──────────────────────────────────────────────────────┐"
    echo "  │      remnawave-node  •  deploy script  v2.0         │"
    echo "  │      github.com/anfixit/routerus                    │"
    echo "  │                                                      │"
    echo "  │      Hardened: admin user, SSH key-only,            │"
    echo "  │      fail2ban, BBR, watchdog, auto-updates          │"
    echo "  └──────────────────────────────────────────────────────┘"
    echo -e "${NC}"

    phase0_checks
    phase1_input
    phase2_deps
    phase3_docker
    phase4_admin_user
    phase5_ssh_hardening
    phase6_fail2ban
    phase7_sysctl
    phase8_ssl
    phase9_nginx
    phase10_keygen
    phase11_node
    phase12_geo
    phase13_node_exporter
    phase14_fakesite
    phase15_certbot_timer
    phase16_unattended
    phase17_watchdog
    phase18_cleanup
    phase19_ufw
    phase20_summary
}

main "$@"
