import logging
import os
import json
from datetime import datetime
from logging.handlers import RotatingFileHandler
import sys
from typing import Dict, Any

# Настройка логирования
class CustomLogger:
    def __init__(self, name: str, log_dir: str = "/opt/routerus/logs"):
        self.logger = logging.getLogger(name)
        self.logger.setLevel(logging.INFO)
        
        # Создаем директорию для логов, если ее нет
        if not os.path.exists(log_dir):
            os.makedirs(log_dir)
        
        # Настройка форматтера для консоли
        console_formatter = logging.Formatter(
            '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
        )
        
        # Настройка консольного логирования
        console_handler = logging.StreamHandler(sys.stdout)
        console_handler.setFormatter(console_formatter)
        self.logger.addHandler(console_handler)
        
        # Настройка файлового логирования
        file_path = os.path.join(log_dir, f"{name}.log")
        file_handler = RotatingFileHandler(
            file_path, maxBytes=10*1024*1024, backupCount=5
        )
        file_formatter = logging.Formatter(
            '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
        )
        file_handler.setFormatter(file_formatter)
        self.logger.addHandler(file_handler)
        
        # Настройка JSON логирования для событий безопасности и аудита
        audit_path = os.path.join(log_dir, f"{name}_audit.json")
        self.audit_handler = RotatingFileHandler(
            audit_path, maxBytes=10*1024*1024, backupCount=5
        )
        self.audit_handler.setLevel(logging.INFO)
        self.logger.addHandler(self.audit_handler)
    
    def log_audit(self, action: str, user_id: int = None, details: Dict[str, Any] = None):
        """Логирование действий пользователей и системы для аудита."""
        log_data = {
            "timestamp": datetime.utcnow().isoformat(),
            "action": action,
            "user_id": user_id,
            "details": details or {}
        }
        self.audit_handler.stream.write(json.dumps(log_data) + "\n")
        self.audit_handler.stream.flush()
    
    def info(self, msg, *args, **kwargs):
        self.logger.info(msg, *args, **kwargs)
    
    def warning(self, msg, *args, **kwargs):
        self.logger.warning(msg, *args, **kwargs)
    
    def error(self, msg, *args, **kwargs):
        self.logger.error(msg, *args, **kwargs)
    
    def debug(self, msg, *args, **kwargs):
        self.logger.debug(msg, *args, **kwargs)
    
    def critical(self, msg, *args, **kwargs):
        self.logger.critical(msg, *args, **kwargs)


# Создание логгеров для разных модулей
api_logger = CustomLogger("api")
auth_logger = CustomLogger("auth")
vpn_logger = CustomLogger("vpn")
system_logger = CustomLogger("system")
