import json
import logging
import subprocess
from pathlib import Path

logger = logging.getLogger(__name__)

class ShadowsocksService:
    def __init__(self, server, port, password, method, timeout, config_path="app/services/shadowsocks_config.json"):
        self.server = server
        self.port = port
        self.password = password
        self.method = method
        self.timeout = timeout
        self.config_path = Path(config_path)

    def create_config(self):
        """
        Создает файл конфигурации для Shadowsocks.
        """
        if self.config_path.exists():
            logger.warning(f"Конфигурация уже существует: {self.config_path}. Перезапись...")
        config = {
            "server": self.server,
            "server_port": self.port,
            "password": self.password,
            "method": self.method,
            "timeout": self.timeout
        }
        try:
            with self.config_path.open("w") as config_file:
                json.dump(config, config_file, indent=4)
            logger.info(f"Конфигурация Shadowsocks сохранена в {self.config_path}")
        except Exception as e:
            logger.error(f"Ошибка при создании конфигурации Shadowsocks: {e}")

    def start_service(self):
        """
        Запускает сервис Shadowsocks.
        """
        try:
            logger.info("Запуск Shadowsocks...")
            command = f"ssserver -c {self.config_path}"  # Замените на команду для запуска
            subprocess.run(command.split(), check=True)
            logger.info("Shadowsocks успешно запущен.")
        except subprocess.CalledProcessError as e:
            logger.error(f"Ошибка при запуске Shadowsocks: {e}")
        except Exception as e:
            logger.error(f"Ошибка при запуске Shadowsocks: {e}")

    def stop_service(self):
        """
        Останавливает сервис Shadowsocks.
        """
        try:
            logger.info("Остановка Shadowsocks...")
            # Здесь должна быть команда для остановки Shadowsocks
            subprocess.run(["killall", "ssserver"], check=True)
            logger.info("Shadowsocks успешно остановлен.")
        except subprocess.CalledProcessError as e:
            logger.error(f"Ошибка при остановке Shadowsocks: {e}")
        except Exception as e:
            logger.error(f"Ошибка при остановке Shadowsocks: {e}")


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    shadowsocks = ShadowsocksService(
        server="213.148.10.128",
        port=8388,
        password="example_password",
        method="chacha20-ietf-poly1305",
        timeout=300
    )
    shadowsocks.create_config()
    shadowsocks.start_service()
