# Makefile для WireGuard Manager

.PHONY: help install run migrate test clean build lint format

help:
	@echo "Доступные команды:"
	@echo "  install     Установить зависимости проекта (poetry)"
	@echo "  run         Запустить сервер разработки (Django)"
	@echo "  migrate     Применить миграции базы данных"
	@echo "  test        Запустить тесты (pytest)"
	@echo "  clean       Очистить временные файлы и кэш"
	@echo "  build       Собрать Docker образы"
	@echo "  lint        Проверка стиля кода (flake8, black, isort)"
	@echo "  format      Автоформатирование кода (black, isort)"

install:
	poetry install

run:
	poetry run python manage.py runserver 0.0.0.0:8000

migrate:
	poetry run python manage.py migrate

test:
	poetry run pytest --maxfail=1 --disable-warnings -q

clean:
	find . -name "*.pyc" -delete
	find . -name "__pycache__" -delete

build:
	docker-compose build

lint:
	poetry run flake8 .
	poetry run black --check .
	poetry run isort --check-only .

format:
	poetry run black .
	poetry run isort .
