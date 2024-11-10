import os
from dotenv import load_dotenv
import yaml

# Load environment variables from .env file
load_dotenv()

# Функция для загрузки общего конфигурационного файла YAML
def load_services_config():
    with open('config/services_config.yaml', 'r') as file:
        config = yaml.safe_load(file)
    return config

# Функция для загрузки конфигурации Shadowsocks
def load_shadowsocks_config():
    config = load_services_config()
    return config['shadowsocks']

# Функция для загрузки конфигурации Xray
def load_xray_config():
    config = load_services_config()
    return config['xray']

# Функция для загрузки конфигурации WireGuard (если нужно)
def load_wireguard_config():
    config = load_services_config()
    return config['wireguard']

def generate_wireguard_config():
    wireguard_config = load_wireguard_config()
    config_content = f"""
    [Interface]
    PrivateKey = {wireguard_config['config']['PrivateKey']}
    Address = {wireguard_config['config']['Address']}
    DNS = {wireguard_config['config']['DNS']}

    [Peer]
    PublicKey = {wireguard_config['config']['PublicKey']}
    Endpoint = {wireguard_config['config']['Endpoint']}
    AllowedIPs = {wireguard_config['config']['AllowedIPs']}
    PersistentKeepalive = {wireguard_config['config']['PersistentKeepalive']}
    """
    # Сохраняем конфигурацию в файл wg0.conf
    with open('/etc/wireguard/wg0.conf', 'w') as config_file:
        config_file.write(config_content)
