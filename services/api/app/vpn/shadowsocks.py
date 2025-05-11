import os
import json
import base64
import uuid
import qrcode
from io import BytesIO
from typing import Dict, List, Optional

from app.core.config import settings


class ShadowsocksManager:
    def __init__(self):
        self.config_dir = settings.SS_CONFIG_DIR
        self.port = settings.SS_PORT
        self.method = settings.SS_METHOD
        self.server_password = settings.SS_PASSWORD
        
        # Инициализируем пароль сервера, если его нет
        if not self.server_password:
            self._initialize_server_password()
    
    def _initialize_server_password(self) -> str:
        """Инициализация пароля сервера Shadowsocks."""
        password_file = os.path.join(self.config_dir, "password.txt")
        
        if os.path.exists(password_file):
            with open(password_file, "r") as f:
                settings.SS_PASSWORD = f.read().strip()
        else:
            # Генерация случайного пароля
            settings.SS_PASSWORD = str(uuid.uuid4())
            with open(password_file, "w") as f:
                f.write(settings.SS_PASSWORD)
                os.chmod(password_file, 0o600)  # Только чтение/запись для владельца
        
        return settings.SS_PASSWORD
    
    def create_client_config(self, name: str, port: Optional[int] = None) -> Dict:
        """Создать новую конфигурацию клиента Shadowsocks."""
        if not port:
            # Используем порт по умолчанию
            port = self.port
            
        # Генерация случайного пароля для клиента
        password = str(uuid.uuid4())
        
        # Создание конфигурации клиента
        client_config = {
            "server": settings.SERVER_HOST,
            "server_port": port,
            "password": password,
            "method": self.method,
            "remarks": name
        }
        
        # Создание URI для QR-кода (ss://base64(method:password@server:port)#name)
        ss_uri = f"{self.method}:{password}@{settings.SERVER_HOST}:{port}"
        ss_uri_encoded = base64.urlsafe_b64encode(ss_uri.encode()).decode()
        ss_uri_full = f"ss://{ss_uri_encoded}#{name}"
        
        # Создание QR-кода
        qr = qrcode.QRCode(
            version=1,
            error_correction=qrcode.constants.ERROR_CORRECT_L,
            box_size=10,
            border=4,
        )
        qr.add_data(ss_uri_full)
        qr.make(fit=True)
        
        img = qr.make_image(fill_color="black", back_color="white")
        buffer = BytesIO()
        img.save(buffer, format="PNG")
        qr_code_base64 = base64.b64encode(buffer.getvalue()).decode("utf-8")
        
        return {
            "name": name,
            "vpn_type": "shadowsocks",
            "password": password,
            "port": port,
            "method": self.method,
            "config_data": json.dumps(client_config),
            "qr_code": qr_code_base64,
            "ss_uri": ss_uri_full
        }
    
    def update_server_config(self, clients: List[Dict]) -> None:
        """Обновить серверную конфигурацию Shadowsocks на основе списка клиентов."""
        # Подготовка списка портов и паролей для активных клиентов
        ports_config = {}
        
        for client in clients:
            if client.get("vpn_type") == "shadowsocks" and client.get("is_active", True):
                port = client.get("port", self.port)
                password = client.get("password")
                if port and password:
                    ports_config[str(port)] = password
        
        # Если нет активных клиентов, используем серверный пароль по умолчанию
        if not ports_config:
            ports_config[str(self.port)] = self.server_password
        
        # Создание базовой конфигурации сервера
        server_config = {
            "server": "0.0.0.0",
            "method": self.method,
            "timeout": 300,
            "port_password": ports_config,
            "fast_open": True,
            "mode": "tcp_and_udp"
        }
        
        # Сохраняем конфигурацию
        config_path = os.path.join(self.config_dir, "config.json")
        with open(config_path, "w") as f:
            json.dump(server_config, f, indent=4)
            os.chmod(config_path, 0o600)  # Только чтение/запись для владельца


shadowsocks_manager = ShadowsocksManager()
