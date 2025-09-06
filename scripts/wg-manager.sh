#!/bin/bash

# WireGuard Obfuscation Setup - Main Management Script
# Управление Docker-based WireGuard сервером с обфускацией

set -e

# Определение директорий
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DOCKER_DIR="$PROJECT_DIR/docker"
ENV_FILE="$PROJECT_DIR/.env"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Функция показа лого
show_logo() {
    echo -e "${CYAN}"
    cat << "EOF"
    ╦═╗┌─┐┬ ┬┌┬┐┌─┐╦═╗┬ ┬┌─┐  ╦  ╦╔═╗╔╗╔
    ╠╦╝│ ││ │ │ ├┤ ╠╦╝│ │└─┐  ╚╗╔╝╠═╝║║║
    ╩╚═└─┘└─┘ ┴ └─┘╩╚═└─┘└─┘   ╚╝ ╩  ╝╚╝
                    Maximum Obfuscation VPN
EOF
    echo -e "${NC}"
}

# Функция проверки Docker
check_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}Docker не установлен. Установите Docker и повторите попытку.${NC}"
        exit 1
    fi

    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        echo -e "${RED}Docker Compose не установлен. Установите Docker Compose и повторите попытку.${NC}"
        exit 1
    fi
}

# Функция проверки конфигурации
check_config() {
    if [[ ! -f "$ENV_FILE" ]]; then
        echo -e "${YELLOW}Файл .env не найден.${NC}"
        echo -e "${BLUE}Запустите настройку: ${GREEN}make setup${NC} или ${GREEN}./setup.sh${NC}"
        exit 1
    fi
}

# Функция загрузки переменных окружения
load_env() {
    if [[ -f "$ENV_FILE" ]]; then
        set -a
        source "$ENV_FILE"
        set +a
    fi
}

# Docker Compose команда (с поддержкой старой и новой версии)
docker_compose() {
    if command -v docker-compose &> /dev/null; then
        docker-compose -f "$PROJECT_DIR/docker-compose.yml" "$@"
    else
        docker compose -f "$PROJECT_DIR/docker-compose.yml" "$@"
    fi
}

# Функция запуска сервисов
start_services() {
    echo -e "${BLUE}Запуск WireGuard Obfuscation Setup...${NC}"

    check_docker
    check_config
    load_env

    cd "$PROJECT_DIR"

    # Создание volumes если их нет
    docker volume create wg-obfuscation_wg_data 2>/dev/null || true
    docker volume create wg-obfuscation_cloak_data 2>/dev/null || true
    docker volume create wg-obfuscation_generated_configs 2>/dev/null || true

    # Запуск основных сервисов
    docker_compose up -d wg-easy stats

    # Запуск Cloak если включен
    if [[ "${CLOAK_ENABLED:-false}" == "true" ]]; then
        echo -e "${YELLOW}Запуск Cloak обфускации...${NC}"
        docker_compose --profile cloak up -d cloak
    fi

    # Ожидание запуска
    echo -e "${YELLOW}Ожидание запуска сервисов...${NC}"
    sleep 10

    # Проверка статуса
    if docker_compose ps | grep -q "Up"; then
        echo -e "${GREEN}Сервисы запущены успешно!${NC}"
        show_access_info
    else
        echo -e "${RED}Ошибка запуска сервисов${NC}"
        docker_compose logs
        exit 1
    fi
}

# Функция остановки сервисов
stop_services() {
    echo -e "${YELLOW}Остановка сервисов...${NC}"

    cd "$PROJECT_DIR"
    docker_compose down

    echo -e "${GREEN}Сервисы остановлены${NC}"
}

# Функция перезапуска сервисов
restart_services() {
    echo -e "${YELLOW}Перезапуск сервисов...${NC}"
    stop_services
    sleep 3
    start_services
}

# Функция показа статуса
show_status() {
    check_config
    load_env

    echo -e "${CYAN}=== Статус WireGuard Obfuscation Setup ===${NC}"
    echo

    cd "$PROJECT_DIR"

    # Статус контейнеров
    echo -e "${YELLOW}Контейнеры:${NC}"
    docker_compose ps
    echo

    # Информация о доступе
    if docker_compose ps | grep -q "wg-easy.*Up"; then
        show_access_info
    fi

    # Статистика WireGuard
    echo -e "${YELLOW}WireGuard статистика:${NC}"
    if docker_compose exec -T wg-easy wg show 2>/dev/null; then
        echo -e "${GREEN}WireGuard работает${NC}"
    else
        echo -e "${RED}WireGuard не доступен${NC}"
    fi
    echo

    # Docker статистика
    echo -e "${YELLOW}Использование ресурсов:${NC}"
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" $(docker_compose ps -q) 2>/dev/null || echo "Контейнеры не запущены"
}

# Функция показа информации о доступе
show_access_info() {
    load_env

    echo -e "${CYAN}=== Информация о доступе ===${NC}"
    echo -e "${GREEN}Веб-интерфейс wg-easy:${NC}"
    echo -e "  URL: ${BLUE}http://${SERVER_ENDPOINT:-localhost}:${WEB_PORT:-51821}${NC}"
    echo -e "  Пароль: ${PURPLE}${WG_EASY_PASSWORD}${NC}"
    echo

    if [[ -n "${STATS_PORT}" ]]; then
        echo -e "${GREEN}Статистика:${NC}"
        echo -e "  URL: ${BLUE}http://${SERVER_ENDPOINT:-localhost}:${STATS_PORT:-8080}${NC}"
        echo
    fi

    echo -e "${GREEN}Управление:${NC}"
    echo -e "  ${BLUE}make status${NC}    - Проверить статус"
    echo -e "  ${BLUE}make logs${NC}      - Просмотр логов"
    echo -e "  ${BLUE}make monitor${NC}   - Мониторинг в реальном времени"
    echo
}

# Функция просмотра логов
show_logs() {
    check_config
    cd "$PROJECT_DIR"

    local service=${1:-""}

    if [[ -n "$service" ]]; then
        echo -e "${BLUE}Логи сервиса $service:${NC}"
        docker_compose logs -f --tail=50 "$service"
    else
        echo -e "${BLUE}Логи всех сервисов:${NC}"
        docker_compose logs -f --tail=50
    fi
}

# Функция создания клиентской конфигурации
create_client_config() {
    local type=${1:-"obfuscated"}
    local name=${2:-"client-$(date +%s)"}

    check_config
    load_env

    echo -e "${BLUE}Создание $type конфигурации для клиента: $name${NC}"

    cd "$PROJECT_DIR"

    # Запуск генератора конфигов
    docker_compose --profile generator run --rm config-generator "$type" "$name"

    # Копирование конфигурации из volume
    echo -e "${YELLOW}Копирование конфигурации...${NC}"

    # Создание локальной директории для конфигов
    mkdir -p "$PROJECT_DIR/generated-configs"

    # Копирование из Docker volume
    docker run --rm -v wg-obfuscation_generated_configs:/data -v "$PROJECT_DIR/generated-configs":/output alpine cp -r /data/ /output/ 2>/dev/null || {
        echo -e "${YELLOW}Конфигурация создана в контейнере. Используйте веб-интерфейс для получения.${NC}"
    }

    echo -e "${GREEN}Конфигурация создана!${NC}"
    echo -e "${BLUE}Используйте веб-интерфейс wg-easy для получения QR-кода и файла конфигурации.${NC}"
}

# Функция мониторинга
monitor_connections() {
    check_config
    load_env

    echo -e "${CYAN}Мониторинг WireGuard подключений (Ctrl+C для выхода)${NC}"
    echo

    cd "$PROJECT_DIR"

    while true; do
        clear
        echo -e "${CYAN}=== WireGuard Connections Monitor - $(date) ===${NC}"
        echo

        # Статус контейнеров
        echo -e "${YELLOW}Контейнеры:${NC}"
        docker_compose ps --format="table {{.Name}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "Ошибка получения статуса"
        echo

        # WireGuard статистика
        echo -e "${YELLOW}WireGuard интерфейс:${NC}"
        docker_compose exec -T wg-easy wg show 2>/dev/null || echo "WireGuard недоступен"
        echo

        # Docker статистика
        echo -e "${YELLOW}Ресурсы:${NC}"
        docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" $(docker_compose ps -q) 2>/dev/null || echo "Статистика недоступна"

        sleep 5
    done
}

# Функция диагностики
run_diagnostics() {
    echo -e "${BLUE}Запуск диагностики WireGuard Obfuscation Setup...${NC}"
    echo

    # Проверка Docker
    echo -e "${YELLOW}Проверка Docker:${NC}"
    if command -v docker &> /dev/null; then
        echo -e "${GREEN}✓ Docker установлен: $(docker --version)${NC}"
    else
        echo -e "${RED}✗ Docker не установлен${NC}"
    fi

    if command -v docker-compose &> /dev/null || docker compose version &> /dev/null; then
        echo -e "${GREEN}✓ Docker Compose доступен${NC}"
    else
        echo -e "${RED}✗ Docker Compose не установлен${NC}"
    fi
    echo

    # Проверка конфигурации
    echo -e "${YELLOW}Проверка конфигурации:${NC}"
    if [[ -f "$ENV_FILE" ]]; then
        echo -e "${GREEN}✓ Файл .env найден${NC}"

        # Проверка основных переменных
        load_env
        [[ -n "$SERVER_ENDPOINT" ]] && echo -e "${GREEN}✓ SERVER_ENDPOINT: $SERVER_ENDPOINT${NC}" || echo -e "${RED}✗ SERVER_ENDPOINT не задан${NC}"
        [[ -n "$WG_EASY_PASSWORD" ]] && echo -e "${GREEN}✓ WG_EASY_PASSWORD задан${NC}" || echo -e "${RED}✗ WG_EASY_PASSWORD не задан${NC}"
        [[ -n "$WEB_PORT" ]] && echo -e "${GREEN}✓ WEB_PORT: $WEB_PORT${NC}" || echo -e "${RED}✗ WEB_PORT не задан${NC}"
    else
        echo -e "${RED}✗ Файл .env не найден${NC}"
        echo -e "${BLUE}  Запустите: make setup или ./setup.sh${NC}"
    fi
    echo

    # Проверка контейнеров
    if [[ -f "$ENV_FILE" ]]; then
        echo -e "${YELLOW}Проверка сервисов:${NC}"
        cd "$PROJECT_DIR"

        if docker_compose ps | grep -q "Up"; then
            echo -e "${GREEN}✓ Контейнеры запущены${NC}"
            docker_compose ps
            echo

            # Проверка доступности веб-интерфейса
            echo -e "${YELLOW}Проверка доступности:${NC}"
            if curl -s -o /dev/null -w "%{http_code}" "http://localhost:${WEB_PORT:-51821}" | grep -q "200\|302\|401"; then
                echo -e "${GREEN}✓ Веб-интерфейс доступен на порту ${WEB_PORT:-51821}${NC}"
            else
                echo -e "${RED}✗ Веб-интерфейс недоступен${NC}"
            fi

            # Проверка WireGuard
            if docker_compose exec -T wg-easy wg show &> /dev/null; then
                echo -e "${GREEN}✓ WireGuard интерфейс работает${NC}"
            else
                echo -e "${RED}✗ WireGuard интерфейс недоступен${NC}"
            fi
        else
            echo -e "${RED}✗ Контейнеры не запущены${NC}"
            echo -e "${BLUE}  Запустите: make start${NC}"
        fi
    fi

    echo
    echo -e "${CYAN}Диагностика завершена${NC}"
}

# Функция показа справки
show_help() {
    show_logo
    echo -e "${YELLOW}Использование: $0 [команда]${NC}"
    echo
    echo -e "${CYAN}Доступные команды:${NC}"
    echo -e "  ${GREEN}start${NC}                    - Запустить все сервисы"
    echo -e "  ${GREEN}stop${NC}                     - Остановить все сервисы"
    echo -e "  ${GREEN}restart${NC}                  - Перезапустить сервисы"
    echo -e "  ${GREEN}status${NC}                   - Показать статус сервисов"
    echo -e "  ${GREEN}logs [сервис]${NC}            - Показать логи (все или конкретного сервиса)"
    echo -e "  ${GREEN}monitor${NC}                  - Мониторинг в реальном времени"
    echo -e "  ${GREEN}diagnostics${NC}              - Запустить диагностику"
    echo
    echo -e "${CYAN}Управление клиентами:${NC}"
    echo -e "  ${GREEN}create-client [тип] [имя]${NC} - Создать клиентскую конфигурацию"
    echo -e "    Типы: mobile, router, desktop, https, obfuscated"
    echo
    echo -e "${CYAN}Примеры:${NC}"
    echo -e "  $0 start"
    echo -e "  $0 create-client mobile phone1"
    echo -e "  $0 create-client router keenetic-home"
    echo -e "  $0 logs wg-easy"
    echo -e "  $0 monitor"
    echo
    echo -e "${YELLOW}Для первоначальной настройки используйте:${NC}"
    echo -e "  ${BLUE}make setup${NC} или ${BLUE}./setup.sh${NC}"
}

# Основная логика
main() {
    case "${1:-help}" in
        start)
            start_services
            ;;
        stop)
            stop_services
            ;;
        restart)
            restart_services
            ;;
        status)
            show_status
            ;;
        logs)
            show_logs "$2"
            ;;
        monitor)
            monitor_connections
            ;;
        diagnostics)
            run_diagnostics
            ;;
        create-client)
            create_client_config "$2" "$3"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo -e "${RED}Неизвестная команда: $1${NC}"
            echo
            show_help
            exit 1
            ;;
    esac
}

# Запуск
main "$@"
