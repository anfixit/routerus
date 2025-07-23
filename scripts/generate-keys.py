#!/usr/bin/env python3
"""
Генератор ключей и паролей для Routerus V2
"""

import secrets
import string
import base64
import uuid
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
import os

def generate_password(length=32):
    """Генерирует безопасный пароль"""
    alphabet = string.ascii_letters + string.digits + "!@#$%^&*"
    return ''.join(secrets.choice(alphabet) for _ in range(length))

def generate_jwt_secret():
    """Генерирует JWT секрет"""
    return secrets.token_urlsafe(64)

def generate_api_secret():
    """Генерирует API секрет"""
    return secrets.token_urlsafe(48)

def generate_reality_keys():
    """Генерирует пару ключей для Reality"""
    # Генерируем 32-байтные ключи
    private_key = secrets.token_bytes(32)
    public_key = secrets.token_bytes(32)

    # Кодируем в base64
    private_b64 = base64.b64encode(private_key).decode()
    public_b64 = base64.b64encode(public_key).decode()

    return private_b64, public_b64

def generate_short_ids(count=3):
    """Генерирует короткие ID для Reality"""
    return [secrets.token_hex(8) for _ in range(count)]

def generate_uuid():
    """Генерирует UUID"""
    return str(uuid.uuid4())

def update_env_file(env_path=".env"):
    """Обновляет .env файл сгенерированными ключами"""

    # Генерируем все ключи
    jwt_secret = generate_jwt_secret()
    api_secret = generate_api_secret()
    admin_password = generate_password(16)
    grafana_password = generate_password(16)
    reality_private, reality_public = generate_reality_keys()
    short_ids = generate_short_ids()

    print("🔑 Генерация ключей для Routerus V2...")
    print("=" * 50)

    # Читаем существующий .env файл
    env_content = {}
    if os.path.exists(env_path):
        with open(env_path, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    env_content[key.strip()] = value.strip()

    # Обновляем только пустые ключи
    updates = {
        'JWT_SECRET': jwt_secret,
        'VPN_API_SECRET': api_secret,
        'ADMIN_PASSWORD': admin_password,
        'GRAFANA_PASSWORD': grafana_password,
        'REALITY_PRIVATE_KEY': reality_private,
        'REALITY_PUBLIC_KEY': reality_public,
        'REALITY_SHORT_IDS': ','.join(short_ids),
    }

    # Проверяем какие ключи нужно обновить
    updated_keys = []
    for key, new_value in updates.items():
        current_value = env_content.get(key, '').strip('"\'')
        if not current_value or current_value in [
            'your-super-secret-jwt-key-change-this-in-production',
            'your-super-secret-api-key-for-vpn-communication',
            'your-strong-admin-password',
            'your-grafana-admin-password',
        ]:
            env_content[key] = new_value
            updated_keys.append(key)

    # Записываем обновленный .env файл
    with open(env_path, 'w', encoding='utf-8') as f:
        f.write("# ===================================================================\n")
        f.write("# Routerus V2 - Конфигурация системы\n")
        f.write("# ===================================================================\n\n")

        sections = {
            'СЕРВЕРЫ': ['WEB_SERVER_IP', 'WEB_DOMAIN', 'VPN_SERVER_IP', 'VPN_DOMAIN', 'VPN_SERVERS'],
            'БЕЗОПАСНОСТЬ': ['JWT_SECRET', 'VPN_API_SECRET', 'ADMIN_PASSWORD'],
            'БАЗА ДАННЫХ': ['DATABASE_URL'],
            'МОНИТОРИНГ': ['GRAFANA_PASSWORD', 'SMTP_HOST', 'SMTP_USER', 'SMTP_PASSWORD'],
            'TELEGRAM BOT': ['TELEGRAM_BOT_TOKEN', 'ADMIN_CHAT_ID'],
            'VPN КОНФИГУРАЦИЯ': ['VLESS_PORT', 'VLESS_FLOW', 'REALITY_DEST', 'REALITY_SERVER_NAME', 'REALITY_SNI', 'REALITY_PRIVATE_KEY', 'REALITY_PUBLIC_KEY', 'REALITY_SHORT_IDS'],
            'SSL СЕРТИФИКАТЫ': ['LETSENCRYPT_EMAIL', 'SSL_DOMAINS'],
            'ЛОГИРОВАНИЕ': ['LOG_LEVEL', 'LOG_MAX_SIZE', 'LOG_BACKUP_COUNT'],
            'РЕЗЕРВНОЕ КОПИРОВАНИЕ': ['BACKUP_PATH', 'BACKUP_SCHEDULE', 'BACKUP_RETENTION_DAYS'],
            'РАЗРАБОТКА': ['DEBUG', 'AUTO_RELOAD', 'CORS_ORIGINS'],
            'ДОПОЛНИТЕЛЬНЫЕ НАСТРОЙКИ': ['TZ', 'MAX_CONNECTIONS_PER_USER', 'TOKEN_EXPIRE_SECONDS', 'DEFAULT_TRAFFIC_LIMIT', 'INACTIVE_USER_CLEANUP_DAYS']
        }

        for section, keys in sections.items():
            f.write(f"# {section}\n")
            f.write("# " + "=" * 50 + "\n")
            for key in keys:
                if key in env_content:
                    value = env_content[key]
                    f.write(f"{key}={value}\n")
            f.write("\n")

    print("✅ Ключи успешно сгенерированы и сохранены в .env файл")
    print("\n📋 Обновленные ключи:")
    for key in updated_keys:
        if 'PASSWORD' in key or 'SECRET' in key or 'KEY' in key:
            print(f"  {key}: {'*' * 20} (скрыт)")
        else:
            print(f"  {key}: {env_content[key]}")

    print("\n⚠️  ВАЖНЫЕ ДАННЫЕ ДЛЯ ЗАПИСИ:")
    print("=" * 50)
    print(f"🔐 Пароль администратора: {admin_password}")
    print(f"📊 Пароль Grafana: {grafana_password}")
    print(f"🔑 Reality Public Key: {reality_public}")

    print("\n📝 ЧТО НУЖНО ДОПОЛНИТЬ ВРУЧНУЮ:")
    print("=" * 50)
    print("1. TELEGRAM_BOT_TOKEN - получи у @BotFather")
    print("2. ADMIN_CHAT_ID - получи у @userinfobot")
    print("3. LETSENCRYPT_EMAIL - твой email для SSL сертификатов")
    print("4. SMTP настройки - если нужны email алерты")

    return env_content

if __name__ == "__main__":
    # Проверяем зависимости
    try:
        from cryptography.hazmat.primitives import hashes
    except ImportError:
        print("❌ Установи cryptography: pip install cryptography")
        exit(1)

    update_env_file()
