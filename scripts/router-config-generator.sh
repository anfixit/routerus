#!/bin/bash

# RouteRus VPN - Router Configuration Generator
# Генератор конфигураций для роутеров (Keenetic, OpenWrt, ASUS, MikroTik)

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Определение директорий
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TEMPLATES_DIR="$PROJECT_DIR/templates"
OUTPUT_DIR="$PROJECT_DIR/generated-configs"

# Функция показа лого
show_logo() {
    echo -e "${CYAN}"
    cat << "EOF"
╦═╗┌─┐┬ ┬┌┬┐┌─┐╦═╗┬ ┬┌─┐  ╦═╗┌─┐┬ ┬┌┬┐┌─┐┬─┐
╠╦╝│ ││ │ │ ├┤ ╠╦╝│ │└─┐  ╠╦╝│ ││ │ │ ├┤ ├┬┘
╩╚═└─┘└─┘ ┴ └─┘╩╚═└─┘└─┘  ╩╚═└─┘└─┘ ┴ └─┘┴└─
                Router Configuration Generator
EOF
    echo -e "${NC}"
}

# Функция генерации ключей
generate_keys() {
    local private_key public_key
    private_key=$(openssl rand -base64 32)
    public_key=$(echo "$private_key" | base64 -d | openssl dgst -sha256 -binary | base64)
    echo "$private_key:$public_key"
}

# Функция создания конфигурации для роутера
create_router_config() {
    local router_name=${1:-"router-$(date +%s)"}
    local router_type=${2:-"keenetic"}

    echo -e "${BLUE}Создание конфигурации для роутера: $router_name (тип: $router_type)${NC}"

    # Загружаем переменные окружения если есть
    if [[ -f "$PROJECT_DIR/.env" ]]; then
        source "$PROJECT_DIR/.env"
    fi

    # Генерируем ключи
    local keys=$(generate_keys)
    local client_private_key=$(echo "$keys" | cut -d':' -f1)
    local client_public_key=$(echo "$keys" | cut -d':' -f2)

    # Получаем следующий доступный IP
    local client_ip="10.8.0.$((RANDOM % 200 + 50))/32"

    # Создаем выходную директорию
    mkdir -p "$OUTPUT_DIR"

    # Копируем шаблон роутера
    local output_file="$OUTPUT_DIR/${router_name}.conf"
    if [[ -f "$TEMPLATES_DIR/client-router.conf" ]]; then
        cp "$TEMPLATES_DIR/client-router.conf" "$output_file"
    else
        echo -e "${RED}Ошибка: шаблон client-router.conf не найден${NC}"
        return 1
    fi

    # Подставляем переменные
    sed -i "s|{{CLIENT_PRIVATE_KEY}}|$client_private_key|g" "$output_file"
    sed -i "s|{{CLIENT_IP}}|$client_ip|g" "$output_file"
    sed -i "s|{{GENERATION_DATE}}|$(date)|g" "$output_file"
    sed -i "s|{{SERVER_ENDPOINT}}|${SERVER_ENDPOINT:-localhost}|g" "$output_file"
    sed -i "s|{{SERVER_PORT}}|${WG_PORT:-51820}|g" "$output_file"
    sed -i "s|{{SERVER_PUBLIC_KEY}}|${SERVER_PUBLIC_KEY:-PLACEHOLDER}|g" "$output_file"
    sed -i "s|{{DNS_SERVERS}}|${ADGUARD_DNS_IP1:-94.140.14.14},${ADGUARD_DNS_IP2:-94.140.15.15}|g" "$output_file"

    # Создаем JSON с информацией о роутере
    cat > "$OUTPUT_DIR/${router_name}.json" << EOJ
{
    "name": "$router_name",
    "type": "router",
    "router_type": "$router_type",
    "private_key": "$client_private_key",
    "public_key": "$client_public_key",
    "ip": "$client_ip",
    "created": "$(date -Iseconds)",
    "config_file": "${router_name}.conf"
}
EOJ

    # Создаем инструкцию по установке
    create_installation_guide "$router_name" "$router_type"

    echo -e "${GREEN}✓ Конфигурация роутера создана:${NC}"
    echo -e "  Файл: $output_file"
    echo -e "  IP: $client_ip"
    echo -e "  Публичный ключ: $client_public_key"
    echo -e "  Инструкция: $OUTPUT_DIR/${router_name}_setup.md"
    echo
    echo -e "${YELLOW}ВАЖНО: Добавьте публичный ключ на сервер WireGuard!${NC}"
}

# Функция создания инструкции по установке
create_installation_guide() {
    local router_name=$1
    local router_type=$2
    local guide_file="$OUTPUT_DIR/${router_name}_setup.md"

    cat > "$guide_file" << 'EOG'
# Инструкция по настройке WireGuard на роутере

## Общие шаги

1. **Войдите в веб-интерфейс роутера**
2. **Найдите раздел VPN или WireGuard**
3. **Создайте новое подключение WireGuard**
4. **Скопируйте настройки из конфигурационного файла**

## Специфичные инструкции по типам роутеров

### Keenetic
1. Перейдите в "Интернет" → "Другие подключения"
2. Нажмите "Добавить подключение" → "WireGuard"
3. Скопируйте параметры из .conf файла
4. Установите MTU = 1420
5. Сохраните и включите подключение

### OpenWrt
1. Установите пакет luci-proto-wireguard
2. Перейдите в Network → Interfaces
3. Add new interface → Protocol: WireGuard VPN
4. Настройте согласно .conf файлу

### ASUS
1. Перейдите в VPN → WireGuard
2. Добавьте клиента
3. Импортируйте .conf файл или введите настройки вручную

### MikroTik
1. Откройте WinBox или веб-интерфейс
2. WireGuard → Add Interface
3. Настройте peer согласно конфигурации

## Важные моменты

- **MTU**: Используйте 1420 для роутеров
- **DNS**: Настройте AdGuard DNS для блокировки рекламы
- **Порт**: Рекомендуется использовать 443 для обхода блокировок
- **Публичный ключ**: Обязательно добавьте на сервер!

## Проверка работы

1. Проверьте статус подключения в интерфейсе роутера
2. Выполните ping к серверу VPN
3. Проверьте смену IP адреса на внешних сайтах
4. Убедитесь что работает блокировка рекламы

## Поддержка

При проблемах проверьте:
- Правильность введенных ключей и настроек
- Доступность сервера на указанном порту
- Настройки firewall роутера
- Логи подключения WireGuard
EOG

    echo -e "${GREEN}✓ Создана инструкция: $guide_file${NC}"
}

# Функция показа справки
show_help() {
    show_logo
    echo -e "${YELLOW}Использование: $0 [имя_роутера] [тип_роутера]${NC}"
    echo
    echo -e "${CYAN}Поддерживаемые типы роутеров:${NC}"
    echo -e "  ${GREEN}keenetic${NC}   - Keenetic (все модели)"
    echo -e "  ${GREEN}openwrt${NC}    - OpenWrt"
    echo -e "  ${GREEN}asus${NC}       - ASUS с поддержкой WireGuard"
    echo -e "  ${GREEN}mikrotik${NC}   - MikroTik"
    echo
    echo -e "${CYAN}Примеры:${NC}"
    echo -e "  $0 home-router keenetic"
    echo -e "  $0 office-gateway openwrt"
    echo -e "  $0 asus-ac86u asus"
    echo
    echo -e "${YELLOW}Файлы будут созданы в: generated-configs/${NC}"
}

# Основная логика
main() {
    if [[ "$1" == "--help" || "$1" == "-h" ]]; then
        show_help
        exit 0
    fi

    local router_name=${1:-""}
    local router_type=${2:-"keenetic"}

    if [[ -z "$router_name" ]]; then
        show_help
        echo
        read -p "Введите имя роутера: " router_name
        if [[ -z "$router_name" ]]; then
            echo -e "${RED}Имя роутера не может быть пустым${NC}"
            exit 1
        fi
    fi

    create_router_config "$router_name" "$router_type"

    echo
    echo -e "${CYAN}Следующие шаги:${NC}"
    echo -e "1. Скопируйте публичный ключ роутера на сервер WireGuard"
    echo -e "2. Следуйте инструкции в файле ${router_name}_setup.md"
    echo -e "3. Проверьте подключение после настройки"
}

# Запуск
main "$@"
