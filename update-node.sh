#!/usr/bin/env bash
# =============================================================================
# update-node.sh v3.10 — накатывает правки аудита на УЖЕ развёрнутую ноду.
#
# Зачем отдельный скрипт: часть находок (BLK-2, BLK-3, H-1, H-4, L-1, L-4)
# живёт на самой ноде, а не в панели, и не ждёт следующего деплоя. Проходить
# девять серверов руками — ровно та работа, ради которой он и задуман.
#
# Запуск на ноде:
#   sudo bash update-node.sh                 # спросит IP панели
#   sudo PANEL_IP=1.2.3.4 bash update-node.sh
#   sudo PANEL_IP=1.2.3.4 DRY_RUN=1 bash update-node.sh   # только показать
#
# Скрипт идемпотентен: повторный запуск ничего не ломает и не дублирует.
# НЕ трогает: ключи Reality, SECRET_KEY, домен, сертификаты, SSH-порт,
# образ ноды и docker-compose.yml. Пересоздания контейнера не делает.
#
# ЧЕГО ОН НЕ УМЕЕТ. BLK-1 (приватные сети → BLOCK) и H-2 (sniffing.routeOnly)
# живут в Config Profile в ПАНЕЛИ, а не на ноде. Их правит человек, скрипт лишь
# проверит локальную копию профиля и напомнит. См. итоговую памятку.
# =============================================================================

set -Eeuo pipefail

readonly OPT_DIR="/opt/remnanode"
readonly NODE_API_PORT=2222
readonly BESZEL_PORT=45876
readonly LOG_FILE="/var/log/update-node.log"
readonly NODE_TZ="${NODE_TZ:-Europe/Moscow}"
DRY_RUN="${DRY_RUN:-0}"
PANEL_IP="${PANEL_IP:-}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

ok()    { echo -e "${GREEN}  ✔ $1${NC}"; }
info()  { echo -e "${CYAN}  ℹ $1${NC}"; }
warn()  { echo -e "${YELLOW}  ⚠ $1${NC}"; }
die()   { echo -e "${RED}  ✖ $1${NC}"; exit 1; }
title() { echo -e "\n${BLUE}━━━ $1 ━━━${NC}"; }
ask()   { echo -ne "${YELLOW}  ▸ $1: ${NC}"; }
skip()  { echo -e "${CYAN}  · $1${NC}"; }

CHANGED=()
note() { CHANGED+=("$1"); }

# В DRY_RUN печатаем команду вместо выполнения.
run() {
    if (( DRY_RUN )); then
        echo -e "${YELLOW}    [dry-run] $*${NC}"
    else
        "$@"
    fi
}

[[ $EUID -ne 0 ]] && die "Запусти от root: sudo bash $0"

umask 077
touch "$LOG_FILE"; chmod 600 "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1
trap 'exec 1>&- 2>&-; wait 2>/dev/null || true' EXIT
trap 'echo -e "${RED}  ✖ Ошибка на строке $LINENO (код $?)${NC}"' ERR

backup_file() { [[ -f "$1" ]] && cp -a "$1" "$1.bak.$(date +%s)"; return 0; }

valid_ipv4() {
    local ip="$1" o x
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    IFS='.' read -ra o <<< "$ip"
    for x in "${o[@]}"; do (( x <= 255 )) || return 1; done
    return 0
}

echo ""
echo -e "${GREEN}  update-node.sh v3.10 — $(hostname) — $(date '+%F %T %Z')${NC}"
(( DRY_RUN )) && warn "DRY_RUN=1 — только показываю, ничего не меняю"
[[ -d "$OPT_DIR" ]] || die "Нет ${OPT_DIR} — это не нода routerus"

# --- Контекст ноды -----------------------------------------------------------
DOMAIN=""
if [[ -f "${OPT_DIR}/node-info.txt" ]]; then
    DOMAIN=$(awk -F= '/^DOMAIN=/{print $2; exit}' "${OPT_DIR}/node-info.txt")
fi
[[ -z "$DOMAIN" ]] && DOMAIN=$(find /etc/letsencrypt/live -mindepth 1 -maxdepth 1 -type d \
    -printf '%f\n' 2>/dev/null | head -1)

# Порты inbound берём у того, кто их РЕАЛЬНО слушает, а не из комментариев UFW.
# Комментарий «Xray Reality XHTTP» старые версии скрипта ставили и на 443 для
# единственного inbound, из-за чего эвристика по UFW выдавала несуществующий
# режим both и дублировала порт. Слушающий процесс — источник истины: именно его
# доступность и проверяет watchdog.
detect_inbound_ports() {
    local p
    # Фильтруем по ПРОЦЕССУ, а не по номеру порта: API ноды держит rw-node,
    # фолбэк — nginx, и оба отсеиваются сами. Исключать 8443 по номеру нельзя —
    # на нодах старых версий именно там и живёт сам Xray.
    p=$(ss -lntpH 2>/dev/null \
        | grep -E 'rw-core|xray' \
        | grep -oE '[:.]([0-9]+) ' \
        | tr -d ':. ' \
        | sort -un \
        | tr '\n' ' ' || true)
    echo "${p% }"
}
# Имя контейнера тоже не константа: ноды старых версий поднимали его как
# `remnanode`, а не `remnawave-node`. Watchdog с зашитым именем считал бы такую
# ноду вечно мёртвой. Определяем по образу.
detect_container() {
    local c
    c=$(docker ps --format '{{.Names}}\t{{.Image}}' 2>/dev/null \
        | grep -iE 'remnawave/node' | head -1 | cut -f1 || true)
    echo "${c:-remnawave-node}"
}
NODE_CONTAINER=$(detect_container)
INBOUND_PORTS=$(detect_inbound_ports)
if [[ -z "$INBOUND_PORTS" ]]; then
    # Xray не слушает ничего — либо нода лежит, либо конфиг из панели не пришёл.
    # Ставим 443 как заведомый минимум, но честно предупреждаем: watchdog будет
    # проверять предположение, а не факт.
    INBOUND_PORTS="443"
    warn "Не нашёл слушающих портов Xray — беру 443 по умолчанию."
    warn "Если нода сейчас не работает, сначала подними её, потом обнови watchdog."
fi
info "Домен: ${DOMAIN:-?} | контейнер: ${NODE_CONTAINER} | inbound: ${INBOUND_PORTS}"

SSH_PORT=$(awk '/^[[:space:]]*Port[[:space:]]+[0-9]+/{print $2; exit}' \
    /etc/ssh/sshd_config.d/00-hardening.conf 2>/dev/null || true)
if [[ -z "$SSH_PORT" ]]; then
    # `| awk … exit` закрывает пайп раньше времени: источник получает SIGPIPE,
    # и под `set -o pipefail` это роняет скрипт с кодом 141. Читаем без пайпа.
    SSH_PORT=$(awk '/^port /{print $2; exit}' <(sshd -T 2>/dev/null) || true)
fi

# --- IP панели ---------------------------------------------------------------
if [[ -z "$PANEL_IP" ]]; then
    echo ""
    info "API ноды (:${NODE_API_PORT}) нужен только панели. Открытый всему миру,"
    info "он выдаёт ноду сканом IPv4 по характерному TLS-ответу Remnawave."
    info "Введи IP панели, 'any' — оставить открытым, 'skip' — не трогать UFW."
    ask "IP панели Remnawave"
    read -r PANEL_IP </dev/tty
fi

# =============================================================================
title "1 / Watchdog: проверка реального inbound (BLK-2)"
# Прежний watchdog смотрел `docker ps | grep` — то есть наличие контейнера, да
# ещё подстрокой по всему выводу. Отказ, который случался на практике (контейнер
# жив, API 2222 отвечает, панель зелёная, Xray на 443 мёртв), он не ловил вовсе.
# Версия в шапке watchdog.sh — единственный надёжный признак «файл устарел».
# Проверять по наличию /dev/tcp мало: нода с watchdog v1 уже содержит эту
# строку, и обновление до v2 (защита от шторма перезапусков) не доезжало бы.
WD_VERSION=3
if [[ -f "${OPT_DIR}/watchdog.sh" ]] \
   && grep -q "watchdog-version: ${WD_VERSION}" "${OPT_DIR}/watchdog.sh" \
   && grep -q "INBOUND_PORTS=\"${INBOUND_PORTS}\"" "${OPT_DIR}/watchdog.sh" \
   && grep -q "CONTAINER=\"${NODE_CONTAINER}\"" "${OPT_DIR}/watchdog.sh"; then
    skip "watchdog уже версии ${WD_VERSION} и проверяет ${INBOUND_PORTS} — пропускаю"
else
    backup_file "${OPT_DIR}/watchdog.sh"
    if (( DRY_RUN )); then
        echo -e "${YELLOW}    [dry-run] перезаписать ${OPT_DIR}/watchdog.sh (v${WD_VERSION}, порты ${INBOUND_PORTS})${NC}"
    else
        cat > "${OPT_DIR}/watchdog.sh" << WDEOF
#!/bin/bash
# watchdog-version: 3
# Проверяет РЕАЛЬНЫЙ inbound, а не только наличие контейнера.
set -uo pipefail
OPT_DIR="${OPT_DIR}"
LOG="/var/log/watchdog.log"
STATE="\${OPT_DIR}/.watchdog_fails"
PRIMED="\${OPT_DIR}/.watchdog_primed"   # нода хоть раз была полностью здорова
GAVEUP="\${OPT_DIR}/.watchdog_giveup"   # счётчик безрезультатных рестартов
CONTAINER="${NODE_CONTAINER}"
INBOUND_PORTS="${INBOUND_PORTS}"
FAIL_THRESHOLD=2     # рестарт только после 2 провалов подряд
MAX_RESTARTS=3       # после стольких безрезультатных — только логировать

exec 9>/run/remnanode-watchdog.lock
flock -n 9 || exit 0

log(){ echo "\$(date '+%F %T') \$*" >> "\$LOG"; }

alive=1
reason=""

docker ps --filter "name=^\${CONTAINER}\\\$" --filter status=running -q \\
    | grep -q . || { alive=0; reason="container \${CONTAINER} down"; }

if (( alive )); then
    for p in \$INBOUND_PORTS; do
        timeout 5 bash -c "exec 3<>/dev/tcp/127.0.0.1/\$p" 2>/dev/null \\
            || { alive=0; reason="port \$p not accepting"; break; }
    done
fi

if (( alive )); then
    echo 0 > "\$STATE"
    echo 0 > "\$GAVEUP"
    [[ -f "\$PRIMED" ]] || { : > "\$PRIMED"; log "primed: нода здорова, автоперезапуск включён"; }
    exit 0
fi

fails=\$(( \$(cat "\$STATE" 2>/dev/null || echo 0) + 1 ))
echo "\$fails" > "\$STATE"
log "unhealthy: \${reason} (fail \${fails}/\${FAIL_THRESHOLD})"
(( fails < FAIL_THRESHOLD )) && exit 0

# Нода НИ РАЗУ не была здоровой — идёт первичная настройка. Причина почти всегда
# в панели (не включены inbound профиля), пересоздание её не лечит, зато рвёт
# те соединения, которые уже работают.
if [[ ! -f "\$PRIMED" ]]; then
    log "НЕ перезапускаю: нода ещё ни разу не была здорова — похоже на незавершённую"
    log "настройку. Проверь в панели Nodes → Edit, что включены ВСЕ inbound профиля."
    echo 0 > "\$STATE"
    exit 0
fi

gaveup=\$(cat "\$GAVEUP" 2>/dev/null || echo 0)
if (( gaveup >= MAX_RESTARTS )); then
    log "НЕ перезапускаю: \${gaveup} перезапусков подряд не помогли (\${reason})."
    log "Нужна диагностика: bash check-node.sh"
    echo 0 > "\$STATE"
    exit 0
fi

log "restarting node (попытка \$(( gaveup + 1 ))/\${MAX_RESTARTS})"
cd "\$OPT_DIR" && docker compose up -d --force-recreate >> "\$LOG" 2>&1
echo \$(( gaveup + 1 )) > "\$GAVEUP"
echo 0 > "\$STATE"
WDEOF
        chmod +x "${OPT_DIR}/watchdog.sh"
        bash -n "${OPT_DIR}/watchdog.sh" || die "Сгенерированный watchdog.sh невалиден"
        # Нода уже работает — считаем её здоровой, иначе первый же сбой попал бы
        # в ветку «ещё ни разу не была здорова» и автолечение не включилось бы.
        : > "${OPT_DIR}/.watchdog_primed"
    fi
    ok "watchdog обновлён до v${WD_VERSION}: порты ${INBOUND_PORTS}, порог 2, предел 3 рестарта"
    note "watchdog не будет пересоздавать ноду при незавершённой настройке панели"
fi

if crontab -l 2>/dev/null | grep -q 'watchdog'; then
    skip "watchdog уже в crontab"
else
    if (( DRY_RUN )); then
        echo -e "${YELLOW}    [dry-run] добавить в crontab: */5 * * * * ${OPT_DIR}/watchdog.sh${NC}"
    else
        { crontab -l 2>/dev/null || true; echo "*/5 * * * * ${OPT_DIR}/watchdog.sh"; } \
            | grep -v '^$' | crontab -
    fi
    ok "watchdog добавлен в crontab (каждые 5 минут)"
    note "watchdog прописан в crontab"
fi

# =============================================================================
title "2 / Снятие geo-машинерии (BLK-3)"
# runetfreedom публикует .dat почти ежедневно → cmp видел разницу →
# docker compose up -d --force-recreate → все активные соединения рвались.
# Каждую ночь и синхронно на всём флоте. Ради единственного правила
# geoip:private, которому эти файлы не нужны: образ несёт свои .dat, а в
# профиле 3.10 приватные сети заданы явными CIDR.
if crontab -l 2>/dev/null | grep -q 'update-geo'; then
    if (( DRY_RUN )); then
        echo -e "${YELLOW}    [dry-run] удалить строку update-geo из crontab${NC}"
    else
        crontab -l 2>/dev/null | grep -v 'update-geo' | grep -v '^$' | crontab - || true
    fi
    ok "снят ночной geo-крон (он пересоздавал контейнер и рвал соединения)"
    note "снят ночной geo-крон — флот больше не падает синхронно"
else
    skip "geo-крона нет"
fi
if [[ -f "${OPT_DIR}/update-geo.sh" ]]; then
    run rm -f "${OPT_DIR}/update-geo.sh"
    ok "удалён update-geo.sh"
else
    skip "update-geo.sh уже отсутствует"
fi
if [[ -d "${OPT_DIR}/geodata" ]]; then
    # Файлы не удаляем: docker-compose.yml их ещё монтирует, а compose этот
    # скрипт принципиально не трогает (в нём может быть пин образа).
    info "${OPT_DIR}/geodata остаётся: его ещё монтирует docker-compose.yml."
    info "Маунты уйдут при следующем деплое deploy-remnanode.sh v3.10."
fi

# =============================================================================
title "3 / UFW: 2222 и 45876 по источнику (H-1)"
if [[ "$PANEL_IP" == "skip" ]]; then
    skip "UFW не трогаю (PANEL_IP=skip)"
elif [[ "$PANEL_IP" == "any" ]]; then
    warn "PANEL_IP=any — порт ${NODE_API_PORT} остаётся открытым всему интернету"
elif valid_ipv4 "$PANEL_IP"; then
    if ufw status 2>/dev/null | grep -qE "^${NODE_API_PORT}/tcp[[:space:]]+ALLOW( IN)?[[:space:]]+Anywhere"; then
        # ufw delete возвращает ненулевой код, если правило уже снято другим
        # прогоном — под set -e это уронило бы скрипт на ровном месте.
        run ufw delete allow "${NODE_API_PORT}/tcp" || true
        ok "убрано правило «${NODE_API_PORT} открыт всем»"
        note "порт ${NODE_API_PORT} закрыт для всех, кроме панели"
    else
        skip "правила «${NODE_API_PORT} открыт всем» нет"
    fi
    if ufw status 2>/dev/null | grep -q "${NODE_API_PORT}.*${PANEL_IP}"; then
        skip "доступ с ${PANEL_IP} к ${NODE_API_PORT} уже разрешён"
    else
        run ufw allow from "$PANEL_IP" to any port "$NODE_API_PORT" proto tcp \
            comment "Remnawave panel"
        ok "API ноды :${NODE_API_PORT} — только с ${PANEL_IP}"
    fi
    warn "ПРОВЕРЬ в панели, что нода осталась зелёной. Если позеленение пропало —"
    warn "IP панели указан неверно, вернуть можно так:"
    warn "    ufw allow ${NODE_API_PORT}/tcp"
else
    die "PANEL_IP должен быть IPv4, 'any' или 'skip' (получено: '${PANEL_IP}')"
fi

# Beszel убран из проекта: хаб отключён, его роль выполняет Prometheus на
# satx-us. На уже развёрнутых нодах агент и открытый порт остаются — снимаем.
if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "beszel-agent"; then
    run docker rm -f beszel-agent || true
    # Том с fingerprint тоже больше не нужен: возвращаться в хаб нода не будет.
    run docker volume rm beszel_agent_data || true
    ok "Beszel agent удалён"
else
    skip "Beszel agent не установлен"
fi
if ufw status 2>/dev/null | grep -qE "^${BESZEL_PORT}/tcp"; then
    run ufw delete allow "${BESZEL_PORT}/tcp" || true
    run ufw delete allow from any to any port "$BESZEL_PORT" proto tcp || true
    ok "порт ${BESZEL_PORT} закрыт"
else
    skip "порт ${BESZEL_PORT} уже закрыт"
fi

# =============================================================================
title "4 / fail2ban: восстановление цепочек (H-4)"
# ufw reset/enable перестраивает filter-таблицу своим набором, в котором цепочек
# f2b-* нет. Fail2ban об этом не узнаёт до собственного рестарта: джейл
# рапортует «enabled», а в iptables пусто — то есть защиты нет вообще.
F2B_ACTION=$(fail2ban-client get sshd actions 2>/dev/null \
    | grep -oiE '(nftables|iptables)[a-z0-9-]*' | head -1)
F2B_BANNED=$(fail2ban-client status sshd 2>/dev/null \
    | awk -F': *' '/Currently banned/{print $2}' | tr -d '[:space:]')
if iptables -S 2>/dev/null | grep -q 'f2b-'; then
    skip "цепочки f2b-* уже на месте (iptables)"
elif command -v nft >/dev/null 2>&1 && nft list ruleset 2>/dev/null | grep -qi 'f2b'; then
    skip "правила f2b уже на месте (nftables)"
elif [[ "$F2B_ACTION" == nftables* && "${F2B_BANNED:-0}" == "0" ]]; then
    # nftables-действие создаёт таблицу при первом бане. Пустая таблица при нуле
    # забаненных — норма, а не следствие ufw reset: у fail2ban своя таблица,
    # которую ufw не трогает, поэтому H-4 здесь не воспроизводится.
    skip "banaction=${F2B_ACTION}, в бане 0 — таблица создастся при первом бане"
else
    warn "правил f2b нет, в бане ${F2B_BANNED:-?} (banaction=${F2B_ACTION:-?})"
    run systemctl restart fail2ban
    (( DRY_RUN )) || sleep 2
    if (( DRY_RUN )) || fail2ban-client status sshd >/dev/null 2>&1; then
        ok "fail2ban перезапущен, джейл sshd отвечает"
        note "перезапущен fail2ban (правила бана не были применены)"
    else
        warn "джейл так и не поднялся — проверь: fail2ban-client status sshd"
    fi
fi

# Порт в джейле должен совпадать с реальным портом sshd.
if [[ -n "$SSH_PORT" ]] && [[ -f /etc/fail2ban/jail.local ]]; then
    JAILPORT=$(awk -F'= *' '/^port/{print $2; exit}' /etc/fail2ban/jail.local)
    if [[ "$JAILPORT" != "$SSH_PORT" ]]; then
        warn "в jail.local порт ${JAILPORT}, а sshd слушает ${SSH_PORT} — бан не сработает"
    else
        skip "порт в jail.local совпадает с sshd (${SSH_PORT})"
    fi
fi

# =============================================================================
title "5 / Таймзона, conntrack, logrotate"
TZNOW=$(timedatectl show -p Timezone --value 2>/dev/null || echo "?")
if [[ "$TZNOW" == "$NODE_TZ" ]]; then
    skip "таймзона уже ${NODE_TZ}"
else
    run timedatectl set-timezone "$NODE_TZ"
    ok "таймзона: ${TZNOW} → ${NODE_TZ}"
    note "таймзона выставлена в ${NODE_TZ} (было ${TZNOW})"
fi

# nf_conntrack_max ставился только через sysctl -w и терялся при ребуте.
if grep -q 'nf_conntrack_max' /etc/sysctl.d/99-remnanode.conf 2>/dev/null; then
    skip "nf_conntrack_max уже в sysctl.d"
else
    if (( DRY_RUN )); then
        echo -e "${YELLOW}    [dry-run] дописать nf_conntrack_max в /etc/sysctl.d/99-remnanode.conf${NC}"
    else
        echo "nf_conntrack" > /etc/modules-load.d/remnanode.conf
        modprobe nf_conntrack 2>/dev/null || true
        backup_file /etc/sysctl.d/99-remnanode.conf
        echo "net.netfilter.nf_conntrack_max = 131072" >> /etc/sysctl.d/99-remnanode.conf
        sysctl -p /etc/sysctl.d/99-remnanode.conf >/dev/null 2>&1 || true
    fi
    ok "nf_conntrack_max закреплён (переживёт ребут)"
    note "nf_conntrack_max больше не теряется при ребуте"
fi

if [[ -f /etc/logrotate.d/remnanode ]]; then
    skip "logrotate уже настроен"
else
    if (( DRY_RUN )); then
        echo -e "${YELLOW}    [dry-run] создать /etc/logrotate.d/remnanode${NC}"
    else
        cat > /etc/logrotate.d/remnanode << 'LREOF'
/var/log/watchdog.log
/var/log/geo-update.log
/var/log/update-node.log
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
    fi
    ok "logrotate: логи ноды ротируются (4 недели)"
    note "включена ротация логов ноды"
fi

# =============================================================================
title "6 / Права на секреты"
for f in "${OPT_DIR}/keys.txt" "${OPT_DIR}/.env" "${OPT_DIR}/config-profile.json" \
         /var/log/deploy-remnanode.log; do
    [[ -f "$f" ]] || continue
    PERM=$(stat -c '%a' "$f" 2>/dev/null)
    if [[ "$PERM" == "600" ]]; then
        skip "$(basename "$f"): ${PERM}"
    else
        run chmod 600 "$f"
        ok "$(basename "$f"): ${PERM} → 600"
        note "исправлены права на $(basename "$f")"
    fi
done

# =============================================================================
title "7 / Проверка после правок"
for p in $INBOUND_PORTS; do
    if timeout 5 bash -c "exec 3<>/dev/tcp/127.0.0.1/${p}" 2>/dev/null; then
        ok "inbound :${p} принимает соединения"
    else
        warn "inbound :${p} не отвечает — проверь docker logs remnawave-node"
    fi
done
if docker ps --filter "name=^${NODE_CONTAINER}$" --filter status=running -q | grep -q .; then
    ok "контейнер ${NODE_CONTAINER} работает (не пересоздавался)"
else
    warn "контейнер ${NODE_CONTAINER} не запущен"
fi

# =============================================================================
title "Итог"
if (( ${#CHANGED[@]} == 0 )); then
    ok "Изменений не потребовалось — нода уже соответствует v3.10"
else
    echo -e "${GREEN}  Сделано на этой ноде:${NC}"
    for c in "${CHANGED[@]}"; do echo -e "${GREEN}    • ${c}${NC}"; done
fi

echo ""
echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║  ОСТАЛОСЬ СДЕЛАТЬ РУКАМИ В ПАНЕЛИ — скрипт туда не ходит${NC}"
echo -e "${YELLOW}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${YELLOW}║  BLK-1. Config Profile → routing.rules: последнее правило${NC}"
echo -e "${YELLOW}║    {\"ip\":[\"geoip:private\"],\"outboundTag\":\"DIRECT\"}${NC}"
echo -e "${YELLOW}║  заменить на BLOCK с явным списком приватных сетей.${NC}"
echo -e "${YELLOW}║  domainStrategy IPIfNonMatch — ОСТАВИТЬ.${NC}"
echo -e "${YELLOW}║${NC}"
echo -e "${YELLOW}║  H-2. В каждом inbound: \"sniffing\": {\"enabled\": true,${NC}"
echo -e "${YELLOW}║    \"destOverride\": [\"http\",\"tls\"], \"routeOnly\": true}${NC}"
echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════╝${NC}"

# Локальная копия профиля — не источник истины (он в панели), но если здесь
# всё ещё DIRECT, то и в панели почти наверняка тоже.
PROFILE="${OPT_DIR}/config-profile.json"
if [[ -f "$PROFILE" ]] && command -v jq >/dev/null 2>&1; then
    if jq -e '.routing.rules[] | select(.outboundTag == "DIRECT") | select((.ip // []) | length > 0)' \
            "$PROFILE" >/dev/null 2>&1; then
        echo ""
        warn "В локальной копии ${PROFILE} правило DIRECT для IP ещё на месте —"
        warn "значит в панели оно, скорее всего, тоже. Это BLK-1, правь сейчас."
    fi
fi

echo ""
info "Полная диагностика: sudo bash check-node.sh"
info "Лог этого прогона: ${LOG_FILE}"
echo ""
