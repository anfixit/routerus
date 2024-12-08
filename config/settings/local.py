from .base import *

# Debug mode enabled for local testing
DEBUG = True

# Allowed hosts for local
ALLOWED_HOSTS = ["127.0.0.1", "localhost"]

# Database configuration
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': os.getenv('DB_NAME', 'wg_manager_local'),
        'USER': os.getenv('DB_USER', 'wg_user'),
        'PASSWORD': os.getenv('DB_PASSWORD', 'password'),
        'HOST': os.getenv('DB_HOST', 'localhost'),
        'PORT': os.getenv('DB_PORT', '5432'),
    }
}

# Static files configuration
STATIC_URL = '/static/'
STATIC_ROOT = os.path.join(BASE_DIR, 'staticfiles')

# Logging for local development
LOGGING['handlers']['console']['level'] = 'DEBUG'
