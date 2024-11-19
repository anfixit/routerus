# Используем официальный Python образ в качестве основы
FROM python:3.12-slim AS base

# Установка зависимостей для сборки
RUN apt-get update && apt-get install -y \
    build-essential \
    libpq-dev \
    curl \
    wireguard-tools

# Установка Poetry
RUN pip install --upgrade pip && pip install poetry

# Установка рабочей директории
WORKDIR /app

# Копируем зависимости и устанавливаем их
COPY pyproject.toml poetry.lock /app/
RUN poetry config virtualenvs.create false && poetry install --no-dev

# Копируем весь проект в контейнер
COPY . /app

# Команда запуска
CMD ["python", "manage.py", "runserver", "0.0.0.0:8000"]
