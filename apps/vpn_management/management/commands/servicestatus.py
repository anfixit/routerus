# app/management/commands/servicestatus.py

import logging

from django.core.management.base import BaseCommand

from apps.services.service_manager import ServiceManager

logger = logging.getLogger(__name__)


class Command(BaseCommand):
    help = "Проверить статус всех сервисов"

    def handle(self, *args, **options):
        manager = ServiceManager()
        logger.info("Проверка статуса всех сервисов...")
        manager.status_all()
        self.stdout.write(self.style.SUCCESS("Статус всех сервисов выведен выше."))
