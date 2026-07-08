#!/usr/bin/env bash
# =============================================================================
# deploy-remnanode.sh v3.9
# VLESS + Reality + (TCP/Vision | XHTTP | BOTH) + steal_oneself
#
# Разворачивает remnawave-node на чистом Ubuntu 24.04.
# Один домен на ноду. Xray на 443 напрямую. nginx — fallback + ACME.
#
# Запуск:
#   wget -O deploy.sh https://raw.githubusercontent.com/anfixit/routerus/main/deploy-remnanode.sh
#   bash deploy.sh
#
# Changelog v3.9 (UX + аудит, все замечания включая минорные):
#   - NEW: выбор транспорта цифрой 1/2/3 (tcp/xhttp/both), слова тоже приняты.
#   - NEW: примеры получения SSH-ключа для macOS/Linux и Windows
#     (PowerShell + cmd.exe), а не только для мака.
#   - SEC: Docker ставится из официального apt-репозитория с проверкой
#     GPG-подписи пакетов (было `curl … | sh` без верификации). Заодно
#     гарантирует docker compose v2 (плагин docker-compose-plugin).
#   - FIX: проверка, что :443 свободен, ДО деплоя (только на первичной
#     установке — на ре-запуске порт держит сама нода, это норма).
#   - FIX: парсинг x25519 берёт первую строку (head -1) — будущий формат
#     вывода Xray с лишними «private»-строками не сломает JSON.
#   - FIX: fallback-цепочка keygen пробует для каждого образа оба вызова
#     (`xray x25519` и `x25519`), а не хардкод `teddysun … xray x25519`.
#   - FIX: check_internet не маскирует недоступность GitHub ICMP-пингом —
#     результат curl/wget теперь авторитетен; ping лишь при отсутствии обоих.
#   - FIX: старт контейнера проверяется поллингом (до 30с), а не слепым sleep.
#   - CHG: 45876 (Beszel) добавлен в список занятых портов (коллизия xhttp).
#   - COSMETIC: выровнены рамки вывода JSON-профиля (левая граница).
# Changelog v3.8 (аудит безопасности + устойчивость деплоя):
#   - FIX(crit): приватный ключ Reality больше не попадает в лог — Config
#     Profile JSON пишется в /opt/remnanode/config-profile.json (600) и на
#     терминал, минуя tee. Раньше JSON с privateKey уходил в /var/log.
#   - FIX(crit): SSH-хардинг в 00-hardening.conf (был hardening.conf). sshd
#     берёт ПЕРВОЕ значение ключа, а 50-cloud-init.conf сортировался раньше и
#     оставлял PasswordAuthentication yes. Плюс явное гашение пароля в cloud-init.
#   - FIX(crit): nginx-fallback больше не публичен — listen 127.0.0.1 и порт
#     8443 убран из UFW (Reality ходит на него по loopback; прямой коннект без
#     proxy_protocol давал аномалию = фингерпринт).
#   - FIX: phase2 не виснет — NEEDRESTART_MODE=a + ожидание cloud-init +
#     DPkg::Lock::Timeout; -q вместо -qq (виден прогресс). +python3-systemd.
#   - FIX: продление сертификата пересоздаёт ноду (renewal-hook, --force-recreate):
#     live/ — симлинк, docker пинует старый inode, нода отдавала истёкший cert.
#   - FIX: обязательный geoip.dat проверяется в phase11 (die), geosite —
#     опционален и монтируется условно; больше нет битого контейнера при сбое GitHub.
#   - FIX: update-geo.sh — up -d --force-recreate вместо restart.
#   - FIX: Beszel — том не сносится (сохраняется fingerprint агента).
#   - NEW: REMNANODE_IMAGE — образ ноды пинуется env-переменной.
#   - CHG: bittorrent → BLOCK (было DIRECT): раздача с IP ноды = DMCA/абузы
#     провайдера. Sniffing уже включён, торрент-трафик отсекается на ноде.
# Changelog v3.7 (аудит + актуализация транспорта):
#   - FIX(crit): фейковый сайт получает chmod 644/755 — под umask 077 он
#     создавался 600 root и nginx-воркер (www-data) отдавал 403 вместо
#     лендинга, ломая steal_oneself ровно там, где он нужен.
#   - FIX: SSH — mask ssh.socket (не disable): apt upgrade больше не воскрешает
#     сокет на :22, из-за которого рвались коннекты. + sshd -t перед рестартом.
#   - FIX: SSL без даунтайма nginx — issuance и renewal через webroot,
#     nginx на :80 держит ACME постоянно (раньше certbot гасил nginx =
#     детектируемая дыра в steal_oneself на время продления).
#   - FIX: update-geo — валидация размера перед подменой live-файла и рестарт
#     ноды ТОЛЬКО при реальном изменении (битый .dat больше не роняет Xray,
#     недоступность GitHub не даёт ночной пустой рестарт).
#   - FIX: NODE_NAME санитизируется (JSON-инъекция), xhttp-порт проверяется на
#     коллизию с занятыми портами, IP при неудаче автодетекта спрашивается.
#   - FIX: SSH_PORT — единая readonly-константа вместо 6 литералов.
#   - FIX: apt upgrade только при первичной установке (защита живой ноды при
#     идемпотентном ре-запуске); парсинг ключей терпим к Xray 26.x (Password).
#   - NEW: XHTTP mode=packet-up + api-образный path — устойчивее к поведенческому
#     анализу мобильного ТСПУ (МТС/Мегафон) в РФ-2026.
# Changelog v3.6:
#   - транспорт both (tcp:443 + xhttp:<port>), UFW сам открывает xhttp-порт
# Changelog v3.5 (аудит безопасности):
#   - лог 600, приватный ключ не в лог, Beszel hub не захардкожен, getent,
#     fail2ban systemd, бэкапы конфигов, HTTPS-проверка сети
# =============================================================================

set -euo pipefail

# --- Константы (единый источник истины) --------------------------------------
readonly SCRIPT_VERSION="3.9"
readonly LOG_FILE="/var/log/deploy-remnanode.log"
readonly SSH_PORT=2810
readonly NODE_API_PORT=2222
readonly NGINX_FALLBACK_PORT=8443
readonly WEBROOT="/var/www/html"
readonly OPT_DIR="/opt/remnanode"
readonly GEO_DIR="${OPT_DIR}/geodata"
readonly STATE_MARKER="${OPT_DIR}/.deployed"   # флаг «уже разворачивали»
readonly GEO_MIN_SIZE=100000                   # <100КБ = битый/HTML-ошибка
readonly GEO_BASE_URL="https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release"

# Образ для генерации x25519. Пинуется env-переменной для воспроизводимости.
readonly XRAY_KEYGEN_IMAGE="${XRAY_KEYGEN_IMAGE:-ghcr.io/xtls/xray-core:latest}"

# Образ ноды. Пинуй тег для воспроизводимости: REMNANODE_IMAGE=remnawave/node:2.8.0
readonly REMNANODE_IMAGE="${REMNANODE_IMAGE:-remnawave/node:latest}"

# Email для Let's Encrypt (пустой → регистрация без email).
readonly CERTBOT_EMAIL="${CERTBOT_EMAIL:-}"

# XHTTP-транспорт. packet-up дробит upload на «api-запросы» — лучший режим
# против поведенческого DPI на мобильных сетях РФ (2026).
readonly XHTTP_MODE="packet-up"
readonly XHTTP_PATH="/api/v1/update"

# Значения по умолчанию, переопределяемые в phase1.
XHTTP_PORT=8444

# Порты, занятые самой нодой (для проверки коллизий xhttp).
# 45876 — Beszel agent (phase16, опционален, но резервируем заранее).
readonly RESERVED_PORTS=(443 80 "$SSH_PORT" "$NODE_API_PORT" "$NGINX_FALLBACK_PORT" 45876)

# --- Цвета и вывод ------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

ok()    { echo -e "${GREEN}  ✔ $1${NC}"; }
info()  { echo -e "${CYAN}  ℹ $1${NC}"; }
warn()  { echo -e "${YELLOW}  ⚠ $1${NC}"; }
die()   { echo -e "${RED}  ✖ $1${NC}"; exit 1; }
title() { echo -e "\n${BLUE}━━━ $1 ━━━${NC}"; }
ask()   { echo -ne "${YELLOW}  ▸ $1: ${NC}"; }

# Печать секрета только на терминал, минуя tee-лог.
secret() { echo -e "${GREEN}  $1${NC}" >/dev/tty; }

# --- Лог (не мир-читаемый: в него уходит весь stdout) ------------------------
umask 077
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

trap 'echo -e "${RED}  ✖ Ошибка на строке $LINENO (код $?)${NC}" >/dev/tty' ERR

# --- Утилиты -----------------------------------------------------------------
backup_file() {
    # Бэкап файла перед деструктивной перезаписью.
    if [[ -f "$1" ]]; then
        cp -a "$1" "$1.bak.$(date +%s)"
    fi
}

check_internet() {
    # GitHub нужен дальше в любом случае (geo, apt-репо Docker), потому проверяем
    # именно его достижимость по HTTPS, а не «интернет вообще».
    # Если HTTP-клиент есть — его результат авторитетен: недоступность GitHub
    # НЕ маскируется ICMP-пингом (раньше ping мог дать ложный «сеть есть»).
    if command -v curl >/dev/null 2>&1; then
        curl -fsS --max-time 6 https://api.github.com >/dev/null 2>&1
        return
    fi
    if command -v wget >/dev/null 2>&1; then
        wget -q --spider --timeout=6 https://api.github.com
        return
    fi
    # Ни curl, ни wget нет (минимальный образ) — HTTPS проверить нечем,
    # ICMP лишь подтверждает базовую связность до установки пакетов в phase2.
    ping -c1 -W3 1.1.1.1 >/dev/null 2>&1
}

get_server_ip() {
    # Только HTTPS: по plaintext MITM мог бы подсунуть чужой IP.
    local ip=''
    if command -v curl >/dev/null 2>&1; then
        ip=$(curl -s4 --max-time 6 https://ifconfig.me 2>/dev/null \
            || curl -s4 --max-time 6 https://icanhazip.com 2>/dev/null) || true
    fi
    if [[ -z "$ip" ]] && command -v wget >/dev/null 2>&1; then
        ip=$(wget -qO- --timeout=6 https://ifconfig.me 2>/dev/null) || true
    fi
    echo "$ip"
}

port_reserved() {
    # 0, если порт входит в список занятых нодой.
    local p="$1" r
    for r in "${RESERVED_PORTS[@]}"; do
        [[ "$p" == "$r" ]] && return 0
    done
    return 1
}

# Сгенерировать x25519 через заданный образ. Пробуем оба стиля вызова:
# `xray x25519` (образ без энтрипоинта xray) и `x25519` (энтрипоинт = xray).
xray_x25519() {
    local img="$1"
    docker run --rm "$img" xray x25519 2>/dev/null \
        || docker run --rm "$img" x25519 2>/dev/null
}

# Скачать один geo-файл с валидацией размера. Возвращает 0 при успехе.
# $1=имя_файла $2=url. Кладёт результат в $GEO_DIR/$1.
fetch_geo() {
    local url="$2" dst="${GEO_DIR}/$1"
    if wget -q --timeout=60 --tries=3 "$url" -O "${dst}.tmp" \
        && [[ -s "${dst}.tmp" ]] \
        && (( $(stat -c%s "${dst}.tmp") >= GEO_MIN_SIZE )); then
        mv "${dst}.tmp" "$dst"
        chmod 644 "$dst"          # контейнер читает bind-mount :ro
        return 0
    fi
    rm -f "${dst}.tmp"
    return 1
}

# =============================================================================
phase0_checks() {
    title "Фаза 0 / Проверки"
    if [[ $EUID -ne 0 ]]; then die "Запусти от root: sudo bash $0"; fi
    ok "root"
    # shellcheck disable=SC1091
    source /etc/os-release 2>/dev/null || die "Не читается /etc/os-release"
    if [[ "$ID" != "ubuntu" || "${VERSION_ID%%.*}" -lt 24 ]]; then
        die "Нужна Ubuntu 24.04+, у тебя $PRETTY_NAME"
    fi
    ok "Ubuntu $VERSION_ID"
    check_internet || die "Нет доступа к сети (проверил HTTPS к api.github.com)"
    ok "Сеть доступна"
    # На первичной установке 443 должен быть свободен: иначе Xray внутри
    # контейнера тихо упадёт на bind в phase12. На ре-запуске порт держит
    # сама нода — это норма, потому проверяем только при отсутствии маркера.
    if [[ ! -f "$STATE_MARKER" ]]; then
        if ss -lntH 2>/dev/null | awk '{print $4}' | grep -qE ':443$'; then
            die "Порт 443 уже занят другим процессом (ss -lntp | grep :443). Освободи его."
        fi
        ok "Порт 443 свободен"
    fi
    echo ""
    echo -e "${GREEN}  deploy-remnanode.sh v${SCRIPT_VERSION}${NC}"
    echo -e "${GREEN}  VLESS + Reality + steal_oneself${NC}"
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

    # getent есть на чистой системе (dig ставится позже, в phase2).
    RESOLVED_IP=$(getent ahostsv4 "$DOMAIN" 2>/dev/null \
        | awk '{print $1; exit}') || true
    SERVER_IP=$(get_server_ip)

    # Автодетект IP мог не сработать — тогда спрашиваем оператора, иначе
    # пустой IP уйдёт в инструкции для панели и сводку.
    if [[ -z "$SERVER_IP" ]]; then
        warn "Не удалось определить внешний IP автоматически."
        ask "Введи внешний IPv4 сервера вручную"
        read -r SERVER_IP </dev/tty
        [[ -z "$SERVER_IP" ]] && die "IP сервера обязателен"
    fi

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
    info "SSH-ключ для пользователя admin (ed25519, rsa, ecdsa)."
    info "Нужен ПУБЛИЧНЫЙ ключ (файл .pub). Как его получить:"
    info "  macOS / Linux:"
    info "    создать (если нет):  ssh-keygen -t ed25519 -C \"admin@node\""
    info "    показать .pub:        cat ~/.ssh/id_ed25519.pub"
    info "  Windows (PowerShell):"
    info "    создать (если нет):  ssh-keygen -t ed25519 -C \"admin@node\""
    info "    показать .pub:        Get-Content \$env:USERPROFILE\\.ssh\\id_ed25519.pub"
    info "  Windows (cmd.exe):"
    info "    показать .pub:        type %USERPROFILE%\\.ssh\\id_ed25519.pub"
    echo ""
    ask "Вставь публичный SSH-ключ"
    read -r SSH_PUB_KEY </dev/tty
    if [[ -z "$SSH_PUB_KEY" ]]; then die "SSH-ключ не может быть пустым"; fi
    case "$SSH_PUB_KEY" in
        ssh-*|ecdsa-*|sk-*) : ;;
        *) die "Неверный формат SSH-ключа" ;;
    esac
    ok "SSH-ключ принят"

    echo ""
    ask "Имя ноды (для тегов, например DE_natty_narwhal)"
    read -r NODE_NAME </dev/tty
    if [[ -z "$NODE_NAME" ]]; then
        NODE_NAME=$(echo "$DOMAIN" | tr '.-' '_')
    fi
    # Имя уходит в JSON как tag — только tag-безопасные символы, иначе
    # ручной ввод с кавычкой/переносом ломает Config Profile.
    if ! [[ "$NODE_NAME" =~ ^[A-Za-z0-9_-]+$ ]]; then
        die "Имя ноды: только латиница, цифры, _ и - (без пробелов и кавычек)"
    fi
    ok "Имя ноды: $NODE_NAME"

    echo ""
    info "Транспорт VLESS + Reality:"
    info "  1) tcp   — RAW + xtls-rprx-vision. Совместим со всеми клиентами"
    info "             (Happ, v2rayNG, podkop/Nikki на mihomo). Рекомендуется."
    info "  2) xhttp — маскировка под HTTP (mode=${XHTTP_MODE}). Устойчив к"
    info "             поведенческому DPI на мобильных сетях РФ."
    info "  3) both  — оба inbound на одной ноде: tcp:443 (для podkop) +"
    info "             xhttp:<port>. Подписка отдаёт обе ссылки."
    ask "Выбери транспорт (1/2/3) [1]"
    read -r _t </dev/tty
    _t="${_t:-1}"
    case "$_t" in
        1|tcp)   TRANSPORT="tcp"   ;;
        2|xhttp) TRANSPORT="xhttp" ;;
        3|both)  TRANSPORT="both"  ;;
        *) die "Выбор должен быть 1 (tcp), 2 (xhttp) или 3 (both)" ;;
    esac
    ok "Транспорт: $TRANSPORT"

    if [[ "$TRANSPORT" == "both" ]]; then
        echo ""
        info "tcp занимает 443, для xhttp нужен отдельный порт."
        info "Менее подозрительно выглядят 2053, 2083, 2096, 8444."
        ask "Порт для xhttp-inbound [8444]"
        read -r _p </dev/tty
        [[ -n "$_p" ]] && XHTTP_PORT="$_p"
        if ! [[ "$XHTTP_PORT" =~ ^[0-9]+$ ]] \
            || (( XHTTP_PORT < 1 || XHTTP_PORT > 65535 )); then
            die "Некорректный порт xhttp (диапазон 1-65535)"
        fi
        if port_reserved "$XHTTP_PORT"; then
            die "Порт $XHTTP_PORT занят нодой (443/80/${SSH_PORT}/${NODE_API_PORT}/${NGINX_FALLBACK_PORT})"
        fi
        ok "xhttp-порт: $XHTTP_PORT"
    fi

    echo ""
    info "Параметры:"
    info "  Домен:     $DOMAIN"
    info "  IP:        $SERVER_IP"
    info "  Нода:      $NODE_NAME"
    info "  Транспорт: $TRANSPORT"
    [[ "$TRANSPORT" == "both" ]] && info "  xhttp-порт: $XHTTP_PORT"
    info "  SSH-ключ:  ${SSH_PUB_KEY:0:40}..."
    echo ""
    ask "Всё верно? (y/n)"
    read -r CONFIRM </dev/tty
    if [[ "$CONFIRM" != "y" ]]; then die "Прервано. Запусти заново"; fi
}

phase2_deps() {
    title "Фаза 2 / Системные зависимости"
    export DEBIAN_FRONTEND=noninteractive
    # needrestart на 24.04 рисует whiptail-меню рестарта сервисов; под tee-редиректом
    # ему некуда выводиться → тихий висяк. Глушим на весь прогон.
    export NEEDRESTART_MODE=a
    export NEEDRESTART_SUSPEND=1
    # На свежей облачной VM cloud-init/unattended-upgrades ещё держит dpkg-lock;
    # без ожидания apt-get -q виснет молча. Ждём завершения инициализации.
    if command -v cloud-init >/dev/null 2>&1; then
        info "Жду завершения cloud-init (до 5 мин)..."
        timeout 300 cloud-init status --wait >/dev/null 2>&1 || true
    fi
    # Lock::Timeout — apt сам подождёт освобождения замка вместо мгновенной ошибки.
    # -q (а не -qq) оставляет видимый прогресс: долгий upgrade больше не выглядит
    # как зависание.
    local APT=(apt-get -o DPkg::Lock::Timeout=300 -q)
    "${APT[@]}" update
    # Полный upgrade — только на первичной установке. На живой ноде при
    # ре-запуске он мог утянуть ядро/докер и оборвать VPN посреди прогона.
    if [[ ! -f "$STATE_MARKER" ]]; then
        "${APT[@]}" upgrade -y
    else
        info "Повторный запуск — пропускаю apt upgrade (защита живой ноды)"
    fi
    # python3-systemd нужен fail2ban backend=systemd (иначе jail молча не работает).
    "${APT[@]}" install -y \
        curl wget git jq openssl cron dnsutils psmisc \
        nginx-full certbot fail2ban python3-systemd \
        unattended-upgrades apt-listchanges \
        ca-certificates gnupg lsb-release \
        || die "Не удалось установить пакеты (см. вывод выше)"
    ok "Пакеты установлены"

    if ! command -v docker &>/dev/null; then
        info "Устанавливаю Docker (официальный apt-репозиторий, GPG-подпись)..."
        # Официальный метод Docker: ключ + репозиторий + подписанные пакеты.
        # Заменяет `curl … | sh` без верификации. Даёт docker compose v2.
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
            -o /etc/apt/keyrings/docker.asc \
            || die "Не удалось скачать GPG-ключ Docker"
        chmod a+r /etc/apt/keyrings/docker.asc
        local deb_arch deb_codename
        deb_arch=$(dpkg --print-architecture)
        # shellcheck disable=SC1091
        deb_codename=$(. /etc/os-release && echo "$VERSION_CODENAME")
        echo "deb [arch=${deb_arch} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${deb_codename} stable" \
            > /etc/apt/sources.list.d/docker.list
        "${APT[@]}" update
        "${APT[@]}" install -y \
            docker-ce docker-ce-cli containerd.io \
            docker-buildx-plugin docker-compose-plugin \
            || die "Не удалось установить Docker из apt-репозитория"
        systemctl enable --now docker
        command -v docker &>/dev/null || die "Docker не установился"
        ok "Docker установлен (apt, подписанные пакеты)"
    else
        ok "Docker уже есть: $(docker --version | cut -d' ' -f3)"
    fi
    systemctl reset-failed docker 2>/dev/null || true

    # Гарантируем docker compose v2 (плагин). Старый docker-compose v1 не подходит:
    # весь скрипт использует синтаксис `docker compose …`.
    docker compose version >/dev/null 2>&1 \
        || die "Нужен docker compose v2 (плагин docker-compose-plugin). Установи его и повтори."

    # Docker log rotation (ДО запуска контейнеров!). Не затираем чужой конфиг.
    mkdir -p /etc/docker
    if [[ -f /etc/docker/daemon.json ]] \
        && ! grep -q '"log-driver"' /etc/docker/daemon.json; then
        warn "/etc/docker/daemon.json уже существует — делаю бэкап"
    fi
    backup_file /etc/docker/daemon.json
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
    chown -R admin:"$(id -gn admin)" /home/admin/.ssh
    ok "SSH-ключ установлен"
    echo "admin ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/admin
    chmod 440 /etc/sudoers.d/admin
    ok "sudo без пароля"

    cp /etc/ssh/sshd_config "/etc/ssh/sshd_config.bak.$(date +%s)"
    mkdir -p /etc/ssh/sshd_config.d /run/sshd
    # sshd берёт ПЕРВОЕ значение каждого ключа. Старое имя hardening.conf
    # сортировалось ПОСЛЕ 50-cloud-init.conf, чей PasswordAuthentication yes
    # побеждал → пароли оставались включены. 00- грузится первым по всем ключам.
    rm -f /etc/ssh/sshd_config.d/hardening.conf
    cat > /etc/ssh/sshd_config.d/00-hardening.conf << SSHEOF
Port ${SSH_PORT}
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
    # Подстраховка: явно гасим пароль и в дроп-ине cloud-init, если он есть.
    if [[ -f /etc/ssh/sshd_config.d/50-cloud-init.conf ]]; then
        sed -i 's/^[#[:space:]]*PasswordAuthentication.*/PasswordAuthentication no/' \
            /etc/ssh/sshd_config.d/50-cloud-init.conf
    fi

    # Валидируем ДО рестарта — иначе опечатка в конфиге запрёт доступ.
    if ! sshd -t; then
        die "sshd -t не прошёл — не рестартую SSH, доступ сохранён"
    fi

    # Ключевое от «SSH постоянно падает»: socket-активация игнорирует Port и
    # оживает после apt upgrade openssh-server. mask держит её выключенной
    # навсегда; порт 2810 обслуживает именно ssh.service.
    systemctl disable --now ssh.socket 2>/dev/null || true
    systemctl mask ssh.socket 2>/dev/null || true
    systemctl unmask ssh 2>/dev/null || true
    systemctl enable --now ssh 2>/dev/null || systemctl enable --now sshd
    systemctl restart ssh 2>/dev/null || systemctl restart sshd

    if ss -lntp 2>/dev/null | grep -qE ":${SSH_PORT}[[:space:]]"; then
        ok "SSH: слушает :${SSH_PORT}, key-only, root запрещён, socket masked"
    else
        warn "SSH не слушает :${SSH_PORT} — проверь из VNC до выхода!"
    fi
    warn "ВАЖНО: проверь из ДРУГОГО терминала: ssh -p ${SSH_PORT} admin@${SERVER_IP}"
}

phase4_fail2ban() {
    title "Фаза 4 / fail2ban"
    # backend=systemd — на Ubuntu 24.04 журнал journald, auth.log может
    # отсутствовать. Порт берётся из единой константы.
    cat > /etc/fail2ban/jail.local << F2BEOF
[sshd]
enabled  = true
port     = ${SSH_PORT}
filter   = sshd
backend  = systemd
maxretry = 3
bantime  = 3600
findtime = 600
F2BEOF
    systemctl enable fail2ban
    systemctl restart fail2ban
    ok "fail2ban: SSH на :${SSH_PORT}, бан после 3 попыток"
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
    title "Фаза 6 / nginx :80 (ACME) + SSL-сертификат"
    # nginx на :80 постоянно обслуживает ACME-challenge и редиректит остальное.
    # Так и первичная выдача, и продление идут через webroot — nginx НЕ гасится,
    # и steal_oneself-fallback не проваливается в connection refused при renewal.
    mkdir -p "$WEBROOT"
    rm -f /etc/nginx/sites-enabled/default
    cat > /etc/nginx/sites-available/redirect.conf << RDEOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    location /.well-known/acme-challenge/ { root ${WEBROOT}; }
    location / { return 301 https://\$host\$request_uri; }
}
RDEOF
    ln -sf /etc/nginx/sites-available/redirect.conf /etc/nginx/sites-enabled/
    nginx -t || die "nginx (redirect) конфиг невалиден"
    systemctl enable nginx
    systemctl restart nginx

    if [[ -d "/etc/letsencrypt/live/${DOMAIN}" ]]; then
        ok "SSL для $DOMAIN уже есть"
    else
        info "Получаю SSL для $DOMAIN (webroot, без остановки nginx)..."
        local email_arg=(--register-unsafely-without-email)
        [[ -n "$CERTBOT_EMAIL" ]] && email_arg=(--email "$CERTBOT_EMAIL")
        certbot certonly --webroot -w "$WEBROOT" --non-interactive --agree-tos \
            "${email_arg[@]}" -d "$DOMAIN" \
            || die "Не удалось получить SSL. Проверь: dig $DOMAIN A +short"
        ok "SSL $DOMAIN получен"
    fi

    # Renewal тоже через webroot + reload (без stop). Глобальный cli.ini
    # безопасен: authenticator webroot не гасит сервисы.
    backup_file /etc/letsencrypt/cli.ini
    # deploy-hook НЕ здесь: recreate ноды делает renewal-hook из фазы 12
    # (одного reload nginx мало — контейнер держит старый inode симлинка).
    cat > /etc/letsencrypt/cli.ini << CERTEOF
authenticator = webroot
webroot-path = ${WEBROOT}
CERTEOF
    systemctl enable certbot.timer 2>/dev/null || true
    ok "Автопродление SSL: webroot (recreate ноды — renewal-hook из фазы 12)"
}

phase7_nginx() {
    title "Фаза 7 / nginx fallback :${NGINX_FALLBACK_PORT}"
    info "Reality dest → 127.0.0.1:${NGINX_FALLBACK_PORT} (пробберы видят сайт)"
    # ПРИМЕЧАНИЕ: синтаксис 'listen ... http2' — для nginx 1.24 (Ubuntu 24.04).
    # Директиву 'http2 on;' вводить нельзя: она с nginx 1.25.1, на 24.04 сломает.
    cat > "/etc/nginx/sites-available/${DOMAIN}.conf" << NGXEOF
server {
    # Только loopback: fallback достижим лишь через Reality dest 127.0.0.1,
    # наружу не публикуется (см. phase15 — порт убран из UFW).
    listen 127.0.0.1:${NGINX_FALLBACK_PORT} ssl http2 proxy_protocol;
    server_name ${DOMAIN};
    set_real_ip_from 127.0.0.1;
    real_ip_header proxy_protocol;
    server_tokens off;
    ssl_certificate     /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    root ${WEBROOT};
    index index.html;
    location / {
        try_files \$uri \$uri/ =404;
    }
}
NGXEOF
    ln -sf "/etc/nginx/sites-available/${DOMAIN}.conf" \
        /etc/nginx/sites-enabled/
    rm -f /etc/nginx/stream-enabled/*.conf 2>/dev/null || true
    nginx -t || die "nginx конфиг невалиден"
    systemctl reload nginx
    ok "nginx: HTTPS fallback на :${NGINX_FALLBACK_PORT}"
}

phase8_fakesite() {
    title "Фаза 8 / Фейковый сайт"
    mkdir -p "$WEBROOT"

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
    # Детерминированный выбор от хэша домена: на ре-запуске сайт не меняется,
    # значит идемпотентность реальна и снятый ранее фингерпринт остаётся валиден.
    local H
    H=$(echo -n "$DOMAIN" | md5sum | tr -dc '0-9a-f')
    local IDX=$(( 16#${H:0:4} % ${#THEMES[@]} ))
    local CIDX=$(( 16#${H:4:4} % ${#COLORS[@]} ))
    IFS='|' read -r BIZ_NAME BIZ_DESC BIZ_SERVICES <<< "${THEMES[$IDX]}"
    IFS='|' read -r COLOR1 COLOR2 BG_COLOR <<< "${COLORS[$CIDX]}"

    local SITE_NAME
    SITE_NAME=$(echo "$DOMAIN" | sed 's/\.[^.]*$//' | sed 's/[-_]/ /g' \
        | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2))}1')
    local YEAR
    YEAR=$(date +%Y)

    cat > "${WEBROOT}/index.html" << SITEEOF
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

    IFS=',' read -ra SVCS <<< "$BIZ_SERVICES"
    for svc in "${SVCS[@]}"; do
        cat >> "${WEBROOT}/index.html" << CARDEOF
            <div class="card">
                <h3>${svc}</h3>
                <p>Professional ${svc,,} services tailored to your business needs and goals.</p>
            </div>
CARDEOF
    done

    cat >> "${WEBROOT}/index.html" << FOOTEOF
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

    # КРИТИЧНО: под umask 077 файлы создаются 600 root, и nginx-воркер
    # (www-data) отдаёт 403 вместо лендинга — steal_oneself ломается ровно
    # там, где нужен. Явно выставляем читаемые всем права.
    find "$WEBROOT" -type d -exec chmod 755 {} +
    find "$WEBROOT" -type f -exec chmod 644 {} +
    ok "Фейковый сайт: ${SITE_NAME} — ${BIZ_NAME} (chmod 644)"
}

# Печатает JSON одного inbound: $1=tag $2=port $3=network(tcp|xhttp).
build_inbound() {
    local tag="$1" port="$2" net="$3" net_block
    if [[ "$net" == "xhttp" ]]; then
        net_block="\"network\": \"xhttp\",
        \"xhttpSettings\": {
          \"mode\": \"${XHTTP_MODE}\",
          \"path\": \"${XHTTP_PATH}\",
          \"extra\": {
            \"noSSEHeader\": true,
            \"xPaddingBytes\": \"100-1000\",
            \"scMaxBufferedPosts\": 30,
            \"scMaxEachPostBytes\": 1000000,
            \"scStreamUpServerSecs\": \"20-80\"
          }
        },"
    else
        net_block='"network": "tcp",'
    fi
    cat << INBEOF
    {
      "tag": "${tag}",
      "port": ${port},
      "protocol": "vless",
      "settings": { "clients": [], "decryption": "none" },
      "sniffing": { "enabled": true, "destOverride": ["http","tls","quic"] },
      "streamSettings": {
        ${net_block}
        "security": "reality",
        "realitySettings": {
          "dest": "127.0.0.1:${NGINX_FALLBACK_PORT}",
          "show": false,
          "xver": 1,
          "shortIds": ["","${SID1}","${SID2}","${SID3}"],
          "privateKey": "${PRIVATE_KEY}",
          "serverNames": ["${DOMAIN}"]
        }
      }
    }
INBEOF
}

phase9_keygen() {
    title "Фаза 9 / x25519 ключи + Config Profile"
    mkdir -p "$OPT_DIR"
    info "Генерирую x25519 ключи (образ: ${XRAY_KEYGEN_IMAGE})..."
    # Пробуем заданный образ, затем ghcr, затем teddysun. Для каждого — оба
    # стиля вызова (см. xray_x25519). ghcr дублирует дефолт, но становится
    # реальным резервом, если XRAY_KEYGEN_IMAGE переопределён env-переменной.
    KEY_OUTPUT=$(xray_x25519 "$XRAY_KEYGEN_IMAGE") \
        || KEY_OUTPUT=$(xray_x25519 "ghcr.io/xtls/xray-core:latest") \
        || KEY_OUTPUT=$(xray_x25519 "teddysun/xray:latest") \
        || die "Не удалось сгенерировать x25519 ключи"
    # Xray 26.x сменил метки: private → 'Private key'/'PrivateKey',
    # public → 'Public key'/'Password'. Терпимый парсинг под оба формата.
    # head -1: если вывод вдруг содержит слово 'private' в нескольких строках
    # (будущий формат с Hash/Fingerprint) — берём только первую, чтобы не
    # получить многострочный ключ и не сломать JSON.
    PRIVATE_KEY=$(echo "$KEY_OUTPUT" | grep -iE 'private' | awk '{print $NF}' | head -1)
    PUBLIC_KEY=$(echo "$KEY_OUTPUT" | grep -iE 'public|password' | awk '{print $NF}' | head -1)
    if [[ -z "$PRIVATE_KEY" || -z "$PUBLIC_KEY" ]]; then
        die "Не удалось извлечь ключи из вывода xray (формат изменился?)"
    fi
    cat > "${OPT_DIR}/keys.txt" << KEYSEOF
# x25519 keys generated $(date +%Y-%m-%d)
PRIVATE_KEY=$PRIVATE_KEY
PUBLIC_KEY=$PUBLIC_KEY
KEYSEOF
    chmod 600 "${OPT_DIR}/keys.txt"
    ok "Ключи сгенерированы (${OPT_DIR}/keys.txt, chmod 600)"
    secret "Private Key: $PRIVATE_KEY"
    secret "Public Key:  $PUBLIC_KEY"

    # shortIds: пустой + 3 случайных разной длины. Общие для обоих inbound.
    SID1=$(openssl rand -hex 1)
    SID2=$(openssl rand -hex 4)
    SID3=$(openssl rand -hex 8)

    local INBOUNDS
    case "$TRANSPORT" in
        both)
            INBOUNDS="$(build_inbound "${NODE_NAME}_tcp" 443 tcp),
$(build_inbound "${NODE_NAME}_xhttp" "$XHTTP_PORT" xhttp)"
            ;;
        xhttp)
            INBOUNDS="$(build_inbound "${NODE_NAME}_xhttp" 443 xhttp)"
            ;;
        *)
            INBOUNDS="$(build_inbound "${NODE_NAME}_tcp" 443 tcp)"
            ;;
    esac

    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  ГОТОВЫЙ JSON ДЛЯ CONFIG PROFILE В REMNAWAVE${NC}"
    echo -e "${CYAN}  Скопируй и вставь в: Config Profiles → Create${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    local PROFILE="${OPT_DIR}/config-profile.json"
    cat > "$PROFILE" << JSONEOF
{
  "log": { "loglevel": "warning" },
  "dns": { "servers": [{"address":"https://94.140.14.14/dns-query","domains":[],"skipFallback":false},"localhost"] },
  "inbounds": [
${INBOUNDS}
  ],
  "outbounds": [
    {"tag":"DIRECT","protocol":"freedom"},
    {"tag":"BLOCK","protocol":"blackhole"}
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {"type":"field","network":"udp","port":"443","outboundTag":"BLOCK"},
      {"type":"field","protocol":["bittorrent"],"outboundTag":"BLOCK"},
      {"type":"field","domain":["domain:doubleclick.net","domain:googlesyndication.com","domain:googleadservices.com","domain:google-analytics.com","domain:analytics.yandex.ru","domain:mc.yandex.ru","domain:crashlytics.com","domain:app-measurement.com","domain:appcenter.ms"],"outboundTag":"BLOCK"},
      {"type":"field","network":"udp","port":"135,137,138,139","outboundTag":"BLOCK"},
      {"type":"field","ip":["geoip:private"],"outboundTag":"DIRECT"}
    ]
  }
}
JSONEOF
    chmod 600 "$PROFILE"
    # Приватный ключ внутри JSON: выводим только на терминал (минуя tee-лог)
    # и держим в файле 600. В /var/log ключ больше НЕ попадает.
    cat "$PROFILE" >/dev/tty
    echo "" >/dev/tty
    info "JSON сохранён в ${PROFILE} (chmod 600, в лог не пишется)"
    echo ""
}

phase10_panel() {
    title "Фаза 10 / Настройка в панели Remnawave"
    echo ""
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  1. Config Profiles → Create — вставь JSON из фазы 9${NC}"
    echo -e "${YELLOW}║  2. Nodes → Create${NC}"
    echo -e "${YELLOW}║     Name: ${NODE_NAME} | Address: ${SERVER_IP} | Port: ${NODE_API_PORT}${NC}"
    echo -e "${YELLOW}║     Привязать профиль, включить все inbound профиля${NC}"
    echo -e "${YELLOW}║     → Скопируй SECRET_KEY после создания!${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    ask "Вставь SECRET_KEY из панели"
    read -r SECRET_KEY </dev/tty
    if [[ -z "$SECRET_KEY" ]]; then die "SECRET_KEY не может быть пустым"; fi
    ok "SECRET_KEY принят"

    echo ""
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  3. Hosts → Create (Fingerprint: chrome, SNI = домен)${NC}"
    echo -e "${YELLOW}║     Flow НЕ задавать — панель добавит его сама для tcp${NC}"

    if [[ "$TRANSPORT" == "tcp" || "$TRANSPORT" == "both" ]]; then
        echo -e "${YELLOW}║   • Host TCP:${NC}"
        echo -e "${YELLOW}║     inbound ${NODE_NAME}_tcp | Address ${DOMAIN} | Port 443${NC}"
        echo -e "${YELLOW}║     ALPN: не задавать (flow vision добавится автоматически)${NC}"
    fi
    if [[ "$TRANSPORT" == "xhttp" ]]; then
        echo -e "${YELLOW}║   • Host XHTTP (mode ${XHTTP_MODE}, path ${XHTTP_PATH}):${NC}"
        echo -e "${YELLOW}║     inbound ${NODE_NAME}_xhttp | Address ${DOMAIN} | Port 443${NC}"
        echo -e "${YELLOW}║     ALPN: h2${NC}"
    fi
    if [[ "$TRANSPORT" == "both" ]]; then
        echo -e "${YELLOW}║   • Host XHTTP (mode ${XHTTP_MODE}, path ${XHTTP_PATH}):${NC}"
        echo -e "${YELLOW}║     inbound ${NODE_NAME}_xhttp | Address ${DOMAIN} | Port ${XHTTP_PORT}${NC}"
        echo -e "${YELLOW}║     ALPN: h2${NC}"
    fi

    echo -e "${YELLOW}║  4. Internal Squads → Default-Squad → добавь ВСЕ inbound${NC}"
    echo -e "${YELLOW}║     ⚠ Без этого нода не попадёт в подписку!${NC}"
    echo -e "${YELLOW}║  5. Nodes → нода зелёная? Клиент → обнови → пинг?${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    info "Проверь в ссылке подписки: для tcp есть &flow=xtls-rprx-vision"
    info "Ключи: ${OPT_DIR}/keys.txt | Лог: $LOG_FILE"
    echo ""
}

phase11_geo() {
    title "Фаза 11 / Geo-файлы (ДО запуска контейнера!)"
    mkdir -p "$GEO_DIR"
    info "Скачиваю geoip.dat и geosite.dat..."
    # geoip.dat обязателен: на него ссылается правило routing geoip:private.
    # Без него Xray не поднимет конфиг — лучше упасть здесь, чем ловить битый
    # контейнер в фазе 12 (docker подставил бы пустую директорию под маунт).
    if fetch_geo geoip.dat "${GEO_BASE_URL}/geoip.dat"; then
        ok "geoip.dat: $(du -h "${GEO_DIR}/geoip.dat" | cut -f1)"
    else
        die "geoip.dat не скачан/невалиден (нужен для geoip:private). Повтори запуск."
    fi
    # geosite.dat текущими правилами не используется — при сбое поднимемся без него.
    if fetch_geo geosite.dat "${GEO_BASE_URL}/geosite.dat"; then
        ok "geosite.dat: $(du -h "${GEO_DIR}/geosite.dat" | cut -f1)"
    else
        warn "geosite.dat не скачан — нода поднимется без него"
    fi
}

phase12_docker() {
    title "Фаза 12 / remnawave-node"
    cat > "${OPT_DIR}/.env" << ENVEOF
SSL_CERT=/etc/letsencrypt/live/${DOMAIN}/fullchain.pem
SSL_KEY=/etc/letsencrypt/live/${DOMAIN}/privkey.pem
SECRET_KEY=${SECRET_KEY}
NODE_PORT=${NODE_API_PORT}
ENVEOF
    chmod 600 "${OPT_DIR}/.env"
    # geoip.dat обязателен (гарантирован phase11), geosite — только если скачался.
    local GEO_VOL="      - ${GEO_DIR}/geoip.dat:/usr/local/share/xray/geoip.dat:ro"
    if [[ -s "${GEO_DIR}/geosite.dat" ]]; then
        GEO_VOL="${GEO_VOL}
      - ${GEO_DIR}/geosite.dat:/usr/local/share/xray/geosite.dat:ro"
    fi
    cat > "${OPT_DIR}/docker-compose.yml" << DCEOF
services:
  remnawave-node:
    image: ${REMNANODE_IMAGE}
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
${GEO_VOL}
DCEOF
    cd "$OPT_DIR"
    docker compose pull
    docker compose up -d
    ok "remnawave-node стартует (network_mode: host, Xray :443)"
    # Поллинг вместо слепого sleep: ждём до 30с появления running-контейнера.
    local _tries=0
    until docker ps --filter name=remnawave-node --filter status=running \
            --format '{{.Names}}' | grep -q remnawave-node; do
        _tries=$((_tries + 1))
        (( _tries >= 15 )) && break
        sleep 2
    done
    if docker ps --filter name=remnawave-node --filter status=running \
            --format '{{.Names}}' | grep -q remnawave-node; then
        ok "Контейнер remnawave-node работает"
    else
        warn "Контейнер не поднялся за ~30с! Логи:"
        docker logs remnawave-node --tail 20 2>&1 || true
    fi

    # Renewal-hook: после продления сертификата пересоздаём ноду, чтобы Xray/node
    # подхватили новый файл. live/ — симлинк, docker пинует старый inode при
    # маунте, поэтому нужен именно --force-recreate, а не restart.
    # ПРИМЕЧАНИЕ: certbot запускает deploy-хук только при renew, НЕ при первичной
    # выдаче. Для первого деплоя ноду уже поднял этот же phase12 выше — ок.
    mkdir -p /etc/letsencrypt/renewal-hooks/deploy
    cat > /etc/letsencrypt/renewal-hooks/deploy/remnanode.sh << RHEOF
#!/bin/bash
systemctl reload nginx
cd ${OPT_DIR} && docker compose up -d --force-recreate
RHEOF
    chmod +x /etc/letsencrypt/renewal-hooks/deploy/remnanode.sh
    ok "Renewal-hook: recreate ноды при продлении сертификата"
}

phase13_maintenance() {
    title "Фаза 13 / Автообслуживание"
    # update-geo: валидирует размер перед подменой live-файла и рестартит ноду
    # ТОЛЬКО если файл реально изменился (битый .dat не роняет Xray; провал
    # загрузки не даёт бессмысленный ночной рестарт).
    cat > "${OPT_DIR}/update-geo.sh" << GEOEOF
#!/bin/bash
set -uo pipefail
GEO_DIR="${GEO_DIR}"
LOG="/var/log/geo-update.log"
MIN_SIZE=${GEO_MIN_SIZE}
BASE="${GEO_BASE_URL}"
CHANGED=0
log(){ echo "\$(date '+%F %T') \$*" >> "\$LOG"; }

update_one() {
    local name="\$1" dst="\${GEO_DIR}/\$1"
    if wget -q --timeout=30 --tries=3 "\${BASE}/\$name" -O "\${dst}.tmp" \\
        && [[ -s "\${dst}.tmp" ]] \\
        && (( \$(stat -c%s "\${dst}.tmp") >= MIN_SIZE )); then
        if ! cmp -s "\${dst}.tmp" "\$dst" 2>/dev/null; then
            mv "\${dst}.tmp" "\$dst"; chmod 644 "\$dst"; CHANGED=1
            log "\$name updated"
        else
            rm -f "\${dst}.tmp"
        fi
    else
        rm -f "\${dst}.tmp"; log "\$name download invalid, kept old"
    fi
}

update_one geosite.dat
update_one geoip.dat

if (( CHANGED )); then
    cd "${OPT_DIR}" && docker compose up -d --force-recreate && log "node recreated"
else
    log "no changes, node untouched"
fi
GEOEOF
    chmod +x "${OPT_DIR}/update-geo.sh"

    local CRON_LINE="0 3 * * * ${OPT_DIR}/update-geo.sh"
    local EXISTING FILTERED
    EXISTING=$(crontab -l 2>/dev/null || true)
    FILTERED=$(echo "$EXISTING" | grep -v "update-geo" || true)
    printf '%s\n%s\n' "$FILTERED" "$CRON_LINE" | grep -v '^$' | crontab -
    ok "Cron: автообновление geo в 03:00 (с валидацией)"

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
    cat > "${OPT_DIR}/watchdog.sh" << WDEOF
#!/bin/bash
if ! docker ps | grep -q remnawave-node; then
    echo "\$(date '+%Y-%m-%d %H:%M:%S') watchdog: restarting" >> /var/log/watchdog.log
    cd "${OPT_DIR}" && docker compose up -d
fi
WDEOF
    chmod +x "${OPT_DIR}/watchdog.sh"
    local CRON_WD="*/5 * * * * ${OPT_DIR}/watchdog.sh"
    local EXISTING FILTERED
    EXISTING=$(crontab -l 2>/dev/null || true)
    FILTERED=$(echo "$EXISTING" | grep -v "watchdog" || true)
    printf '%s\n%s\n' "$FILTERED" "$CRON_WD" | grep -v '^$' | crontab -
    ok "Watchdog: проверка каждые 5 минут"
}

phase15_ufw() {
    title "Фаза 15 / UFW"
    warn "ufw --force reset сбросит существующие правила (бэкап в /etc/ufw)"
    ufw --force reset >/dev/null 2>&1
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow "${SSH_PORT}/tcp"            comment "SSH"
    ufw allow 443/tcp                      comment "Xray Reality"
    ufw allow 80/tcp                       comment "HTTP redirect + certbot"
    # nginx-fallback (${NGINX_FALLBACK_PORT}) наружу НЕ открываем: Reality ходит
    # на него по 127.0.0.1, а прямой коннект без proxy_protocol давал аномалию.
    ufw allow "${NODE_API_PORT}/tcp"       comment "Remnawave node API"
    if [[ "$TRANSPORT" == "both" ]]; then
        ufw allow "${XHTTP_PORT}/tcp" comment "Xray Reality XHTTP"
        ok "UFW: +${XHTTP_PORT}(xhttp)"
    fi
    ufw --force enable
    ok "UFW: ${SSH_PORT}(SSH) 443(Xray) 80(HTTP) ${NODE_API_PORT}(API)"
}

phase16_beszel() {
    title "Фаза 16 / Beszel agent"
    echo ""
    ask "Установить Beszel agent? (y/n)"
    read -r INSTALL_BESZEL </dev/tty
    if [[ "$INSTALL_BESZEL" != "y" ]]; then
        info "Beszel пропущен. Можно установить позже"
        return 0
    fi
    echo ""
    ask "Beszel hub URL (Enter — пропустить подсказку)"
    read -r BESZEL_HUB </dev/tty
    if [[ -n "$BESZEL_HUB" ]]; then
        info "Beszel hub: $BESZEL_HUB"
        info "  1. В Beszel UI → Systems → Add System"
        info "  2. Name: ${NODE_NAME} | Host: ${SERVER_IP} | Port: 45876"
        info "  3. Скопируй Key из Beszel"
    fi
    echo ""
    ask "Вставь Beszel KEY (ssh-ed25519 ...)"
    read -r BESZEL_KEY </dev/tty
    if [[ -z "$BESZEL_KEY" ]]; then
        warn "Key не указан, пропускаю"
        return 0
    fi
    ufw allow 45876/tcp comment "Beszel agent"
    docker stop beszel-agent 2>/dev/null || true
    docker rm beszel-agent 2>/dev/null || true
    # Том НЕ удаляем: в нём fingerprint агента. Снос = повторное добавление
    # ноды в хабе на каждом ре-запуске.
    docker run -d \
        --name beszel-agent \
        --restart unless-stopped \
        --network host \
        -v /var/run/docker.sock:/var/run/docker.sock:ro \
        -v beszel_agent_data:/var/lib/beszel-agent \
        -e KEY="$BESZEL_KEY" \
        -e LISTEN=:45876 \
        henrygd/beszel-agent:latest
    local _tries=0
    until docker ps --filter name=beszel-agent --filter status=running \
            --format '{{.Names}}' | grep -q beszel-agent; do
        _tries=$((_tries + 1))
        (( _tries >= 6 )) && break
        sleep 2
    done
    if docker ps --filter name=beszel-agent --filter status=running \
            --format '{{.Names}}' | grep -q beszel-agent; then
        ok "Beszel agent запущен на порту 45876"
        info "Проверь в Beszel UI: нода зелёная и есть fingerprint"
    else
        warn "Beszel agent не запустился. Проверь: docker logs beszel-agent"
    fi
}

phase17_summary() {
    title "Фаза 17 / Готово!"
    # Ставим маркер: следующий запуск на этой ноде пропустит apt upgrade.
    touch "$STATE_MARKER"
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  DEPLOY v${SCRIPT_VERSION} ЗАВЕРШЁН${NC}"
    echo -e "${GREEN}║  VLESS + Reality + ${TRANSPORT} + steal_oneself${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║  Домен:       ${DOMAIN}${NC}"
    echo -e "${GREEN}║  IP:          ${SERVER_IP}${NC}"
    echo -e "${GREEN}║  Нода:        ${NODE_NAME}${NC}"
    echo -e "${GREEN}║  Транспорт:   ${TRANSPORT}${NC}"
    [[ "$TRANSPORT" == "both" ]] && \
        echo -e "${GREEN}║  Порты:       tcp:443 + xhttp:${XHTTP_PORT}${NC}"
    echo -e "${GREEN}║  SSH:         ssh -p ${SSH_PORT} admin@${SERVER_IP}${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    secret "Private Key: ${PRIVATE_KEY}"
    secret "Public Key:  ${PUBLIC_KEY}"
    echo ""
    echo -e "${YELLOW}  ⚠ Заверши настройку в панели Remnawave (см. фазу 10 выше)${NC}"
    echo ""
    info "Ключи: ${OPT_DIR}/keys.txt"
    info "Лог:   $LOG_FILE (chmod 600, без приватного ключа)"
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
