import logging
import subprocess

from apps.core.service_configurator import get_wireguard_config

logger = logging.getLogger(__name__)


class WireGuardService:
    def __init__(self):
        cfg = get_wireguard_config()
        self.private_key = cfg["private_key"]
        self.public_key = cfg["public_key"]
        self.server_ip = cfg["server_ip"]
        self.server_port = cfg["server_port"]
        self.peer_dns = cfg["peer_dns"]
        self.allowed_ips = cfg["allowed_ips"]

    def check_wg_installed(self):
        if (
            subprocess.call(
                ["which", "wg"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )
            != 0
        ):
            logger.error(
                "wg не установлен. Установите WireGuard и повторите попытку.",
                extra={"service": "wireguard"},
            )
            raise EnvironmentError("wg not found")

    def start_service(self):
        self.check_wg_installed()
        try:
            logger.info("Настройка WireGuard...", extra={"service": "wireguard"})
            subprocess.run(
                [
                    "wg",
                    "set",
                    "wg0",
                    "private-key",
                    "/dev/stdin",
                    "listen-port",
                    str(self.server_port),
                    "peer",
                    self.public_key,
                    "allowed-ips",
                    self.allowed_ips,
                    "endpoint",
                    f"{self.server_ip}:{self.server_port}",
                ],
                input=self.private_key.encode(),
                check=True,
            )

            logger.info(
                "WireGuard успешно настроен. Поднятие интерфейса...",
                extra={"service": "wireguard"},
            )
            subprocess.run(["ip", "link", "set", "up", "dev", "wg0"], check=True)
            subprocess.run(
                ["ip", "addr", "add", self.server_ip, "dev", "wg0"], check=True
            )
            logger.info("WireGuard успешно запущен.", extra={"service": "wireguard"})
        except subprocess.CalledProcessError as e:
            logger.error(
                f"Ошибка при настройке WireGuard: {e}", extra={"service": "wireguard"}
            )
            raise

    def stop_service(self):
        self.check_wg_installed()
        try:
            logger.info("Остановка WireGuard...", extra={"service": "wireguard"})
            subprocess.run(["ip", "link", "set", "down", "dev", "wg0"], check=True)
            logger.info("WireGuard успешно остановлен.", extra={"service": "wireguard"})
        except subprocess.CalledProcessError as e:
            logger.error(
                f"Ошибка при остановке WireGuard: {e}", extra={"service": "wireguard"}
            )
            raise

    def is_active(self):
        try:
            result = subprocess.run(
                ["ip", "link", "show", "wg0"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            return "state UP" in result.stdout
        except Exception as e:
            logger.error(
                f"Ошибка при проверке состояния WireGuard: {e}",
                extra={"service": "wireguard"},
            )
            return False
