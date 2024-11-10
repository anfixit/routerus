import os
from dotenv import load_dotenv
import yaml

load_dotenv()

def load_services_config():
    with open('config/services_config.yaml', 'r') as file:
        config = yaml.safe_load(file)
    return config

def load_shadowsocks_config():
    config = load_services_config()
    return config['shadowsocks']

import os
import yaml

def load_services_config():
    config_path = os.getenv('CONFIG_PATH', 'config_manager/services_config.yaml')
    try:
        with open(config_path, 'r') as file:
            return yaml.safe_load(file)
    except FileNotFoundError:
        raise FileNotFoundError(f"Конфигурационный файл {config_path} не найден. Убедитесь, что файл существует и путь указан правильно.")
    except yaml.YAMLError as e:
        raise Exception(f"Ошибка при чтении YAML файла: {e}")

def load_xray_config():
    config = load_services_config()
    if 'xray' not in config:
        raise KeyError("Конфигурация 'xray' не найдена в файле services_config.yaml.")
    return config['xray']

def load_wireguard_config():
    config = load_services_config()
    if 'wireguard' not in config:
        raise KeyError("Конфигурация 'wireguard' не найдена в файле services_config.yaml.")
    return config['wireguard']

def generate_wireguard_config():
    wireguard_config = load_wireguard_config()
    
    try:
        interface_config = wireguard_config['config']
    except KeyError:
        raise KeyError("Раздел 'config' не найден в конфигурации WireGuard.")
    
    config_content = f"""
    [Interface]
    PrivateKey = {interface_config['PrivateKey']}
    Address = {interface_config['Address']}
    DNS = {interface_config['DNS']}

    [Peer]
    PublicKey = {interface_config['PublicKey']}
    Endpoint = {interface_config['Endpoint']}
    AllowedIPs = {interface_config['AllowedIPs']}
    PersistentKeepalive = {interface_config['PersistentKeepalive']}
    """
    
    config_path = '/etc/wireguard/wg0.conf'
    try:
        with open(config_path, 'w') as config_file:
            config_file.write(config_content.strip())
        print(f"Конфигурационный файл WireGuard успешно сохранен: {config_path}")
    except PermissionError:
        raise PermissionError(f"Недостаточно прав для записи в файл {config_path}. Попробуйте запустить с правами суперпользователя.")
