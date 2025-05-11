import os
import subprocess
import ipaddress
import base64
import json
from typing import Dict, List, Optional, Tuple
import qrcode
from io import BytesIO
import random

from app.core.config import settings


class WireGuardManager:
    def __init__(self):
        self.config_dir = settings.WG_CONFIG_DIR
        self.interface = settings.WG_INTERFACE
        self.network = ipaddress.IPv4Network(settings.WG_NETWORK)
        self.port = settings.WG_PORT
        self.server_private_key = settings.WG_PRIVATE_KEY
        self.server_public_key = settings.WG_PUBLIC_KEY

        # Инициализируем ключи сервера, если их нет
        if not self.server_private_key or not self.server_public_key:
            self._initialize_server_keys()

    def _initialize_server_keys(self) -> Tuple[str, str]:
        """Инициализация серверных ключей WireGuard."""
        private_key_file = os.path.join(self.config_dir, f"{self.interface}_private.key")
        public_key_file = os.path.join(self.config_dir, f"{self.interface}_public.key")

        if os.path.exists(private_key_file) and os.path.exists(public_key_file):
            with open(private_key_file, "r") as f:
                settings.WG_PRIVATE_KEY = f.read().strip()
            with open(public_key_file, "r") as f:
                settings.WG_PUBLIC_KEY = f.read().strip()
        else:
            try:
                # Генерация приватного ключа
                private_key = subprocess.check_output(["wg", "genkey"]).decode("utf-8").strip()
                with open(private_key_file, "w") as f:
                    f.write(private_key)
                    os.chmod(private_key_file, 0o600)  # Только чтение/запись для владельца
                
                # Генерация публичного ключа
                public_key = subprocess.check_output(["wg", "pubkey"], input=private_key.encode()).decode("utf-8").strip()
                with open(public_key_file, "w") as f:
                    f.write(public_key)
                
                settings.WG_PRIVATE_KEY = private_key
                settings.WG_PUBLIC_KEY = public_key
            except subprocess.CalledProcessError as e:
                raise Exception(f"Ошибка при генерации ключей WireGuard: {str(e)}")

        return settings.WG_PRIVATE_KEY, settings.WG_PUBLIC_KEY

    def _find_available_ip(self, existing_configs: List[Dict]) -> str:
        """Найти свободный IP-адрес из подсети."""
        # Исключаем адрес сети, широковещательный адрес и адрес сервера
        reserved_ips = {str(self.network.network_address), str(self.network.broadcast_address), str(next(self.network.hosts()))}
        used_ips = {cfg.get("ip_address") for cfg in existing_configs if cfg.get("ip_address")}
        
        for ip in self.network.hosts():
            ip_str = str(ip)
            if ip_str not in reserved_ips and ip_str not in used_ips:
                return ip_str
                
        raise Exception("Нет доступных IP-адресов в подсети.")

    def create_client_config(self, name: str, existing_configs: List[Dict]) -> Dict:
        """Создать новую конфигурацию клиента WireGuard."""
        # Генерация ключей клиента
        private_key = subprocess.check_output(["wg", "genkey"]).decode("utf-8").strip()
        public_key = subprocess.check_output(["wg", "pubkey"], input=private_key.encode()).decode("utf-8").strip()
        
        # Назначение IP
        ip_address = self._find_available_ip(existing_configs)
        
        # Настройки конфигурации клиента
        server_endpoint = f"{settings.SERVER_HOST}:{settings.WG_PORT}"
        
        # Создание конфигурации в формате INI
        client_config = f"""[Interface]
PrivateKey = {private_key}
Address = {ip_address}/32
DNS = 1.1.1.1, 8.8.8.8

[Peer]
PublicKey = {settings.WG_PUBLIC_KEY}
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = {server_endpoint}
PersistentKeepalive = 25
"""
        
        # Создание QR-кода
        qr = qrcode.QRCode(
            version=1,
            error_correction=qrcode.constants.ERROR_CORRECT_L,
            box_size=10,
            border=4,
        )
        qr.add_data(client_config)
        qr.make(fit=True)
        
        img = qr.make_image(fill_color="black", back_color="white")
        buffer = BytesIO()
        img.save(buffer, format="PNG")
        qr_code_base64 = base64.b64encode(buffer.getvalue()).decode("utf-8")
        
        return {
            "name": name,
            "vpn_type": "wireguard",
            "private_key": private_key,
            "public_key": public_key,
            "ip_address": ip_address,
            "config_data": client_config,
            "qr_code": qr_code_base64
        }

    def update_server_config(self, clients: List[Dict]) -> None:
        """Обновить серверную конфигурацию WireGuard на основе списка клиентов."""
        # Получаем первый хост для сервера
        server_ip = str(next(self.network.hosts()))
        
        # Создаем заголовок конфигурации
        config = f"""[Interface]
PrivateKey = {settings.WG_PRIVATE_KEY}
Address = {server_ip}/{self.network.prefixlen}
ListenPort = {settings.WG_PORT}
"""
        
        # Добавляем постобработку для включения форвардинга и NAT
        config += """
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
"""
        
        # Добавляем пиры (клиенты)
        for client in clients:
            if client.get("vpn_type") == "wireguard" and client.get("is_active", True):
                config += f"""
[Peer]
PublicKey = {client.get("public_key")}
AllowedIPs = {client.get("ip_address")}/32
"""
        
        # Сохраняем конфигурацию
        config_path = os.path.join(self.config_dir, f"{self.interface}.conf")
        with open(config_path, "w") as f:
            f.write(config)
            os.chmod(config_path, 0o600)  # Только чтение/запись для владельца
        
        # Перезапускаем интерфейс WireGuard если он уже запущен
        try:
            subprocess.run(["wg", "show", self.interface], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            # Если команда выполнилась успешно, значит интерфейс существует, перезапускаем его
            subprocess.run(["wg", "syncconf", self.interface, config_path], check=True)
        except subprocess.CalledProcessError:
            # Интерфейс не существует, создаем его
            subprocess.run(["ip", "link", "add", "dev", self.interface, "type", "wireguard"], check=True)
            subprocess.run(["wg", "setconf", self.interface, config_path], check=True)
            subprocess.run(["ip", "addr", "add", f"{server_ip}/{self.network.prefixlen}", "dev", self.interface], check=True)
            subprocess.run(["ip", "link", "set", "up", "dev", self.interface], check=True)


wireguard_manager = WireGuardManager()
