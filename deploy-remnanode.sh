#!/usr/bin/env bash
# =============================================================================
# deploy-remnanode.sh v3.10
# VLESS + Reality + (TCP/Vision | XHTTP | BOTH) + steal_oneself
#
# Разворачивает remnawave-node на чистом Ubuntu 24.04.
# Один домен на ноду. Xray на 443 напрямую. nginx — fallback + ACME.
#
# Запуск:
#   wget -O deploy.sh https://raw.githubusercontent.com/anfixit/routerus/main/deploy-remnanode.sh
#   bash deploy.sh
#
# Для УЖЕ развёрнутых нод правки этой версии накатывает update-node.sh,
# а состояние ноды показывает check-node.sh (оба в этом же репозитории).
#
# Changelog v3.10 (аудит: 3 блокера, 6 высоких, 10 средних, 16 минорных):
#   - BLK-1(crit): routing больше НЕ отдаёт приватные сети в DIRECT. Правило
#     geoip:private→DIRECT кодифицировало SSRF с ноды: клиент мог указать в
#     VLESS-заголовке 169.254.169.254 (cloud-metadata), 10/8 (внутренняя сеть
#     хостера) или 127.0.0.1:2222 (node API в обход UFW). Теперь явный список
#     CIDR → BLOCK. domainStrategy IPIfNonMatch сохранён: он резолвит домен ДО
#     проверки IP-правил, иначе evil.example.com→169.254.169.254 прошёл бы мимо.
#   - BLK-2(crit): watchdog проверяет РЕАЛЬНЫЙ inbound (коннект на 443, в режиме
#     both — и на xhttp-порт), а не только наличие контейнера. Прежний
#     `docker ps | grep` молчал в самом частом сценарии: контейнер жив, API 2222
#     отвечает, панель зелёная, Xray мёртв. Плюс порог в 2 провала подряд
#     (кратковременный up -d не даёт рестарт-петлю) и flock от наложения.
#   - BLK-3: geo-машинерия убрана целиком. Единственным её потребителем было
#     правило geoip:private, заменённое явными CIDR; geosite-правил в конфиге
#     нет, а образ ноды несёт собственные .dat. Ушли: ночной cron, ежедневный
#     --force-recreate всего флота из-за обновления runetfreedom, зависимость
#     деплоя от доступности GitHub. Заодно задаётся таймзона (было: cron в UTC
#     при расчёте «на МСК»).
#   - H-1: 2222 (node API) и 45876 (Beszel) больше не открыты всему интернету —
#     UFW пускает только с IP панели и хаба. Открытый 2222 с характерным
#     TLS-ответом Remnawave был маркером, по которому одна опознанная нода
#     выдавала остальные сканом IPv4.
#   - H-2: sniffing routeOnly=true. Без него подслушанный SNI подменял адрес
#     назначения → двойной резолв на соединение и потеря CDN-локальности.
#     Мёртвый quic из destOverride убран (UDP/443 блокируется правилом выше).
#   - H-3: DNS клиентов больше не уходит на фильтрующий сторонний резолвер.
#   - H-4: fail2ban перезапускается ПОСЛЕ ufw reset — иначе цепочки f2b-*
#     не восстанавливались и джейл «включён» без единого правила в iptables.
#   - H-5: authorized_keys дополняется, а не перезаписывается (ре-запуск больше
#     не сносит второй ключ — ноутбука, коллеги, CI).
#   - H-6: явная пауза на подтверждение SSH-доступа до продолжения. Раньше
#     опечатка в ключе обнаруживалась через 15 минут, после выхода из сессии.
#   - SEC: SSH-порт случайный на ноду (был константой на всём флоте = маркер),
#     переиспользуется при ре-запуске. Лендинг рандомизируется по структуре,
#     а не только по палитре: число и порядок карточек, секции, шрифты, CSS,
#     robots.txt/favicon/вторая страница.
#   - M: set -E (ERR-trap не работал ни разу — весь код в функциях), валидация
#     домена, идемпотентная генерация ключей (ре-запуск больше не печатает НОВЫЙ
#     профиль, вставка которого рвала всех клиентов ноды), условный ufw reset,
#     jq-мёрдж daemon.json + рестарт docker только при реальном изменении,
#     сохранение пина образа из существующего compose, переиспользование
#     SECRET_KEY из .env, дроп-ин unattended-upgrades вместо затирания
#     дистрибутивного, проверка срока сертификата вместо факта наличия.
#   - L: nf_conntrack_max переживает ребут, cli.ini не навязывается всему хосту,
#     logrotate для логов ноды, visudo -cf, проверка эффективного конфига sshd,
#     admin добавляется в docker при повторном запуске, валидация ключа через
#     ssh-keygen, проверка занятости xhttp-порта, предупреждение об уникальности
#     тегов, внятная ошибка без /dev/tty, лог дописывается до конца.
# Changelog v3.9 (UX + аудит):
#   - выбор транспорта цифрой 1/2/3, SSH-примеры для Windows, Docker из
#     подписанного apt-репозитория, проверка свободного :443, head -1 в парсинге
#     ключа, check_internet без ICMP-маскировки, поллинг старта контейнера.
# Changelog v3.8 (аудит безопасности + устойчивость деплоя):
#   - privateKey не в лог, SSH-хардинг в 00-hardening.conf, nginx-fallback
#     только на loopback, фикс зависания phase2, renewal пересоздаёт ноду,
#     bittorrent → BLOCK, пин образа REMNANODE_IMAGE.
# Changelog v3.7 (аудит + актуализация транспорта):
#   - chmod фейк-сайта (фикс 403), mask ssh.socket, zero-downtime SSL (webroot),
#     санитизация имени ноды, XHTTP mode=packet-up.
# Changelog v3.6: транспорт both (tcp:443 + xhttp:<port>).
# Changelog v3.5: лог 600, ключи не в лог, hub не захардкожен, бэкапы конфигов.
# =============================================================================

# -E обязателен: без errtrace ERR-trap НЕ наследуется функциями, а весь код
# живёт в phaseN_*. До 3.10 trap не срабатывал ни разу, и падение выглядело
# как молчаливый обрыв вывода.
set -Eeuo pipefail

# --- Константы (единый источник истины) --------------------------------------
readonly SCRIPT_VERSION="3.10"
readonly LOG_FILE="/var/log/deploy-remnanode.log"
readonly NODE_API_PORT=2222
readonly NGINX_FALLBACK_PORT=8443
readonly BESZEL_PORT=45876
readonly WEBROOT="/var/www/html"
readonly OPT_DIR="/opt/remnanode"
readonly STATE_MARKER="${OPT_DIR}/.deployed"   # флаг «уже разворачивали»
readonly NODE_INFO="${OPT_DIR}/node-info.txt"  # шпаргалка по ноде для оператора

# SSH-порт выбирается случайно НА НОДУ. Константа на всём флоте (была 2810) —
# сильный признак кластеризации: одна опознанная нода выдавала остальные
# поиском по редкому порту в Censys/Shodan. На ре-запуске порт читается из
# уже написанного дроп-ина sshd, чтобы доступ не потерялся.
readonly SSH_PORT_MIN=20000
readonly SSH_PORT_MAX=60000
SSH_PORT=""

# Таймзона ноды. Свежая Ubuntu = UTC, из-за чего «ночной» крон приходился на
# утро по МСК. Задаётся явно, чтобы расписание и логи читались однозначно.
readonly NODE_TZ="${NODE_TZ:-Europe/Moscow}"

# Приватные и служебные диапазоны, недостижимые для клиента через ноду (BLK-1).
# Явный список вместо geoip:private — не требует geoip.dat, значит не требует
# и его ночного обновления с рестартом контейнера.
readonly PRIVATE_CIDRS='"0.0.0.0/8","10.0.0.0/8","100.64.0.0/10","127.0.0.0/8","169.254.0.0/16","172.16.0.0/12","192.0.0.0/24","192.168.0.0/16","198.18.0.0/15","224.0.0.0/4","240.0.0.0/4","::1/128","fc00::/7","fe80::/10"'

# DNS для резолва на ноде. Нефильтрующий: фильтрующий сторонний резолвер, во-первых,
# делает передачу доменных запросов клиентов третьей стороне раскрываемым фактом
# для Политики конфиденциальности, во-вторых, ломает краш-репортинг и A/B-конфиги
# мобильных приложений — пользователь приходит в поддержку, а связь с VPN не строит.
# Блокировка рекламы осталась в routing (по домену), она от резолвера не зависит.
readonly DNS_SERVER="${DNS_SERVER:-https://1.1.1.1/dns-query}"

# Образ для генерации x25519. Пинуется env-переменной для воспроизводимости.
readonly XRAY_KEYGEN_IMAGE="${XRAY_KEYGEN_IMAGE:-ghcr.io/xtls/xray-core:latest}"

# Образ ноды. Пустой = взять тег из существующего compose (ре-запуск не должен
# молча апгрейдить ядро на живой ноде), при первичной установке — :latest.
REMNANODE_IMAGE="${REMNANODE_IMAGE:-}"
readonly REMNANODE_IMAGE_DEFAULT="remnawave/node:latest"

# Email для Let's Encrypt (пустой → регистрация без email).
readonly CERTBOT_EMAIL="${CERTBOT_EMAIL:-}"

# XHTTP-транспорт. packet-up дробит upload на «api-запросы» — лучший режим
# против поведенческого DPI на мобильных сетях РФ (2026).
readonly XHTTP_MODE="packet-up"
readonly XHTTP_PATH="/api/v1/update"

# Значения по умолчанию, переопределяемые в phase1.
XHTTP_PORT=8444
PANEL_IP=""
BESZEL_HUB_IP=""

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

# --- Терминал обязателен (L-12) ----------------------------------------------
# Все вопросы читаются из /dev/tty. Без терминала (`ssh host 'bash -s' < deploy.sh`
# без -t) скрипт падал неинформативно на первом же read.
if ! : >/dev/tty 2>/dev/null; then
    echo "deploy-remnanode.sh: нужен терминал — все вопросы читаются из /dev/tty." >&2
    echo "Запусти на сервере напрямую, либо: ssh -t root@IP 'bash -s' < deploy.sh" >&2
    exit 1
fi

# --- Лог (не мир-читаемый: в него уходит весь stdout) ------------------------
umask 077
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

# tee — отдельный процесс; без ожидания хвост лога терялся при выходе (L-13).
_flush_log() {
    exec 1>&- 2>&- || true
    wait 2>/dev/null || true
}
trap _flush_log EXIT
trap 'echo -e "${RED}  ✖ Ошибка на строке $LINENO (код $?)${NC}" >/dev/tty' ERR

# --- Утилиты -----------------------------------------------------------------
backup_file() {
    # Бэкап файла перед деструктивной перезаписью.
    if [[ -f "$1" ]]; then
        cp -a "$1" "$1.bak.$(date +%s)"
    fi
}

check_internet() {
    # GitHub нужен дальше (apt-репо Docker), потому проверяем именно его
    # достижимость по HTTPS, а не «интернет вообще». Если HTTP-клиент есть —
    # его результат авторитетен: недоступность НЕ маскируется ICMP-пингом.
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
    echo "$ip" | tr -d '[:space:]'
}

valid_ipv4() {
    local ip="$1" o x
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    IFS='.' read -ra o <<< "$ip"
    for x in "${o[@]}"; do (( x <= 255 )) || return 1; done
    return 0
}

port_reserved() {
    # 0, если порт уже занят самой нодой. SSH_PORT участвует, только когда
    # уже выбран (порядок: сначала SSH, потом xhttp).
    local p="$1" r
    for r in 443 80 "$NODE_API_PORT" "$NGINX_FALLBACK_PORT" "$BESZEL_PORT" "${SSH_PORT:-}"; do
        [[ -n "$r" && "$p" == "$r" ]] && return 0
    done
    return 1
}

port_listening() {
    # 0, если на порту реально кто-то слушает (L-10).
    ss -lntH 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${1}\$"
}

rand_int() {
    # Равномерное целое в [$1;$2]. RANDOM даёт максимум 32767 — для диапазона
    # SSH-портов этого не хватает, потому берём 4 байта из urandom.
    local lo="$1" hi="$2" span r
    span=$(( hi - lo + 1 ))
    r=$(od -An -N4 -tu4 < /dev/urandom | tr -d ' ')
    echo $(( lo + r % span ))
}

pick_ssh_port() {
    # Уже настроенная нода: берём порт из своего дроп-ина, иначе ре-запуск
    # сменил бы порт и запер оператора снаружи.
    local existing p tries=0
    existing=$(awk '/^[[:space:]]*Port[[:space:]]+[0-9]+/{print $2; exit}' \
        /etc/ssh/sshd_config.d/00-hardening.conf 2>/dev/null || true)
    if [[ "$existing" =~ ^[0-9]+$ ]]; then
        echo "$existing"
        return 0
    fi
    while (( tries++ < 100 )); do
        p=$(rand_int "$SSH_PORT_MIN" "$SSH_PORT_MAX")
        port_reserved "$p" && continue
        port_listening "$p" && continue
        echo "$p"
        return 0
    done
    # Практически недостижимо, но пусть будет детерминированный исход.
    echo 2810
}

# Сгенерировать x25519 через заданный образ. Пробуем оба стиля вызова:
# `xray x25519` (образ без энтрипоинта xray) и `x25519` (энтрипоинт = xray).
xray_x25519() {
    local img="$1"
    docker run --rm "$img" xray x25519 2>/dev/null \
        || docker run --rm "$img" x25519 2>/dev/null
}

# =============================================================================
phase0_checks() {
    title "Фаза 0 / Проверки"
    if [[ $EUID -ne 0 ]]; then die "Запусти от root: sudo bash $0"; fi
    ok "root"
    # shellcheck disable=SC1091
    source /etc/os-release 2>/dev/null || die "Не читается /etc/os-release"
    # Без явной проверки отсутствующий VERSION_ID под set -u давал unbound
    # variable вместо внятной ошибки (L-14).
    if [[ -z "${ID:-}" || -z "${VERSION_ID:-}" ]]; then
        die "В /etc/os-release нет ID/VERSION_ID — дистрибутив не опознан"
    fi
    if [[ "$ID" != "ubuntu" || "${VERSION_ID%%.*}" -lt 24 ]]; then
        die "Нужна Ubuntu 24.04+, у тебя ${PRETTY_NAME:-$ID $VERSION_ID}"
    fi
    ok "Ubuntu $VERSION_ID"
    check_internet || die "Нет доступа к сети (проверил HTTPS к api.github.com)"
    ok "Сеть доступна"
    # На первичной установке 443 должен быть свободен: иначе Xray внутри
    # контейнера тихо упадёт на bind. На ре-запуске порт держит сама нода.
    if [[ ! -f "$STATE_MARKER" ]]; then
        if port_listening 443; then
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
    # Домен уходит в имя файла nginx, server_name, -d для certbot, serverNames
    # в JSON и пути маунтов compose. Пробел, кавычка, / или ; — от битого
    # конфига до инъекции в nginx (M-2).
    if ! [[ "$DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$ ]]; then
        die "Некорректный домен: '$DOMAIN' (ожидается вида example.ru)"
    fi

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
        valid_ipv4 "$SERVER_IP" || die "IP сервера обязателен и должен быть IPv4"
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
    # Проверка префикса не ловит битый base64 — а такой ключ становится
    # причиной локаута уже после рестарта sshd (L-9).
    if command -v ssh-keygen >/dev/null 2>&1; then
        ssh-keygen -l -f /dev/stdin <<< "$SSH_PUB_KEY" >/dev/null 2>&1 \
            || die "SSH-ключ не парсится (обрезан при копировании?). Вставь строку целиком."
    fi
    ok "SSH-ключ принят и проверен"

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
    # Remnawave требует уникальности тегов inbound по ВСЕМ Config Profile —
    # одинаковое имя на двух нодах даст конфликт уже в панели (L-11).
    warn "Имя должно быть уникальным по всему флоту: из него собираются теги"
    warn "inbound (${NODE_NAME}_tcp / ${NODE_NAME}_xhttp), а Remnawave требует"
    warn "уникальности тегов по всем Config Profile."

    # --- SSH-порт ------------------------------------------------------------
    SSH_PORT=$(pick_ssh_port)
    if [[ -f /etc/ssh/sshd_config.d/00-hardening.conf ]]; then
        ok "SSH-порт: ${SSH_PORT} (взят из текущей конфигурации ноды)"
    else
        echo ""
        info "SSH-порт предлагается случайный: одинаковый нестандартный порт на"
        info "всём флоте — редкое сочетание, по которому ноды собираются одним"
        info "поиском в Censys. Отдельно взятой ноде случайность стойкости не даёт."
        warn "ВАЖНО: у части хостеров есть внешний файрвол (security group), где"
        warn "высокие порты закрыты. Если не уверена, что ${SSH_PORT} пропускают"
        warn "снаружи — задай свой порт, который точно открыт."
        ask "SSH-порт [${SSH_PORT}]"
        read -r _sshport </dev/tty
        if [[ -n "$_sshport" ]]; then
            if ! [[ "$_sshport" =~ ^[0-9]+$ ]] || (( _sshport < 1 || _sshport > 65535 )); then
                die "Некорректный SSH-порт (диапазон 1-65535)"
            fi
            if port_reserved "$_sshport"; then
                die "Порт $_sshport занят нодой (443/80/${NODE_API_PORT}/${NGINX_FALLBACK_PORT}/${BESZEL_PORT})"
            fi
            if port_listening "$_sshport"; then
                die "На порту $_sshport уже кто-то слушает (ss -lntp | grep :$_sshport)"
            fi
            SSH_PORT="$_sshport"
        fi
        ok "SSH-порт: ${SSH_PORT}"
        warn "ЗАПИШИ ЭТОТ ПОРТ. Он же продублирован в ${NODE_INFO} и в итоговой сводке."
    fi

    # --- IP панели для UFW (H-1) ---------------------------------------------
    echo ""
    info "API ноды (:${NODE_API_PORT}) нужен только панели Remnawave."
    info "Открытый всему интернету, он выдаёт ноду сканом IPv4 по характерному"
    info "TLS-ответу — то есть по одной опознанной ноде находятся остальные."
    info "Укажи IP панели, чтобы UFW пускал только её. 'any' — оставить открытым."
    ask "IP панели Remnawave"
    read -r PANEL_IP </dev/tty
    if [[ "$PANEL_IP" == "any" ]]; then
        warn "API ноды останется открытым всему интернету (маркер для сканеров)."
        PANEL_IP="any"
    elif ! valid_ipv4 "$PANEL_IP"; then
        die "Нужен IPv4 панели или 'any'"
    else
        ok "API ноды будет доступен только с ${PANEL_IP}"
        info "При смене IP панели нода отвалится от управления — VPN при этом"
        info "продолжит работать (Xray живёт своим конфигом). Правится на ноде:"
        info "  ufw allow from НОВЫЙ_IP to any port ${NODE_API_PORT} proto tcp"
    fi

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
            die "Порт $XHTTP_PORT занят нодой (443/80/${SSH_PORT}/${NODE_API_PORT}/${NGINX_FALLBACK_PORT}/${BESZEL_PORT})"
        fi
        # Список зарезервированного не покрывает чужие сервисы на хосте (L-10).
        if [[ ! -f "$STATE_MARKER" ]] && port_listening "$XHTTP_PORT"; then
            die "На порту $XHTTP_PORT уже кто-то слушает (ss -lntp | grep :$XHTTP_PORT)"
        fi
        ok "xhttp-порт: $XHTTP_PORT"
    fi

    echo ""
    info "Параметры:"
    info "  Домен:     $DOMAIN"
    info "  IP:        $SERVER_IP"
    info "  Нода:      $NODE_NAME"
    info "  SSH-порт:  $SSH_PORT"
    info "  IP панели: $PANEL_IP"
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

    configure_docker_logging
}

configure_docker_logging() {
    # Ротация docker-логов (ДО запуска контейнеров). Раньше файл переписывался
    # целиком: предупреждение о бэкапе печаталось, а чужие настройки демона
    # (registry-mirrors, dns, storage-driver) молча терялись (M-5). Плюс
    # безусловный `systemctl restart docker` на живой ноде рвал все соединения
    # клиентов, даже когда менять было нечего (M-6).
    mkdir -p /etc/docker
    local dj=/etc/docker/daemon.json tmp
    tmp=$(mktemp)
    if [[ -s "$dj" ]]; then
        if ! jq -S '. + {"log-driver": "json-file"}
                 | .["log-opts"] = ((.["log-opts"] // {})
                     + {"max-size": "10m", "max-file": "3"})' \
                "$dj" > "$tmp" 2>/dev/null; then
            warn "/etc/docker/daemon.json не парсится как JSON — перезаписываю (бэкап рядом)"
            jq -S -n '{"log-driver": "json-file",
                       "log-opts": {"max-size": "10m", "max-file": "3"}}' > "$tmp"
        fi
    else
        jq -S -n '{"log-driver": "json-file",
                   "log-opts": {"max-size": "10m", "max-file": "3"}}' > "$tmp"
    fi

    if cmp -s "$tmp" "$dj" 2>/dev/null; then
        rm -f "$tmp"
        ok "Docker: log rotation уже настроена, демон не трогаю"
        return 0
    fi
    backup_file "$dj"
    install -m 0644 "$tmp" "$dj"
    rm -f "$tmp"
    systemctl restart docker 2>/dev/null || true
    ok "Docker: log rotation 10MB × 3 (демон перезапущен — конфиг изменился)"
}

phase3_ssh() {
    title "Фаза 3 / SSH hardening"
    if id "admin" &>/dev/null; then
        ok "Пользователь admin уже существует"
        # Нода, где admin был создан раньше Docker: без этого `docker ps`
        # из-под admin не работает (L-8).
        usermod -aG sudo admin 2>/dev/null || true
        if getent group docker >/dev/null 2>&1; then
            usermod -aG docker admin 2>/dev/null || true
        fi
    else
        groupadd -f admin
        useradd -m -s /bin/bash -g admin -G sudo,docker admin 2>/dev/null \
            || useradd -m -s /bin/bash -G sudo,docker admin 2>/dev/null
        ok "Пользователь admin создан"
    fi
    mkdir -p /home/admin/.ssh
    # Дописываем, а не перезаписываем: скрипт идемпотентен и предполагает
    # повторные запуски, а `>` молча сносил второй ключ — ноутбука, коллеги,
    # CI. Оператор, запустивший скрипт с другой машины, терял старый доступ (H-5).
    touch /home/admin/.ssh/authorized_keys
    if grep -qxF "$SSH_PUB_KEY" /home/admin/.ssh/authorized_keys; then
        ok "SSH-ключ уже в authorized_keys"
    else
        echo "$SSH_PUB_KEY" >> /home/admin/.ssh/authorized_keys
        ok "SSH-ключ добавлен (существующие ключи сохранены)"
    fi
    chmod 700 /home/admin/.ssh
    chmod 600 /home/admin/.ssh/authorized_keys
    chown -R admin:"$(id -gn admin)" /home/admin/.ssh

    # visudo -cf перед установкой: содержимое статичное, но битый файл в
    # sudoers.d ломает sudo целиком (L-6).
    local sudo_tmp
    sudo_tmp=$(mktemp)
    echo "admin ALL=(ALL) NOPASSWD:ALL" > "$sudo_tmp"
    if visudo -cf "$sudo_tmp" >/dev/null 2>&1; then
        install -m 0440 "$sudo_tmp" /etc/sudoers.d/admin
        ok "sudo без пароля"
    else
        rm -f "$sudo_tmp"
        die "Сгенерированный /etc/sudoers.d/admin не прошёл visudo -cf"
    fi
    rm -f "$sudo_tmp"

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

    # UFW настраивается в фазе 14, но порт SSH меняется ЗДЕСЬ. Если файрвол уже
    # активен (ре-запуск, образ хостера с включённым ufw), новый порт окажется
    # закрыт ровно в тот момент, когда мы просим проверить доступ, — и проверка
    # провалится не из-за ключа, а из-за файрвола. Открываем заранее.
    # Правило идемпотентно: ufw не дублирует одинаковые записи.
    if command -v ufw >/dev/null 2>&1; then
        ufw allow "${SSH_PORT}/tcp" comment "SSH" >/dev/null 2>&1 || true
        if ufw status 2>/dev/null | grep -q "Status: active"; then
            ok "UFW активен — порт ${SSH_PORT} открыт заранее, до рестарта sshd"
        else
            info "Порт ${SSH_PORT} внесён в UFW заранее (файрвол включится в фазе 14)"
        fi
    fi

    # Ключевое от «SSH постоянно падает»: socket-активация игнорирует Port и
    # оживает после apt upgrade openssh-server. mask держит её выключенной
    # навсегда; выбранный порт обслуживает именно ssh.service.
    systemctl disable --now ssh.socket 2>/dev/null || true
    systemctl mask ssh.socket 2>/dev/null || true
    systemctl unmask ssh 2>/dev/null || true
    systemctl enable --now ssh 2>/dev/null || systemctl enable --now sshd
    systemctl restart ssh 2>/dev/null || systemctl restart sshd

    # sshd -t проверяет только синтаксис. Какое значение реально победило в
    # склейке дроп-инов, показывает лишь -T (L-7).
    local eff
    eff=$(sshd -T 2>/dev/null | grep -iE '^(port|passwordauthentication|permitrootlogin) ' || true)
    if [[ -n "$eff" ]]; then
        info "Эффективный конфиг sshd:"
        while IFS= read -r line; do info "    $line"; done <<< "$eff"
    fi
    if ! grep -qi "^port ${SSH_PORT}\$" <<< "$eff"; then
        warn "sshd -T не подтверждает порт ${SSH_PORT} — проверь дроп-ины в /etc/ssh/sshd_config.d"
    fi
    if ! grep -qi '^passwordauthentication no$' <<< "$eff"; then
        warn "sshd -T показывает включённую парольную аутентификацию!"
    fi

    if ss -lntp 2>/dev/null | grep -qE ":${SSH_PORT}[[:space:]]"; then
        ok "SSH: слушает :${SSH_PORT}, key-only, root запрещён, socket masked"
    else
        warn "SSH не слушает :${SSH_PORT} — проверь из VNC до выхода!"
    fi

    # Пауза (H-6). Раньше скрипт печатал предупреждение и шёл дальше: опечатка
    # в ключе или закрытый порт обнаруживались через 15 минут, когда сессия уже
    # закрыта, и оставался только VNC. Текущая сессия ещё жива — проверяем сейчас.
    echo ""
    warn "ПРОВЕРЬ СЕЙЧАС из ДРУГОГО терминала, не закрывая этот:"
    warn "    ssh -p ${SSH_PORT} admin@${SERVER_IP}"
    warn "Текущая сессия остаётся живой, пока ты не ответишь."
    info "Если не пускает — частые причины по убыванию:"
    info "  • внешний файрвол хостера (security group) закрывает порт ${SSH_PORT};"
    info "  • ключ вставлен не полностью или это приватный ключ вместо .pub;"
    info "  • подключаешься под root, а разрешён только admin."
    ask "Доступ подтверждён? (y/n)"
    read -r _sshok </dev/tty
    if [[ "$_sshok" != "y" ]]; then
        # Сессия ещё жива, но sshd уже переехал на новый порт. Предлагаем вернуть
        # прежний конфиг: иначе после закрытия терминала остаётся только консоль
        # хостера, а это ровно тот сценарий, ради которого пауза и добавлена.
        echo ""
        ask "Вернуть прежнюю конфигурацию SSH? (y/n) [y]"
        read -r _revert </dev/tty
        if [[ -z "$_revert" || "$_revert" == "y" ]]; then
            rm -f /etc/ssh/sshd_config.d/00-hardening.conf
            systemctl unmask ssh.socket 2>/dev/null || true
            if sshd -t 2>/dev/null; then
                systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
                ok "Хардинг SSH откачен, sshd вернулся к прежним настройкам"
                info "Порт ${SSH_PORT} остался открытым в UFW — вреда нет, уберёшь позже"
            else
                warn "sshd -t не прошёл после отката — НЕ закрывай эту сессию!"
                warn "Бэкапы конфига: /etc/ssh/sshd_config.bak.* (бери самый свежий)"
            fi
        else
            warn "Откат не делаю. НЕ закрывай эту сессию, пока не починишь доступ."
            warn "Дроп-ин с портом: /etc/ssh/sshd_config.d/00-hardening.conf"
        fi
        die "Прервано до потери доступа. Разберись с SSH и запусти скрипт заново."
    fi
    ok "SSH-доступ подтверждён"
}

phase4_fail2ban() {
    title "Фаза 4 / fail2ban"
    # backend=systemd — на Ubuntu 24.04 журнал journald, auth.log может
    # отсутствовать. Порт берётся из выбранного в phase1.
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
    info "Цепочки f2b-* пересоздаются ещё раз после UFW (фаза 14) — см. H-4."
}

phase5_sysctl() {
    title "Фаза 5 / Kernel tuning + таймзона"
    # nf_conntrack_max жил только в `sysctl -w` и терялся при ребуте (L-1).
    # Модуль грузится через modules-load.d, иначе на свежем ядре ключа
    # net.netfilter.* ещё нет в момент применения sysctl.
    echo "nf_conntrack" > /etc/modules-load.d/remnanode.conf
    modprobe nf_conntrack 2>/dev/null || true
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
net.netfilter.nf_conntrack_max = 131072
fs.file-max = 1048576
fs.nr_open = 1048576
SYSEOF
    sysctl -p /etc/sysctl.d/99-remnanode.conf >/dev/null 2>&1 || true
    ok "BBR, TCP buffers, SYN flood protection, conntrack (переживает ребут)"

    # Свежая Ubuntu = UTC. Крон и логи читались как «по Москве», хотя были в UTC
    # (BLK-3): «ночные» задачи приходились на утро по МСК.
    if timedatectl set-timezone "$NODE_TZ" 2>/dev/null; then
        ok "Таймзона: ${NODE_TZ} ($(date '+%F %T %Z'))"
    else
        warn "Не удалось задать таймзону ${NODE_TZ} — расписание считай в UTC"
    fi
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

    # Проверка «директория есть» пропускала протухший сертификат: нода,
    # пролежавшая пару месяцев, получала «SSL уже есть», fallback-nginx отдавал
    # невалидный cert, и Reality-проббер видел аномалию ровно там, где нужна
    # неотличимость от обычного хостинга (M-10).
    local fullchain="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
    local email_arg=(--register-unsafely-without-email)
    [[ -n "$CERTBOT_EMAIL" ]] && email_arg=(--email "$CERTBOT_EMAIL")

    if [[ -f "$fullchain" ]] \
        && openssl x509 -checkend 604800 -noout -in "$fullchain" >/dev/null 2>&1; then
        local until
        until=$(openssl x509 -enddate -noout -in "$fullchain" 2>/dev/null | cut -d= -f2)
        ok "SSL для $DOMAIN валиден (до ${until:-?})"
    elif [[ -f "$fullchain" ]]; then
        warn "Сертификат $DOMAIN истёк или истекает в ближайшие 7 дней — продлеваю"
        certbot renew --force-renewal --cert-name "$DOMAIN" \
            --webroot -w "$WEBROOT" --non-interactive \
            || die "Не удалось продлить SSL. Проверь: dig $DOMAIN A +short"
        ok "SSL $DOMAIN продлён"
    else
        info "Получаю SSL для $DOMAIN (webroot, без остановки nginx)..."
        certbot certonly --webroot -w "$WEBROOT" --non-interactive --agree-tos \
            "${email_arg[@]}" -d "$DOMAIN" \
            || die "Не удалось получить SSL. Проверь: dig $DOMAIN A +short"
        ok "SSL $DOMAIN получен"
    fi

    # Глобальный /etc/letsencrypt/cli.ini навязывал authenticator=webroot ВСЕМ
    # будущим сертификатам хоста, включая DNS-01. Параметры выпуска и так
    # сохраняются в renewal/DOMAIN.conf, так что файл избыточен (L-2).
    # Снимаем свою версию, если её оставил прошлый прогон; чужую не трогаем.
    if [[ -f /etc/letsencrypt/cli.ini ]] \
        && grep -q '^authenticator = webroot$' /etc/letsencrypt/cli.ini \
        && grep -q "^webroot-path = ${WEBROOT}\$" /etc/letsencrypt/cli.ini \
        && [[ $(grep -cvE '^\s*(#|$)' /etc/letsencrypt/cli.ini) -eq 2 ]]; then
        backup_file /etc/letsencrypt/cli.ini
        rm -f /etc/letsencrypt/cli.ini
        info "Убран глобальный cli.ini прошлых версий (влиял на все сертификаты хоста)"
    fi
    systemctl enable certbot.timer 2>/dev/null || true
    ok "Автопродление SSL: webroot (recreate ноды — renewal-hook из фазы 11)"
}

phase7_nginx() {
    title "Фаза 7 / nginx fallback :${NGINX_FALLBACK_PORT}"
    info "Reality dest → 127.0.0.1:${NGINX_FALLBACK_PORT} (пробберы видят сайт)"
    # ПРИМЕЧАНИЕ: синтаксис 'listen ... http2' — для nginx 1.24 (Ubuntu 24.04).
    # Директиву 'http2 on;' вводить нельзя: она с nginx 1.25.1, на 24.04 сломает.
    cat > "/etc/nginx/sites-available/${DOMAIN}.conf" << NGXEOF
server {
    # Только loopback: fallback достижим лишь через Reality dest 127.0.0.1,
    # наружу не публикуется (см. фазу 14 — порт убран из UFW).
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
    # Голый 404 на «сайте студии» выглядит небрежно — отдаём свою страницу.
    error_page 404 /404.html;
    location = /404.html { internal; }
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

# --- Генератор лендинга -------------------------------------------------------
# Всё производное берётся из хэша домена: на ре-запуске сайт не меняется
# (идемпотентность, снятый ранее фингерпринт остаётся валиден), но между нодами
# различается не только палитрой. До 3.10 HTML-скелет, порядок CSS-правил,
# тексты карточек и футер были байт-в-байт одинаковы на всём флоте — хэш
# нормализованной структуры страницы совпадал, и одна опознанная нода выдавала
# остальные одним запросом в Censys.
_site_hash=""
hx() {
    # Целое из среза хэша домена: $1 — смещение, $2 — длина. Срезы не должны
    # перекрываться, иначе производные значения окажутся связаны между собой —
    # ради этого источник склеен из двух md5 (64 символа на ~20 срезов).
    echo $(( 16#${_site_hash:$1:$2} ))
}

_write_favicon() {
    # Минимальный валидный 16×16 ICO, залитый цветом темы. Отсутствие
    # favicon.ico у «сайта компании» — заметная аномалия, а одинаковый файл на
    # весь флот стал бы новым маркером, поэтому цвет берётся из палитры ноды.
    local out="$1" hex="${2#\#}" i px
    local r=$(( 16#${hex:0:2} )) g=$(( 16#${hex:2:2} )) b=$(( 16#${hex:4:2} ))
    px=$(printf '\\x%02x\\x%02x\\x%02x\\xff' "$b" "$g" "$r")
    {
        # ICONDIR: reserved=0, type=1 (icon), count=1
        printf '%b' '\x00\x00\x01\x00\x01\x00'
        # ICONDIRENTRY: 16×16, палитра 0, planes=1, bpp=32,
        # размер данных 0x468 = 40 (заголовок) + 1024 (XOR) + 64 (AND), offset 22
        printf '%b' '\x10\x10\x00\x00\x01\x00\x20\x00\x68\x04\x00\x00\x16\x00\x00\x00'
        # BITMAPINFOHEADER: size=40, w=16, h=32 (XOR+AND), planes=1, bpp=32
        printf '%b' '\x28\x00\x00\x00\x10\x00\x00\x00\x20\x00\x00\x00\x01\x00\x20\x00'
        printf '%b' '\x00\x00\x00\x00\x00\x04\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00'
        printf '%b' '\x00\x00\x00\x00\x00\x00\x00\x00'
        # XOR-битмап: 256 пикселей BGRA
        for ((i = 0; i < 256; i++)); do printf '%b' "$px"; done
        # AND-маска: 16 строк по 4 байта (16 бит выравниваются до слова)
        for ((i = 0; i < 64; i++)); do printf '%b' '\x00'; done
    } > "$out"
}

phase8_fakesite() {
    title "Фаза 8 / Фейковый сайт"
    mkdir -p "$WEBROOT"

    # Шесть услуг на тему — из них берётся 3-5 в порядке, зависящем от домена.
    local THEMES=(
        "Web Development Studio|We build modern web applications|Web Development,Cloud Solutions,API Integration,DevOps Consulting,Performance Audit,Legacy Migration"
        "Digital Marketing Agency|Data-driven marketing for growing brands|SEO Optimization,Content Strategy,PPC Management,Social Media,Email Campaigns,Market Research"
        "Cloud Infrastructure|Enterprise-grade cloud hosting solutions|Managed Hosting,Auto Scaling,Monitoring,CDN Services,Backup and Recovery,Cost Optimization"
        "Design Bureau|Creative solutions for digital products|UI/UX Design,Brand Identity,Motion Graphics,Print Design,Design Systems,Prototyping"
        "IT Consulting|Technology solutions for modern business|Infrastructure Audit,Security Assessment,Migration Planning,Team Training,Vendor Selection,Process Design"
        "Software Solutions|Custom software for complex problems|Enterprise Apps,Mobile Development,Data Analytics,System Integration,QA Automation,Technical Support"
        "Network Services|Reliable connectivity for your business|Network Design,VoIP Solutions,Fiber Optics,Managed WiFi,Site Surveys,Structured Cabling"
        "Data Analytics|Turn your data into actionable insights|Business Intelligence,Data Warehousing,ML Models,Dashboards,Data Governance,Reporting"
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
    local FONTS=(
        "-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif"
        "'Helvetica Neue', Helvetica, Arial, sans-serif"
        "system-ui, 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif"
        "Georgia, 'Times New Roman', Times, serif"
    )
    local CARD_COPY=(
        "Professional %s services tailored to your business needs and goals."
        "End-to-end %s delivered by a senior team with a track record."
        "Practical %s work, scoped to your budget and timeline."
        "We handle %s so your team can focus on the product."
    )
    # Имена классов — самый устойчивый признак страницы: селекторы переживают
    # смену палитры и текста, и .hero/.card/.services, одинаковые на всём флоте,
    # опознавались надёжнее любой структуры. Берём из пула по хэшу домена.
    local HERO_POOL=(hero banner masthead intro lead)
    local WRAP_POOL=(container wrap content inner page)
    local GRID_POOL=(services grid offer cards features)
    local CARD_POOL=(card item tile box panel)
    local ABOUT_POOL=(about text prose info copy)

    _site_hash="$(echo -n "$DOMAIN" | md5sum | tr -dc '0-9a-f')$(echo -n "${DOMAIN}-layout" | md5sum | tr -dc '0-9a-f')"

    # Внешний вид (срезы 0-31)
    local IDX=$(( $(hx 0 4) % ${#THEMES[@]} ))
    local CIDX=$(( $(hx 4 4) % ${#COLORS[@]} ))
    local FIDX=$(( $(hx 8 2) % ${#FONTS[@]} ))
    local RADIUS=$(( 4 + $(hx 10 2) % 13 ))          # скругление 4..16px
    local PAD=$(( 56 + $(hx 12 2) % 40 ))            # вертикальные отступы
    local HERO_PAD=$(( 60 + $(hx 14 2) % 50 ))
    local WIDTH=$(( 860 + $(hx 16 2) % 300 ))
    local COPYV=$(( $(hx 18 2) % ${#CARD_COPY[@]} ))
    local FOUNDED=$(( 2009 + $(hx 20 2) % 13 ))      # год основания 2009..2021
    local FIDX2=$(( $(hx 22 2) % 3 ))                # вариант футера
    local ROBOTSV=$(( $(hx 24 2) % 2 ))
    local CSSV=$(( $(hx 26 2) % 2 ))                 # форматирование CSS

    # Структура (срезы 32-63) — то, что видит фингерпринтер, нормализовавший
    # текст и цвета: имена классов, теги, число блоков.
    local NCARDS=$(( 3 + $(hx 32 2) % 3 ))           # 3..5 карточек
    local ROT=$(( $(hx 34 2) % 6 ))                  # сдвиг порядка услуг
    local ORDER=$(( $(hx 36 2) % 2 ))                # порядок секций
    local EXTRA=$(( $(hx 38 2) % 3 ))                # 0 — без доп. секции
    local NABOUT=$(( 1 + $(hx 40 2) % 3 ))           # 1..3 абзаца в About
    local C_HERO="${HERO_POOL[$(( $(hx 42 2) % ${#HERO_POOL[@]} ))]}"
    local C_WRAP="${WRAP_POOL[$(( $(hx 44 2) % ${#WRAP_POOL[@]} ))]}"
    local C_GRID="${GRID_POOL[$(( $(hx 46 2) % ${#GRID_POOL[@]} ))]}"
    local C_CARD="${CARD_POOL[$(( $(hx 48 2) % ${#CARD_POOL[@]} ))]}"
    local C_ABOUT="${ABOUT_POOL[$(( $(hx 50 2) % ${#ABOUT_POOL[@]} ))]}"
    # Обёртка блока услуг: section или div — ещё один разряд в хэше структуры.
    local SECTAG="div"
    if (( $(hx 52 2) % 2 )); then SECTAG="section"; fi
    # Наличие nav: одностраничник и сайт с навигацией различаются заметно.
    local WITH_NAV=$(( $(hx 54 2) % 2 ))

    IFS='|' read -r BIZ_NAME BIZ_DESC BIZ_SERVICES <<< "${THEMES[$IDX]}"
    IFS='|' read -r COLOR1 COLOR2 BG_COLOR <<< "${COLORS[$CIDX]}"

    local SITE_NAME
    SITE_NAME=$(echo "$DOMAIN" | sed 's/\.[^.]*$//' | sed 's/[-_]/ /g' \
        | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2))}1')
    local YEAR
    YEAR=$(date +%Y)
    # Год основания больше не константа 2019 на всех нодах: домену, купленному
    # неделю назад, «since 2019» противоречило датам WHOIS и CT-логов (L-16).
    (( FOUNDED > YEAR - 2 )) && FOUNDED=$(( YEAR - 2 ))

    local ALL_SVCS SVCS=()
    IFS=',' read -ra ALL_SVCS <<< "$BIZ_SERVICES"
    local i
    for ((i = 0; i < NCARDS; i++)); do
        SVCS+=( "${ALL_SVCS[$(( (i + ROT) % ${#ALL_SVCS[@]} ))]}" )
    done

    # --- CSS ---------------------------------------------------------------
    local CSS
    CSS=$(cat << CSSEOF
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: ${FONTS[$FIDX]}; color: #1f2937; background: #fff; }
        .${C_HERO} { background: linear-gradient(135deg, ${COLOR1}, ${COLOR2}); color: #fff; padding: ${HERO_PAD}px 20px; text-align: center; }
        .${C_HERO} h1 { font-size: 2.5rem; font-weight: 700; margin-bottom: 1rem; }
        .${C_HERO} p { font-size: 1.2rem; opacity: 0.9; max-width: 600px; margin: 0 auto; }
        .${C_WRAP} { max-width: ${WIDTH}px; margin: 0 auto; padding: ${PAD}px 20px; }
        .${C_GRID} { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 24px; margin-top: 40px; }
        .${C_CARD} { background: ${BG_COLOR}; border-radius: ${RADIUS}px; padding: 24px; text-align: center; }
        .${C_CARD} h3 { color: ${COLOR1}; margin-bottom: 8px; font-size: 1.1rem; }
        .${C_CARD} p { color: #6b7280; font-size: 0.9rem; line-height: 1.5; }
        .${C_ABOUT} { margin-top: ${PAD}px; line-height: 1.8; color: #4b5563; }
        nav { padding: 16px 20px; text-align: right; font-size: 0.9rem; }
        nav a { margin-left: 16px; text-decoration: none; }
        footer { text-align: center; padding: 40px 20px; color: #9ca3af; font-size: 0.85rem; border-top: 1px solid #f3f4f6; margin-top: ${PAD}px; }
        a { color: ${COLOR1}; }
CSSEOF
)
    # Половина нод отдаёт CSS «в одну строку на правило», половина — развёрнуто.
    # Дешёвый способ развести хэш нормализованного стиля между нодами.
    if (( CSSV == 0 )); then
        CSS=$(echo "$CSS" | sed 's/; /;\n            /g; s/ { /{\n            /g')
    fi

    # --- Секции ------------------------------------------------------------
    local SEC_SERVICES SEC_ABOUT SEC_EXTRA=""
    SEC_SERVICES="        <h2 style=\"text-align:center;font-size:1.8rem;\">Our Services</h2>
        <${SECTAG} class=\"${C_GRID}\">"
    local svc desc
    for svc in "${SVCS[@]}"; do
        # shellcheck disable=SC2059
        desc=$(printf "${CARD_COPY[$COPYV]}" "${svc,,}")
        SEC_SERVICES="${SEC_SERVICES}
            <div class=\"${C_CARD}\">
                <h3>${svc}</h3>
                <p>${desc}</p>
            </div>"
    done
    SEC_SERVICES="${SEC_SERVICES}
        </${SECTAG}>"

    local ABOUT_PARAS=(
        "<p>${SITE_NAME} is a team of experienced professionals delivering ${BIZ_NAME,,} services since ${FOUNDED}. We work with clients across Europe, helping them achieve their technology goals with modern, scalable solutions.</p>"
        "<p style=\"margin-top:12px;\">Our engagements range from short audits to multi-year retainers. We keep teams small and senior, so the people who scope the work are the people who deliver it.</p>"
        "<p style=\"margin-top:12px;\">Based in Europe. Available worldwide. <a href=\"mailto:info@${DOMAIN}\">Get in touch</a>.</p>"
    )
    SEC_ABOUT="        <div class=\"${C_ABOUT}\">
            <h2 style=\"margin-bottom:16px;\">About Us</h2>"
    for ((i = 0; i < NABOUT; i++)); do
        SEC_ABOUT="${SEC_ABOUT}
            ${ABOUT_PARAS[$i]}"
    done
    SEC_ABOUT="${SEC_ABOUT}
        </div>"

    case "$EXTRA" in
        1) SEC_EXTRA="        <div class=\"${C_ABOUT}\">
            <h2 style=\"margin-bottom:16px;\">How We Work</h2>
            <p>Every engagement starts with a short discovery call, followed by a written scope and a fixed estimate. We ship in two-week iterations and keep a shared board so you always know what is in progress.</p>
        </div>" ;;
        2) SEC_EXTRA="        <div class=\"${C_ABOUT}\">
            <h2 style=\"margin-bottom:16px;\">Why Clients Stay</h2>
            <p>Most of our work comes from referrals and repeat projects. We keep teams small, senior and stable, so the people who scoped your project are the people who deliver it.</p>
        </div>" ;;
    esac

    local FOOTERS=(
        "&copy; ${FOUNDED}-${YEAR} ${SITE_NAME}. All rights reserved."
        "${SITE_NAME} &middot; ${FOUNDED}-${YEAR} &middot; All rights reserved."
        "Copyright ${FOUNDED}-${YEAR} ${SITE_NAME}."
    )

    local NAV=""
    if (( WITH_NAV )); then
        NAV="    <nav><a href=\"/\">Home</a><a href=\"/about.html\">About</a><a href=\"mailto:info@${DOMAIN}\">Contact</a></nav>"
    fi

    # --- index.html --------------------------------------------------------
    {
        cat << HEADEOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <link rel="icon" href="/favicon.ico" sizes="16x16">
    <title>${SITE_NAME} — ${BIZ_NAME}</title>
    <style>
${CSS}
    </style>
</head>
<body>
${NAV}
    <div class="${C_HERO}">
        <h1>${SITE_NAME}</h1>
        <p>${BIZ_DESC}</p>
    </div>
    <div class="${C_WRAP}">
HEADEOF
        if (( ORDER == 0 )); then
            echo "$SEC_SERVICES"
            echo "$SEC_ABOUT"
        else
            echo "$SEC_ABOUT"
            echo "$SEC_SERVICES"
        fi
        [[ -n "$SEC_EXTRA" ]] && echo "$SEC_EXTRA"
        cat << FOOTEOF
    </div>
    <footer>
        ${FOOTERS[$FIDX2]} | <a href="mailto:info@${DOMAIN}">info@${DOMAIN}</a>
    </footer>
</body>
</html>
FOOTEOF
    } > "${WEBROOT}/index.html"

    # --- about.html --------------------------------------------------------
    # Одностраничник — сам по себе признак. Вторая страница и robots.txt делают
    # ноду похожей на обычный сайт при беглом обходе.
    cat > "${WEBROOT}/about.html" << ABOUTEOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <link rel="icon" href="/favicon.ico" sizes="16x16">
    <title>About — ${SITE_NAME}</title>
    <style>
${CSS}
    </style>
</head>
<body>
${NAV}
    <div class="${C_WRAP}">
        <h1 style="font-size:2rem;margin-bottom:16px;">About ${SITE_NAME}</h1>
        <div class="${C_ABOUT}">
            <p>${SITE_NAME} has been delivering ${BIZ_NAME,,} services since ${FOUNDED}. We are a small senior team: the people who scope a project are the people who build it.</p>
            <p style="margin-top:12px;">We work remotely with clients across Europe. For new enquiries write to <a href="mailto:info@${DOMAIN}">info@${DOMAIN}</a> — we reply within two business days.</p>
        </div>
    </div>
    <footer>
        ${FOOTERS[$FIDX2]} | <a href="mailto:info@${DOMAIN}">info@${DOMAIN}</a>
    </footer>
</body>
</html>
ABOUTEOF

    # --- 404.html ----------------------------------------------------------
    cat > "${WEBROOT}/404.html" << E404EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Page not found — ${SITE_NAME}</title>
    <style>
${CSS}
    </style>
</head>
<body>
    <div class="${C_WRAP}">
        <h1 style="font-size:2rem;margin-bottom:12px;">Page not found</h1>
        <p class="${C_ABOUT}">The page you requested does not exist. <a href="/">Back to the homepage</a>.</p>
    </div>
</body>
</html>
E404EOF

    # --- robots.txt --------------------------------------------------------
    if (( ROBOTSV == 0 )); then
        printf 'User-agent: *\nDisallow:\n' > "${WEBROOT}/robots.txt"
    else
        printf 'User-agent: *\nAllow: /\nDisallow: /cgi-bin/\n' > "${WEBROOT}/robots.txt"
    fi

    _write_favicon "${WEBROOT}/favicon.ico" "$COLOR1"

    # КРИТИЧНО: под umask 077 файлы создаются 600 root, и nginx-воркер
    # (www-data) отдаёт 403 вместо лендинга — steal_oneself ломается ровно
    # там, где нужен. Явно выставляем читаемые всем права.
    find "$WEBROOT" -type d -exec chmod 755 {} +
    find "$WEBROOT" -type f -exec chmod 644 {} +
    ok "Сайт: ${SITE_NAME} — ${BIZ_NAME}, ${NCARDS} карточек, since ${FOUNDED}"
    ok "Плюс about.html, 404.html, robots.txt, favicon.ico (структура своя у каждой ноды)"
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
    # routeOnly=true: подслушанный SNI отдаётся правилам маршрутизации, но НЕ
    # подменяет адрес назначения. Без него на каждое соединение приходилось два
    # резолва (роутинг через DNS Xray + freedom через системный), и терялась
    # CDN-локальность: клиент выбрал ближайший edge, а нода шла на тот, что
    # вернул её резолвер. quic убран — UDP/443 блокируется правилом ниже (H-2).
    cat << INBEOF
    {
      "tag": "${tag}",
      "port": ${port},
      "protocol": "vless",
      "settings": { "clients": [], "decryption": "none" },
      "sniffing": { "enabled": true, "destOverride": ["http","tls"], "routeOnly": true },
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

    # Ре-запуск перегенерировал ключи и shortId. Сама нода не падала (privateKey
    # живёт в панели), но скрипт печатал НОВЫЙ Config Profile, а оператор,
    # следуя инструкции фазы 10, вставлял его в панель — и все клиенты этой
    # ноды мгновенно теряли доступ (M-3). Теперь ключи переиспользуются.
    local KEYS="${OPT_DIR}/keys.txt" REUSED=0
    if [[ -f "$KEYS" ]]; then
        PRIVATE_KEY=$(awk -F= '/^PRIVATE_KEY=/{print $2; exit}' "$KEYS" 2>/dev/null || true)
        PUBLIC_KEY=$(awk -F= '/^PUBLIC_KEY=/{print $2; exit}' "$KEYS" 2>/dev/null || true)
        SID1=$(awk -F= '/^SID1=/{print $2; exit}' "$KEYS" 2>/dev/null || true)
        SID2=$(awk -F= '/^SID2=/{print $2; exit}' "$KEYS" 2>/dev/null || true)
        SID3=$(awk -F= '/^SID3=/{print $2; exit}' "$KEYS" 2>/dev/null || true)
        if [[ -n "$PRIVATE_KEY" && -n "$PUBLIC_KEY" \
              && -n "$SID1" && -n "$SID2" && -n "$SID3" ]]; then
            REUSED=1
            ok "Ключи и shortId взяты из ${KEYS} — профиль не изменится"
            info "Клиенты этой ноды продолжат работать: вставлять JSON в панель"
            info "повторно не нужно (он совпадёт с уже сохранённым)."
        elif [[ -n "$PRIVATE_KEY" && -n "$PUBLIC_KEY" ]]; then
            # keys.txt от версий ≤3.9: ключи есть, shortId в файле не хранились.
            SID1=$(openssl rand -hex 1)
            SID2=$(openssl rand -hex 4)
            SID3=$(openssl rand -hex 8)
            REUSED=1
            warn "В ${KEYS} нет сохранённых shortId (файл от версии ≤3.9)."
            warn "Ключи переиспользованы, shortId сгенерированы заново — их надо"
            warn "обновить в Config Profile, иначе профиль в панели и на ноде разойдутся."
        fi
    fi

    if (( ! REUSED )); then
        info "Генерирую x25519 ключи (образ: ${XRAY_KEYGEN_IMAGE})..."
        # Пробуем заданный образ, затем ghcr, затем teddysun. Для каждого — оба
        # стиля вызова (см. xray_x25519).
        KEY_OUTPUT=$(xray_x25519 "$XRAY_KEYGEN_IMAGE") \
            || KEY_OUTPUT=$(xray_x25519 "ghcr.io/xtls/xray-core:latest") \
            || KEY_OUTPUT=$(xray_x25519 "teddysun/xray:latest") \
            || die "Не удалось сгенерировать x25519 ключи"
        # Xray 26.x сменил метки: private → 'Private key'/'PrivateKey',
        # public → 'Public key'/'Password'. head -1 защищает от многострочного
        # вывода будущих версий (Hash/Fingerprint) — иначе ключ ломает JSON.
        PRIVATE_KEY=$(echo "$KEY_OUTPUT" | grep -iE 'private' | awk '{print $NF}' | head -1)
        PUBLIC_KEY=$(echo "$KEY_OUTPUT" | grep -iE 'public|password' | awk '{print $NF}' | head -1)
        if [[ -z "$PRIVATE_KEY" || -z "$PUBLIC_KEY" ]]; then
            die "Не удалось извлечь ключи из вывода xray (формат изменился?)"
        fi
        # shortIds: пустой + 3 случайных разной длины. Общие для обоих inbound.
        SID1=$(openssl rand -hex 1)
        SID2=$(openssl rand -hex 4)
        SID3=$(openssl rand -hex 8)
        ok "Ключи сгенерированы"
    fi

    backup_file "$KEYS"
    cat > "$KEYS" << KEYSEOF
# x25519 keys + shortIds. Файл — источник истины для идемпотентного ре-запуска:
# пока он на месте, повторный прогон печатает ТОТ ЖЕ Config Profile.
# Сгенерировано: $(date +%Y-%m-%d)
PRIVATE_KEY=$PRIVATE_KEY
PUBLIC_KEY=$PUBLIC_KEY
SID1=$SID1
SID2=$SID2
SID3=$SID3
KEYSEOF
    chmod 600 "$KEYS"
    ok "Ключи в ${KEYS} (chmod 600)"
    secret "Private Key: $PRIVATE_KEY"
    secret "Public Key:  $PUBLIC_KEY"

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
    # Последнее правило routing — BLOCK приватных сетей, а не DIRECT. DIRECT —
    # это freedom-outbound: нода САМА шла по адресу, который ей передал клиент,
    # то есть 169.254.169.254 (cloud-metadata хостера), внутренняя сеть
    # провайдера и собственные 127.0.0.1:${NODE_API_PORT} / :${NGINX_FALLBACK_PORT}
    # в обход UFW — коннект инициируется нодой, а не приходит снаружи (BLK-1).
    # domainStrategy IPIfNonMatch обязателен: он резолвит домен ДО проверки
    # IP-правил, иначе evil.example.com → 169.254.169.254 обошёл бы блок.
    cat > "$PROFILE" << JSONEOF
{
  "log": { "loglevel": "warning" },
  "dns": { "servers": [{"address":"${DNS_SERVER}","domains":[],"skipFallback":false},"localhost"] },
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
      {"type":"field","ip":[${PRIVATE_CIDRS}],"outboundTag":"BLOCK"},
      {"type":"field","network":"udp","port":"443","outboundTag":"BLOCK"},
      {"type":"field","protocol":["bittorrent"],"outboundTag":"BLOCK"},
      {"type":"field","domain":["domain:doubleclick.net","domain:googlesyndication.com","domain:googleadservices.com","domain:google-analytics.com","domain:analytics.yandex.ru","domain:mc.yandex.ru"],"outboundTag":"BLOCK"},
      {"type":"field","network":"udp","port":"135,137,138,139","outboundTag":"BLOCK"}
    ]
  }
}
JSONEOF
    # Профиль обязан быть валидным JSON: битый конфиг обнаружился бы только
    # после вставки в панель, уже на живых клиентах.
    jq empty "$PROFILE" 2>/dev/null || die "Сгенерированный Config Profile невалиден как JSON"
    chmod 600 "$PROFILE"
    # Приватный ключ внутри JSON: выводим только на терминал (минуя tee-лог)
    # и держим в файле 600. В /var/log ключ НЕ попадает.
    cat "$PROFILE" >/dev/tty
    echo "" >/dev/tty
    info "JSON сохранён в ${PROFILE} (chmod 600, в лог не пишется)"
    info "Приватные сети (metadata, RFC1918, loopback) — в BLOCK: нода не пойдёт"
    info "туда по просьбе клиента. Правило первое в списке, менять порядок нельзя."
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

    # Ре-запуск гонял оператора в панель за ключом ноды, которая и так работает,
    # хотя значение лежит в .env рядом (M-8).
    SECRET_KEY=""
    if [[ -f "${OPT_DIR}/.env" ]] && grep -q '^SECRET_KEY=' "${OPT_DIR}/.env"; then
        local existing
        existing=$(awk -F= '/^SECRET_KEY=/{print $2; exit}' "${OPT_DIR}/.env")
        if [[ -n "$existing" ]]; then
            ask "Найден SECRET_KEY в ${OPT_DIR}/.env. Использовать его? (y/n) [y]"
            read -r _use </dev/tty
            if [[ -z "$_use" || "$_use" == "y" ]]; then
                SECRET_KEY="$existing"
                ok "SECRET_KEY взят из .env"
            fi
        fi
    fi
    if [[ -z "$SECRET_KEY" ]]; then
        ask "Вставь SECRET_KEY из панели"
        read -r SECRET_KEY </dev/tty
        if [[ -z "$SECRET_KEY" ]]; then die "SECRET_KEY не может быть пустым"; fi
        ok "SECRET_KEY принят"
    fi

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

phase11_docker() {
    title "Фаза 11 / remnawave-node"
    backup_file "${OPT_DIR}/.env"
    cat > "${OPT_DIR}/.env" << ENVEOF
SSL_CERT=/etc/letsencrypt/live/${DOMAIN}/fullchain.pem
SSL_KEY=/etc/letsencrypt/live/${DOMAIN}/privkey.pem
SECRET_KEY=${SECRET_KEY}
NODE_PORT=${NODE_API_PORT}
ENVEOF
    chmod 600 "${OPT_DIR}/.env"

    # README учит фиксировать версию правкой image: в compose, а скрипт при
    # ре-запуске затирал файл значением по умолчанию и делал pull — то есть
    # молча апгрейдил ядро на живой ноде вопреки документации (M-7).
    local image="$REMNANODE_IMAGE"
    if [[ -z "$image" && -f "${OPT_DIR}/docker-compose.yml" ]]; then
        image=$(awk '/^[[:space:]]*image:[[:space:]]*/{print $2; exit}' \
            "${OPT_DIR}/docker-compose.yml" 2>/dev/null || true)
        [[ -n "$image" ]] && info "Образ взят из существующего compose: ${image}"
    fi
    image="${image:-$REMNANODE_IMAGE_DEFAULT}"

    backup_file "${OPT_DIR}/docker-compose.yml"
    # Маунтим /etc/letsencrypt целиком :ro — короче двух отдельных pem плюс
    # archive/, и не ломается при изменении структуры каталога (L-15).
    # geo-файлы не монтируются: правил geosite нет, а geoip:private заменён
    # явными CIDR, так что образ обходится встроенными .dat (BLK-3).
    cat > "${OPT_DIR}/docker-compose.yml" << DCEOF
services:
  remnawave-node:
    image: ${image}
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
      - /etc/letsencrypt:/etc/letsencrypt:ro
DCEOF
    cd "$OPT_DIR"

    if [[ -f "$STATE_MARKER" && "$image" == *:latest && -z "$REMNANODE_IMAGE" ]]; then
        warn "Образ ${image} не пинован: pull подтянет свежее ядро и пересоздаст"
        warn "контейнер — все текущие соединения клиентов оборвутся."
        ask "Обновить образ ноды сейчас? (y/n) [n]"
        read -r _pull </dev/tty
        if [[ "$_pull" == "y" ]]; then
            docker compose pull || die "docker compose pull не прошёл"
        else
            info "Пропускаю pull — работает текущий локальный образ"
        fi
    else
        docker compose pull || die "docker compose pull не прошёл"
    fi

    docker compose up -d
    ok "remnawave-node стартует (network_mode: host, Xray :443)"
    # Поллинг вместо слепого sleep: ждём до 30с появления running-контейнера.
    local _tries=0
    until docker ps --filter "name=^remnawave-node\$" --filter status=running \
            --format '{{.Names}}' | grep -q .; do
        _tries=$((_tries + 1))
        (( _tries >= 15 )) && break
        sleep 2
    done
    if docker ps --filter "name=^remnawave-node\$" --filter status=running \
            --format '{{.Names}}' | grep -q .; then
        ok "Контейнер remnawave-node работает"
    else
        warn "Контейнер не поднялся за ~30с! Логи:"
        docker logs remnawave-node --tail 20 2>&1 || true
    fi

    # Renewal-hook: после продления сертификата пересоздаём ноду, чтобы Xray/node
    # подхватили новый файл. live/ — симлинк, docker пинует старый inode при
    # маунте, поэтому нужен именно --force-recreate, а не restart.
    # ПРИМЕЧАНИЕ: certbot запускает deploy-хук только при renew, НЕ при первичной
    # выдаче. Для первого деплоя ноду уже поднял этот же phase11 выше — ок.
    mkdir -p /etc/letsencrypt/renewal-hooks/deploy
    cat > /etc/letsencrypt/renewal-hooks/deploy/remnanode.sh << RHEOF
#!/bin/bash
systemctl reload nginx
cd ${OPT_DIR} && docker compose up -d --force-recreate
RHEOF
    chmod +x /etc/letsencrypt/renewal-hooks/deploy/remnanode.sh
    ok "Renewal-hook: recreate ноды при продлении сертификата"
}

phase12_maintenance() {
    title "Фаза 12 / Автообслуживание"

    # Снимаем geo-машинерию версий ≤3.9. Её единственным потребителем было
    # правило geoip:private, заменённое явными CIDR. Цена, которую она брала:
    # runetfreedom публикует .dat почти ежедневно → cmp видел разницу →
    # docker compose up -d --force-recreate → все активные соединения на ноде
    # рвались. Каждую ночь и одновременно на всём флоте (BLK-3).
    local EXISTING FILTERED
    EXISTING=$(crontab -l 2>/dev/null || true)
    if grep -q 'update-geo' <<< "$EXISTING"; then
        FILTERED=$(grep -v 'update-geo' <<< "$EXISTING" || true)
        printf '%s\n' "$FILTERED" | grep -v '^$' | crontab - || true
        ok "Снят ночной geo-крон (он пересоздавал контейнер и рвал соединения)"
    fi
    if [[ -f "${OPT_DIR}/update-geo.sh" ]]; then
        rm -f "${OPT_DIR}/update-geo.sh"
        info "Удалён ${OPT_DIR}/update-geo.sh — geo-файлы больше не нужны"
    fi
    if [[ -d "${OPT_DIR}/geodata" ]]; then
        info "Каталог ${OPT_DIR}/geodata больше не используется, можно удалить вручную"
    fi

    # Дистрибутивный 50unattended-upgrades несёт blacklist пакетов, настройки
    # почты и обработку конфликтов конфигов — прошлые версии заменяли его тремя
    # строками. Восстанавливаем из пакета, своё кладём дроп-ином (M-9).
    local uu=/etc/apt/apt.conf.d/50unattended-upgrades
    local uu_dist=/usr/share/unattended-upgrades/50unattended-upgrades
    if [[ -f "$uu" ]] && ! grep -q 'Package-Blacklist' "$uu" && [[ -f "$uu_dist" ]]; then
        backup_file "$uu"
        cp "$uu_dist" "$uu"
        ok "Восстановлен дистрибутивный 50unattended-upgrades"
    fi
    cat > /etc/apt/apt.conf.d/52-remnanode.conf << 'UUEOF'
// Дроп-ин routerus. Дистрибутивный 50unattended-upgrades не трогаем.
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::Automatic-Reboot "false";
UUEOF
    systemctl enable unattended-upgrades
    ok "Автообновления безопасности: дроп-ин 52-remnanode.conf"

    # Логи ноды росли без ротации (L-4).
    cat > /etc/logrotate.d/remnanode << 'LREOF'
/var/log/watchdog.log
/var/log/deploy-remnanode.log
{
    weekly
    rotate 4
    compress
    delaycompress
    missingok
    notifempty
    create 0600 root root
}
LREOF
    ok "logrotate: watchdog.log и deploy-remnanode.log (4 недели)"
}

phase13_watchdog() {
    title "Фаза 13 / Watchdog"
    # Проверялся только факт существования контейнера — и подстрокой по всему
    # выводу `docker ps`, то есть матч ловил и имя образа, и чужой контейнер с
    # похожим именем. Самый частый отказ так не ловился вовсе: контейнер жив,
    # API 2222 отвечает, панель зелёная, Xray на 443 мёртв — молчали и watchdog,
    # и панель, и Beszel, а диагностика приходила от клиентов (BLK-2).
    local INBOUND_PORTS="443"
    if [[ "$TRANSPORT" == "both" ]]; then
        INBOUND_PORTS="443 ${XHTTP_PORT}"
    fi
    cat > "${OPT_DIR}/watchdog.sh" << WDEOF
#!/bin/bash
# Проверяет РЕАЛЬНЫЙ inbound, а не только наличие контейнера.
set -uo pipefail
OPT_DIR="${OPT_DIR}"
LOG="/var/log/watchdog.log"
STATE="\${OPT_DIR}/.watchdog_fails"
INBOUND_PORTS="${INBOUND_PORTS}"
FAIL_THRESHOLD=2     # рестарт только после 2 провалов подряд

# Без flock зависший прогон и следующий по крону могли наложиться и пересоздать
# контейнер дважды.
exec 9>/run/remnanode-watchdog.lock
flock -n 9 || exit 0

log(){ echo "\$(date '+%F %T') \$*" >> "\$LOG"; }

alive=1
reason=""

# Точное имя (^…\$) вместо подстроки по всему выводу docker ps.
docker ps --filter "name=^remnawave-node\\\$" --filter status=running -q \\
    | grep -q . || { alive=0; reason="container down"; }

if (( alive )); then
    for p in \$INBOUND_PORTS; do
        timeout 5 bash -c "exec 3<>/dev/tcp/127.0.0.1/\$p" 2>/dev/null \\
            || { alive=0; reason="port \$p not accepting"; break; }
    done
fi

if (( alive )); then
    echo 0 > "\$STATE"
    exit 0
fi

fails=\$(( \$(cat "\$STATE" 2>/dev/null || echo 0) + 1 ))
echo "\$fails" > "\$STATE"
log "unhealthy: \${reason} (fail \${fails}/\${FAIL_THRESHOLD})"
(( fails < FAIL_THRESHOLD )) && exit 0

log "restarting node"
cd "\$OPT_DIR" && docker compose up -d --force-recreate >> "\$LOG" 2>&1
echo 0 > "\$STATE"
WDEOF
    chmod +x "${OPT_DIR}/watchdog.sh"
    local CRON_WD="*/5 * * * * ${OPT_DIR}/watchdog.sh"
    local EXISTING FILTERED
    EXISTING=$(crontab -l 2>/dev/null || true)
    FILTERED=$(echo "$EXISTING" | grep -v "watchdog" || true)
    printf '%s\n%s\n' "$FILTERED" "$CRON_WD" | grep -v '^$' | crontab -
    ok "Watchdog: коннект на ${INBOUND_PORTS} каждые 5 минут, рестарт после 2 провалов"
}

phase14_ufw() {
    title "Фаза 14 / UFW"
    # Безусловный reset на ре-запуске закрывал 45876, добавленный предыдущим
    # прогоном, и стирал любое ручное правило — мониторинг тихо умирал (M-4).
    if [[ ! -f "$STATE_MARKER" ]]; then
        warn "Первичная установка: ufw --force reset (бэкап правил в /etc/ufw)"
        ufw --force reset >/dev/null 2>&1
    else
        info "Повторный запуск — правила не сбрасываю, добавляю нужные поверх"
    fi
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow "${SSH_PORT}/tcp"            comment "SSH"
    ufw allow 443/tcp                      comment "Xray Reality"
    ufw allow 80/tcp                       comment "HTTP redirect + certbot"
    # nginx-fallback (${NGINX_FALLBACK_PORT}) наружу НЕ открываем: Reality ходит
    # на него по 127.0.0.1, а прямой коннект без proxy_protocol давал аномалию.

    # API ноды — только с панели (H-1). Открытый миру :2222 с характерным
    # TLS-ответом Remnawave позволял найти весь флот сканом IPv4.
    ufw delete allow "${NODE_API_PORT}/tcp" >/dev/null 2>&1 || true
    if [[ "$PANEL_IP" == "any" ]]; then
        ufw allow "${NODE_API_PORT}/tcp" comment "Remnawave node API (открыт всем)"
        warn "API ноды открыт всему интернету — это маркер для сканеров"
    else
        ufw allow from "$PANEL_IP" to any port "$NODE_API_PORT" proto tcp \
            comment "Remnawave panel"
        ok "API ноды :${NODE_API_PORT} — только с ${PANEL_IP}"
    fi

    if [[ "$TRANSPORT" == "both" ]]; then
        ufw allow "${XHTTP_PORT}/tcp" comment "Xray Reality XHTTP"
        ok "UFW: +${XHTTP_PORT}(xhttp)"
    fi
    ufw --force enable
    ok "UFW: ${SSH_PORT}(SSH) 443(Xray) 80(HTTP) ${NODE_API_PORT}(API, ограничен)"

    # ufw reset/enable перестраивает filter-таблицу своим набором, в котором
    # цепочек f2b-* нет. Fail2ban об этом не узнаёт до собственного рестарта:
    # `fail2ban-client status sshd` показывает «enabled», а `iptables -S | grep
    # f2b` — пусто, то есть защиты нет вообще (H-4).
    systemctl restart fail2ban 2>/dev/null || true
    sleep 1
    if iptables -S 2>/dev/null | grep -q 'f2b-'; then
        ok "fail2ban перезапущен, цепочки f2b-* на месте"
    else
        warn "Цепочек f2b-* нет в iptables — проверь: fail2ban-client status sshd"
    fi
}

phase15_beszel() {
    title "Фаза 15 / Beszel agent"
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
        info "  2. Name: ${NODE_NAME} | Host: ${SERVER_IP} | Port: ${BESZEL_PORT}"
        info "  3. Скопируй Key из Beszel"
    fi
    echo ""
    ask "Вставь Beszel KEY (ssh-ed25519 ...)"
    read -r BESZEL_KEY </dev/tty
    if [[ -z "$BESZEL_KEY" ]]; then
        warn "Key не указан, пропускаю"
        return 0
    fi

    # Открытый всему миру :45876 — такой же маркер флота, как и :2222 (H-1).
    echo ""
    info "К агенту подключается только хаб Beszel. Укажи его IP, чтобы UFW"
    info "не публиковал порт ${BESZEL_PORT} всему интернету. 'any' — оставить открытым."
    ask "IP хаба Beszel"
    read -r BESZEL_HUB_IP </dev/tty
    ufw delete allow "${BESZEL_PORT}/tcp" >/dev/null 2>&1 || true
    if [[ "$BESZEL_HUB_IP" == "any" ]]; then
        ufw allow "${BESZEL_PORT}/tcp" comment "Beszel agent (открыт всем)"
        warn "Порт ${BESZEL_PORT} открыт всему интернету — маркер для сканеров"
    elif valid_ipv4 "$BESZEL_HUB_IP"; then
        ufw allow from "$BESZEL_HUB_IP" to any port "$BESZEL_PORT" proto tcp \
            comment "Beszel hub"
        ok "Beszel :${BESZEL_PORT} — только с ${BESZEL_HUB_IP}"
    else
        die "Нужен IPv4 хаба Beszel или 'any'"
    fi

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
        -e LISTEN=":${BESZEL_PORT}" \
        henrygd/beszel-agent:latest
    local _tries=0
    until docker ps --filter "name=^beszel-agent\$" --filter status=running \
            --format '{{.Names}}' | grep -q .; do
        _tries=$((_tries + 1))
        (( _tries >= 6 )) && break
        sleep 2
    done
    if docker ps --filter "name=^beszel-agent\$" --filter status=running \
            --format '{{.Names}}' | grep -q .; then
        ok "Beszel agent запущен на порту ${BESZEL_PORT}"
        info "Проверь в Beszel UI: нода зелёная и есть fingerprint"
    else
        warn "Beszel agent не запустился. Проверь: docker logs beszel-agent"
    fi
}

phase16_summary() {
    title "Фаза 16 / Готово!"
    # Ставим маркер: следующий запуск на этой ноде пропустит apt upgrade
    # и не будет сбрасывать UFW.
    touch "$STATE_MARKER"

    # Шпаргалка по ноде. С рандомным SSH-портом реестр нод обязателен: порт
    # больше не угадывается и не одинаков на флоте.
    cat > "$NODE_INFO" << NIEOF
# routerus node info — сгенерировано $(date '+%F %T %Z')
NODE_NAME=${NODE_NAME}
DOMAIN=${DOMAIN}
SERVER_IP=${SERVER_IP}
SSH_PORT=${SSH_PORT}
SSH_COMMAND=ssh -p ${SSH_PORT} admin@${SERVER_IP}
TRANSPORT=${TRANSPORT}
XHTTP_PORT=$([[ "$TRANSPORT" == "both" ]] && echo "$XHTTP_PORT" || echo "-")
NODE_API_PORT=${NODE_API_PORT}
PANEL_IP=${PANEL_IP}
SCRIPT_VERSION=${SCRIPT_VERSION}
NIEOF
    chmod 600 "$NODE_INFO"

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
    echo -e "${YELLOW}  ⚠ SSH-порт этой ноды — ${SSH_PORT}. Он случайный и НЕ совпадает${NC}"
    echo -e "${YELLOW}    с другими нодами. Занеси его в свой реестр: ${NODE_INFO}${NC}"
    echo ""
    echo -e "${YELLOW}  ⚠ Заверши настройку в панели Remnawave (см. фазу 10 выше)${NC}"
    echo ""
    info "Ключи:    ${OPT_DIR}/keys.txt"
    info "Инфо:     ${NODE_INFO}"
    info "Лог:      $LOG_FILE (chmod 600, без приватного ключа)"
    info "Проверка: bash check-node.sh (из репозитория routerus)"
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
    phase11_docker
    phase12_maintenance
    phase13_watchdog
    phase14_ufw
    phase15_beszel
    phase16_summary
}

main "$@"
