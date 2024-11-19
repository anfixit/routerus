import os
from django.core.wsgi import get_wsgi_application

# Установка пути к настройкам Django (указываем development или production в зависимости от окружения)
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings.development')

application = get_wsgi_application()
