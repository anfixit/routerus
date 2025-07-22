# app/management/commands/servicestop.py

import logging

from django.core.management.base import BaseCommand

from apps.services.service_manager import ServiceManager

logger = logging.getLogger(__name__)


class Command(BaseCommand):
    help = "Остановить все сервисы"

    def handle(self, *args, **options):
        manager = ServiceManager()
        logger.info("Остановка всех сервисов...")
        manager.stop_all()
        self.stdout.write(self.style.SUCCESS("Все сервисы успешно остановлены."))
