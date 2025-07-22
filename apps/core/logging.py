import json
import logging
import os
import sys
from logging.handlers import RotatingFileHandler

LOG_DIR = "/var/log/routerus"
if not os.path.exists(LOG_DIR):
    os.makedirs(LOG_DIR, exist_ok=True)

LOG_FILE = os.path.join(LOG_DIR, "app.log")


class JSONFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        log_record = {
            "timestamp": self.formatTime(record, self.datefmt),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }
        # Если есть атрибут service, добавим его:
        if hasattr(record, "service"):
            log_record["service"] = record.service
        return json.dumps(log_record, ensure_ascii=False)


# Создаем корневой логгер
logger = logging.getLogger()
logger.setLevel(logging.DEBUG)  # В PROD можно поменять на INFO

# Формат для консольного хендлера (человеко-читаемый)
console_formatter = logging.Formatter(
    "%(asctime)s [%(levelname)s] %(name)s: %(message)s", datefmt="%Y-%m-%d %H:%M:%S"
)

console_handler = logging.StreamHandler(sys.stdout)
console_handler.setFormatter(console_formatter)
console_handler.setLevel(logging.DEBUG)

# Ротирующий файловый хендлер с JSON форматом
file_handler = RotatingFileHandler(LOG_FILE, maxBytes=5 * 1024 * 1024, backupCount=5)
file_handler.setLevel(logging.INFO)
file_handler.setFormatter(JSONFormatter("%Y-%m-%d %H:%M:%S"))

logger.addHandler(console_handler)
logger.addHandler(file_handler)

# Пример использования в коде:
# logger.info("Сервис запущен", extra={"service": "wireguard"})
