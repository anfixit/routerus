#!/usr/bin/env python
import os
import sys
from app.utils import load_xray_config  # Добавим импорт функции

if __name__ == "__main__":
    os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")

    # Загрузим конфигурацию Xray
    xray_config = load_xray_config()
    print("Загруженная конфигурация Xray:", xray_config)

    try:
        from django.core.management import execute_from_command_line
    except ImportError as exc:
        raise ImportError(
            "Couldn't import Django. Are you sure it's installed and "
            "available on your PYTHONPATH environment variable? Did you "
            "forget to activate a virtual environment?"
        ) from exc
    execute_from_command_line(sys.argv)
