#!/bin/bash
# start.sh: Скрипт для запуска всех сервисов

set -e

# Чтение переменных из .env и экспорт
if [ ! -f /opt/routerus/.env ]; then
    echo ".env файл не найден. Убедитесь, что он существует в /opt/routerus/"
    exit 1
fi
set -o allexport
source /opt/routerus/.env
set +o allexport

# Проверка и создание директории для логов
LOG_DIR="/var/log/routerus"
if [ ! -d "$LOG_DIR" ]; then
    mkdir -p "$LOG_DIR" || { echo "Не удалось создать директорию логов: $LOG_DIR"; exit 1; }
    echo "Директория логов создана: $LOG_DIR"
fi

# Запуск Nginx через systemctl
if systemctl is-active --quiet nginx; then
    echo "Nginx уже запущен."
else
    echo "Запуск Nginx..."
    if ! systemctl start nginx; then
        echo "Не удалось запустить Nginx. Проверьте systemctl status nginx.service"
        exit 1
    fi
fi

# Запуск всех сервисов через service_manager.py
echo "Запуск всех сервисов через service_manager.py..."
if python3 /opt/routerus/app/services/service_manager.py start_all; then
    echo "Все сервисы успешно запущены."
else
    echo "Не удалось запустить все сервисы."
    exit 1
fi
