import os
from pathlib import Path
from dotenv import load_dotenv

# Загружаем переменные из .env
load_dotenv()

# Папки для конфигураций
CONFIG_DIR = Path('./config')
WIREGUARD_CONFIG_DIR = CONFIG_DIR / 'wireguard'
XRAY_CONFIG_DIR = CONFIG_DIR / 'xray'

# Создаем необходимые папки, если их нет
WIREGUARD_CONFIG_DIR.mkdir(parents=True, exist_ok=True)
XRAY_CONFIG_DIR.mkdir(parents=True, exist_ok=True)

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
                        {
                            "id": os.getenv("XRAY_UUID")
                        }
                    ],
                    "decryption": "none"
                },
                "streamSettings": {
                    "network": os.getenv("XRAY_VLESS_NETWORK"),
                    "wsSettings": {
                        "path": os.getenv("XRAY_VLESS_PATH")
                    }
                }
            }
        ],
        "outbounds": [{"protocol": "freedom", "settings": {}}]
    }
    with open(XRAY_CONFIG_DIR / 'config.json', 'w') as f:
        json.dump(config_content, f, indent=4)

def main():
    print("Generating WireGuard configuration...")
    generate_wireguard_config()
    print("Generating Shadowsocks configuration...")
    generate_shadowsocks_config()
    print("Generating Xray configuration...")
    generate_xray_config()
    print("Configuration files have been generated successfully.")

if __name__ == "__main__":
    main()
