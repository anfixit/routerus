import os
import json
from pathlib import Path
from dotenv import load_dotenv

# Загружаем переменные из .env
load_dotenv()

# Базовая директория
BASE_DIR = Path(__file__).resolve().parent.parent
CONFIG_DIR = BASE_DIR / 'config'
WIREGUARD_CONFIG_DIR = CONFIG_DIR / 'wireguard'
XRAY_CONFIG_DIR = CONFIG_DIR / 'xray'

# Создаем необходимые папки
def create_directories():
    required_dirs = [
        CONFIG_DIR,
        WIREGUARD_CONFIG_DIR,
        XRAY_CONFIG_DIR,
        WIREGUARD_CONFIG_DIR / 'clients'
    ]
    for directory in required_dirs:
        if not directory.exists():
            directory.mkdir(parents=True, exist_ok=True)
            print(f"Created directory: {directory}")

# Проверяем, что все переменные окружения установлены
def check_environment_variables():
    required_env_vars = [
        'SECRET_KEY', 'DB_NAME', 'DB_USER', 'DB_PASSWORD', 'DB_HOST',
        'WIREGUARD_PRIVATE_KEY', 'WIREGUARD_SERVER_PUBLIC_KEY',
        'WIREGUARD_SERVER_IP', 'WIREGUARD_SERVER_PORT', 'WIREGUARD_PEERDNS',
        'XRAY_UUID', 'XRAY_VLESS_PORT', 'XRAY_VLESS_PATH'
    ]
    missing_vars = [var for var in required_env_vars if not os.getenv(var)]
    if missing_vars:
        raise EnvironmentError(f"Missing required environment variables: {', '.join(missing_vars)}")
    print("All required environment variables are set.")

# Генерация конфигурации WireGuard
def generate_wireguard_config():
    config_content = f"""
[Interface]
Address = {os.getenv("WIREGUARD_SERVER_IP")}
PrivateKey = {os.getenv("WIREGUARD_PRIVATE_KEY")}
ListenPort = {os.getenv("WIREGUARD_SERVER_PORT")}
DNS = {os.getenv("WIREGUARD_PEERDNS")}

[Peer]
PublicKey = {os.getenv("WIREGUARD_SERVER_PUBLIC_KEY")}
AllowedIPs = {os.getenv("WIREGUARD_ALLOWEDIPS")}
PersistentKeepalive = {os.getenv("WIREGUARD_PERSISTENTKEEPALIVE")}
    """
    with open(WIREGUARD_CONFIG_DIR / 'wg0.conf', 'w') as f:
        f.write(config_content.strip())
    print("WireGuard configuration generated.")

# Генерация конфигурации Shadowsocks
def generate_shadowsocks_config():
    config_content = {
        "server": os.getenv("SHADOWSOCKS_SERVER"),
        "server_port": int(os.getenv("SHADOWSOCKS_PORT")),
        "password": os.getenv("SHADOWSOCKS_PASSWORD"),
        "method": os.getenv("SHADOWSOCKS_METHOD"),
        "timeout": int(os.getenv("SHADOWSOCKS_TIMEOUT"))
    }
    with open(CONFIG_DIR / 'shadowsocks.json', 'w') as f:
        json.dump(config_content, f, indent=4)
    print("Shadowsocks configuration generated.")

# Генерация конфигурации Xray
def generate_xray_config():
    config_content = {
        "log": {
            "access": os.getenv("XRAY_ACCESS_LOG_PATH"),
            "error": os.getenv("XRAY_ERROR_LOG_PATH"),
            "loglevel": os.getenv("XRAY_LOG_LEVEL")
        },
        "inbounds": [
            {
                "port": int(os.getenv("XRAY_VLESS_PORT")),
                "protocol": "vless",
                "settings": {
                    "clients": [
                        {"id": os.getenv("XRAY_UUID")}
                    ],
                    "decryption": "none"
                },
                "streamSettings": {
                    "network": os.getenv("XRAY_VLESS_NETWORK"),
                    "wsSettings": {"path": os.getenv("XRAY_VLESS_PATH")}
                }
            }
        ],
        "outbounds": [{"protocol": "freedom", "settings": {}}]
    }
    with open(XRAY_CONFIG_DIR / 'config.json', 'w') as f:
        json.dump(config_content, f, indent=4)
    print("Xray configuration generated.")

# Основная функция
def main():
    print("Setting up project...")
    create_directories()
    check_environment_variables()
    generate_wireguard_config()
    generate_shadowsocks_config()
    generate_xray_config()
    print("Setup complete. All configuration files are ready.")

if __name__ == "__main__":
    main()
