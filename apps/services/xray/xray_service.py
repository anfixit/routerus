import json
import logging
import subprocess
from pathlib import Path

from apps.core.service_configurator import get_xray_config

logger = logging.getLogger(__name__)


class XrayService:
    def __init__(self, config_path="app/services/xray/xray_config.json"):
        cfg = get_xray_config()
        self.config_path = Path(config_path)
        self.uuid = cfg["uuid"]
        self.log_level = cfg["log_level"]
        self.vless_port = cfg["vless_port"]
        self.vless_network = cfg["vless_network"]
        self.vless_path = cfg["vless_path"]
        self.shadowsocks_port = cfg["shadowsocks_port"]
        self.shadowsocks_method = cfg["shadowsocks_method"]
        self.shadowsocks_password = cfg["shadowsocks_password"]
        self.wireguard_port = cfg["wireguard_port"]
        self.wireguard_secret_key = cfg["wireguard_secret_key"]
        self.wireguard_public_key = cfg["wireguard_public_key"]
        self.wireguard_address = self.wireguard_address = cfg["wireguard_address"]

    def check_xray_installed(self):
        if (
            subprocess.call(
                ["which", "xray"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )
            != 0
        ):
            logger.error(
                "Xray не установлен. Установите Xray перед запуском.",
                extra={"service": "xray"},
            )
            raise EnvironmentError("Xray not found")

    def create_config(self):
        if self.config_path.exists():
            logger.warning(
                f"Конфигурация уже существует: {self.config_path}. Перезапись...",
                extra={"service": "xray"},
            )
        config = {
            "log": {"loglevel": self.log_level},
            "inbounds": [
                {
                    "port": self.vless_port,
                    "protocol": "vless",
                    "settings": {"clients": [{"id": self.uuid}]},
                    "streamSettings": {
                        "network": self.vless_network,
                        "wsSettings": {"path": self.vless_path},
                    },
                },
                {
                    "port": self.shadowsocks_port,
                    "protocol": "shadowsocks",
                    "settings": {
                        "method": self.shadowsocks_method,
                        "password": self.shadowsocks_password,
                    },
                },
            ],
            "outbounds": [{"protocol": "freedom"}],
        }

        try:
            self.config_path.write_text(json.dumps(config, indent=4))
            logger.info(
                f"Конфигурация Xray сохранена в {self.config_path}",
                extra={"service": "xray"},
            )
        except Exception as e:
            logger.error(
                f"Ошибка при создании конфигурации Xray: {e}", extra={"service": "xray"}
            )

    def start_service(self):
        self.check_xray_installed()
        try:
            logger.info("Запуск Xray...", extra={"service": "xray"})
            subprocess.run(["xray", "-config", str(self.config_path)], check=True)
            logger.info("Xray успешно запущен.", extra={"service": "xray"})
        except subprocess.CalledProcessError as e:
            logger.error(f"Ошибка при запуске Xray: {e}", extra={"service": "xray"})
        except Exception as e:
            logger.error(
                f"Общая ошибка при запуске Xray: {e}", extra={"service": "xray"}
            )

    def stop_service(self):
        try:
            logger.info("Остановка Xray...", extra={"service": "xray"})
            subprocess.run(["pkill", "-f", "xray"], check=True)
            logger.info("Xray успешно остановлен.", extra={"service": "xray"})
        except subprocess.CalledProcessError as e:
            logger.error(f"Ошибка при остановке Xray: {e}", extra={"service": "xray"})
        except Exception as e:
            logger.error(
                f"Общая ошибка при остановке Xray: {e}", extra={"service": "xray"}
            )

    def is_active(self):
        result = subprocess.run(
            ["pgrep", "-f", "xray"], stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
        return result.returncode == 0
