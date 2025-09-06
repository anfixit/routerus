# WireGuard Maximum Obfuscation Setup - Makefile
# Упрощенное управление проектом

.PHONY: help setup start stop restart status logs clean install update backup restore

# Цвета для вывода
CYAN := \033[0;36m
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
NC := \033[0m

help: ## Показать это сообщение справки
	@echo "$(CYAN)WireGuard Maximum Obfuscation Setup$(NC)"
	@echo "$(YELLOW)Доступные команды:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-15s$(NC) %s\n", $$1, $$2}'

setup: ## Интерактивная настройка .env файла
	@echo "$(CYAN)Запуск интерактивной настройки...$(NC)"
	@chmod +x setup.sh
	@./setup.sh

install: setup ## Полная установка (setup + start)
	@echo "$(GREEN)Установка завершена, запуск сервисов...$(NC)"
	@$(MAKE) start

start: ## Запустить все сервисы
	@echo "$(GREEN)Запуск WireGuard VPN...$(NC)"
	@docker-compose up -d
	@echo "$(GREEN)Сервисы запущены!$(NC)"
	@$(MAKE) status

stop: ## Остановить все сервисы
	@echo "$(YELLOW)Остановка сервисов...$(NC)"
	@docker-compose down
	@echo "$(GREEN)Сервисы остановлены$(NC)"

restart: ## Перезапустить все сервисы
	@echo "$(YELLOW)Перезапуск сервисов...$(NC)"
	@docker-compose restart
	@echo "$(GREEN)Сервисы перезапущены$(NC)"

status: ## Показать статус сервисов
	@echo "$(CYAN)Статус сервисов:$(NC)"
	@docker-compose ps
	@echo ""
	@if [ -f .env ]; then \
		echo "$(CYAN)Конфигурация:$(NC)"; \
		grep -E "^(SERVER_ENDPOINT|WEB_PORT|WG_PORT)" .env | sed 's/^/  /'; \
		echo ""; \
		SERVER_ENDPOINT=$$(grep "^SERVER_ENDPOINT=" .env | cut -d'=' -f2); \
		WEB_PORT=$$(grep "^WEB_PORT=" .env | cut -d'=' -f2); \
		echo "$(GREEN)Веб-интерфейс: http://$$SERVER_ENDPOINT:$$WEB_PORT$(NC)"; \
	fi

logs: ## Показать логи сервисов
	@docker-compose logs -f --tail=50

logs-wg: ## Показать логи только WireGuard
	@docker-compose logs -f wg-easy

logs-stats: ## Показать логи статистики
	@docker-compose logs -f stats

build: ## Пересобрать Docker образы
	@echo "$(YELLOW)Пересборка Docker образов...$(NC)"
	@docker-compose build --no-cache
	@echo "$(GREEN)Образы пересобраны$(NC)"

update: ## Обновить и перезапустить
	@echo "$(CYAN)Обновление проекта...$(NC)"
	@git pull
	@$(MAKE) build
	@$(MAKE) restart
	@echo "$(GREEN)Обновление завершено$(NC)"

clean: ## Остановить и удалить все контейнеры и volumes
	@echo "$(RED)ВНИМАНИЕ: Это удалит ВСЕ данные WireGuard!$(NC)"
	@read -p "Вы уверены? [y/N]: " confirm && [ "$$confirm" = "y" ]
	@docker-compose down -v
	@docker system prune -f
	@echo "$(GREEN)Очистка завершена$(NC)"

backup: ## Создать бэкап конфигураций
	@echo "$(CYAN)Создание бэкапа...$(NC)"
	@mkdir -p backups
	@docker run --rm -v wg-obfuscation_wg_data:/data -v $(PWD)/backups:/backup alpine tar czf /backup/wireguard-backup-$(shell date +%Y%m%d-%H%M%S).tar.gz -C /data .
	@cp .env backups/env-backup-$(shell date +%Y%m%d-%H%M%S).env 2>/dev/null || true
	@echo "$(GREEN)Бэкап создан в папке backups/$(NC)"

restore: ## Восстановить из бэкапа
	@echo "$(YELLOW)Доступные бэкапы:$(NC)"
	@ls -la backups/*.tar.gz 2>/dev/null || echo "Бэкапы не найдены"
	@read -p "Введите имя файла бэкапа: " backup_file; \
	if [ -f "backups/$$backup_file" ]; then \
		echo "$(CYAN)Восстановление из $$backup_file...$(NC)"; \
		docker run --rm -v wg-obfuscation_wg_data:/data -v $(PWD)/backups:/backup alpine tar xzf /backup/$$backup_file -C /data; \
		echo "$(GREEN)Восстановление завершено$(NC)"; \
	else \
		echo "$(RED)Файл не найден!$(NC)"; \
	fi

generate-mobile: ## Создать конфигурацию для мобильного устройства
	@read -p "Имя клиента: " client_name; \
	docker-compose exec wg-easy wg-config-generator mobile "$$client_name"

generate-router: ## Создать конфигурацию для роутера
	@read -p "Имя роутера: " router_name; \
	docker-compose exec wg-easy wg-config-generator router "$$router_name"

generate-desktop: ## Создать конфигурацию для десктопа
	@read -p "Имя клиента: " client_name; \
	docker-compose exec wg-easy wg-config-generator desktop "$$client_name"

qr: ## Показать QR-код последнего созданного клиента
	@docker-compose exec wg-easy show-qr-code

monitor: ## Мониторинг подключений в реальном времени
	@echo "$(CYAN)Мониторинг подключений (Ctrl+C для выхода):$(NC)"
	@while true; do \
		clear; \
		echo "$(CYAN)=== WireGuard Connections Monitor ===$(NC)"; \
		echo "$(YELLOW)Время: $$(date)$(NC)"; \
		echo ""; \
		docker-compose exec wg-easy wg show 2>/dev/null || echo "WireGuard не запущен"; \
		echo ""; \
		echo "$(CYAN)=== Docker Stats ===$(NC)"; \
		docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" $$(docker-compose ps -q) 2>/dev/null || true; \
		sleep 5; \
	done

check-ports: ## Проверить доступность портов
	@echo "$(CYAN)Проверка портов...$(NC)"
	@if [ -f .env ]; then \
		WEB_PORT=$$(grep "^WEB_PORT=" .env | cut -d'=' -f2); \
		WG_PORT=$$(grep "^WG_PORT=" .env | cut -d'=' -f2); \
		echo "Проверка веб-интерфейса (порт $$WEB_PORT):"; \
		curl -s -o /dev/null -w "%{http_code}" http://localhost:$$WEB_PORT/ && echo " - OK" || echo " - Недоступен"; \
		echo "Проверка WireGuard (порт $$WG_PORT):"; \
		nc -u -z localhost $$WG_PORT && echo " - OK" || echo " - Недоступен"; \
	else \
		echo "$(RED).env файл не найден. Запустите 'make setup'$(NC)"; \
	fi

shell: ## Войти в контейнер wg-easy
	@docker-compose exec wg-easy /bin/bash

shell-stats: ## Войти в контейнер статистики
	@docker-compose exec stats /bin/bash

info: ## Показать полную информацию о системе
	@echo "$(CYAN)=== Информация о системе ===$(NC)"
	@echo "$(YELLOW)Docker версия:$(NC)"
	@docker --version
	@echo "$(YELLOW)Docker Compose версия:$(NC)"
	@docker-compose --version
	@echo ""
	@echo "$(YELLOW)Запущенные контейнеры:$(NC)"
	@docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
	@echo ""
	@if [ -f .env ]; then \
		echo "$(YELLOW)Текущая конфигурация:$(NC)"; \
		cat .env | grep -E "^[A-Z]" | head -10; \
	fi

test-dns: ## Тестировать DNS внутри VPN
	@echo "$(CYAN)Тестирование DNS...$(NC)"
	@docker-compose exec wg-easy nslookup google.com || echo "DNS тест не удался"

edit-env: ## Редактировать .env файл
	@if [ -f .env ]; then \
		${EDITOR:-nano} .env; \
	else \
		echo "$(RED).env файл не найден. Запустите 'make setup'$(NC)"; \
	fi

# Дефолтная цель
.DEFAULT_GOAL := help
