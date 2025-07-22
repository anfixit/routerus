#!/bin/bash
set -e

# Параметры
VENV_PATH=${VENV_PATH:-"/opt/routerus/venv"}
LOG_FILE="/var/log/routerus/deploy.log"

# Логирование
exec >> $LOG_FILE 2>&1
echo "[$(date +"%Y-%m-%d %H:%M:%S")] Starting deployment..."

# Активация виртуального окружения
if [[ -d $VENV_PATH ]]; then
    source $VENV_PATH/bin/activate
    echo "Activated virtual environment: $VENV_PATH"
else
    echo "Error: Virtual environment not found at $VENV_PATH"
    exit 1
fi

# Миграции базы данных
if python manage.py migrate; then
    echo "Database migrations applied successfully."
else
    echo "Error: Failed to apply database migrations."
    exit 1
fi

# Сбор статических файлов
if python manage.py collectstatic --noinput; then
    echo "Static files collected successfully."
else
    echo "Error: Failed to collect static files."
    exit 1
fi

# Перезапуск приложения
if systemctl restart routerus; then
    echo "Application restarted successfully."
else
    echo "Error: Failed to restart application."
    exit 1
fi

echo "[$(date +"%Y-%m-%d %H:%M:%S")] Deployment complete!"
