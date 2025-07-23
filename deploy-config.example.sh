#!/bin/bash
# Routerus V2 - Скрипт деплоя

set -e

echo "🚀 Деплой Routerus V2"
echo "===================="

# Проверяем аргументы
if [ "$#" -ne 2 ]; then
    echo "Использование: $0 <vpn|web> <server_type>"
    echo "Примеры:"
    echo "  $0 vpn vpn       # Деплой VPN сервера"
    echo "  $0 web web       # Деплой веб-интерфейса"
    echo ""
    echo "Настройте серверы в deploy-config.sh (скопируйте из deploy-config.example.sh)"
    exit 1
fi

MODE=$1
SERVER_TYPE=$2

# Загрузка конфигурации
if [ ! -f "deploy-config.sh" ]; then
    echo "❌ Файл deploy-config.sh не найден!"
    echo "Скопируйте deploy-config.example.sh в deploy-config.sh и настройте"
    exit 1
fi

source deploy-config.sh

# Настройки подключения
if [ "$SERVER_TYPE" = "vpn" ]; then
    SERVER_IP="$VPN_SERVER_IP"
    SSH_USER="$VPN_SSH_USER"
    SSH_PORT="$VPN_SSH_PORT"
elif [ "$SERVER_TYPE" = "web" ]; then
    SERVER_IP="$WEB_SERVER_IP"
    SSH_USER="$WEB_SSH_USER"
    SSH_PORT="$WEB_SSH_PORT"
else
    echo "❌ Неизвестный тип сервера: $SERVER_TYPE"
    echo "Доступные типы: vpn, web"
    exit 1
fi

SSH_OPTS=""
if [ "$SSH_PORT" != "22" ]; then
    SSH_OPTS="-p $SSH_PORT"
fi

echo "Режим: $MODE"
echo "Сервер: $SERVER_TYPE ($SERVER_IP)"
echo "SSH: $SSH_USER@$SERVER_IP:$SSH_PORT"
echo ""

# Проверяем SSH подключение
echo "🔍 Проверка SSH подключения..."
if ! ssh $SSH_OPTS $SSH_USER@$SERVER_IP "echo 'SSH работает'" 2>/dev/null; then
    echo "❌ Не удалось подключиться к серверу $SERVER_IP"
    echo "Проверьте SSH ключи и доступность сервера"
    exit 1
fi
echo "✅ SSH подключение работает"

# Создаем директорию на сервере с правильными правами
echo "📁 Создание директории на сервере..."
if [ "$SSH_USER" != "root" ]; then
    ssh $SSH_OPTS $SSH_USER@$SERVER_IP "sudo mkdir -p /opt/routerus && sudo chown -R $SSH_USER:$SSH_USER /opt/routerus"
else
    ssh $SSH_OPTS $SSH_USER@$SERVER_IP "mkdir -p /opt/routerus"
fi

# Копируем файлы на сервер
echo "📤 Копирование файлов..."
rsync -avz --exclude='.git' --exclude='node_modules' --exclude='venv' --exclude='__pycache__' \
    --exclude='data' --exclude='logs' --exclude='*.log' --exclude='.DS_Store' --exclude='.DS_Store?' \
    --exclude='*.pyc' --exclude='.ropeproject' \
    -e "ssh $SSH_OPTS" \
    ./ $SSH_USER@$SERVER_IP:/opt/routerus/

echo "✅ Файлы скопированы"

# Копируем .env файл отдельно если его нет на сервере
echo "📋 Проверка .env файла..."
if ! ssh $SSH_OPTS $SSH_USER@$SERVER_IP "test -f /opt/routerus/.env"; then
    if [ -f ".env" ]; then
        echo "📤 Копирование .env файла..."
        scp $SSH_OPTS .env $SSH_USER@$SERVER_IP:/opt/routerus/.env
    else
        echo "❌ .env файл не найден локально! Создайте его из .env.example"
        exit 1
    fi
else
    echo "✅ .env файл уже существует на сервере"
fi

# Устанавливаем права на скрипты
echo "🔧 Настройка прав доступа..."
ssh $SSH_OPTS $SSH_USER@$SERVER_IP "cd /opt/routerus && chmod +x scripts/*.sh deploy.sh"

# Переключаемся на root если нужно (для Contabo)
if [ "$SSH_USER" != "root" ]; then
    echo "🔑 Переключение на root пользователя..."
    INSTALL_CMD="sudo /opt/routerus/scripts/install-$MODE.sh"
else
    INSTALL_CMD="/opt/routerus/scripts/install-$MODE.sh"
fi

# Подключаемся к серверу и запускаем установку
echo "🔧 Запуск установки на сервере..."
ssh $SSH_OPTS $SSH_USER@$SERVER_IP "$INSTALL_CMD"

echo ""
echo "✅ Деплой завершен!"
echo ""
echo "🌐 Информация о развернутом сервере:"
echo "Тип: $MODE"
echo "IP: $SERVER_IP"

if [ "$MODE" = "vpn" ]; then
    echo "VPN порт: 443 (VLESS+Reality)"
    echo "API: http://$SERVER_IP:8080"
    echo "Мониторинг: http://$SERVER_IP:9100"
    echo ""
    echo "Управление: ssh $SSH_OPTS $SSH_USER@$SERVER_IP routerus-vpn status"
else
    echo "Веб-интерфейс: https://$SERVER_IP"
    echo "Grafana: https://$SERVER_IP/grafana"
    echo "Prometheus: https://$SERVER_IP/prometheus"
    echo ""
    echo "Управление: ssh $SSH_OPTS $SSH_USER@$SERVER_IP routerus-web status"
fi

echo ""
echo "📋 Полезные команды:"
echo "Проверка статуса: ssh $SSH_OPTS $SSH_USER@$SERVER_IP 'cd /opt/routerus && docker compose ps'"
echo "Просмотр логов: ssh $SSH_OPTS $SSH_USER@$SERVER_IP 'cd /opt/routerus && docker compose logs'"
