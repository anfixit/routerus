import os
import subprocess
import json
import logging
from pathlib import Path

logger = logging.getLogger(__name__)

class XrayService:
    def __init__(self, config_path="app/services/xray_config.json"):
        self.config_path = Path(config_path)

    def check_xray_installed(self):
        """Проверяет, установлен ли Xray."""
        if subprocess.call(["which", "xray"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) != 0:
            logger.error("Xray не установлен. Установите Xray перед запуском.")
            raise EnvironmentError("Xray not found")

    def create_config(self, uuid, log_level="info", vless_port=443, vless_network="ws",
                      vless_path="/vless", shadowsocks_port=8388, shadowsocks_method="chacha20-ietf-poly1305",
                      shadowsocks_password=None, wireguard_port=51820):
        """
        Создает конфигурационный файл Xray.
        """
        if self.config_path.exists():
            logger.warning(f"Конфигурация уже существует: {self.config_path}. Перезапись...")
        config = {
            "log": {
                "loglevel": log_level
            },
            "inbounds": [
                {
                    "port": vless_port,
                    "protocol": "vless",
                    "settings": {
                        "clients": [
                            {"id": uuid}
                        ]
                    },
                    "streamSettings": {
                        "network": vless_network,
                        "wsSettings": {"path": vless_path}
                    }
                },
                {
                    "port": shadowsocks_port,
                    "protocol": "shadowsocks",
                    "settings": {
                        "method": shadowsocks_method,
                        "password": shadowsocks_password
                    }
                }
            ],
            "outbounds": [
                {"protocol": "freedom"}
            ]
        }

        try:
            self.config_path.write_text(json.dumps(config, indent=4))
            logger.info(f"Конфигурация Xray сохранена в {self.config_path}")
        except Exception as e:
            logger.error(f"Ошибка при создании конфигурации Xray: {e}")

    def start_service(self):
        """
        Запускает сервис Xray.
        """
        self.check_xray_installed()
        try:
            logger.info("Запуск Xray...")
            subprocess.run(["xray", "-config", str(self.config_path)], check=True)
            logger.info("Xray успешно запущен.")
        except subprocess.CalledProcessError as e:
            logger.error(f"Ошибка при запуске Xray: {e}")
        except Exception as e:
            logger.error(f"Общая ошибка при запуске Xray: {e}")

    def stop_service(self):
        """
        Останавливает процесс Xray.
        """
        try:
            logger.info("Остановка Xray...")
            subprocess.run(["pkill", "-f", "xray"], check=True)
            logger.info("Xray успешно остановлен.")
        except subprocess.CalledProcessError as e:
            logger.error(f"Ошибка при остановке Xray: {e}")
        except Exception as e:
            logger.error(f"Общая ошибка при остановке Xray: {e}")


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    xray = XrayService()
    xray.create_config(
        uuid=os.getenv("XRAY_UUID", "example_uuid"),
        log_level=os.getenv("XRAY_LOG_LEVEL", "info"),
        vless_port=int(os.getenv("XRAY_VLESS_PORT", 443)),
        vless_network=os.getenv("XRAY_VLESS_NETWORK", "ws"),
        vless_path=os.getenv("XRAY_VLESS_PATH", "/vless"),
        shadowsocks_port=int(os.getenv("XRAY_SHADOWSOCKS_PORT", 8388)),
        shadowsocks_method=os.getenv("XRAY_SHADOWSOCKS_METHOD", "chacha20-ietf-poly1305"),
        shadowsocks_password=os.getenv("XRAY_SHADOWSOCKS_PASSWORD", "example_password"),
        wireguard_port=int(os.getenv("XRAY_WIREGUARD_PORT", 51820))
    )
    xray.start_service()
