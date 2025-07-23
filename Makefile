.PHONY: help build up down restart logs clean backup restore deploy status

# Цвета для вывода
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
NC := \033[0m

help: ## Показать помощь
	@echo "$(GREEN)Routerus V2 - Управление VPN системой$(NC)"
	@echo "$(YELLOW)Доступные команды:$(NC)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(GREEN)%-15s$(NC) %s\n", $$1, $$2}' $(MAKEFILE_LIST)

build: ## Собрать все Docker образы
	@echo "$(GREEN)Сборка Docker образов...$(NC)"
	docker-compose build --no-cache

up: ## Запустить все сервисы
	@echo "$(GREEN)Запуск сервисов...$(NC)"
	docker-compose up -d
	@echo "$(GREEN)Сервисы запущены!$(NC)"
	@echo "$(YELLOW)Веб-интерфейс: https://$(shell grep DOMAIN .env | cut -d '=' -f2)$(NC)"
	@echo "$(YELLOW)Grafana: http://$(shell grep DOMAIN .env | cut -d '=' -f2):3000$(NC)"

down: ## Остановить все сервисы
	@echo "$(RED)Остановка сервисов...$(NC)"
	docker-compose down

restart: ## Перезапустить все сервисы
	@echo "$(YELLOW)Перезапуск сервисов...$(NC)"
	docker-compose restart

logs: ## Показать логи всех сервисов
	docker-compose logs -f

logs-backend: ## Показать логи backend
	docker-compose logs -f backend

logs-vpn: ## Показать логи VPN сервера
	docker-compose logs -f vpn-server

logs-nginx: ## Показать логи Nginx
	docker-compose logs -f nginx

status: ## Показать статус сервисов
	@echo "$(GREEN)Статус сервисов:$(NC)"
	docker-compose ps
	@echo ""
	@echo "$(GREEN)Использование ресурсов:$(NC)"
	docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}"

health: ## Проверить здоровье сервисов
	@echo "$(GREEN)Проверка здоровья сервисов:$(NC)"
	@docker-compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
	@echo ""
	@echo "$(GREEN)Backend API:$(NC)"
	@curl -s http://localhost:8000/health | python3 -m json.tool || echo "$(RED)Backend недоступен$(NC)"

clean: ## Очистить Docker данные
	@echo "$(YELLOW)Очистка Docker данных...$(NC)"
	docker-compose down -v
	docker system prune -f
	docker volume prune -f

backup: ## Создать резервную копию
	@echo "$(GREEN)Создание резервной копии...$(NC)"
	./scripts/backup.sh

restore: ## Восстановить из резервной копии
	@echo "$(YELLOW)Восстановление из резервной копии...$(NC)"
	./scripts/restore.sh

deploy: ## Развернуть на удаленном сервере
	@echo "$(GREEN)Развертывание на сервере...$(NC)"
	./scripts/deploy.sh

update: ## Обновить систему
	@echo "$(GREEN)Обновление системы...$(NC)"
	git pull origin main
	docker-compose build --no-cache
	docker-compose up -d

install-deps: ## Установить зависимости на сервер
	@echo "$(GREEN)Установка зависимостей...$(NC)"
	./scripts/install-docker.sh
	./scripts/setup-server.sh

# Для разработки
dev-backend: ## Запустить только backend для разработки
	cd backend && python -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

dev-frontend: ## Запустить только frontend для разработки
	cd frontend && npm run dev

dev-setup: ## Настроить окружение для разработки
	@echo "$(GREEN)Настройка окружения разработки...$(NC)"
	cd backend && pip install -r requirements.txt
	cd frontend && npm install

# Мониторинг
monitor: ## Открыть Grafana в браузере
	@echo "$(GREEN)Открываем Grafana...$(NC)"
	@python -c "import webbrowser; webbrowser.open('http://localhost:3000')"

prometheus: ## Открыть Prometheus в браузере
	@echo "$(GREEN)Открываем Prometheus...$(NC)"
	@python -c "import webbrowser; webbrowser.open('http://localhost:9090')"

# Пользователи VPN
add-user: ## Добавить пользователя VPN
	@read -p "Email пользователя: " email; \
	curl -X POST "http://localhost:8000/api/users" \
		-H "Content-Type: application/json" \
		-d "{\"email\":\"$$email\",\"server_id\":\"default\"}"

list-users: ## Показать всех пользователей
	@curl -s "http://localhost:8000/api/users" | python3 -m json.tool

# SSL сертификаты
ssl-generate: ## Генерировать SSL сертификаты
	@echo "$(GREEN)Генерация SSL сертификатов...$(NC)"
	docker-compose run --rm certbot

ssl-renew: ## Обновить SSL сертификаты
	@echo "$(GREEN)Обновление SSL сертификатов...$(NC)"
	docker-compose run --rm certbot renew

# По умолчанию показываем help
.DEFAULT_GOAL := help
