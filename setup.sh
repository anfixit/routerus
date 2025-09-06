#!/bin/bash

# WireGuard Maximum Obfuscation Setup - Interactive Configuration
# Автоматическая настройка .env файла с генерацией ключей

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Файлы
ENV_FILE=".env"
ENV_EXAMPLE=".env.example"

# Лого
show_logo() {
    echo -e "${CYAN}"
    cat << "EOF"
╦ ╦┬┬─┐┌─┐╔═╗┬ ┬┌─┐┬─┐┌┬┐  ╔═╗┌┐ ┌─┐┬ ┬┌─┐┌─┐┌─┐┌┬┐┬┌─┐┌┐┌
║║║││├┬┘├┤ ║ ╦│ │├─┤├┬┘ ││  ║ ║├┴┐├┤ │ │└─┐│  ├─┤ │ ││ ││││
╚╩╝┴┴┴└─└─┘╚═╝└─┘┴ ┴┴└──┴┘  ╚═╝└─┘└  └─┘└─┘└─┘┴ ┴ ┴ ┴└─┘┘└┘
                 Docker Setup - Maximum Security VPN
EOF
    echo -e "${NC}"
}

# Проверка наличия .env
check_env_exists() {
    if [[ -f "$ENV_FILE" ]]; then
        echo -e "${YELLOW}Найден существующий .env файл${NC}"
        echo -e "${BLUE}1)${NC} Использовать существующую конфигурацию"
        echo -e "${BLUE}2)${NC} Создать новую конфигурацию"
        echo -e "${BLUE}3)${NC} Отредактировать существующую"
        echo
        read -p "Выберите действие (1-3): " choice

        case $choice in
            1)
                echo -e "${GREEN}Используется существующая конфигурация${NC}"
                return 0
                ;;
            2)
                echo -e "${YELLOW}Создается новая конфигурация...${NC}"
                rm -f "$ENV_FILE"
                ;;
            3)
                echo -e "${BLUE}Режим редактирования существующей конфигурации${NC}"
                return 2
                ;;
            *)
                echo -e "${RED}Неверный выбор, создается новая конфигурация${NC}"
                rm -f "$ENV_FILE"
                ;;
        esac
    fi
    return 1
}

# Генерация случайных значений
generate_random_values() {
    # Magic headers (случайные значения от 50 до 200)
    S1=$((RANDOM % 150 + 50))
    S2=$((RANDOM % 150 + 50))

    # Magic hashes (случайные 10-значные числа)
    H1=$(openssl rand -hex 5 | tr 'a-f' '0-9')
    H2=$(openssl rand -hex 5 | tr 'a-f' '0-9')
    H3=$(openssl rand -hex 5 | tr 'a-f' '0-9')
    H4=$(openssl rand -hex 5 | tr 'a-f' '0-9')

    echo -e "${GREEN}Сгенерированы случайные параметры обфускации:${NC}"
    echo -e "  S1: ${CYAN}$S1${NC}, S2: ${CYAN}$S2${NC}"
    echo -e "  H1: ${CYAN}$H1${NC}, H2: ${CYAN}$H2${NC}"
    echo -e "  H3: ${CYAN}$H3${NC}, H4: ${CYAN}$H4${NC}"
}

# Генерация безопасного пароля
generate_password() {
    local length=${1:-16}
    openssl rand -base64 $length | tr -d "=+/" | cut -c1-$length
}

# Получение внешнего IP
get_external_ip() {
    local ip
    ip=$(curl -s https://ipinfo.io/ip 2>/dev/null || curl -s https://api.ipify.org 2>/dev/null || curl -s https://ifconfig.me 2>/dev/null)
    echo "$ip"
}

# Интерактивная настройка
interactive_setup() {
    echo -e "${YELLOW}=== Конфигурация WireGuard Obfuscation Setup ===${NC}"
    echo

    # Автоопределение внешнего IP
    external_ip=$(get_external_ip)
    if [[ -n "$external_ip" ]]; then
        echo -e "${GREEN}Автоматически определен внешний IP: $external_ip${NC}"
        read -p "Использовать этот IP или ввести домен? [IP/домен]: " server_choice
        if [[ "$server_choice" =~ ^[Dd] ]]; then
            read -p "Введите ваш домен: " SERVER_ENDPOINT
        else
            SERVER_ENDPOINT="$external_ip"
        fi
    else
        read -p "Введите внешний IP адрес или домен сервера: " SERVER_ENDPOINT
    fi

    while [[ -z "$SERVER_ENDPOINT" ]]; do
        echo -e "${RED}Адрес сервера не может быть пустым${NC}"
        read -p "Введите внешний IP адрес или домен сервера: " SERVER_ENDPOINT
    done

    # Пароль для веб-интерфейса
    echo
    echo -e "${BLUE}Настройка пароля для веб-интерфейса wg-easy${NC}"
    suggested_password=$(generate_password 12)
    echo -e "Предлагаемый безопасный пароль: ${GREEN}$suggested_password${NC}"
    read -p "Использовать предлагаемый пароль? [y/n]: " use_suggested

    if [[ "$use_suggested" =~ ^[Yy] ]]; then
        WG_EASY_PASSWORD="$suggested_password"
        echo -e "${GREEN}Используется сгенерированный пароль${NC}"
    else
        read -s -p "Введите собственный пароль (минимум 8 символов): " WG_EASY_PASSWORD
        echo
        while [[ ${#WG_EASY_PASSWORD} -lt 8 ]]; do
            echo -e "${RED}Пароль должен содержать минимум 8 символов${NC}"
            read -s -p "Введите пароль: " WG_EASY_PASSWORD
            echo
        done
    fi

    # Порты
    echo
    echo -e "${BLUE}Настройка портов${NC}"
    read -p "Порт для веб-интерфейса (по умолчанию 51821): " WEB_PORT
    WEB_PORT=${WEB_PORT:-51821}

    read -p "Порт для WireGuard (по умолчанию 51820): " WG_PORT
    WG_PORT=${WG_PORT:-51820}

    # Настройка DNS
    echo
    echo -e "${CYAN}=== Настройка AdGuard DNS ===${NC}"
    echo "AdGuard DNS блокирует рекламу, трекеры и вредоносные сайты"
    echo
    echo -e "${BLUE}1)${NC} У меня есть персональный AdGuard DNS (рекомендуется)"
    echo -e "${BLUE}2)${NC} Использовать публичные AdGuard DNS серверы"
    echo -e "${BLUE}3)${NC} Использовать Google DNS (без блокировки рекламы)"
    echo

    read -p "Выберите опцию (1-3): " dns_choice

    case $dns_choice in
        1)
            echo -e "${BLUE}Настройка персонального AdGuard DNS${NC}"
            echo "Получите ваши персональные DNS на: https://adguard-dns.io/"
            echo
            read -p "DNS-over-HTTPS URL: " ADGUARD_DNS_HTTPS
            read -p "DNS-over-TLS URL: " ADGUARD_DNS_TLS
            read -p "Первичный DNS IP (можно оставить пустым): " ADGUARD_DNS_IP1
            read -p "Вторичный DNS IP (можно оставить пустым): " ADGUARD_DNS_IP2

            # Если IP не указаны, используем публичные
            ADGUARD_DNS_IP1=${ADGUARD_DNS_IP1:-94.140.14.14}
            ADGUARD_DNS_IP2=${ADGUARD_DNS_IP2:-94.140.15.15}
            ;;
        2)
            echo -e "${BLUE}Использование публичных AdGuard DNS серверов${NC}"
            ADGUARD_DNS_IP1="94.140.14.14"
            ADGUARD_DNS_IP2="94.140.15.15"
            ADGUARD_DNS_HTTPS="https://dns.adguard-dns.com/dns-query"
            ADGUARD_DNS_TLS="tls://dns.adguard-dns.com"
            ;;
        3)
            echo -e "${YELLOW}Использование Google DNS (без блокировки рекламы)${NC}"
            ADGUARD_DNS_IP1="8.8.8.8"
            ADGUARD_DNS_IP2="8.8.4.4"
            ADGUARD_DNS_HTTPS=""
            ADGUARD_DNS_TLS=""
            ;;
        *)
            echo -e "${RED}Неверный выбор, используются публичные AdGuard DNS${NC}"
            ADGUARD_DNS_IP1="94.140.14.14"
            ADGUARD_DNS_IP2="94.140.15.15"
            ADGUARD_DNS_HTTPS="https://dns.adguard-dns.com/dns-query"
            ADGUARD_DNS_TLS="tls://dns.adguard-dns.com"
            ;;
    esac

    # Параметры обфускации
    echo
    echo -e "${PURPLE}=== Параметры обфускации AmneziaWG ===${NC}"
    echo "Эти параметры делают VPN трафик неразличимым от обычного"
    echo
    echo -e "${BLUE}1)${NC} Автоматически сгенерировать (рекомендуется)"
    echo -e "${BLUE}2)${NC} Настроить вручную"
    echo

    read -p "Выберите опцию (1-2): " obf_choice

    if [[ "$obf_choice" == "2" ]]; then
        echo -e "${BLUE}Ручная настройка параметров обфускации${NC}"
        read -p "Количество мусорных пакетов (1-10, по умолчанию 5): " JC
        JC=${JC:-5}

        read -p "Минимальный размер мусорного пакета (50-500, по умолчанию 100): " JMIN
        JMIN=${JMIN:-100}

        read -p "Максимальный размер мусорного пакета (500-2000, по умолчанию 1000): " JMAX
        JMAX=${JMAX:-1000}

        generate_random_values
    else
        echo -e "${GREEN}Автоматическая генерация параметров обфускации${NC}"
        JC=5
        JMIN=100
        JMAX=1000
        generate_random_values
    fi

    # Дополнительные возможности
    echo
    echo -e "${CYAN}=== Дополнительные возможности ===${NC}"

    read -p "Включить Cloak для дополнительной обфускации? [y/n]: " enable_cloak
    if [[ "$enable_cloak" =~ ^[Yy] ]]; then
        CLOAK_ENABLED="true"
        echo -e "${GREEN}Cloak будет включен${NC}"

        # Запускаем генератор Cloak конфигурации
        if [[ -f "scripts/setup-cloak.sh" ]]; then
            echo -e "${BLUE}Настройка Cloak обфускации...${NC}"
            chmod +x scripts/setup-cloak.sh
            ./scripts/setup-cloak.sh
        else
            echo -e "${YELLOW}Скрипт настройки Cloak не найден, будет настроен позже${NC}"
        fi
    else
        CLOAK_ENABLED="false"
    fi

    read -p "Включить веб-статистику на порту 8080? [y/n]: " enable_stats
    if [[ "$enable_stats" =~ ^[Yy] ]]; then
        STATS_PORT="8080"
        echo -e "${GREEN}Веб-статистика будет доступна на :8080${NC}"
    else
        STATS_PORT=""
    fi
}

# Создание .env файла
create_env_file() {
    echo -e "${BLUE}Создание .env файла...${NC}"

    cat > "$ENV_FILE" << EOF
# WireGuard Maximum Obfuscation Setup - Environment Variables
# Автоматически сгенерировано: $(date)

# =================
# ОСНОВНЫЕ НАСТРОЙКИ
# =================
SERVER_ENDPOINT=$SERVER_ENDPOINT
WG_EASY_PASSWORD=$WG_EASY_PASSWORD
WEB_PORT=$WEB_PORT
WG_PORT=$WG_PORT
WG_SUBNET=10.8.0.x
WG_ALLOWED_IPS=0.0.0.0/0
WG_KEEPALIVE=25
WG_MTU=1280

# ======================
# ПАРАМЕТРЫ ОБФУСКАЦИИ
# ======================
JC=$JC
JMIN=$JMIN
JMAX=$JMAX
S1=$S1
S2=$S2
H1=$H1
H2=$H2
H3=$H3
H4=$H4

# ===============
# DNS НАСТРОЙКИ
# ===============
ADGUARD_DNS_IP1=$ADGUARD_DNS_IP1
ADGUARD_DNS_IP2=$ADGUARD_DNS_IP2
ADGUARD_DNS_HTTPS=$ADGUARD_DNS_HTTPS
ADGUARD_DNS_TLS=$ADGUARD_DNS_TLS

# ===================
# ДОПОЛНИТЕЛЬНЫЕ ПОРТЫ
# ===================
STATS_PORT=${STATS_PORT:-8080}
CLOAK_ENABLED=$CLOAK_ENABLED
CLOAK_HTTPS_PORT=8443
CLOAK_HTTP_PORT=8080

# =================
# ГЕНЕРАЦИЯ КОНФИГОВ
# =================
MOBILE_KEEPALIVE=25
MOBILE_MTU=1280
ROUTER_KEEPALIVE=0
ROUTER_MTU=1420
DESKTOP_KEEPALIVE=0
DESKTOP_MTU=1420

# ==================
# БЕЗОПАСНОСТЬ
# ==================
AUTO_KEY_ROTATION_DAYS=30
MAX_CLIENTS=50
ENABLE_LOGGING=true
LOG_LEVEL=info

# =================
# ДОПОЛНИТЕЛЬНО
# =================
LANG=ru
UI_TRAFFIC_STATS=true
UI_CHART_TYPE=2
WG_ENABLE_ONE_TIME_LINKS=true
DOMAIN=$SERVER_ENDPOINT
LETSENCRYPT_EMAIL=admin@$SERVER_ENDPOINT
EOF

    echo -e "${GREEN}.env файл создан успешно${NC}"
}

# Показать итоговую конфигурацию
show_summary() {
    echo
    echo -e "${CYAN}===============================================${NC}"
    echo -e "${GREEN}    Конфигурация завершена успешно!${NC}"
    echo -e "${CYAN}===============================================${NC}"
    echo
    echo -e "${YELLOW}Основные параметры:${NC}"
    echo -e "  Сервер: ${BLUE}$SERVER_ENDPOINT${NC}"
    echo -e "  Веб-интерфейс: ${BLUE}http://$SERVER_ENDPOINT:$WEB_PORT${NC}"
    echo -e "  Пароль: ${PURPLE}$WG_EASY_PASSWORD${NC}"
    echo -e "  WireGuard порт: ${BLUE}$WG_PORT${NC}"
    echo
    echo -e "${YELLOW}DNS серверы:${NC}"
    echo -e "  Первичный: ${BLUE}$ADGUARD_DNS_IP1${NC}"
    echo -e "  Вторичный: ${BLUE}$ADGUARD_DNS_IP2${NC}"
    echo
    echo -e "${YELLOW}Обфускация AmneziaWG:${NC}"
    echo -e "  JC=${BLUE}$JC${NC}, JMIN=${BLUE}$JMIN${NC}, JMAX=${BLUE}$JMAX${NC}"
    echo -e "  S1=${BLUE}$S1${NC}, S2=${BLUE}$S2${NC}"
    echo
    echo -e "${YELLOW}Дополнительно:${NC}"
    echo -e "  Cloak: ${BLUE}$CLOAK_ENABLED${NC}"
    if [[ -n "$STATS_PORT" ]]; then
        echo -e "  Статистика: ${BLUE}http://$SERVER_ENDPOINT:$STATS_PORT${NC}"
    fi
    echo
    echo -e "${GREEN}Теперь запустите: ${CYAN}docker-compose up -d${NC}"
    echo -e "${CYAN}===============================================${NC}"
}

# Основная функция
main() {
    show_logo

    # Проверяем .env
    env_status=1
    check_env_exists && env_status=$?

    if [[ $env_status -eq 0 ]]; then
        echo -e "${GREEN}Используется существующая конфигурация${NC}"
        echo -e "${BLUE}Запустите: docker-compose up -d${NC}"
        return 0
    elif [[ $env_status -eq 2 ]]; then
        echo -e "${YELLOW}Для редактирования используйте: nano .env${NC}"
        return 0
    fi

    # Проверяем наличие шаблона
    if [[ ! -f "$ENV_EXAMPLE" ]]; then
        echo -e "${RED}Ошибка: не найден файл $ENV_EXAMPLE${NC}"
        exit 1
    fi

    interactive_setup
    create_env_file
    show_summary
}

# Обработка ошибок
trap 'echo -e "${RED}Произошла ошибка в строке $LINENO${NC}"; exit 1' ERR

# Запуск
main "$@"
