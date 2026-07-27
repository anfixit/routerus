#!/usr/bin/env bash
# =============================================================================
# check-node.sh v3.10 — диагностика развёрнутой ноды routerus.
#
# READ-ONLY: ничего не меняет, не рестартует и не пишет в конфиги. Задача —
# пройти флот и увидеть, где что не так, до того как это увидят клиенты.
#
# Запуск на ноде:
#   sudo bash check-node.sh
#
# Коды выхода: 0 — всё чисто, 1 — есть FAIL, 2 — только WARN.
# =============================================================================

set -uo pipefail

readonly OPT_DIR="/opt/remnanode"
readonly NODE_API_PORT=2222
readonly NGINX_FALLBACK_PORT=8443
readonly BESZEL_PORT=45876

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

FAILS=0
WARNS=0

pass()  { echo -e "${GREEN}  ✔ $1${NC}"; }
fail()  { echo -e "${RED}  ✖ $1${NC}"; FAILS=$((FAILS + 1)); }
warn()  { echo -e "${YELLOW}  ⚠ $1${NC}"; WARNS=$((WARNS + 1)); }
info()  { echo -e "${CYAN}  ℹ $1${NC}"; }
title() { echo -e "\n${BLUE}━━━ $1 ━━━${NC}"; }

[[ $EUID -ne 0 ]] && { echo "Запусти от root: sudo bash $0"; exit 1; }

DOMAIN=""
SSH_PORT=""
TRANSPORT=""
XHTTP_PORT=""
if [[ -f "${OPT_DIR}/node-info.txt" ]]; then
    DOMAIN=$(awk -F= '/^DOMAIN=/{print $2; exit}'      "${OPT_DIR}/node-info.txt")
    SSH_PORT=$(awk -F= '/^SSH_PORT=/{print $2; exit}'  "${OPT_DIR}/node-info.txt")
    TRANSPORT=$(awk -F= '/^TRANSPORT=/{print $2; exit}' "${OPT_DIR}/node-info.txt")
    XHTTP_PORT=$(awk -F= '/^XHTTP_PORT=/{print $2; exit}' "${OPT_DIR}/node-info.txt")
fi
# Нода, развёрнутая версией ≤3.9, node-info.txt не имеет — вытаскиваем что можем.
[[ -z "$SSH_PORT" ]] && SSH_PORT=$(awk '/^[[:space:]]*Port[[:space:]]+[0-9]+/{print $2; exit}' \
    /etc/ssh/sshd_config.d/00-hardening.conf 2>/dev/null)
[[ -z "$DOMAIN" ]] && DOMAIN=$(find /etc/letsencrypt/live -mindepth 1 -maxdepth 1 -type d \
    -printf '%f\n' 2>/dev/null | head -1)

echo ""
echo -e "${GREEN}  check-node.sh — $(hostname) — $(date '+%F %T %Z')${NC}"
[[ -n "$DOMAIN" ]] && info "Домен: ${DOMAIN}"

# --- 1. Реальный inbound -----------------------------------------------------
title "1 / Xray inbound (то, что панель НЕ проверяет)"
# Панель мониторит только API-порт: контейнер жив, 2222 отвечает, нода зелёная,
# а Xray на 443 мёртв. Именно этот отказ и не ловился до 3.10.
#
# Ожидаемые порты берём из самого профиля, а не из node-info.txt: панель отдаёт
# ноде ТОЛЬКО те inbound, что отмечены в Nodes → Edit. Профиль может содержать
# два, а работать будет один — и нода при этом останется зелёной.
PROFILE="${OPT_DIR}/config-profile.json"
declare -a EXP_PORTS=() EXP_TAGS=()
if [[ -f "$PROFILE" ]] && command -v jq >/dev/null 2>&1; then
    mapfile -t EXP_PORTS < <(jq -r '.inbounds[].port' "$PROFILE" 2>/dev/null || true)
    mapfile -t EXP_TAGS  < <(jq -r '.inbounds[].tag'  "$PROFILE" 2>/dev/null || true)
fi
if (( ${#EXP_PORTS[@]} == 0 )); then
    # Профиля нет (нода от версии ≤3.9) — падаем на node-info.txt.
    EXP_PORTS=(443)
    EXP_TAGS=("inbound")
    if [[ "$TRANSPORT" == "both" && -n "$XHTTP_PORT" && "$XHTTP_PORT" != "-" ]]; then
        EXP_PORTS=(443 "$XHTTP_PORT")
        EXP_TAGS=("tcp" "xhttp")
    fi
fi

info "В профиле inbound: ${#EXP_PORTS[@]} (${EXP_TAGS[*]})"
DEAD=0
for i in "${!EXP_PORTS[@]}"; do
    p="${EXP_PORTS[$i]}"
    t="${EXP_TAGS[$i]:-inbound}"
    if timeout 5 bash -c "exec 3<>/dev/tcp/127.0.0.1/${p}" 2>/dev/null; then
        pass "inbound ${t} :${p} принимает соединения"
    else
        fail "inbound ${t} :${p} НЕ отвечает — этот inbound не работает"
        DEAD=$((DEAD + 1))
    fi
done

# Часть портов жива, часть мертва — почти всегда это не сбой Xray, а невключённый
# inbound в панели. Отдельная подсказка, потому что симптом («нода зелёная, но
# половина ссылок не работает») сам по себе на причину не указывает.
if (( DEAD > 0 && DEAD < ${#EXP_PORTS[@]} )); then
    warn "Работает не весь профиль: ${DEAD} из ${#EXP_PORTS[@]} inbound молчат."
    warn "Самая частая причина — в панели Nodes → Edit включены НЕ ВСЕ inbound"
    warn "профиля. Нода поднимает только отмеченные, оставаясь зелёной."
    warn "Что реально получено из панели:"
    warn "    docker logs remnawave-node --tail 50 | grep '·'"
fi

if docker ps --filter "name=^remnawave-node$" --filter status=running -q | grep -q .; then
    pass "контейнер remnawave-node запущен"
    RESTARTS=$(docker inspect -f '{{.RestartCount}}' remnawave-node 2>/dev/null || echo "?")
    UPSINCE=$(docker inspect -f '{{.State.StartedAt}}' remnawave-node 2>/dev/null || echo "")
    # docker отдаёт UTC, а нода живёт в своей таймзоне — без перевода время
    # контейнера расходится с временем в watchdog.log на несколько часов.
    UPLOCAL=$(date -d "$UPSINCE" '+%F %T %Z' 2>/dev/null || echo "${UPSINCE:-?}")
    info "рестартов: ${RESTARTS}, запущен: ${UPLOCAL}"
    # --force-recreate обнуляет RestartCount, поэтому шторм перезапусков виден
    # только в логе watchdog, а не в docker inspect.
    if [[ -f /var/log/watchdog.log ]]; then
        RECENT=$(grep -c 'restarting node' /var/log/watchdog.log 2>/dev/null || echo 0)
        if (( RECENT > 0 )); then
            info "watchdog перезапускал ноду ${RECENT} раз(а) за всю историю лога"
            LASTR=$(grep 'restarting node' /var/log/watchdog.log | tail -1 | cut -d' ' -f1-2)
            info "последний раз: ${LASTR}"
        fi
    fi
    (( RESTARTS > 5 )) 2>/dev/null && warn "много рестартов (${RESTARTS}) — смотри docker logs remnawave-node"
else
    fail "контейнер remnawave-node не запущен"
fi

# --- 2. Routing: приватные сети (BLK-1) --------------------------------------
title "2 / Config Profile: приватные сети"
if [[ -f "$PROFILE" ]] && command -v jq >/dev/null 2>&1; then
    # Профиль на ноде — только копия для оператора; источник истины в панели.
    # Но если здесь ещё лежит geoip:private→DIRECT, в панели почти наверняка
    # то же самое: нода ходит по приватным адресам, которые ей назвал клиент.
    if jq -e '.routing.rules[] | select(.outboundTag == "DIRECT") | select((.ip // []) | length > 0)' \
            "$PROFILE" >/dev/null 2>&1; then
        fail "в ${PROFILE} есть IP-правило с outboundTag DIRECT (SSRF с ноды, BLK-1)"
        info "проверь Config Profile в панели: приватные сети должны идти в BLOCK"
    elif jq -e '.routing.rules[] | select(.outboundTag == "BLOCK") | select((.ip // []) | index("169.254.0.0/16"))' \
            "$PROFILE" >/dev/null 2>&1; then
        pass "приватные сети (включая 169.254/16) блокируются"
    else
        warn "в ${PROFILE} не нашёл правила BLOCK для приватных сетей — проверь панель"
    fi

    if jq -e '.inbounds[] | select(.sniffing.routeOnly != true)' "$PROFILE" >/dev/null 2>&1; then
        warn "есть inbound без sniffing.routeOnly — двойной резолв и ломка CDN (H-2)"
    else
        pass "sniffing.routeOnly включён на всех inbound"
    fi

    DNSADDR=$(jq -r '.dns.servers[0].address // "?"' "$PROFILE" 2>/dev/null)
    info "DNS в профиле: ${DNSADDR}"

    # Панель хранит инбаунды отдельными записями и при повторной вставке профиля
    # может их не обновить: ноде уходит свежий конфиг, а ссылки подписки строятся
    # из старых записей — с чужим публичным ключом. Снаружи это неотличимо от
    # сломанной ноды: Reality молча отдаёт клиента на лендинг.
    PUBKEY=$(awk -F= '/^PUBLIC_KEY=/{print $2; exit}' "${OPT_DIR}/keys.txt" 2>/dev/null || true)
    if [[ -n "$PUBKEY" ]]; then
        echo ""
        info "Публичный ключ этой ноды:"
        info "    ${PUBKEY}"
        info "СВЕРЬ его с pbk= в ссылке подписки — значения обязаны совпадать."
        info "Не совпало → хост в панели привязан к устаревшей записи инбаунда;"
        info "пересоздай хост, ноду переустанавливать не нужно."
    fi

    # Порты в профиле обязаны различаться, иначе один inbound не поднимется.
    DUPPORT=$(jq -r '[.inbounds[].port] | group_by(.) | map(select(length > 1)) | flatten | unique | join(", ")' \
        "$PROFILE" 2>/dev/null || true)
    if [[ -n "$DUPPORT" && "$DUPPORT" != "null" ]]; then
        fail "в профиле несколько inbound на одном порту (${DUPPORT}) — один из них не запустится"
    fi
    [[ "$DNSADDR" == *"94.140.14"* ]] \
        && warn "фильтрующий резолвер AdGuard: раскрываемый факт для Политики + ломает часть приложений (H-3)"
else
    warn "нет ${PROFILE} или jq — проверь Config Profile в панели вручную"
fi

# --- 3. fail2ban (H-4) -------------------------------------------------------
title "3 / fail2ban"
# ufw reset/enable перестраивает filter-таблицу без цепочек f2b-*. Fail2ban
# об этом не узнаёт: джейл рапортует «enabled», а правил в iptables нет.
if systemctl is-active --quiet fail2ban; then
    pass "служба fail2ban активна"
    # Смотреть только в iptables нельзя: banaction может быть nftables-*, и тогда
    # цепочки живут в nft ruleset, а `iptables -S` пуст — здоровая нода получала
    # ложный FAIL. Проверяем оба фронта и заодно спрашиваем сам fail2ban.
    F2B_WHERE=""
    iptables -S 2>/dev/null | grep -q 'f2b-' && F2B_WHERE="iptables"
    if [[ -z "$F2B_WHERE" ]] && command -v nft >/dev/null 2>&1; then
        nft list ruleset 2>/dev/null | grep -qi 'f2b' && F2B_WHERE="nftables"
    fi
    JAILED=$(fail2ban-client status sshd 2>/dev/null || true)
    BANNED=$(awk -F': *' '/Currently banned/{print $2}' <<< "$JAILED" | tr -d '[:space:]')
    F2B_ACTION=$(fail2ban-client get sshd actions 2>/dev/null \
        | grep -oiE '(nftables|iptables)[a-z0-9-]*' | head -1)

    if [[ -z "$JAILED" ]]; then
        fail "джейл sshd не отвечает — fail2ban не защищает SSH"
        info "чинится так: systemctl restart fail2ban && fail2ban-client status sshd"
    elif [[ -n "$F2B_WHERE" ]]; then
        pass "правила f2b на месте (${F2B_WHERE}, в бане сейчас: ${BANNED:-0})"
    elif [[ "$F2B_ACTION" == nftables* && "${BANNED:-0}" == "0" ]]; then
        # Действие nftables создаёт таблицу f2b-table лениво, при первом бане.
        # Её отсутствие при нуле забаненных — нормальная работа, а не поломка.
        # Заодно: H-4 (ufw reset сносит цепочки) на nftables не воспроизводится —
        # у fail2ban своя таблица, ufw её не трогает.
        pass "джейл sshd активен, banaction=${F2B_ACTION} (в бане: 0)"
        info "таблица f2b создаётся при первом бане — сейчас её отсутствие штатно"
    else
        # Джейл жив, есть баны, но правил не видно — вот это уже H-4: ufw reset
        # снёс цепочки, а fail2ban об этом не узнает до своего рестарта.
        fail "джейл запущен (в бане ${BANNED:-?}), но правил нет — banaction=${F2B_ACTION:-?} (H-4)"
        info "чинится так: systemctl restart fail2ban"
    fi
else
    fail "служба fail2ban не активна"
fi

# --- 4. UFW (H-1) ------------------------------------------------------------
title "4 / UFW"
if command -v ufw >/dev/null 2>&1 && ufw status >/dev/null 2>&1; then
    UFWOUT=$(ufw status verbose 2>/dev/null)
    if grep -q "Status: active" <<< "$UFWOUT"; then
        pass "UFW активен"
    else
        fail "UFW не активен"
    fi
    # Открытый миру 2222 с характерным TLS-ответом Remnawave — маркер, по
    # которому одна опознанная нода выдаёт остальные сканом IPv4.
    if grep -qE "^${NODE_API_PORT}/tcp[[:space:]]+ALLOW IN[[:space:]]+Anywhere" <<< "$UFWOUT"; then
        fail "порт ${NODE_API_PORT} (node API) открыт всему интернету (H-1)"
        info "чинится так: ufw delete allow ${NODE_API_PORT}/tcp && ufw allow from IP_ПАНЕЛИ to any port ${NODE_API_PORT} proto tcp"
    else
        pass "порт ${NODE_API_PORT} не открыт всем"
    fi
    if grep -qE "^${BESZEL_PORT}/tcp[[:space:]]+ALLOW IN[[:space:]]+Anywhere" <<< "$UFWOUT"; then
        warn "порт ${BESZEL_PORT} (Beszel) открыт всему интернету (H-1)"
    fi
    if grep -qE "^${NGINX_FALLBACK_PORT}/tcp[[:space:]]+ALLOW IN" <<< "$UFWOUT"; then
        fail "порт ${NGINX_FALLBACK_PORT} (nginx-fallback) открыт наружу — прямой коннект без proxy_protocol даёт аномалию"
    else
        pass "nginx-fallback :${NGINX_FALLBACK_PORT} наружу не опубликован"
    fi
else
    fail "UFW не установлен или недоступен"
fi

# --- 4b. nginx: fallback для Reality -----------------------------------------
title "4b / nginx (fallback steal_oneself)"
# Reality отдаёт неопознанных клиентов и DPI-пробберы на 127.0.0.1:8443. Если
# nginx лежит, проббер получает connection refused вместо сайта — то есть ровно
# ту аномалию, ради устранения которой steal_oneself и делался.
if systemctl is-active --quiet nginx; then
    pass "nginx запущен"
    if timeout 5 bash -c "exec 3<>/dev/tcp/127.0.0.1/${NGINX_FALLBACK_PORT}" 2>/dev/null; then
        pass "fallback :${NGINX_FALLBACK_PORT} принимает соединения"
    else
        fail "fallback :${NGINX_FALLBACK_PORT} не отвечает — маскировка сломана"
    fi
else
    fail "nginx НЕ запущен — Reality некуда отдавать пробберов (маскировка сломана)"
    info "чинится так: nginx -t && systemctl start nginx"
fi
for f in index.html about.html 404.html robots.txt favicon.ico; do
    [[ -f "/var/www/html/$f" ]] || warn "нет /var/www/html/$f — лендинг неполный"
done

# --- 5. SSL ------------------------------------------------------------------
title "5 / Сертификат"
if [[ -n "$DOMAIN" && -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]]; then
    CERT="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
    ENDDATE=$(openssl x509 -enddate -noout -in "$CERT" 2>/dev/null | cut -d= -f2)
    if openssl x509 -checkend 604800 -noout -in "$CERT" >/dev/null 2>&1; then
        pass "сертификат валиден ещё >7 дней (до ${ENDDATE})"
    elif openssl x509 -checkend 0 -noout -in "$CERT" >/dev/null 2>&1; then
        warn "сертификат истекает в ближайшие 7 дней (до ${ENDDATE})"
    else
        fail "сертификат ИСТЁК (${ENDDATE}) — fallback отдаёт невалидный cert, проббер видит аномалию"
    fi
    # Продление без пересоздания контейнера бесполезно: live/ — симлинк,
    # docker пинует старый inode и нода продолжает отдавать прежний файл.
    if [[ -x /etc/letsencrypt/renewal-hooks/deploy/remnanode.sh ]]; then
        pass "renewal-hook на месте (пересоздаёт ноду при продлении)"
    else
        warn "нет renewal-hook — после продления нода будет отдавать старый сертификат"
    fi
else
    warn "не нашёл сертификат для домена '${DOMAIN:-?}'"
fi

# --- 6. Watchdog (BLK-2) -----------------------------------------------------
title "6 / Watchdog и cron"
if [[ -f "${OPT_DIR}/watchdog.sh" ]]; then
    if grep -q '/dev/tcp/' "${OPT_DIR}/watchdog.sh"; then
        pass "watchdog проверяет реальный inbound"
    else
        fail "watchdog проверяет только наличие контейнера (BLK-2)"
        info "мёртвый Xray при живом контейнере он не заметит — накати update-node.sh"
    fi
else
    fail "нет ${OPT_DIR}/watchdog.sh"
fi
if crontab -l 2>/dev/null | grep -q 'watchdog'; then
    pass "watchdog в crontab"
else
    fail "watchdog не прописан в crontab"
fi
# geo-крон рвал соединения на всём флоте одновременно каждую ночь.
if crontab -l 2>/dev/null | grep -q 'update-geo'; then
    fail "остался ночной geo-крон: --force-recreate рвёт все соединения (BLK-3)"
    info "снимается через update-node.sh"
else
    pass "ночного geo-крона нет"
fi

# --- 7. SSH ------------------------------------------------------------------
title "7 / SSH"
EFF=$(sshd -T 2>/dev/null)
if [[ -n "$EFF" ]]; then
    EFFPORT=$(awk '/^port /{print $2; exit}' <<< "$EFF")
    pass "sshd слушает порт ${EFFPORT}"
    if [[ "$EFFPORT" == "2810" ]]; then
        warn "порт 2810 — константа прошлых версий, одинакова на всём флоте (маркер)"
    fi
    if grep -qi '^passwordauthentication no$' <<< "$EFF"; then
        pass "парольная аутентификация выключена"
    else
        fail "парольная аутентификация ВКЛЮЧЕНА"
    fi
    if grep -qi '^permitrootlogin no$' <<< "$EFF"; then
        pass "вход root запрещён"
    else
        warn "вход root разрешён"
    fi
else
    warn "sshd -T не отработал"
fi
if systemctl is-enabled ssh.socket >/dev/null 2>&1; then
    warn "ssh.socket не замаскирован — apt upgrade может вернуть :22"
else
    pass "ssh.socket замаскирован"
fi

# --- 8. Прочее ---------------------------------------------------------------
title "8 / Прочее"
TZNOW=$(timedatectl show -p Timezone --value 2>/dev/null || echo "?")
if [[ "$TZNOW" == "UTC" ]]; then
    warn "таймзона UTC — расписание крона считай в UTC, а не по МСК"
else
    pass "таймзона: ${TZNOW}"
fi

if [[ -f /etc/logrotate.d/remnanode ]]; then
    pass "logrotate для логов ноды настроен"
else
    warn "нет ротации /var/log/watchdog.log — файл растёт без ограничений"
fi

for f in "${OPT_DIR}/keys.txt" "${OPT_DIR}/.env" "${OPT_DIR}/config-profile.json"; do
    [[ -f "$f" ]] || continue
    PERM=$(stat -c '%a' "$f" 2>/dev/null)
    if [[ "$PERM" == "600" ]]; then
        pass "$(basename "$f"): права ${PERM}"
    else
        fail "$(basename "$f"): права ${PERM}, ожидается 600"
    fi
done

DISK=$(df -h / | awk 'NR==2{print $5}' | tr -d '%')
if [[ "$DISK" =~ ^[0-9]+$ ]] && (( DISK >= 90 )); then
    warn "диск заполнен на ${DISK}%"
else
    pass "диск: ${DISK}% занято"
fi

# --- Итог --------------------------------------------------------------------
echo ""
if (( FAILS > 0 )); then
    echo -e "${RED}  ИТОГ: ${FAILS} FAIL, ${WARNS} WARN — нужно вмешательство${NC}"
    echo ""
    exit 1
elif (( WARNS > 0 )); then
    echo -e "${YELLOW}  ИТОГ: 0 FAIL, ${WARNS} WARN${NC}"
    echo ""
    exit 2
else
    echo -e "${GREEN}  ИТОГ: всё чисто${NC}"
    echo ""
    exit 0
fi
