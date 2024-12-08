import os
from pathlib import Path

# Основные настройки
BASE_DIR = Path(__file__).resolve().parent.parent.parent

SECRET_KEY = os.getenv('SECRET_KEY', 'your-secret-key-here')
DEBUG = os.getenv('DEBUG', 'False') == 'True'
ALLOWED_HOSTS = os.getenv('ALLOWED_HOSTS', 'localhost,127.0.0.1').split(',')

# Приложения Django
INSTALLED_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
    'app',  # Основное приложение
]

MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]

ROOT_URLCONF = 'app.services.urls'

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [BASE_DIR / 'app/templates'],  # Исправлено на app/templates
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.debug',
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
            ],
        },
    },
]

WSGI_APPLICATION = 'config.wsgi.application'

# Настройки базы данных
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': os.getenv('DB_NAME', 'wg_manager_db'),
        'USER': os.getenv('DB_USER', 'wg_user'),
        'PASSWORD': os.getenv('DB_PASSWORD', 'your_password_here'),
        'HOST': os.getenv('DB_HOST', 'localhost'),
        'PORT': os.getenv('DB_PORT', '5432'),
    }
}

# Интернационализация
LANGUAGE_CODE = 'en-us'
TIME_ZONE = os.getenv('TZ', 'UTC')
USE_I18N = True
USE_L10N = True
USE_TZ = True

# Статические файлы
STATIC_URL = '/static/'
STATICFILES_DIRS = [BASE_DIR / 'app/static']

# Логирование
LOGGING = {
    'version': 1,
    'disable_existing_loggers': False,
    'handlers': {
        'console': {
            'level': 'DEBUG',
            'class': 'logging.StreamHandler',
        },
    },
    'loggers': {
        'django': {
            'handlers': ['console'],
            'level': 'DEBUG' if DEBUG else 'INFO',
            'propagate': True,
        },
    },
}


# Дополнительные настройки безопасности
if not DEBUG:
    CSRF_COOKIE_SECURE = True
    SESSION_COOKIE_SECURE = True
    SECURE_BROWSER_XSS_FILTER = True
    SECURE_CONTENT_TYPE_NOSNIFF = True
    SECURE_HSTS_SECONDS = 31536000
    SECURE_HSTS_INCLUDE_SUBDOMAINS = True
    SECURE_HSTS_PRELOAD = True

# Dropbox
DROPBOX_ACCESS_TOKEN = os.getenv('DROPBOX_ACCESS_TOKEN', None)
DROPBOX_APP_KEY = os.getenv('DROPBOX_APP_KEY', None)
DROPBOX_APP_SECRET = os.getenv('DROPBOX_APP_SECRET', None)

# Shadowsocks
SHADOWSOCKS_SERVER = os.getenv('SHADOWSOCKS_SERVER', '127.0.0.1')
SHADOWSOCKS_PORT = int(os.getenv('SHADOWSOCKS_PORT', 8388))
SHADOWSOCKS_PASSWORD = os.getenv('SHADOWSOCKS_PASSWORD', 'password')
SHADOWSOCKS_METHOD = os.getenv('SHADOWSOCKS_METHOD', 'chacha20-ietf-poly1305')
SHADOWSOCKS_TIMEOUT = int(os.getenv('SHADOWSOCKS_TIMEOUT', 300))

# Xray
XRAY_LOG_LEVEL = os.getenv('XRAY_LOG_LEVEL', 'info')
XRAY_VLESS_PORT = int(os.getenv('XRAY_VLESS_PORT', 443))
XRAY_UUID = os.getenv('XRAY_UUID', None)
XRAY_VLESS_NETWORK = os.getenv('XRAY_VLESS_NETWORK', 'ws')
XRAY_VLESS_PATH = os.getenv('XRAY_VLESS_PATH', '/vless')
XRAY_SHADOWSOCKS_PORT = int(os.getenv('XRAY_SHADOWSOCKS_PORT', 8388))
XRAY_SHADOWSOCKS_METHOD = os.getenv('XRAY_SHADOWSOCKS_METHOD', 'chacha20-ietf-poly1305')
XRAY_SHADOWSOCKS_PASSWORD = os.getenv('XRAY_SHADOWSOCKS_PASSWORD', None)

# WireGuard
WIREGUARD_PRIVATE_KEY = os.getenv('WIREGUARD_PRIVATE_KEY', None)
WIREGUARD_SERVER_PUBLIC_KEY = os.getenv('WIREGUARD_SERVER_PUBLIC_KEY', None)
WIREGUARD_SERVER_IP = os.getenv('WIREGUARD_SERVER_IP', '127.0.0.1')
WIREGUARD_SERVER_PORT = int(os.getenv('WIREGUARD_SERVER_PORT', 51820))
WIREGUARD_PEERDNS = os.getenv('WIREGUARD_PEERDNS', '1.1.1.1')
WIREGUARD_ALLOWEDIPS = os.getenv('WIREGUARD_ALLOWEDIPS', '0.0.0.0/0,::/0')
WIREGUARD_PERSISTENTKEEPALIVE = int(os.getenv('WIREGUARD_PERSISTENTKEEPALIVE', 25))
