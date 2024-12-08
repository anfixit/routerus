# Используем Python 3.12 slim как базовый образ
FROM python:3.12-slim AS base

# Устанавливаем системные зависимости
RUN apt-get update && apt-get install -y \
    build-essential \
    libpq-dev \
    curl \
    wireguard-tools \
    nginx \
    && apt-get clean

# Обновляем pip и устанавливаем Poetry
RUN pip install --upgrade pip && pip install poetry

# Устанавливаем рабочую директорию
WORKDIR /app

# Копируем файлы зависимостей Poetry
COPY pyproject.toml poetry.lock /app/

# Устанавливаем зависимости, включая python-dotenv
RUN poetry config virtualenvs.create false && poetry install --no-dev

# Копируем исходный код приложения
COPY . /app

# Устанавливаем переменную окружения для Django настроек
ENV DJANGO_SETTINGS_MODULE=config.settings.production

# Выполняем миграции базы данных
RUN poetry run python manage.py migrate

# Настраиваем Nginx
COPY ./config/nginx/nginx.conf /etc/nginx/nginx.conf
RUN mkdir -p /var/www/static/ && cp -r /app/app/static/ /var/www/static/

# Указываем команду запуска
CMD ["poetry", "run", "gunicorn", "config.wsgi:application", "--bind", "0.0.0.0:8000"]
