#!/bin/bash

# Убедитесь, что скрипт останавливается при ошибке
set -e

# Определите основные переменные
LOKI_URL="http://localhost:3100/loki/api/v1/query_range"  # URL Loki, проверь, что порт совпадает с твоим
LOG_QUERY='{job="wireguard"}'  # Здесь замените на правильный job из настроек Promtail
START_TIME=$(date -d "yesterday" --utc +%FT%TZ)  # Начало интервала - 24 часа назад
END_TIME=$(date --utc +%FT%TZ)  # Конец интервала - сейчас
OUTPUT_FILE="/tmp/loki_logs_$(date +%F).json"  # Файл для хранения логов

# Для отладки - вывод URL
echo "URL: ${LOKI_URL}?query=${LOG_QUERY}&start=${START_TIME}&end=${END_TIME}"

# Выполнить запрос к Loki для получения логов
echo "Запрашиваем логи у Loki с $START_TIME до $END_TIME..."

curl -G -s "${LOKI_URL}" \
    --data-urlencode "query=${LOG_QUERY}" \
    --data-urlencode "start=${START_TIME}" \
    --data-urlencode "end=${END_TIME}" \
    --data-urlencode "limit=5000" \
    -o "${OUTPUT_FILE}"

# Проверка успешного сохранения логов
if [[ -f "$OUTPUT_FILE" ]]; then
    echo "Логи успешно сохранены в $OUTPUT_FILE"
else
    echo "Ошибка: Не удалось сохранить логи в файл."
    exit 1
fi
