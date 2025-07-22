# app/management/commands/servicestart.py

import logging

from django.core.management.base import BaseCommand

from apps.services.service_manager import ServiceManager

logger = logging.getLogger(__name__)


class Command(BaseCommand):
    help = "Запустить все сервисы"

    def handle(self, *args, **options):
        manager = ServiceManager()
        logger.info("Запуск всех сервисов...")
        manager.start_all()
        self.stdout.write(self.style.SUCCESS("Все сервисы успешно запущены."))
