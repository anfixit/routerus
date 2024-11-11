# config/settings.py

import os
from pathlib import Path
import environ

# Инициализация django-environ
env = environ.Env(
    DEBUG=(bool, False)
)

# Чтение файла .env
BASE_DIR = Path(__file__).resolve().parent.parent
environ.Env.read_env(os.path.join(BASE_DIR, '.env'))

# Настройки безопасности
SECRET_KEY = env('SECRET_KEY', default='your-default-secret-key-here')
DEBUG = env.bool('DEBUG', default=False)
ALLOWED_HOSTS = env.list('ALLOWED_HOSTS', default=['localhost', '127.0.0.1'])

# Настройки базы данных
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': env('DB_NAME', default='wg_manager_db'),
        'USER': env('DB_USER', default='wg_user'),
        'PASSWORD': env('DB_PASSWORD', default='zamiralovesme8'),
        'HOST': env('DB_HOST', default='localhost'),
        'PORT': env('DB_PORT', default='5432'),
    }
}

# Настройки Shadowsocks
SHADOWSOCKS_SERVER = env('SHADOWSOCKS_SERVER')
SHADOWSOCKS_PORT = env.int('SHADOWSOCKS_PORT', default=8388)
SHADOWSOCKS_PASSWORD = env('SHADOWSOCKS_PASSWORD')
SHADOWSOCKS_METHOD = env('SHADOWSOCKS_METHOD', default='chacha20-ietf-poly1305')
SHADOWSOCKS_TIMEOUT = env.int('SHADOWSOCKS_TIMEOUT', default=300)

# Настройки Xray
XRAY_ACCESS_LOG_PATH = env('XRAY_ACCESS_LOG_PATH', default='/var/log/xray/access.log')
XRAY_ERROR_LOG_PATH = env('XRAY_ERROR_LOG_PATH', default='/var/log/xray/error.log')
XRAY_LOG_LEVEL = env('XRAY_LOG_LEVEL', default='info')

# Xray Inbound Settings
XRAY_SHADOWSOCKS_PORT = env.int('XRAY_SHADOWSOCKS_PORT', default=8388)
XRAY_SHADOWSOCKS_METHOD = env('XRAY_SHADOWSOCKS_METHOD', default='chacha20-ietf-poly1305')
XRAY_SHADOWSOCKS_PASSWORD = env('XRAY_SHADOWSOCKS_PASSWORD')
XRAY_WIREGUARD_PORT = env.int('XRAY_WIREGUARD_PORT', default=51820)
XRAY_WIREGUARD_SECRET_KEY = env('XRAY_WIREGUARD_SECRET_KEY')
XRAY_WIREGUARD_PUBLIC_KEY = env('XRAY_WIREGUARD_PUBLIC_KEY')
XRAY_WIREGUARD_ADDRESS = env('XRAY_WIREGUARD_ADDRESS')
XRAY_VLESS_PORT = env.int('XRAY_VLESS_PORT', default=443)
XRAY_UUID = env('XRAY_UUID')
XRAY_VLESS_NETWORK = env('XRAY_VLESS_NETWORK', default='ws')
XRAY_VLESS_PATH = env('XRAY_VLESS_PATH', default='/vless')

# Настройки WireGuard
WIREGUARD_PRIVATE_KEY = env('WIREGUARD_PRIVATE_KEY')
WIREGUARD_SERVER_PUBLIC_KEY = env('WIREGUARD_SERVER_PUBLIC_KEY')
WIREGUARD_SERVER_IP = env('WIREGUARD_SERVER_IP')
WIREGUARD_SERVER_PORT = env.int('WIREGUARD_SERVER_PORT', default=51820)
WIREGUARD_PEERDNS = env('WIREGUARD_PEERDNS', default='1.1.1.1')
WIREGUARD_ALLOWEDIPS = env('WIREGUARD_ALLOWEDIPS', default='0.0.0.0/0, ::/0')
WIREGUARD_PERSISTENTKEEPALIVE = env.int('WIREGUARD_PERSISTENTKEEPALIVE', default=25)

# Настройки для статических и медиа-файлов
STATIC_URL = '/static/'
MEDIA_URL = '/media/'

# Автоматическое поле для первичного ключа
DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'
