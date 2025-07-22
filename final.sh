# 1. Переключаемся на development режим для локальной разработки
export DJANGO_SETTINGS_MODULE="config.settings.development"

# 2. Обновляем .env файл для правильного окружения
sed -i '' 's/DJANGO_SETTINGS_MODULE="config.settings.production"/DJANGO_SETTINGS_MODULE="config.settings.development"/' .env 2>/dev/null || \
sed -i 's/DJANGO_SETTINGS_MODULE="config.settings.production"/DJANGO_SETTINGS_MODULE="config.settings.development"/' .env

# 3. Создаем директории для логов (на случай если понадобятся)
sudo mkdir -p /var/log/routerus
sudo chown $USER:staff /var/log/routerus 2>/dev/null || sudo chown $USER:$USER /var/log/routerus

# 4. Исправляем production.py - делаем логирование более безопасным
cat > config/settings/production.py << 'EOF'
from .base import *

DEBUG = False
ALLOWED_HOSTS = os.getenv("ALLOWED_HOSTS", "").split(",")

# Security settings
SECURE_BROWSER_XSS_FILTER = True
SECURE_CONTENT_TYPE_NOSNIFF = True
X_FRAME_OPTIONS = "DENY"
SECURE_HSTS_SECONDS = 31536000
SECURE_HSTS_INCLUDE_SUBDOMAINS = True
SECURE_HSTS_PRELOAD = True

if not DEBUG:
    CSRF_COOKIE_SECURE = True
    SESSION_COOKIE_SECURE = True

# Безопасное логирование для production
import os
LOG_DIR = "/var/log/routerus"
if not os.path.exists(LOG_DIR):
    os.makedirs(LOG_DIR, exist_ok=True)

LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {
        "verbose": {
            "format": "{levelname} {asctime} {module} {process:d} {thread:d} {message}",
            "style": "{",
        },
    },
    "handlers": {
        "file": {
            "level": "INFO",
            "class": "logging.FileHandler",
            "filename": f"{LOG_DIR}/django.log",
            "formatter": "verbose",
        },
        "console": {
            "level": "ERROR",
            "class": "logging.StreamHandler",
            "formatter": "verbose",
        },
    },
    "root": {
        "handlers": ["file", "console"],
        "level": "INFO",
    },
}
EOF

# 5. Проверяем Django
echo "🧪 Проверяем Django с development настройками:"
python manage.py check

# 6. Если все ОК, создаем миграции
if [ $? -eq 0 ]; then
    echo "✅ Django проверка прошла успешно!"
    echo "📝 Создаем миграции для новой структуры:"
    python manage.py makemigrations vpn_management
fi
