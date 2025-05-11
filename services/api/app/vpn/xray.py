import os
import json
import base64
import uuid
import qrcode
from io import BytesIO
from typing import Dict, List, Optional
import random

from app.core.config import settings


class XrayManager:
    def __init__(self):
        self.config_dir = settings.XRAY_CONFIG_DIR
        self.port = settings.XRAY_PORT
        self.server_uuid = settings.XRAY_UUID
        
        # Инициализируем UUID сервера, если его нет
        if not self.server_uuid:
            self._initialize_server_uuid()
    
    def _initialize_server_uuid(self) -> str:
        """Инициализация UUID сервера Xray."""
        uuid_file = os.path.join(self.config_dir, "uuid.txt")
        
        if os.path.exists(uuid_file):
            with open(uuid_file, "r") as f:
                settings.XRAY_UUID = f.read().strip()
        else:
            # Генерация UUID
            settings.XRAY_UUID = str(uuid.uuid4())
            with open(uuid_file, "w") as f:
                f.write(settings.XRAY_UUID)
                os.chmod(uuid_file, 0o600)  # Только чтение/запись для владельца
        
        return settings.XRAY_UUID
    
    def create_client_config(self, name: str) -> Dict:
        """Создать новую конфигурацию клиента Xray (VLESS over WebSocket over TLS)."""
        # Генерация UUID для клиента
        client_uuid = str(uuid.uuid4())
        
        # Имитируем популярные сайты для SNI спуфинга
        popular_domains = ["www.google.com", "www.microsoft.com", "www.apple.com", "www.amazon.com", "www.cloudflare.com"]
        fake_sni = random.choice(popular_domains)
        
        # Создание конфигурации клиента в формате JSON
        client_config = {
            "outbounds": [
                {
                    "protocol": "vless",
                    "settings": {
                        "vnext": [
                            {
                                "address": settings.SERVER_HOST,
                                "port": self.port,
                                "users": [
                                    {
                                        "id": client_uuid,
                                        "encryption": "none"
                                    }
                                ]
                            }
                        ]
                    },
                    "streamSettings": {
                        "network": "ws",
                        "security": "tls",
                        "tlsSettings": {
                            "serverName": fake_sni,  # SNI спуфинг
                            "allowInsecure": False
                        },
                        "wsSettings": {
                            "path": "/ws",
                            "headers": {
                                "Host": settings.SERVER_HOST
                            }
                        }
                    }
                }
            ]
        }
        
        # Создание строки для QR-кода
        vless_link = f"vless://{client_uuid}@{settings.SERVER_HOST}:{self.port}?type=ws&security=tls&path=/ws&host={settings.SERVER_HOST}&sni={fake_sni}#{name}"
        
        # Создание QR-кода
        qr = qrcode.QRCode(
            version=1,
            error_correction=qrcode.constants.ERROR_CORRECT_L,
            box_size=10,
            border=4,
        )
        qr.add_data(vless_link)
        qr.make(fit=True)
        
        img = qr.make_image(fill_color="black", back_color="white")
        buffer = BytesIO()
        img.save(buffer, format="PNG")
        qr_code_base64 = base64.b64encode(buffer.getvalue()).decode("utf-8")
        
        return {
            "name": name,
            "vpn_type": "xray",
            "uuid": client_uuid,
            "config_data": json.dumps(client_config),
            "qr_code": qr_code_base64,
            "vless_link": vless_link,
            "sni": fake_sni
        }
    
    def update_server_config(self, clients: List[Dict]) -> None:
        """Обновить серверную конфигурацию Xray на основе списка клиентов."""
        # Список клиентских UUID
        client_ids = []
        
        for client in clients:
            if client.get("vpn_type") == "xray" and client.get("is_active", True):
                client_uuid = client.get("uuid")
                if client_uuid:
                    client_ids.append({
                        "id": client_uuid,
                        "level": 0
                    })
        
        # Добавляем серверный UUID, если нет активных клиентов
        if not client_ids:
            client_ids.append({
                "id": settings.XRAY_UUID,
                "level": 0
            })
        
        # Создание серверной конфигурации Xray
        server_config = {
            "log": {
                "loglevel": "warning"
            },
            "inbounds": [
                {
                    "port": self.port,
                    "protocol": "vless",
                    "settings": {
                        "clients": client_ids,
                        "decryption": "none"
                    },
                    "streamSettings": {
                        "network": "ws",
                        "security": "tls",
                        "tlsSettings": {
                            "certificates": [
                                {
                                    "certificateFile": "/etc/ssl/xray/server.crt",
                                    "keyFile": "/etc/ssl/xray/server.key"
                                }
                            ]
                        },
                        "wsSettings": {
                            "path": "/ws",
                            "maxConnectionIdleInMinutes": 3
                        }
                    }
                }
            ],
            "outbounds": [
                {
                    "protocol": "freedom"
                }
            ],
            "routing": {
                "rules": [
                    {
                        "type": "field",
                        "ip": ["geoip:private"],
                        "outboundTag": "blocked"
                    }
                ]
            }
        }
        
        # Сохраняем конфигурацию
        config_path = os.path.join(self.config_dir, "config.json")
        with open(config_path, "w") as f:
            json.dump(server_config, f, indent=4)
            os.chmod(config_path, 0o644)  # Чтение/запись для владельца, чтение для всех


xray_manager = XrayManager()
