#!/bin/bash
# Routerus V2 - Установка VPN сервера (Contabo)

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

# Проверка root прав
if [[ $EUID -ne 0 ]]; then
    error "Скрипт должен запускаться с правами root"
fi

log "🚀 Установка Routerus V2 VPN сервера"
log "====================================="

# Определяем IP сервера
SERVER_IP=$(curl -s ifconfig.me || echo "178.18.243.123")
log "IP сервера: $SERVER_IP"

# Обновление системы
log "📦 Обновление системы..."
apt update -y
apt upgrade -y
apt install -y curl wget unzip git docker.io docker-compose-plugin ufw fail2ban htop

# Запуск Docker
systemctl enable docker
systemctl start docker

# Добавляем пользователя в группу docker
usermod -aG docker $USER || true

# Настройка файрвола
log "🔥 Настройка файрвола..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 443/tcp comment 'VLESS Reality'
ufw allow 80/tcp comment 'HTTP'
ufw allow 8080/tcp comment 'API'
ufw allow 9100/tcp comment 'Node Exporter'
ufw --force enable

# Создание директорий
log "📁 Создание директорий..."
mkdir -p /opt/routerus/{data,logs,certs}
chown -R root:root /opt/routerus

# Проверяем наличие .env файла
if [ ! -f /opt/routerus/.env ]; then
    error ".env файл не найден! Скопируйте .env файл на сервер."
fi

# Настройка .env для VPN режима
log "⚙️ Настройка конфигурации..."
sed -i "s/MODE=WEB_INTERFACE/MODE=VPN_ONLY/" /opt/routerus/.env
sed -i "s/VPN_SERVER_IP=.*/VPN_SERVER_IP=$SERVER_IP/" /opt/routerus/.env
sed -i "s/DEBUG=true/DEBUG=false/" /opt/routerus/.env

# Установка Docker Compose V2
log "🐳 Проверка Docker Compose..."
if ! command -v docker compose &> /dev/null; then
    log "Установка Docker Compose V2..."
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
fi

# Сборка и запуск контейнеров
log "🏗️ Сборка Docker образов..."
cd /opt/routerus
docker compose -f docker-compose.vpn.yml build --no-cache

log "🚀 Запуск VPN сервера..."
docker compose -f docker-compose.vpn.yml up -d

# Ожидание запуска сервисов
log "⏳ Ожидание запуска сервисов..."
sleep 30

# Проверка статуса
log "📊 Проверка статуса сервисов..."
docker compose -f docker-compose.vpn.yml ps

# Проверка API
log "🔍 Проверка API..."
if curl -f http://localhost:8080/health &>/dev/null; then
    log "✅ API доступен"
else
    warn "⚠️ API пока недоступен, может потребоваться время"
fi

# Настройка автозапуска
log "🔄 Настройка автозапуска..."
cat > /etc/systemd/system/routerus-vpn.service << 'EOF'
[Unit]
Description=Routerus VPN Server
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/routerus
ExecStart=/usr/bin/docker compose -f docker-compose.vpn.yml up -d
ExecStop=/usr/bin/docker compose -f docker-compose.vpn.yml down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

systemctl enable routerus-vpn
systemctl daemon-reload

# Настройка логирования
log "📝 Настройка логирования..."
mkdir -p /var/log/routerus
cat > /etc/logrotate.d/routerus << 'EOF'
/var/log/routerus/*.log {
    daily
    missingok
    rotate 52
    compress
    delaycompress
    notifempty
    create 644 root root
}
EOF

# Создание скрипта управления
log "🛠️ Создание скрипта управления..."
cat > /usr/local/bin/routerus-vpn << 'EOF'
#!/bin/bash
cd /opt/routerus

case "$1" in
    start)
        echo "Запуск VPN сервера..."
        docker compose -f docker-compose.vpn.yml up -d
        ;;
    stop)
        echo "Остановка VPN сервера..."
        docker compose -f docker-compose.vpn.yml down
        ;;
    restart)
        echo "Перезапуск VPN сервера..."
        docker compose -f docker-compose.vpn.yml restart
        ;;
    status)
        echo "=== Статус контейнеров ==="
        docker compose -f docker-compose.vpn.yml ps
        echo ""
        echo "=== Использование ресурсов ==="
        docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"
        ;;
    logs)
        docker compose -f docker-compose.vpn.yml logs -f
        ;;
    update)
        echo "Обновление VPN сервера..."
        docker compose -f docker-compose.vpn.yml pull
        docker compose -f docker-compose.vpn.yml up -d
        ;;
    *)
        echo "Использование: $0 {start|stop|restart|status|logs|update}"
        exit 1
        ;;
esac
EOF

chmod +x /usr/local/bin/routerus-vpn

# Финальная информация
log "🎉 Установка VPN сервера завершена!"
echo ""
echo -e "${BLUE}📋 Информация о сервере:${NC}"
echo "IP адрес: $SERVER_IP"
echo "VPN порт: 443 (VLESS+Reality)"
echo "API порт: 8080"
echo "Мониторинг: 9100 (Node Exporter)"
echo ""
echo -e "${BLUE}🔧 Команды управления:${NC}"
echo "routerus-vpn start    - запуск"
echo "routerus-vpn stop     - остановка"
echo "routerus-vpn restart  - перезапуск"
echo "routerus-vpn status   - статус"
echo "routerus-vpn logs     - логи"
echo ""
echo -e "${GREEN}✅ VPN сервер готов к работе!${NC}"

# Показываем статус
routerus-vpn status
