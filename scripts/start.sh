#!/bin/bash

# Остановка скрипта при любой ошибке
set -e

# Определение цветов для вывода
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Функция для красивого вывода
log() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Проверка наличия Docker
if ! command -v docker &> /dev/null; then
    error "Docker не установлен. Установите Docker перед запуском."
fi

# Переход в директорию проекта
cd /opt/routerus

# Проверка наличия необходимых файлов
log "Проверка конфигурационных файлов..."
if [ ! -f ".env" ]; then
    error "Файл .env не найден. Создайте файл .env перед запуском."
fi

if [ ! -f "docker-compose.yml" ]; then
    error "Файл docker-compose.yml не найден."
fi

# Создание директорий для данных, если они не существуют
log "Создание директорий для данных..."
mkdir -p data/db
mkdir -p data/prometheus
mkdir -p data/grafana
mkdir -p logs
mkdir -p config/wireguard
mkdir -p config/shadowsocks
mkdir -p config/xray

# Проверка наличия SSL сертификатов
log "Проверка SSL сертификатов..."
if [ ! -f "ssl/server.crt" ] || [ ! -f "ssl/server.key" ]; then
    log "SSL сертификаты не найдены. Создание самоподписанных сертификатов..."
    mkdir -p ssl
    openssl req -x509 -nodes -days 365 -newkey rsa:2048         -keyout ssl/server.key         -out ssl/server.crt         -subj "/C=RU/ST=Moscow/L=Moscow/O=RouteRus/CN=vpn.routerus.ru"         -passout pass:routerus
    chmod 600 ssl/server.key
    success "Самоподписанные SSL сертификаты созданы."
fi

# Запуск сервисов
log "Запуск сервисов..."
docker-compose down || true
docker-compose up -d

# Пауза для инициализации базы данных
log "Ожидание инициализации базы данных..."
sleep 10

# Запуск инициализации первого администратора
log "Инициализация первого администратора..."
docker-compose exec api python -m app.initial_setup

success "RouteRus VPN успешно запущен!"
echo ""
echo "Доступ к административной панели: https://vpn.routerus.ru/admin"
echo "API документация: https://vpn.routerus.ru/docs"
echo "Grafana дашборды: https://vpn.routerus.ru/grafana"
echo ""
echo "Логин администратора: $(grep ADMIN_USERNAME .env | cut -d '=' -f2)"
echo "Пароль администратора: $(grep ADMIN_PASSWORD .env | cut -d '=' -f2)"
echo ""
echo "Для просмотра логов используйте: docker-compose logs -f"
