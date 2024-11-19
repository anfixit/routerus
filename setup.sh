# setup.sh
#!/bin/bash

# Остановка выполнения при ошибках
set -e

# Загрузка переменных окружения
if [ -f .env ]; then
    echo "Загружаю переменные окружения из .env файла..."
    export $(grep -v '^#' .env | xargs)
else
    echo ".env файл не найден! Завершение установки."
    exit 1
fi

# 1. Установка зависимостей
echo "Устанавливаю необходимые зависимости..."
apt-get update
apt-get install -y python3 python3-pip python3-venv postgresql postgresql-contrib wireguard-tools curl

# 2. Создание виртуального окружения
echo "Создаю виртуальное окружение..."
python3 -m venv ./venvs/wg-manager-venv
source ./venvs/wg-manager-venv/bin/activate

# 3. Установка зависимостей Python
echo "Устанавливаю зависимости Python..."
pip install --upgrade pip
pip install poetry
poetry install

# 4. Настройка базы данных PostgreSQL
echo "Настраиваю базу данных PostgreSQL..."
sudo -u postgres psql -c "CREATE DATABASE ${DB_NAME};"
sudo -u postgres psql -c "CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASSWORD}';"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};"

# 5. Применение миграций
echo "Применяю миграции Django..."
python manage.py makemigrations
python manage.py migrate

# 6. Установка необходимых сервисов (WireGuard, Shadowsocks, Xray)
echo "Настраиваю WireGuard..."
cp ./config/wireguard/templates/server.conf /etc/wireguard/wg0.conf
wg-quick up wg0

# 7. Информация о завершении
echo "Установка завершена! Вы можете запустить сервер командой:"
echo "source ./venvs/wg-manager-venv/bin/activate && python manage.py runserver 0.0.0.0:8000"
