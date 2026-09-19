#!/usr/bin/env bash
# =============================================================================
# update-bot.sh v1.0 — обновляет бота продаж (Bedolaga) и возвращает наши правки.
#
# Зачем отдельный скрипт: бот чужой, обновляется из репозитория автора, а поверх
# него лежат три наши правки в отслеживаемых файлах. Каждое обновление было
# ритуалом из шести шагов по памятке KAK-OBNOVLYAT.txt, и любой пропущенный шаг
# означал потерянную правку. Скрипт проходит памятку сам и сам себя проверяет.
#
# Запуск на сервере бота (aeza-nl-bots):
#   sudo bash update-bot.sh               # обновить до origin/main
#   sudo DRY_RUN=1 bash update-bot.sh     # только показать, что будет сделано
#   sudo FORCE=1 bash update-bot.sh       # пересобрать, даже если обновлять нечего
#
# Что делает:
#   1. Копия в /opt/bedolaga-backup-<дата>/: дамп базы, .env, compose, locales,
#      правленые файлы, наши правки одним патчем, текущий коммит.
#   2. Снимает правки, обновляет код (только fast-forward), возвращает правки.
#      Если правка не ложится на новый код, откатывает код к прежнему коммиту,
#      возвращает правки и останавливается. Контейнер при этом не трогает:
#      бот продолжает работать на старой версии.
#   3. Пересобирает и поднимает только сервис bot, ждёт healthy.
#   4. Проверяет, что правки доехали до контейнера, а locales не изменились.
#
# НЕ трогает: .env, docker-compose.override.yml, Caddyfile, базу (кроме дампа),
# каталог locales/ (он вне git, обновление его не задевает).
#
# ЧЕГО ОН НЕ УМЕЕТ. Откатить миграции базы. Если новая версия поднялась
# нездоровой, скрипт скажет, где лежит дамп и на какой коммит вернуться, но
# восстанавливать базу будет человек.
# =============================================================================

set -Eeuo pipefail

readonly BOT_DIR="${BOT_DIR:-/opt/remnawave-bedolaga-telegram-bot}"
readonly BOT_CONTAINER="remnawave_bot"
readonly DB_CONTAINER="remnawave_bot_db"
readonly BOT_SERVICE="bot"
readonly REPO_OWNER="admin:admin"
readonly HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-300}"
readonly LOG_FILE="/var/log/update-bot.log"
DRY_RUN="${DRY_RUN:-0}"
FORCE="${FORCE:-0}"

# Правки в отслеживаемых файлах. Текстовые едут патчем, логотип копией:
# бинарный файл в патч без --binary не ложится, а копия проще и надёжнее.
readonly PATCHED_TEXT=(
    "app/keyboards/inline.py"
    "app/services/monitoring_service.py"
)
readonly PATCHED_BINARY=(
    "vpn_logo.png"
)
# Строка, по которой видно, что правка автоплатежа доехала до контейнера.
readonly MARKER_FILE="app/services/monitoring_service.py"
readonly MARKER_TEXT="Не хватает"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

ok()    { echo -e "${GREEN}  ✔ $1${NC}"; }
info()  { echo -e "${CYAN}  ℹ $1${NC}"; }
warn()  { echo -e "${YELLOW}  ⚠ $1${NC}"; }
die()   { echo -e "${RED}  ✖ $1${NC}"; exit 1; }
title() { echo -e "\n${BLUE}━━━ $1 ━━━${NC}"; }

PROBLEMS=()
problem() { PROBLEMS+=("$1"); warn "$1"; }

# В DRY_RUN печатаем команду вместо выполнения.
run() {
    if (( DRY_RUN )); then
        echo -e "${YELLOW}    [dry-run] $*${NC}"
    else
        "$@"
    fi
}

g() { git -C "$BOT_DIR" -c safe.directory="$BOT_DIR" "$@"; }

md5_of() { md5sum "$1" | cut -d' ' -f1; }

# ----------------------------------------------------------------------------
title "0. Проверка перед началом"

[[ $EUID -eq 0 ]] || die "Нужен root: в .git есть каталоги от root, под admin git падает. Запустите через sudo."
[[ -d "$BOT_DIR/.git" ]] || die "Не найден репозиторий бота: $BOT_DIR"
command -v docker >/dev/null || die "Нет docker"
docker inspect "$BOT_CONTAINER" >/dev/null 2>&1 || die "Нет контейнера $BOT_CONTAINER"
docker inspect "$DB_CONTAINER" >/dev/null 2>&1 || die "Нет контейнера $DB_CONTAINER"

if (( ! DRY_RUN )); then
    exec > >(tee -a "$LOG_FILE") 2>&1
    echo "=== $(date '+%F %T') update-bot.sh ==="
fi

# Кроме наших правок в рабочей копии не должно быть ничего изменённого:
# иначе merge упрётся в чужую правку, про которую скрипт не знает.
mapfile -t DIRTY < <(g status --porcelain --untracked-files=no | awk '{print $2}')
for f in "${DIRTY[@]}"; do
    known=0
    for p in "${PATCHED_TEXT[@]}" "${PATCHED_BINARY[@]}"; do
        [[ "$f" == "$p" ]] && known=1
    done
    (( known )) || die "В рабочей копии изменён файл, которого нет в списке правок: $f. Добавьте его в PATCHED_* или верните к исходному."
done

for p in "${PATCHED_TEXT[@]}" "${PATCHED_BINARY[@]}"; do
    if g diff --quiet -- "$p"; then
        problem "Правки в $p сейчас НЕТ (файл совпадает с исходным). Возвращать будет нечего."
    fi
done

OLD_COMMIT="$(g rev-parse HEAD)"
OLD_VERSION="$(g describe --tags 2>/dev/null || echo '?')"
info "Сейчас: ${OLD_COMMIT:0:8} ($OLD_VERSION)"

# fetch выполняется и в пробном прогоне: рабочую копию он не меняет, а без
# него прогон сравнивал бы с устаревшим origin/main. Пишет в .git от root,
# поэтому владельца возвращаем при любом выходе.
trap 'chown -R "$REPO_OWNER" "$BOT_DIR/.git" 2>/dev/null || true; [[ -n "${TMP_PATCH:-}" ]] && rm -f "$TMP_PATCH"' EXIT
g fetch --quiet --tags origin
NEW_COMMIT="$(g rev-parse origin/main)"
NEW_VERSION="$(g describe --tags origin/main 2>/dev/null || echo '?')"
info "В origin/main: ${NEW_COMMIT:0:8} ($NEW_VERSION)"

if [[ "$OLD_COMMIT" == "$NEW_COMMIT" ]] && (( ! FORCE )); then
    ok "Обновлять нечего. FORCE=1 пересоберёт контейнер на текущем коде."
    exit 0
fi

if ! g merge-base --is-ancestor "$OLD_COMMIT" "$NEW_COMMIT"; then
    die "origin/main не продолжает текущий коммит (fast-forward невозможен). Разбираться руками."
fi

COMMITS_BEHIND="$(g rev-list --count "$OLD_COMMIT..$NEW_COMMIT")"
info "Новых коммитов: $COMMITS_BEHIND"

# ----------------------------------------------------------------------------
title "1. Копия"

BACKUP_DIR="/opt/bedolaga-backup-$(date '+%Y%m%d-%H%M')"
info "Каталог: $BACKUP_DIR"
run mkdir -p "$BACKUP_DIR"
run chmod 700 "$BACKUP_DIR"

if (( DRY_RUN )); then
    echo -e "${YELLOW}    [dry-run] pg_dump → $BACKUP_DIR/baza-do-obnovleniya.sql${NC}"
else
    docker exec "$DB_CONTAINER" sh -c 'pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB"' \
        > "$BACKUP_DIR/baza-do-obnovleniya.sql"
    [[ -s "$BACKUP_DIR/baza-do-obnovleniya.sql" ]] || die "Дамп базы пустой. Обновление остановлено, ничего не изменено."
    ok "Дамп базы: $(du -h "$BACKUP_DIR/baza-do-obnovleniya.sql" | cut -f1)"
fi

for f in .env docker-compose.yml docker-compose.override.yml Caddyfile; do
    [[ -f "$BOT_DIR/$f" ]] && run cp -p "$BOT_DIR/$f" "$BACKUP_DIR/"
done
for p in "${PATCHED_TEXT[@]}" "${PATCHED_BINARY[@]}"; do
    run cp -p "$BOT_DIR/$p" "$BACKUP_DIR/"
done
run tar -czf "$BACKUP_DIR/locales.tar.gz" -C "$BOT_DIR" locales

PATCH_FILE="$BACKUP_DIR/nashi-pravki.patch"
if (( DRY_RUN )); then
    echo -e "${YELLOW}    [dry-run] git diff → $PATCH_FILE${NC}"
    TMP_PATCH="$(mktemp)"
    PATCH_FILE="$TMP_PATCH"
fi
g diff -- "${PATCHED_TEXT[@]}" > "$PATCH_FILE"
(( DRY_RUN )) || echo "$OLD_COMMIT ($OLD_VERSION)" > "$BACKUP_DIR/tekushchij-kommit.txt"

LOCALES_MD5_BEFORE="$(md5_of "$BOT_DIR/locales/ru.json")"
ok "Копия готова"

# ----------------------------------------------------------------------------
title "2. Код: снять правки, обновить, вернуть правки"

# Сначала проверяем на чистой копии нового кода, ляжет ли патч. Рабочую
# копию при этом не трогаем: если не ляжет, останавливаемся, ничего не сломав.
if [[ -s "$PATCH_FILE" ]]; then
    CHECK_DIR="$(mktemp -d)"
    g worktree add --detach "$CHECK_DIR" "$NEW_COMMIT" >/dev/null 2>&1
    if git -C "$CHECK_DIR" apply --check "$PATCH_FILE" 2>/dev/null; then
        ok "Правки ложатся на новый код без конфликтов"
        PATCH_MODE="plain"
    elif git -C "$CHECK_DIR" apply --check --3way "$PATCH_FILE" 2>/dev/null; then
        ok "Правки ложатся на новый код трёхсторонним слиянием"
        PATCH_MODE="3way"
    else
        g worktree remove --force "$CHECK_DIR" >/dev/null 2>&1 || true
        die "Автор изменил те же места, что и наши правки: патч на новый код не ложится. Ничего не изменено, бот работает на ${OLD_COMMIT:0:8}. Патч лежит в $PATCH_FILE, переносить руками."
    fi
    g worktree remove --force "$CHECK_DIR" >/dev/null 2>&1 || true
else
    PATCH_MODE="none"
    warn "Патч пустой: текстовых правок нет"
fi

if (( DRY_RUN )); then
    echo -e "${YELLOW}    [dry-run] checkout правленых файлов, merge --ff-only, apply патча, копия логотипа, chown .git${NC}"
else
    rollback_code() {
        warn "Откатываю код к ${OLD_COMMIT:0:8} и возвращаю правки"
        g reset --hard "$OLD_COMMIT" >/dev/null
        [[ -s "$PATCH_FILE" ]] && g apply "$PATCH_FILE"
        for p in "${PATCHED_BINARY[@]}"; do cp -p "$BACKUP_DIR/$(basename "$p")" "$BOT_DIR/$p"; done
        chown -R "$REPO_OWNER" "$BOT_DIR/.git"
    }

    g checkout -- "${PATCHED_TEXT[@]}" "${PATCHED_BINARY[@]}"
    if ! g merge --ff-only "$NEW_COMMIT" >/dev/null; then
        rollback_code
        die "merge --ff-only не прошёл. Код и правки возвращены, контейнер не тронут."
    fi

    if [[ "$PATCH_MODE" == "plain" ]]; then
        g apply "$PATCH_FILE" || { rollback_code; die "Патч не лёг. Код и правки возвращены, контейнер не тронут."; }
    elif [[ "$PATCH_MODE" == "3way" ]]; then
        g apply --3way "$PATCH_FILE" || { rollback_code; die "Патч не лёг. Код и правки возвращены, контейнер не тронут."; }
        # --3way кладёт результат в индекс. Правки у нас живут незакоммиченными.
        g reset -q -- "${PATCHED_TEXT[@]}"
    fi
    for p in "${PATCHED_BINARY[@]}"; do
        cp -p "$BACKUP_DIR/$(basename "$p")" "$BOT_DIR/$p"
    done
    chown -R "$REPO_OWNER" "$BOT_DIR/.git"
    ok "Код: ${OLD_COMMIT:0:8} → ${NEW_COMMIT:0:8}, правки на месте"
fi

# ----------------------------------------------------------------------------
title "3. Сборка и запуск"

run docker compose --project-directory "$BOT_DIR" build "$BOT_SERVICE"
run docker compose --project-directory "$BOT_DIR" up -d "$BOT_SERVICE"

if (( ! DRY_RUN )); then
    info "Жду healthy, не дольше ${HEALTH_TIMEOUT} с"
    waited=0
    state="starting"
    while (( waited < HEALTH_TIMEOUT )); do
        state="$(docker inspect "$BOT_CONTAINER" --format '{{.State.Status}}/{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}')"
        [[ "$state" == "running/healthy" ]] && break
        [[ "$state" == exited/* || "$state" == dead/* ]] && break
        sleep 5; waited=$(( waited + 5 ))
    done
    if [[ "$state" == "running/healthy" ]]; then
        ok "Контейнер healthy через ${waited} с"
    else
        echo
        docker logs --tail 40 "$BOT_CONTAINER" 2>&1 | sed 's/^/    /'
        die "Контейнер не стал healthy (состояние: $state). Миграции базы скрипт не откатывает. Дамп: $BACKUP_DIR/baza-do-obnovleniya.sql, прежний коммит: $OLD_COMMIT."
    fi
fi

# ----------------------------------------------------------------------------
title "4. Проверка правок"

if (( DRY_RUN )); then
    info "[dry-run] сверка md5 правленых файлов с контейнером, строка «$MARKER_TEXT», md5 locales/ru.json, alembic в журнале"
else
    for p in "${PATCHED_TEXT[@]}" "${PATCHED_BINARY[@]}"; do
        host_md5="$(md5_of "$BOT_DIR/$p")"
        cont_md5="$(docker exec "$BOT_CONTAINER" md5sum "/app/$p" 2>/dev/null | cut -d' ' -f1 || true)"
        if [[ -n "$cont_md5" && "$host_md5" == "$cont_md5" ]]; then
            ok "$p в контейнере совпадает с правленым"
        else
            problem "$p в контейнере НЕ совпадает с правленым файлом на диске"
        fi
    done

    if docker exec "$BOT_CONTAINER" grep -q "$MARKER_TEXT" "/app/$MARKER_FILE"; then
        ok "Строка «$MARKER_TEXT» в контейнере есть"
    else
        problem "Строки «$MARKER_TEXT» в контейнере нет: правка автоплатежа потерялась"
    fi

    if [[ "$(md5_of "$BOT_DIR/locales/ru.json")" == "$LOCALES_MD5_BEFORE" ]]; then
        ok "locales/ru.json не изменился"
    else
        problem "locales/ru.json изменился за время обновления. Копия: $BACKUP_DIR/locales.tar.gz"
    fi

    if docker logs --since 10m "$BOT_CONTAINER" 2>&1 | grep -iE "alembic.*(error|fail)|Traceback" | head -3 | grep -q .; then
        problem "В журнале за последние 10 минут есть ошибки alembic или Traceback: docker logs $BOT_CONTAINER"
    else
        ok "Ошибок alembic и Traceback в журнале нет"
    fi
fi

# ----------------------------------------------------------------------------
title "Итог"

if (( DRY_RUN )); then
    info "Это был пробный прогон: ничего не изменено."
    exit 0
fi

echo "  Версия: $OLD_VERSION → $(g describe --tags 2>/dev/null || echo '?')"
echo "  Копия:  $BACKUP_DIR"
if (( ${#PROBLEMS[@]} )); then
    echo
    warn "Требует внимания:"
    for p in "${PROBLEMS[@]}"; do echo "    - $p"; done
    exit 2
fi
ok "Обновление прошло, все правки на месте"
