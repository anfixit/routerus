import json
import logging
import subprocess
from pathlib import Path

from apps.core.service_configurator import get_shadowsocks_config

logger = logging.getLogger(__name__)


class ShadowsocksService:
    def __init__(self, config_path="app/services/shadowsocks/shadowsocks_config.json"):
        cfg = get_shadowsocks_config()
        self.server = cfg["server"]
        self.port = cfg["port"]
        self.password = cfg["password"]
        self.method = cfg["method"]
        self.timeout = cfg["timeout"]
        self.config_path = Path(config_path)

    def create_config(self):
        if self.config_path.exists():
            logger.warning(
                f"Конфигурация уже существует: {self.config_path}. Перезапись...",
                extra={"service": "shadowsocks"},
            )
        config = {
            "server": self.server,
            "server_port": self.port,
            "password": self.password,
            "method": self.method,
            "timeout": self.timeout,
        }
        try:
            with self.config_path.open("w") as config_file:
                json.dump(config, config_file, indent=4)
            logger.info(
                f"Конфигурация Shadowsocks сохранена в {self.config_path}",
                extra={"service": "shadowsocks"},
            )
        except Exception as e:
            logger.error(
                f"Ошибка при создании конфигурации Shadowsocks: {e}",
                extra={"service": "shadowsocks"},
            )

    def start_service(self):
        try:
            logger.info("Запуск Shadowsocks...", extra={"service": "shadowsocks"})
            command = f"ssserver -c {self.config_path}"
            subprocess.run(command.split(), check=True)
            logger.info(
                "Shadowsocks успешно запущен.", extra={"service": "shadowsocks"}
            )
        except subprocess.CalledProcessError as e:
            logger.error(
                f"Ошибка при запуске Shadowsocks: {e}", extra={"service": "shadowsocks"}
            )
        except Exception as e:
            logger.error(
                f"Ошибка при запуске Shadowsocks: {e}", extra={"service": "shadowsocks"}
            )

    def stop_service(self):
        try:
            logger.info("Остановка Shadowsocks...", extra={"service": "shadowsocks"})
            subprocess.run(["killall", "ssserver"], check=True)
            logger.info(
                "Shadowsocks успешно остановлен.", extra={"service": "shadowsocks"}
            )
        except subprocess.CalledProcessError as e:
            logger.error(
                f"Ошибка при остановке Shadowsocks: {e}",
                extra={"service": "shadowsocks"},
            )
        except Exception as e:
            logger.error(
                f"Ошибка при остановке Shadowsocks: {e}",
                extra={"service": "shadowsocks"},
            )

    def is_active(self):
        # Проверим, запущен ли процесс ssserver
        result = subprocess.run(
            ["pgrep", "-f", "ssserver"], stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
        return result.returncode == 0
