#!/bin/bash
# setup_server.sh: Полная автоматическая настройка сервера для Routerus

set -e

echo "🚀 Начинаем автоматическую настройку Routerus VPN сервера..."

# Проверка прав root
if [[ $EUID -ne 0 ]]; then
   echo "❌ Этот скрипт должен запускаться с правами root (sudo)"
   exit 1
fi

# Определение пользователя (для случая sudo)
REAL_USER=${SUDO_USER:-$(whoami)}
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

# Конфигурация
PROJECT_DIR="/opt/routerus"
VENV_DIR="$PROJECT_DIR/venv"
LOG_DIR="/var/log/routerus"

echo "📦 Обновление системы и установка пакетов..."
apt update && apt upgrade -y
apt install -y python3.12 python3.12-venv python3-pip postgresql postgresql-contrib \
    nginx wireguard-tools git curl ufw build-essential libpq-dev

echo "📁 Создание рабочей директории..."
mkdir -p "$PROJECT_DIR"
mkdir -p "$LOG_DIR"
chown -R "$REAL_USER:$REAL_USER" "$PROJECT_DIR"
chown -R "$REAL_USER:$REAL_USER" "$LOG_DIR"

echo "🐍 Создание виртуального окружения..."
cd "$PROJECT_DIR"
sudo -u "$REAL_USER" python3.12 -m venv "$VENV_DIR"
sudo -u "$REAL_USER" "$VENV_DIR/bin/pip" install --upgrade pip poetry

echo "🗃️ Настройка PostgreSQL..."
systemctl start postgresql
systemctl enable postgresql

# Проверка существования пользователя БД
if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='wg_user'" | grep -q 1; then
    echo "Пользователь wg_user уже существует"
else
    sudo -u postgres createuser --createdb wg_user
fi

# Проверка существования БД
if sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw wg_manager_db; then
    echo "База данных wg_manager_db уже существует"
else
    sudo -u postgres createdb -O wg_user wg_manager_db
fi

# Устанавливаем пароль пользователю БД
sudo -u postgres psql -c "ALTER USER wg_user PASSWORD 'zamiralovesme8becauseimthebest1';"

echo "📋 Создание systemd сервиса..."
cat > /etc/systemd/system/routerus.service << 'EOF'
[Unit]
Description=Routerus VPN Management System
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=exec
User=root
Group=root
WorkingDirectory=/opt/routerus
Environment=DJANGO_SETTINGS_MODULE=config.settings.production
EnvironmentFile=/opt/routerus/.env
ExecStartPre=/opt/routerus/venv/bin/python manage.py migrate
ExecStartPre=/opt/routerus/venv/bin/python manage.py collectstatic --noinput
ExecStart=/opt/routerus/venv/bin/gunicorn config.wsgi:application --bind 0.0.0.0:8000 --workers 3
ExecReload=/bin/kill -HUP $MAINPID
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

# Security settings
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/routerus /var/log/routerus /var/lib/wireguard

[Install]
WantedBy=multi-user.target
EOF

echo "🔥 Настройка firewall..."
ufw --force enable
ufw allow ssh
ufw allow 8000/tcp
ufw allow 51820/udp  # WireGuard
ufw allow 8388/tcp   # Shadowsocks
ufw allow 443/tcp    # Xray
ufw allow 80/tcp     # HTTP
ufw reload

echo "⚙️ Настройка Nginx reverse proxy..."
cat > /etc/nginx/sites-available/routerus << 'EOF'
server {
    listen 80;
    server_name _;

    location /static/ {
        alias /opt/routerus/staticfiles/;
        expires 30d;
    }

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
EOF

# Активация конфигурации Nginx
ln -sf /etc/nginx/sites-available/routerus /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx
systemctl enable nginx

echo "🔐 Включение IP forwarding для VPN..."
echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
echo 'net.ipv6.conf.all.forwarding=1' >> /etc/sysctl.conf
sysctl -p

echo "⚡ Активация сервисов..."
systemctl daemon-reload
systemctl enable routerus

echo "📝 Создание скрипта для быстрого деплоя..."
cat > "$PROJECT_DIR/quick_deploy.sh" << 'EOF'
#!/bin/bash
# Быстрый деплой после git pull
set -e
cd /opt/routerus
source venv/bin/activate
git pull origin main
poetry install --no-dev
python manage.py migrate
python manage.py collectstatic --noinput
sudo systemctl restart routerus
echo "✅ Деплой завершен!"
EOF

chmod +x "$PROJECT_DIR/quick_deploy.sh"
chown "$REAL_USER:$REAL_USER" "$PROJECT_DIR/quick_deploy.sh"

echo ""
echo "✅ Настройка сервера завершена!"
echo ""
echo "📋 Что делать дальше:"
echo "1. Склонируйте ваш проект: cd /opt/routerus && git clone <your-repo> ."
echo "2. Создайте файл .env с вашими настройками"
echo "3. Установите зависимости: source venv/bin/activate && poetry install --no-dev"
echo "4. Запустите сервис: sudo systemctl start routerus"
echo ""
echo "🔧 Полезные команды:"
echo "  sudo systemctl status routerus  - статус сервиса"
echo "  sudo systemctl restart routerus - перезапуск"
echo "  sudo journalctl -u routerus -f  - просмотр логов"
echo "  ./quick_deploy.sh               - быстрый деплой"
echo ""
