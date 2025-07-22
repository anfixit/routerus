#!/bin/bash
# stop.sh: Скрипт для остановки всех сервисов

set -e

# Чтение переменных из .env и экспорт
if [ ! -f /opt/routerus/.env ]; then
    echo ".env файл не найден. Убедитесь, что он существует в /opt/routerus/"
    exit 1
fi
set -o allexport
source /opt/routerus/.env
set +o allexport

# Остановка всех сервисов через service_manager.py
echo "Остановка всех сервисов через service_manager.py..."
if python3 /opt/routerus/app/services/service_manager.py stop_all; then
    echo "Все сервисы успешно остановлены."
else
    echo "Не удалось остановить все сервисы."
    exit 1
fi

# Остановка Nginx через systemctl
if systemctl is-active --quiet nginx; then
    echo "Остановка Nginx..."
    if ! systemctl stop nginx; then
        echo "Не удалось остановить Nginx"
        exit 1
    fi
else
    echo "Nginx не запущен."
fi
