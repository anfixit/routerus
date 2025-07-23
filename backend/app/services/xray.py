import json
import subprocess
import asyncio
import logging
from typing import Dict, List, Optional, Tuple
from pathlib import Path
import urllib.parse
import qrcode
import io
import base64

from ..core.config import get_settings
from ..core.security import generate_vpn_user_id, generate_reality_keys, generate_short_ids

logger = logging.getLogger(__name__)
settings = get_settings()


class XrayConfigGenerator:
    """Генератор конфигураций Xray"""

    def __init__(self, server_ip: str, server_port: int = 443):
        self.server_ip = server_ip
        self.server_port = server_port
        self.reality_config = {
            "dest": settings.reality_dest,
            "server_names": [settings.reality_server_name],
            "private_key": settings.reality_private_key,
            "public_key": settings.reality_public_key,
            "short_ids": settings.reality_short_id_list or ["0123456789abcdef"]
        }

        # Если ключи не заданы, генерируем новые
        if not self.reality_config["private_key"] or not self.reality_config["public_key"]:
            private_key, public_key = generate_reality_keys()
            self.reality_config["private_key"] = private_key
            self.reality_config["public_key"] = public_key

        if not self.reality_config["short_ids"]:
            self.reality_config["short_ids"] = generate_short_ids()

    def generate_server_config(self, users: List[Dict]) -> Dict:
        """Генерирует серверную конфигурацию Xray"""

        # Преобразуем пользователей в формат Xray
        clients = []
        for user in users:
            clients.append({
                "id": user["vpn_uuid"],
                "email": user["email"],
                "flow": settings.vless_flow
            })

        config = {
            "log": {
                "loglevel": "warning",
                "access": "none",
                "error": "/var/log/xray/error.log"
            },
            "inbounds": [
                {
                    "port": self.server_port,
                    "protocol": "vless",
                    "settings": {
                        "clients": clients,
                        "decryption": "none"
                    },
                    "streamSettings": {
                        "network": "tcp",
                        "security": "reality",
                        "realitySettings": {
                            "dest": self.reality_config["dest"],
                            "serverNames": self.reality_config["server_names"],
                            "privateKey": self.reality_config["private_key"],
                            "shortIds": self.reality_config["short_ids"]
                        }
                    },
                    "sniffing": {
                        "enabled": True,
                        "destOverride": ["http", "tls", "quic"]
                    }
                }
            ],
            "outbounds": [
                {
                    "protocol": "freedom",
                    "settings": {},
                    "tag": "direct"
                },
                {
                    "protocol": "blackhole",
                    "settings": {},
                    "tag": "block"
                }
            ],
            "routing": {
                "domainStrategy": "AsIs",
                "rules": [
                    {
                        "type": "field",
                        "outboundTag": "block",
                        "ip": ["geoip:private"]
                    }
                ]
            },
            "policy": {
                "levels": {
                    "0": {
                        "handshake": 2,
                        "connIdle": 120,
                        "uplinkOnly": 0,
                        "downlinkOnly": 0
                    }
                },
                "system": {
                    "statsInboundUplink": False,
                    "statsInboundDownlink": False,
                    "statsOutboundUplink": False,
                    "statsOutboundDownlink": False
                }
            }
        }

        return config

    def generate_client_config(self, user_uuid: str, email: str) -> Dict:
        """Генерирует клиентскую конфигурацию"""
        config = {
            "log": {
                "loglevel": "warning"
            },
            "inbounds": [
                {
                    "port": 10808,
                    "protocol": "socks",
                    "settings": {
                        "udp": True
                    },
                    "tag": "socks-in"
                },
                {
                    "port": 10809,
                    "protocol": "http",
                    "tag": "http-in"
                }
            ],
            "outbounds": [
                {
                    "protocol": "vless",
                    "settings": {
                        "vnext": [
                            {
                                "address": self.server_ip,
                                "port": self.server_port,
                                "users": [
                                    {
                                        "id": user_uuid,
                                        "email": email,
                                        "encryption": "none",
                                        "flow": settings.vless_flow
                                    }
                                ]
                            }
                        ]
                    },
                    "streamSettings": {
                        "network": "tcp",
                        "security": "reality",
                        "realitySettings": {
                            "serverName": self.reality_config["server_names"][0],
                            "fingerprint": "chrome",
                            "publicKey": self.reality_config["public_key"],
                            "shortId": self.reality_config["short_ids"][0],
                            "spiderX": "/"
                        }
                    },
                    "tag": "vless-out"
                }
            ],
            "routing": {
                "domainStrategy": "AsIs",
                "rules": [
                    {
                        "type": "field",
                        "inboundTag": ["socks-in", "http-in"],
                        "outboundTag": "vless-out"
                    }
                ]
            }
        }

        return config

    def generate_vless_url(self, user_uuid: str, email: str) -> str:
        """Генерирует VLESS URL для клиента"""
        # Базовый URL: vless://UUID@SERVER:PORT
        base_url = f"vless://{user_uuid}@{self.server_ip}:{self.server_port}"

        # Параметры
        params = {
            "type": "tcp",
            "security": "reality",
            "sni": self.reality_config["server_names"][0],
            "fp": "chrome",
            "pbk": self.reality_config["public_key"],
            "sid": self.reality_config["short_ids"][0],
            "spx": "%2F",  # URL encoded "/"
            "flow": settings.vless_flow
        }

        # Собираем URL
        query_string = urllib.parse.urlencode(params)
        full_url = f"{base_url}?{query_string}#{urllib.parse.quote(email)}"

        return full_url

    def generate_qr_code(self, vless_url: str) -> str:
        """Генерирует QR код для VLESS URL"""
        qr = qrcode.QRCode(
            version=1,
            error_correction=qrcode.constants.ERROR_CORRECT_L,
            box_size=10,
            border=4,
        )
        qr.add_data(vless_url)
        qr.make(fit=True)

        # Создаем изображение
        img = qr.make_image(fill_color="black", back_color="white")

        # Конвертируем в base64
        buffer = io.BytesIO()
        img.save(buffer, format='PNG')
        img_str = base64.b64encode(buffer.getvalue()).decode()

        return f"data:image/png;base64,{img_str}"


class XrayManager:
    """Менеджер Xray сервера"""

    def __init__(self, config_path: str = "/etc/xray/config.json"):
        self.config_path = Path(config_path)
        self.xray_binary = "/usr/local/bin/xray"
        self.generator = XrayConfigGenerator(settings.vpn_server_ip or "127.0.0.1")

    async def save_config(self, config: Dict) -> bool:
        """Сохраняет конфигурацию в файл"""
        try:
            # Создаем директорию если не существует
            self.config_path.parent.mkdir(parents=True, exist_ok=True)

            # Записываем конфигурацию
            with open(self.config_path, 'w', encoding='utf-8') as f:
                json.dump(config, f, indent=2, ensure_ascii=False)

            logger.info(f"Конфигурация сохранена в {self.config_path}")
            return True

        except Exception as e:
            logger.error(f"Ошибка сохранения конфигурации: {e}")
            return False

    async def reload_config(self) -> bool:
        """Перезагружает конфигурацию Xray"""
        try:
            # Сначала проверяем конфигурацию
            if not await self.test_config():
                return False

            # Отправляем сигнал перезагрузки
            process = await asyncio.create_subprocess_exec(
                "pkill", "-USR1", "xray",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )

            stdout, stderr = await process.communicate()

            if process.returncode == 0:
                logger.info("Конфигурация Xray перезагружена")
                return True
            else:
                logger.error(f"Ошибка перезагрузки Xray: {stderr.decode()}")
                return False

        except Exception as e:
            logger.error(f"Ошибка перезагрузки конфигурации: {e}")
            return False

    async def test_config(self) -> bool:
        """Тестирует конфигурацию Xray"""
        try:
            process = await asyncio.create_subprocess_exec(
                self.xray_binary, "-test", "-config", str(self.config_path),
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )

            stdout, stderr = await process.communicate()

            if process.returncode == 0:
                logger.info("Конфигурация Xray прошла проверку")
                return True
            else:
                logger.error(f"Ошибка в конфигурации Xray: {stderr.decode()}")
                return False

        except Exception as e:
            logger.error(f"Ошибка тестирования конфигурации: {e}")
            return False

    async def get_stats(self) -> Optional[Dict]:
        """Получает статистику Xray"""
        try:
            # Пытаемся получить статистику через API
            process = await asyncio.create_subprocess_exec(
                self.xray_binary, "api", "statsquery",
                "--server=127.0.0.1:10085",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )

            stdout, stderr = await process.communicate()

            if process.returncode == 0:
                # Парсим JSON ответ
                stats_data = json.loads(stdout.decode())
                return stats_data
            else:
                logger.warning("Статистика Xray недоступна")
                return None

        except Exception as e:
            logger.error(f"Ошибка получения статистики Xray: {e}")
            return None

    async def add_user(self, user_data: Dict) -> Tuple[str, str]:
        """Добавляет нового пользователя и возвращает VLESS URL и QR код"""
        try:
            # Генерируем VLESS URL
            vless_url = self.generator.generate_vless_url(
                user_data["vpn_uuid"],
                user_data["email"]
            )

            # Генерируем QR код
            qr_code = self.generator.generate_qr_code(vless_url)

            return vless_url, qr_code

        except Exception as e:
            logger.error(f"Ошибка добавления пользователя: {e}")
            raise

    async def update_server_config(self, users: List[Dict]) -> bool:
        """Обновляет серверную конфигурацию с новым списком пользователей"""
        try:
            # Генерируем новую конфигурацию
            config = self.generator.generate_server_config(users)

            # Сохраняем конфигурацию
            if await self.save_config(config):
                # Перезагружаем Xray
                return await self.reload_config()

            return False

        except Exception as e:
            logger.error(f"Ошибка обновления конфигурации сервера: {e}")
            return False


# Глобальный экземпляр менеджера
xray_manager = XrayManager()


def get_xray_manager() -> XrayManager:
    """Возвращает экземпляр менеджера Xray"""
    return xray_manager
