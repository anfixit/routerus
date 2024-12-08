#!/bin/bash

# Убедитесь, что скрипт останавливается при ошибке
set -e

# Чтение переменных из .env файла и их экспорт
set -o allexport
source /opt/wg-manager/.env
set +o allexport

# Путь в Dropbox, куда будут загружаться логи
DROPBOX_DIR="/WGManagerLogsApp/logs/$(date +%F)"

# Проверка наличия Access Token
if [[ -z "${DROPBOX_ACCESS_TOKEN}" ]]; then
    echo "Ошибка: Dropbox Access Token не установлен. Проверьте файл .env."
    exit 1
fi

# Запрос логов у Loki с использованием скрипта loki_log_fetcher.sh
echo "Запрашиваем логи у Loki..."
./tools/loki_log_fetcher.sh

# Путь к временной директории, где хранятся извлеченные логи
TEMP_LOG_DIR="/tmp/loki_logs"

# Проверка наличия директории с логами
if [[ ! -d "${TEMP_LOG_DIR}" ]]; then
    echo "Ошибка: Директория с логами ${TEMP_LOG_DIR} не найдена."
    exit 1
fi

# Функция загрузки файла в Dropbox
upload_to_dropbox() {
    local FILE_PATH=$1
    local DEST_PATH=$2

    curl -X POST https://content.dropboxapi.com/2/files/upload \
        --header "Authorization: Bearer ${DROPBOX_ACCESS_TOKEN}" \
        --header "Dropbox-API-Arg: {\"path\": \"${DROPBOX_DIR}/${DEST_PATH}\", \"mode\": \"add\", \"autorename\": true, \"mute\": false, \"strict_conflict\": false}" \
        --header "Content-Type: application/octet-stream" \
        --data-binary @"${FILE_PATH}"
}

# Перебираем и загружаем все файлы с логами из временной директории
for LOG_FILE in "${TEMP_LOG_DIR}"/*
do
    if [ -f "$LOG_FILE" ]; then
        echo "Загружаем $LOG_FILE в Dropbox..."
        upload_to_dropbox "$LOG_FILE" "$(basename $LOG_FILE)"
        if [ $? -eq 0 ]; then
            echo "Успешно загружено $LOG_FILE. Удаляем файл..."
            rm -f "$LOG_FILE"
        else
            echo "Не удалось загрузить $LOG_FILE. Пропускаем удаление."
        fi
    else
        echo "Предупреждение: $LOG_FILE не найден, пропускаем."
    fi
done

echo "Все доступные логи были загружены в Dropbox и удалены локально."
