import logging

from apps.services.dropbox.dropbox_service import DropboxService
from apps.services.shadowsocks.shadowsocks_service import ShadowsocksService
from apps.services.wireguard.wireguard_service import WireGuardService
from apps.services.xray.xray_service import XrayService

logger = logging.getLogger(__name__)


class ServiceManager:
    def __init__(self):
        self.services = {
            "wireguard": WireGuardService(),
            "shadowsocks": ShadowsocksService(),
            "xray": XrayService(),
            "dropbox": DropboxService(),
        }

    def start_all(self):
        for name, service in self.services.items():
            logger.info(f"Запуск сервиса: {name}", extra={"service": name})
            service.start_service()

    def stop_all(self):
        for name, service in self.services.items():
            logger.info(f"Остановка сервиса: {name}", extra={"service": name})
            service.stop_service()

    def status_all(self):
        for name, service in self.services.items():
            status = "активен" if service.is_active() else "не запущен"
            logger.info(f"Сервис {name}: {status}", extra={"service": name})
            print(f"Сервис {name}: {status}")

    def start_service(self, service_name):
        service = self.services.get(service_name)
        if service:
            logger.info(
                f"Запуск сервиса: {service_name}", extra={"service": service_name}
            )
            service.start_service()
        else:
            logger.error(
                f"Сервис {service_name} не найден.", extra={"service": service_name}
            )

    def stop_service(self, service_name):
        service = self.services.get(service_name)
        if service:
            logger.info(
                f"Остановка сервиса: {service_name}", extra={"service": service_name}
            )
            service.stop_service()
        else:
            logger.error(
                f"Сервис {service_name} не найден.", extra={"service": service_name}
            )

    def status_service(self, service_name):
        service = self.services.get(service_name)
        if service:
            status = "активен" if service.is_active() else "не запущен"
            logger.info(
                f"Сервис {service_name}: {status}", extra={"service": service_name}
            )
            print(f"Сервис {service_name}: {status}")
        else:
            logger.error(
                f"Сервис {service_name} не найден.", extra={"service": service_name}
            )
