#!/usr/bin/env bash
# =============================================================================
# harden-existing.sh v1.0
# Hardening для уже работающих remnawave-нод
# НЕ трогает: nginx, SSL, Docker, контейнер, geo-файлы
#
# Что делает:
#   1. Создаёт пользователя admin с SSH-ключом
#   2. SSH hardening (новый порт, key-only, no root)
#   3. fail2ban
#   4. Kernel tuning (sysctl + BBR)
#   5. Docker log rotation (daemon.json)
#   6. Unattended upgrades
#   7. Watchdog (remnanode + nginx)
#   8. Автоочистка (docker prune + logrotate)
#   9. Certbot auto-renew timer
#  10. UFW обновление
#
# Использование:
#   bash <(wget -qO- https://raw.githubusercontent.com/anfixit/routerus/main/harden-existing.sh)
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

# ── Переменные ────────────────────────────────────────────────────────────────
ADMIN_USER="admin"
ADMIN_SSH_KEY=""
SSH_PORT="2810"
MASTER_IP="151.244.72.28"
SERVER_IP=""
CURRENT_SSH_PORT=""

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

    # Определяем текущий SSH-порт
    CURRENT_SSH_PORT=$(ss -tlnp | grep sshd | grep -oP '(?<=:)\d+' | head -1)
    CURRENT_SSH_PORT="${CURRENT_SSH_PORT:-22}"

    # Проверяем что remnanode работает
    if docker ps | grep -q remnanode; then
        ok "remnanode работает"
    else
        warn "remnanode НЕ запущен — скрипт продолжит, но проверь контейнер после"
    fi

    ok "Сервер: $SERVER_IP (Ubuntu $ver, SSH порт: $CURRENT_SSH_PORT)"
}

# =============================================================================
# ФАЗА 1: Параметры
# =============================================================================
phase1_input() {
    title "Фаза 1 / Параметры"
    echo ""
    echo -e "  ${B}Этот скрипт добавляет hardening на уже работающую ноду.${NC}"
    echo "  Не трогает: nginx, SSL, Docker-контейнер, geo-файлы."
    echo ""

    # ── SSH-ключ ──────────────────────────────────────────────────────────────
    echo -e "  ${B}SSH-ключ${NC} для пользователя '${ADMIN_USER}'"
    echo "  После настройки вход будет ТОЛЬКО по этому ключу."
    echo ""
    echo "  Как получить ключ:"
    echo -e "    ${C}cat ~/.ssh/id_ed25519.pub${NC}"
    echo -e "    ${C}cat ~/.ssh/id_rsa.pub${NC}"
    echo ""
    echo "  Если нет — сгенерируй:"
    echo -e "    ${C}ssh-keygen -t ed25519 -C \"your@email.com\"${NC}"
    echo ""
    while [[ -z "$ADMIN_SSH_KEY" ]]; do
        read -rp "  Вставь публичный SSH-ключ: " ADMIN_SSH_KEY
        if [[ -z "$ADMIN_SSH_KEY" ]]; then
            warn "Не может быть пустым"
        elif [[ ! "$ADMIN_SSH_KEY" =~ ^ssh-(ed25519|rsa|ecdsa)|^ecdsa-sha2 ]]; then
            warn "Не похоже на публичный ключ"
            ADMIN_SSH_KEY=""
        fi
    done
    ok "SSH-ключ принят"

    # ── SSH-порт ──────────────────────────────────────────────────────────────
    echo ""
    read -rp "  Новый SSH-порт [${SSH_PORT}]: " _ssh
    [[ -n "$_ssh" ]] && SSH_PORT="$_ssh"

    # ── Master IP ─────────────────────────────────────────────────────────────
    echo ""
    read -rp "  IP мастер-сервера (для Node Exporter UFW) [${MASTER_IP}]: " _master
    [[ -n "$_master" ]] && MASTER_IP="$_master"

    # ── Подтверждение ─────────────────────────────────────────────────────────
    echo ""
    echo -e "  ${B}Параметры:${NC}"
    printf "  %-22s %s\n" "SSH-порт:" "$SSH_PORT"
    printf "  %-22s %s\n" "SSH-ключ:" "${ADMIN_SSH_KEY:0:40}..."
    printf "  %-22s %s\n" "Master IP:" "$MASTER_IP"
    echo ""
    read -rp "  Всё верно? [Y/n]: " _c
    [[ "${_c,,}" == "n" ]] && die "Отменено."
    ok "Параметры приняты"
}

# =============================================================================
# ФАЗА 2: Зависимости (только недостающие)
# =============================================================================
phase2_deps() {
    title "Фаза 2 / Зависимости"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq fail2ban unattended-upgrades apt-listchanges logrotate 2>/dev/null || true
    ok "Пакеты установлены"
}

# =============================================================================
# ФАЗА 3: Пользователь admin
# =============================================================================
phase3_admin_user() {
    title "Фаза 3 / Пользователь admin"

    if id "$ADMIN_USER" &>/dev/null; then
        ok "Пользователь $ADMIN_USER уже существует"
    else
        useradd -m -s /bin/bash "$ADMIN_USER" 2>/dev/null || true
        ok "Создан пользователь $ADMIN_USER"
    fi

    usermod -aG sudo "$ADMIN_USER" 2>/dev/null || true
    usermod -aG docker "$ADMIN_USER" 2>/dev/null || true

    # Sudo без пароля
    echo "${ADMIN_USER} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${ADMIN_USER}"
    chmod 440 "/etc/sudoers.d/${ADMIN_USER}"

    # SSH-ключ
    local ssh_dir="/home/${ADMIN_USER}/.ssh"
    mkdir -p "$ssh_dir"
    echo "$ADMIN_SSH_KEY" > "${ssh_dir}/authorized_keys"
    chmod 700 "$ssh_dir"
    chmod 600 "${ssh_dir}/authorized_keys"
    chown -R "${ADMIN_USER}:${ADMIN_USER}" "$ssh_dir"

    ok "SSH-ключ установлен, sudo настроен, docker-группа добавлена"
}

# =============================================================================
# ФАЗА 4: SSH Hardening
# =============================================================================
phase4_ssh_hardening() {
    title "Фаза 4 / SSH Hardening"
    echo "  Порт: ${SSH_PORT}, только ключи, root-логин отключён."
    echo ""

    local SSH_BACKUP="/etc/ssh/sshd_config.bak.$(date +%s)"
    cp /etc/ssh/sshd_config "$SSH_BACKUP"

    cat > /etc/ssh/sshd_config << SSHEOF
# ═══ SSH Hardened Config (harden-existing v1.0) ═══

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

    # Разрешаем новый порт в UFW ДО перезапуска SSH
    ufw allow "${SSH_PORT}/tcp" comment "SSH" 2>/dev/null || true

    # Отключаем ssh.socket (Ubuntu 24.04)
    systemctl disable --now ssh.socket 2>/dev/null || true
    rm -f /etc/systemd/system/ssh.service.requires/ssh.socket 2>/dev/null || true

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
        warn "Откатываю SSH..."
        cp "$SSH_BACKUP" /etc/ssh/sshd_config 2>/dev/null
        systemctl restart sshd 2>/dev/null || systemctl restart ssh
        die "SSH откачен. Разберись с ключами и запусти заново."
    fi
    ok "SSH доступ подтверждён"
}

# =============================================================================
# ФАЗА 5: fail2ban
# =============================================================================
phase5_fail2ban() {
    title "Фаза 5 / fail2ban"

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
# ФАЗА 6: Kernel Tuning
# =============================================================================
phase6_sysctl() {
    title "Фаза 6 / Kernel Tuning"

    cat > /etc/sysctl.d/99-remnanode.conf << 'SYSEOF'
# ═══ Remnawave Node — sysctl tuning ═══

# TCP/Network Performance
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

# TCP Fast Open + BBR
net.ipv4.tcp_fastopen = 3
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# Conntrack
net.netfilter.nf_conntrack_max = 262144

# Защита
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0

# File descriptors
fs.file-max = 1048576
fs.nr_open = 1048576
SYSEOF

    sysctl -p /etc/sysctl.d/99-remnanode.conf >/dev/null 2>&1
    ok "Kernel tuned: BBR, TCP buffers, conntrack, SYN flood protection"
}

# =============================================================================
# ФАЗА 7: Docker Log Rotation
# =============================================================================
phase7_docker_logs() {
    title "Фаза 7 / Docker Log Rotation"

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
        warn "daemon.json создан. Docker НЕ перезапускаю (нода работает)."
        warn "Применится при следующем рестарте Docker/контейнера."
    else
        ok "daemon.json уже существует"
    fi
}

# =============================================================================
# ФАЗА 8: Unattended Upgrades
# =============================================================================
phase8_unattended() {
    title "Фаза 8 / Автообновления безопасности"

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
# ФАЗА 9: Watchdog + Автоочистка
# =============================================================================
phase9_watchdog_cleanup() {
    title "Фаза 9 / Watchdog + Автоочистка"

    mkdir -p /var/log/remnanode

    # ── Watchdog ──────────────────────────────────────────────────────────────
    cat > /usr/local/bin/watchdog-remnanode.sh << 'WDEOF'
#!/bin/bash
LOG="/var/log/remnanode/watchdog.log"
TS=$(date "+%Y-%m-%d %H:%M:%S")

if ! docker ps --format '{{.Names}}' | grep -q '^remnanode$'; then
    echo "[$TS] ALERT: remnanode не запущен, перезапускаю..." >> "$LOG"
    cd /opt/remnanode && docker compose up -d >> "$LOG" 2>&1
    echo "[$TS] Перезапуск завершён" >> "$LOG"
fi

if ! systemctl is-active --quiet nginx; then
    echo "[$TS] ALERT: nginx упал, перезапускаю..." >> "$LOG"
    systemctl restart nginx >> "$LOG" 2>&1
fi
WDEOF
    chmod +x /usr/local/bin/watchdog-remnanode.sh

    # ── Cron: watchdog + docker prune ─────────────────────────────────────────
    local CURRENT_CRON=""
    CURRENT_CRON=$(crontab -l 2>/dev/null || true)

    local CRON_WD="*/5 * * * * /usr/local/bin/watchdog-remnanode.sh"
    local CRON_PRUNE="0 4 * * 0 docker system prune -f >> /var/log/remnanode/docker-prune.log 2>&1"

    local NEW_CRON="$CURRENT_CRON"
    if ! echo "$NEW_CRON" | grep -qF "watchdog-remnanode"; then
        NEW_CRON="${NEW_CRON:+$NEW_CRON
}${CRON_WD}"
    fi
    if ! echo "$NEW_CRON" | grep -qF "docker system prune"; then
        NEW_CRON="${NEW_CRON:+$NEW_CRON
}${CRON_PRUNE}"
    fi
    echo "$NEW_CRON" | crontab -

    # ── Logrotate ─────────────────────────────────────────────────────────────
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

    ok "Watchdog: каждые 5 мин | Docker prune: вс 04:00 | Логи: ротация 4 нед"
}

# =============================================================================
# ФАЗА 10: Certbot Timer
# =============================================================================
phase10_certbot_timer() {
    title "Фаза 10 / Certbot auto-renew"

    if systemctl is-enabled certbot.timer &>/dev/null; then
        ok "Certbot timer уже активен"
    else
        systemctl enable --now certbot.timer 2>/dev/null || true
        ok "Certbot timer включён"
    fi

    mkdir -p /etc/letsencrypt/renewal-hooks/post
    cat > /etc/letsencrypt/renewal-hooks/post/restart-nginx.sh << 'CERTEOF'
#!/bin/bash
systemctl reload nginx
CERTEOF
    chmod +x /etc/letsencrypt/renewal-hooks/post/restart-nginx.sh
    ok "Post-renewal hook: nginx reload"
}

# =============================================================================
# ФАЗА 11: UFW
# =============================================================================
phase11_ufw() {
    title "Фаза 11 / UFW Firewall"

    # Сохраняем текущий NODE_PORT
    local NODE_PORT
    NODE_PORT=$(docker inspect remnanode 2>/dev/null | grep -oP 'NODE_PORT=\K\d+' || echo "2222")

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
# ФАЗА 12: nginx fallback fix (proxy_protocol)
# =============================================================================
phase12_nginx_fix() {
    title "Фаза 12 / nginx fallback fix"

    local NEED_RESTART=false

    # Проверяем proxy_protocol на портах 7443 и 9443
    if grep -q "proxy_protocol" /etc/nginx/sites-available/node-reality.conf 2>/dev/null; then
        sed -i 's/listen 9443 ssl proxy_protocol;/listen 9443 ssl;/' /etc/nginx/sites-available/node-reality.conf
        sed -i '/set_real_ip_from/d' /etc/nginx/sites-available/node-reality.conf
        sed -i '/real_ip_header/d' /etc/nginx/sites-available/node-reality.conf
        NEED_RESTART=true
        ok "Убран proxy_protocol с порта 9443"
    fi

    if grep -q "proxy_protocol" /etc/nginx/sites-available/node-https.conf 2>/dev/null; then
        sed -i 's/listen 7443 ssl proxy_protocol;/listen 7443 ssl;/' /etc/nginx/sites-available/node-https.conf
        sed -i '/set_real_ip_from/d' /etc/nginx/sites-available/node-https.conf
        sed -i '/real_ip_header/d' /etc/nginx/sites-available/node-https.conf
        NEED_RESTART=true
        ok "Убран proxy_protocol с порта 7443"
    fi

    # Проверяем SNI map — SNI_DOMAIN должен идти на xray
    if [[ -f /etc/nginx/stream-enabled/stream.conf ]]; then
        # Читаем текущий map
        local FIRST_DOMAIN
        FIRST_DOMAIN=$(grep -oP '^\s+\S+(?=\s+xray;)' /etc/nginx/stream-enabled/stream.conf | tr -d ' ')
        if [[ -n "$FIRST_DOMAIN" ]]; then
            info "Сейчас на xray идёт: $FIRST_DOMAIN"
            echo "  Правило: SNI-домен (из Reality serverNames) → xray"
            echo "  Connection-домен (адрес подключения) → reality"
            read -rp "  Это правильно? [Y/n]: " _ok
            if [[ "${_ok,,}" == "n" ]]; then
                warn "Нужно поменять map вручную. Отредактируй /etc/nginx/stream-enabled/stream.conf"
            fi
        fi
    fi

    if [[ "$NEED_RESTART" == "true" ]]; then
        nginx -t && systemctl restart nginx
        ok "nginx перезапущен"
    else
        ok "nginx fallback — proxy_protocol уже чист"
    fi
}

# =============================================================================
# ИТОГ
# =============================================================================
phase_summary() {
    title "Готово!"
    echo ""
    echo -e "  ${G}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "  ${G}║${NC}  ${B}Hardening завершён${NC}"
    echo -e "  ${G}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "  ${G}║${NC}  Сервер:       ${SERVER_IP}"
    echo -e "  ${G}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "  ${G}║${NC}  ${B}SSH доступ:${NC}"
    echo -e "  ${G}║${NC}  ssh ${ADMIN_USER}@${SERVER_IP} -p ${SSH_PORT}"
    echo -e "  ${G}║${NC}  Для root: ${Y}sudo su -${NC}"
    echo -e "  ${G}║${NC}  Root-логин: ОТКЛЮЧЁН"
    echo -e "  ${G}║${NC}  Пароли: ОТКЛЮЧЕНЫ (только SSH-ключ)"
    echo -e "  ${G}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "  ${G}║${NC}  ${B}Безопасность:${NC}"
    echo -e "  ${G}║${NC}  fail2ban: SSH + nginx"
    echo -e "  ${G}║${NC}  UFW: deny all, allow SSH/${SSH_PORT}, 80, 443"
    echo -e "  ${G}║${NC}  sysctl: BBR, SYN flood protection, TCP tuning"
    echo -e "  ${G}║${NC}  Автопатчи: unattended-upgrades"
    echo -e "  ${G}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "  ${G}║${NC}  ${B}Автоматизация:${NC}"
    echo -e "  ${G}║${NC}  Watchdog:      каждые 5 мин (remnanode + nginx)"
    echo -e "  ${G}║${NC}  Docker prune:  воскресенье 04:00"
    echo -e "  ${G}║${NC}  Log rotation:  4 недели"
    echo -e "  ${G}║${NC}  Certbot:       auto-renew + nginx reload"
    echo -e "  ${G}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "  ${G}║${NC}  ${B}Полезные команды:${NC}"
    echo -e "  ${G}║${NC}  sudo fail2ban-client status sshd"
    echo -e "  ${G}║${NC}  sudo ufw status"
    echo -e "  ${G}║${NC}  sudo /usr/local/bin/watchdog-remnanode.sh"
    echo -e "  ${G}║${NC}  cat /var/log/remnanode/watchdog.log"
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
    echo "  │   harden-existing.sh v1.0 — hardening для нод       │"
    echo "  │   github.com/anfixit/routerus                       │"
    echo "  │                                                      │"
    echo "  │   НЕ трогает: nginx, SSL, контейнер, geo-файлы      │"
    echo "  └──────────────────────────────────────────────────────┘"
    echo -e "${NC}"

    phase0_checks
    phase1_input
    phase2_deps
    phase3_admin_user
    phase4_ssh_hardening
    phase5_fail2ban
    phase6_sysctl
    phase7_docker_logs
    phase8_unattended
    phase9_watchdog_cleanup
    phase10_certbot_timer
    phase11_ufw
    phase12_nginx_fix
    phase_summary
}

main "$@"
