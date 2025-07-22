# app/management/commands/servicestatus_service.py

import logging

from django.core.management.base import BaseCommand, CommandError

from apps.services.service_manager import ServiceManager

logger = logging.getLogger(__name__)


class Command(BaseCommand):
    help = "Проверить статус конкретного сервиса"

    def add_arguments(self, parser):
        parser.add_argument(
            "service_name",
            type=str,
            help="Имя сервиса (wireguard, shadowsocks, xray, dropbox)",
        )

    def handle(self, *args, **options):
        service_name = options["service_name"]
        manager = ServiceManager()
        logger.info(f"Проверка статуса сервиса: {service_name}")
        # Проверим, есть ли такой сервис
        if service_name not in manager.services:
            raise CommandError(
                f"Сервис {service_name} не найден. Доступные сервисы: {', '.join(manager.services.keys())}"
            )

        manager.status_service(service_name)
        self.stdout.write(
            self.style.SUCCESS(f"Статус сервиса {service_name} выведен выше.")
        )
