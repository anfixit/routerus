#!/bin/bash

# RouteRus VPN - Cloak Configuration Generator
# Генерация ключей и конфигурации для Cloak обфускации

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Директории
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CLOAK_DIR="$PROJECT_DIR/docker/cloak"
TEMPLATE_FILE="$CLOAK_DIR/config-template.json"
CONFIG_FILE="$CLOAK_DIR/config.json"

echo -e "${CYAN}RouteRus VPN - Cloak Configuration Generator${NC}"
echo

# Функция генерации случайного UID
generate_uid() {
    openssl rand -base64 16 | tr -d "=+/" | cut -c1-16
}

# Функция генерации Cloak приватного ключа
generate_cloak_private_key() {
    openssl rand -base64 32 | tr -d "=+/"
}

# Функция создания конфигурации Cloak
create_cloak_config() {
    echo -e "${BLUE}Генерация Cloak конфигурации...${NC}"

    # Проверяем наличие шаблона
    if [[ ! -f "$TEMPLATE_FILE" ]]; then
        echo -e "${RED}Ошибка: шаблон $TEMPLATE_FILE не найден${NC}"
        exit 1
    fi

    # Генерируем ключи и UID
    local private_key=$(generate_cloak_private_key)
    local admin_uid=$(generate_uid)
    local bypass_uid=$(generate_uid)

    echo -e "${GREEN}Сгенерированы Cloak ключи:${NC}"
    echo -e "  Private Key: ${CYAN}${private_key:0:20}...${NC}"
    echo -e "  Admin UID: ${CYAN}$admin_uid${NC}"
    echo -e "  Bypass UID: ${CYAN}$bypass_uid${NC}"

    # Создаем конфигурацию из шаблона
    cp "$TEMPLATE_FILE" "$CONFIG_FILE"

    # Подставляем сгенерированные значения
    sed -i "s/CLOAK_PRIVATE_KEY_PLACEHOLDER/$private_key/g" "$CONFIG_FILE"
    sed -i "s/ADMIN_UID_PLACEHOLDER/$admin_uid/g" "$CONFIG_FILE"
    sed -i "s/BYPASS_UID_PLACEHOLDER/$bypass_uid/g" "$CONFIG_FILE"

    echo -e "${GREEN}✓ Cloak конфигурация создана: $CONFIG_FILE${NC}"

    # Создаем клиентскую конфигурацию
    create_client_config "$admin_uid" "$bypass_uid"

    # Создаем .env переменные для Cloak
    create_cloak_env_vars "$private_key" "$admin_uid" "$bypass_uid"
}

# Функция создания клиентской конфигурации
create_client_config() {
    local admin_uid=$1
    local bypass_uid=$2

    echo -e "${BLUE}Создание клиентской конфигурации Cloak...${NC}"

    # Загружаем переменные окружения
    if [[ -f "$PROJECT_DIR/.env" ]]; then
        source "$PROJECT_DIR/.env"
    fi

    local server_endpoint=${SERVER_ENDPOINT:-"localhost"}

    cat > "$CLOAK_DIR/client-config.json" << EOC
{
  "Transport": "direct",
  "ProxyMethod": "openvpn",
  "EncryptionMethod": "plain",
  "UID": "$admin_uid",
  "PublicKey": "server_public_key_will_be_generated",
  "ServerName": "$server_endpoint",
  "NumConn": 4,
  "BrowserSig": "chrome",
  "StreamTimeout": 300
}
EOC

    echo -e "${GREEN}✓ Клиентская конфигурация: $CLOAK_DIR/client-config.json${NC}"

    # Создаем инструкцию по использованию
    create_usage_instructions "$admin_uid" "$bypass_uid"
}

# Функция создания переменных окружения для Cloak
create_cloak_env_vars() {
    local private_key=$1
    local admin_uid=$2
    local bypass_uid=$3

    cat > "$CLOAK_DIR/cloak.env" << EOE
# Cloak Environment Variables
# Эти переменные используются для настройки Cloak обфускации

CLOAK_PRIVATE_KEY=$private_key
CLOAK_ADMIN_UID=$admin_uid
CLOAK_BYPASS_UID=$bypass_uid

# Порты Cloak
CLOAK_HTTPS_PORT=8443
CLOAK_HTTP_PORT=8080

# Настройки обфускации
CLOAK_REDIRECT_ADDR=www.google.com:443
CLOAK_DATABASE_PATH=/opt/cloak/data/userinfo.db
CLOAK_STREAM_TIMEOUT=300
CLOAK_KEEP_ALIVE=15
EOE

    echo -e "${GREEN}✓ Переменные окружения: $CLOAK_DIR/cloak.env${NC}"
}

# Функция создания инструкции по использованию
create_usage_instructions() {
    local admin_uid=$1
    local bypass_uid=$2

    cat > "$CLOAK_DIR/CLOAK_USAGE.md" << 'EOU'
# Использование Cloak обфускации

## Что такое Cloak

Cloak - это дополнительный уровень обфускации, который маскирует VPN трафик под обычный HTTPS веб-трафик. Это помогает обходить DPI (Deep Packet Inspection) системы.

## Настройка сервера

Cloak уже настроен автоматически при использовании docker-compose с профилем cloak:

```bash
# Включить Cloak в .env
CLOAK_ENABLED=true

# Запустить с Cloak
docker-compose --profile cloak up -d
```

## Клиентская настройка

### Для AmneziaVPN (рекомендуется)

1. Откройте AmneziaVPN
2. Добавьте новый сервер
3. Выберите "Cloak" как протокол
4. Используйте настройки из client-config.json
5. Укажите ваш сервер и порт 8443

### Для стандартного Cloak клиента

1. Скачайте Cloak клиент с https://github.com/cbeuw/Cloak
2. Используйте client-config.json для подключения
3. Настройте туннелирование к WireGuard

## Порты

- **8443** - HTTPS порт (основной)
- **8080** - HTTP порт (резервный)

## Безопасность

- **Admin UID**: используется для управления
- **Bypass UID**: для обхода ограничений
- Ключи сгенерированы случайно и уникальны

## Проверка работы

1. Подключитесь через Cloak
2. Проверьте что трафик идет через порт 8443
3. Убедитесь что VPN работает внутри Cloak туннеля

## Важно

Cloak добавляет дополнительную задержку, но значительно улучшает обфускацию. Используйте только при необходимости максимального обхода блокировок.
EOU

    echo -e "${GREEN}✓ Инструкция по использованию: $CLOAK_DIR/CLOAK_USAGE.md${NC}"
}

# Функция показа итоговой информации
show_completion_info() {
    echo
    echo -e "${CYAN}================================${NC}"
    echo -e "${GREEN}  Cloak настроен успешно!${NC}"
    echo -e "${CYAN}================================${NC}"
    echo
    echo -e "${YELLOW}Созданные файлы:${NC}"
    echo -e "  📄 $CONFIG_FILE"
    echo -e "  📄 $CLOAK_DIR/client-config.json"
    echo -e "  📄 $CLOAK_DIR/cloak.env"
    echo -e "  📄 $CLOAK_DIR/CLOAK_USAGE.md"
    echo
    echo -e "${YELLOW}Для использования Cloak:${NC}"
    echo -e "  1. Установите CLOAK_ENABLED=true в .env"
    echo -e "  2. Запустите: ${BLUE}docker-compose --profile cloak up -d${NC}"
    echo -e "  3. Настройте клиент согласно CLOAK_USAGE.md"
    echo
    echo -e "${YELLOW}Порты Cloak:${NC}"
    echo -e "  🔐 HTTPS: ${CYAN}8443${NC}"
    echo -e "  🌐 HTTP: ${CYAN}8080${NC}"
    echo
}

# Основная функция
main() {
    # Проверяем что мы в правильной директории
    if [[ ! -f "$PROJECT_DIR/docker-compose.yml" ]]; then
        echo -e "${RED}Ошибка: запустите скрипт из корня проекта RouteRus VPN${NC}"
        exit 1
    fi

    # Создаем директорию если нужно
    mkdir -p "$CLOAK_DIR"

    echo -e "${BLUE}Настройка Cloak обфускации для RouteRus VPN${NC}"
    echo

    # Проверяем наличие конфигурации
    if [[ -f "$CONFIG_FILE" ]]; then
        echo -e "${YELLOW}Cloak уже настроен. Перегенерировать? [y/N]${NC}"
        read -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${GREEN}Использую существующую конфигурацию Cloak${NC}"
            exit 0
        fi
    fi

    create_cloak_config
    show_completion_info
}

# Запуск
main "$@"
