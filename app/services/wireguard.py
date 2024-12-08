import os
import subprocess
import logging
from pathlib import Path

logger = logging.getLogger(__name__)

class WireGuardService:
    def __init__(self, private_key, public_key, server_ip, server_port, peer_dns, allowed_ips, config_path="app/services/wireguard.conf"):
        self.private_key = private_key
        self.public_key = public_key
        self.server_ip = server_ip
        self.server_port = server_port
        self.peer_dns = peer_dns
        self.allowed_ips = allowed_ips
        self.config_path = Path(config_path)

    def check_wg_quick(self):
        """Проверяет наличие команды wg-quick."""
        if subprocess.call(["which", "wg-quick"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) != 0:
            logger.error("wg-quick не установлен. Установите WireGuard и повторите попытку.")
            raise EnvironmentError("wg-quick not found")

    def create_config(self):
        """Создает конфигурационный файл WireGuard."""
        if self.config_path.exists():
            logger.warning(f"Конфигурация уже существует: {self.config_path}. Перезапись...")
        config_content = f"""
        [Interface]
        PrivateKey = {self.private_key}
        Address = {self.server_ip}
        ListenPort = {self.server_port}
        DNS = {self.peer_dns}

        [Peer]
        PublicKey = {self.public_key}
        AllowedIPs = {self.allowed_ips}
        Endpoint = {self.server_ip}:{self.server_port}
        PersistentKeepalive = 25
        """
        try:
            self.config_path.write_text(config_content.strip())
            logger.info(f"Конфигурация WireGuard сохранена в {self.config_path}")
        except Exception as e:
            logger.error(f"Ошибка при создании конфигурации WireGuard: {e}")

    def start_service(self):
        """Запускает сервис WireGuard."""
        self.check_wg_quick()
        try:
            logger.info("Запуск WireGuard...")
            subprocess.run(["wg-quick", "up", str(self.config_path)], check=True)
            logger.info("WireGuard успешно запущен.")
        except subprocess.CalledProcessError as e:
            logger.error(f"Ошибка при запуске WireGuard: {e}")
        except Exception as e:
            logger.error(f"Общая ошибка при запуске WireGuard: {e}")

    def stop_service(self):
        """Останавливает сервис WireGuard."""
        self.check_wg_quick()
        try:
            logger.info("Остановка WireGuard...")
            subprocess.run(["wg-quick", "down", str(self.config_path)], check=True)
            logger.info("WireGuard успешно остановлен.")
        except subprocess.CalledProcessError as e:
            logger.error(f"Ошибка при остановке WireGuard: {e}")
        except Exception as e:
            logger.error(f"Общая ошибка при остановке WireGuard: {e}")


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    wireguard = WireGuardService(
        private_key=os.getenv("WIREGUARD_PRIVATE_KEY", "example_private_key"),
        public_key=os.getenv("WIREGUARD_SERVER_PUBLIC_KEY", "example_public_key"),
        server_ip=os.getenv("WIREGUARD_SERVER_IP", "213.148.10.128"),
        server_port=os.getenv("WIREGUARD_SERVER_PORT", "51820"),
        peer_dns=os.getenv("WIREGUARD_PEERDNS", "1.1.1.1"),
        allowed_ips=os.getenv("WIREGUARD_ALLOWEDIPS", "0.0.0.0/0, ::/0")
    )
    wireguard.create_config()
    wireguard.start_service()
