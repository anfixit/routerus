#!/bin/bash
# Routerus V2 - Установка веб-интерфейса (Москва)

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

log "🌐 Установка Routerus V2 веб-интерфейса"
log "======================================="

# Определяем IP сервера
SERVER_IP=$(curl -s ifconfig.me || echo "109.73.194.190")
log "IP сервера: $SERVER_IP"

# Обновление системы
log "📦 Обновление системы..."
apt update -y
apt upgrade -y
apt install -y curl wget unzip git docker.io docker-compose-plugin nginx certbot python3-certbot-nginx ufw fail2ban htop nodejs npm

# Запуск Docker
systemctl enable docker
systemctl start docker
usermod -aG docker $USER || true

# Настройка файрвола
log "🔥 Настройка файрвола..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'
ufw allow 3000/tcp comment 'Grafana'
ufw allow 9090/tcp comment 'Prometheus'
ufw --force enable

# Создание директорий
log "📁 Создание директорий..."
mkdir -p /opt/routerus/{data,logs,ssl}
chown -R root:root /opt/routerus

# Проверяем наличие .env файла
if [ ! -f /opt/routerus/.env ]; then
    error ".env файл не найден! Скопируйте .env файл на сервер."
fi

# Настройка .env для веб режима
log "⚙️ Настройка конфигурации..."
sed -i "s/MODE=VPN_ONLY/MODE=WEB_INTERFACE/" /opt/routerus/.env
sed -i "s/WEB_SERVER_IP=.*/WEB_SERVER_IP=$SERVER_IP/" /opt/routerus/.env
sed -i "s/DEBUG=true/DEBUG=false/" /opt/routerus/.env

# Установка Docker Compose V2
log "🐳 Проверка Docker Compose..."
if ! command -v docker compose &> /dev/null; then
    log "Установка Docker Compose V2..."
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
fi

# Сборка фронтенда
log "🏗️ Сборка React приложения..."
cd /opt/routerus/frontend
npm install
npm run build

# Настройка Nginx
log "🌐 Настройка Nginx..."
cat > /etc/nginx/sites-available/routerus << 'EOF'
server {
    listen 80;
    server_name _;

    # Redirect HTTP to HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name _;

    # SSL Configuration (will be updated by certbot)
    ssl_certificate /etc/ssl/certs/routerus.crt;
    ssl_certificate_key /etc/ssl/private/routerus.key;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Frontend
    location / {
        root /opt/routerus/frontend/dist;
        try_files $uri $uri/ /index.html;

        # Cache static assets
        location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2)$ {
            expires 1y;
            add_header Cache-Control "public, immutable";
        }
    }

    # Backend API
    location /api/ {
        proxy_pass http://127.0.0.1:8000/api/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        proxy_read_timeout 86400;
    }

    # Grafana
    location /grafana/ {
        proxy_pass http://127.0.0.1:3000/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Prometheus
    location /prometheus/ {
        proxy_pass http://127.0.0.1:9090/prometheus/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF

# Создание самоподписанных сертификатов (временно)
log "🔐 Создание временных SSL сертификатов..."
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/private/routerus.key \
    -out /etc/ssl/certs/routerus.crt \
    -subj "/C=RU/ST=Moscow/L=Moscow/O=Routerus/CN=routerus.ru"

# Активация сайта
ln -sf /etc/nginx/sites-available/routerus /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Проверка конфигурации Nginx
nginx -t

# Запуск Nginx
systemctl enable nginx
systemctl restart nginx

# Сборка и запуск Docker контейнеров
log "🏗️ Сборка Docker образов..."
cd /opt/routerus
docker compose build --no-cache

log "🚀 Запуск веб-интерфейса..."
docker compose up -d

# Ожидание запуска сервисов
log "⏳ Ожидание запуска сервисов..."
sleep 30

# Проверка статуса
log "📊 Проверка статуса сервисов..."
docker compose ps

# Проверка API
log "🔍 Проверка API..."
if curl -f http://localhost:8000/health &>/dev/null; then
    log "✅ Backend API доступен"
else
    warn "⚠️ Backend API пока недоступен"
fi

# Проверка Nginx
if curl -f http://localhost/ &>/dev/null; then
    log "✅ Nginx работает"
else
    warn "⚠️ Nginx недоступен"
fi

# Настройка автозапуска
log "🔄 Настройка автозапуска..."
cat > /etc/systemd/system/routerus-web.service << 'EOF'
[Unit]
Description=Routerus Web Interface
Requires=docker.service nginx.service
After=docker.service nginx.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/routerus
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

systemctl enable routerus-web
systemctl daemon-reload

# Создание скрипта управления
log "🛠️ Создание скрипта управления..."
cat > /usr/local/bin/routerus-web << 'EOF'
#!/bin/bash
cd /opt/routerus

case "$1" in
    start)
        echo "Запуск веб-интерфейса..."
        docker compose up -d
        systemctl start nginx
        ;;
    stop)
        echo "Остановка веб-интерфейса..."
        docker compose down
        systemctl stop nginx
        ;;
    restart)
        echo "Перезапуск веб-интерфейса..."
        docker compose restart
        systemctl restart nginx
        ;;
    status)
        echo "=== Статус контейнеров ==="
        docker compose ps
        echo ""
        echo "=== Статус Nginx ==="
        systemctl status nginx --no-pager -l
        echo ""
        echo "=== Использование ресурсов ==="
        docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"
        ;;
    logs)
        docker compose logs -f
        ;;
    nginx-logs)
        tail -f /var/log/nginx/access.log /var/log/nginx/error.log
        ;;
    ssl)
        echo "Получение SSL сертификата..."
        certbot --nginx -d routerus.ru -d www.routerus.ru --non-interactive --agree-tos -m admin@routerus.ru
        ;;
    update)
        echo "Обновление веб-интерфейса..."
        cd frontend && npm run build && cd ..
        docker compose pull
        docker compose up -d
        systemctl reload nginx
        ;;
    *)
        echo "Использование: $0 {start|stop|restart|status|logs|nginx-logs|ssl|update}"
        exit 1
        ;;
esac
EOF

chmod +x /usr/local/bin/routerus-web

# Финальная информация
log "🎉 Установка веб-интерфейса завершена!"
echo ""
echo -e "${BLUE}📋 Информация о сервере:${NC}"
echo "IP адрес: $SERVER_IP"
echo "HTTP: http://$SERVER_IP"
echo "HTTPS: https://$SERVER_IP"
echo "Grafana: https://$SERVER_IP/grafana"
echo "Prometheus: https://$SERVER_IP/prometheus"
echo ""
echo -e "${BLUE}🔧 Команды управления:${NC}"
echo "routerus-web start       - запуск"
echo "routerus-web stop        - остановка"
echo "routerus-web restart     - перezапуск"
echo "routerus-web status      - статус"
echo "routerus-web logs        - логи"
echo "routerus-web ssl         - получить SSL сертификат"
echo ""
echo -e "${YELLOW}⚠️ Следующие шаги:${NC}"
echo "1. Настройте DNS: A-запись routerus.ru -> $SERVER_IP"
echo "2. Получите SSL: routerus-web ssl"
echo "3. Подключите VPN сервер в веб-интерфейсе"
echo ""
echo -e "${GREEN}✅ Веб-интерфейс готов к работе!${NC}"

# Показываем статус
routerus-web status
