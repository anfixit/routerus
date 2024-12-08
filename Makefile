# Makefile для WireGuard Manager

.PHONY: help install run migrate test clean build

help:
	@echo "Доступные команды:"
	@echo "  install     Установить зависимости проекта"
	@echo "  run         Запустить сервер разработки"
	@echo "  migrate     Применить миграции базы данных"
	@echo "  test        Запустить тесты"
	@echo "  clean       Очистить временные файлы и кэш"
	@echo "  build       Собрать Docker образы"

install:
	poetry install

run:
	python manage.py runserver 0.0.0.0:8000

migrate:
	python manage.py migrate

test:
	pytest

clean:
	find . -name "*.pyc" -delete
	find . -name "__pycache__" -delete

build:
	docker-compose build
