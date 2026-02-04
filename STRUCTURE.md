# RouteRus Project Structure

```
routerus/
│
├── .github/
│   └── workflows/
│       └── validate.yml          # CI/CD для проверки синтаксиса скриптов
│
├── .ropeproject/                 # IDE конфигурация (игнорируется git)
│
├── configs/
│   └── routing/                  # Шаблоны конфигураций маршрутизации
│       ├── base-routing.json     # Базовый шаблон роутинга
│       ├── adblock-rule.json     # Правила блокировки рекламы
│       ├── ru-direct-rule.json   # Правила прямого роутинга для РФ
│       └── quic-block-rule.json  # Правила блокировки QUIC
│
├── scripts/                      # Модульные скрипты установки
│   ├── helpers.sh               # Вспомогательные функции
│   ├── system-update.sh         # Обновление системы
│   ├── cleanup.sh               # Очистка старых установок
│   ├── domain-setup.sh          # Настройка доменов
│   ├── routing-config.sh        # Конфигурация роутинга
│   ├── install-packages.sh      # Установка пакетов
│   ├── install-xui.sh           # Установка 3X-UI
│   ├── ssl-setup.sh             # Настройка SSL
│   ├── db-config.sh             # Конфигурация БД
│   ├── setup-routing.sh         # Применение правил роутинга
│   ├── nginx-config.sh          # Настройка Nginx
│   ├── create-inbounds.sh       # Создание inbound'ов
│   ├── optimize.sh              # Оптимизация системы (BBR)
│   ├── firewall.sh              # Настройка UFW
│   ├── cron-setup.sh            # Настройка cron задач
│   ├── show-results.sh          # Вывод результатов
│   └── uninstall.sh             # Удаление RouteRus
│
├── services/                     # Systemd service files (будущее)
│
├── docs/                         # Дополнительная документация (будущее)
│
├── .env.example                  # Пример конфигурации
├── .gitignore                    # Git ignore правила
├── .gitattributes                # Git атрибуты
├── LICENSE                       # MIT лицензия с благодарностями
├── README.md                     # Главная документация
├── CHANGELOG.md                  # История изменений
├── install.sh                    # Главный установочный скрипт
└── quick-install.sh              # Быстрая установка (одна команда)
```

## Описание компонентов

### Главные файлы

- **install.sh** - Основной модульный установочный скрипт
  - Вызывает все модули по порядку
  - Поддерживает аргументы командной строки
  - Обрабатывает интерактивный и автоматический режимы

- **quick-install.sh** - Упрощенная установка
  - Скачивает и запускает install.sh
  - Используется для одной команды: `bash <(wget -qO- ...)`

### Модули scripts/

Каждый модуль отвечает за свою часть установки:

1. **helpers.sh** - Общие функции
   - Цветной вывод (msg_ok, msg_err, msg_inf, msg_warn)
   - Генерация случайных строк и портов
   - Проверка доступности портов
   - Backup функции

2. **system-update.sh** - Обновление Ubuntu
   - `apt update && apt upgrade`
   - Очистка пакетов

3. **cleanup.sh** - Удаление старых установок
   - Остановка сервисов
   - Удаление файлов 3X-UI
   - Очистка Nginx конфигов

4. **domain-setup.sh** - Конфигурация доменов
   - Интерактивный ввод или из аргументов
   - Валидация DNS
   - Инструкции по DuckDNS

5. **routing-config.sh** - Выбор опций роутинга
   - Блокировка рекламы
   - Российский роутинг
   - Блокировка QUIC

6. **install-packages.sh** - Установка зависимостей
   - nginx, certbot, sqlite3, ufw
   - netcat, jq, wget, curl

7. **install-xui.sh** - Установка 3X-UI
   - Определение архитектуры
   - Скачивание последней версии через GitHub API
   - Установка systemd service

8. **ssl-setup.sh** - SSL сертификаты
   - Certbot + Let's Encrypt
   - Автоматическое обновление

9. **db-config.sh** - Настройка базы данных
   - Обновление портов и путей
   - **ФИКС:** subDomain и webDomain для Telegram бота
   - Конфигурация подписок

10. **setup-routing.sh** - Применение правил роутинга
    - Чтение шаблонов из configs/routing/
    - Генерация финального config.json
    - Обновление GeoIP/GeoSite баз

11. **nginx-config.sh** - Конфигурация Nginx
    - Stream модуль для SNI routing
    - Reverse proxy для панели
    - Фейковый сайт на порту 9443

12. **create-inbounds.sh** - Создание inbound'ов
    - VLESS + REALITY
    - VLESS + WebSocket (опционально)
    - Генерация ключей

13. **optimize.sh** - Оптимизация системы
    - Включение BBR
    - Настройка sysctl параметров

14. **firewall.sh** - UFW firewall
    - Разрешение портов 22, 80, 443
    - Блокировка всего остального

15. **cron-setup.sh** - Cron задачи
    - Автообновление SSL
    - Перезапуск сервисов

16. **show-results.sh** - Вывод результатов
    - Красивый финальный экран
    - Учетные данные
    - Следующие шаги

17. **uninstall.sh** - Удаление RouteRus
    - Полная очистка системы

### Конфигурации configs/routing/

Шаблоны JSON для разных типов маршрутизации:

- **base-routing.json** - Базовая структура
- **adblock-rule.json** - Блокировка рекламы (из работы @Corvus-Malus)
- **ru-direct-rule.json** - Российский роутинг (из работы @Corvus-Malus)
- **quic-block-rule.json** - Блокировка QUIC (из работы @Corvus-Malus)

## Workflow установки

```
1. quick-install.sh → скачивает install.sh
2. install.sh → вызывает модули:
   ├─ helpers.sh (загрузка функций)
   ├─ system-update.sh
   ├─ cleanup.sh
   ├─ domain-setup.sh
   ├─ routing-config.sh
   ├─ install-packages.sh
   ├─ install-xui.sh
   ├─ ssl-setup.sh
   ├─ db-config.sh
   ├─ setup-routing.sh (читает configs/routing/*.json)
   ├─ nginx-config.sh
   ├─ create-inbounds.sh
   ├─ optimize.sh
   ├─ firewall.sh
   ├─ cron-setup.sh
   └─ show-results.sh
```

## Расширение проекта

### Добавление нового модуля

1. Создать `/scripts/new-module.sh`
2. Добавить функцию с понятным именем
3. Вызвать в `install.sh` в нужном месте
4. Обновить STRUCTURE.md

### Добавление новых правил роутинга

1. Создать `/configs/routing/new-rule.json`
2. Добавить логику в `setup-routing.sh`
3. Добавить опцию в `routing-config.sh`

## Соглашения

### Именование

- Файлы скриптов: `kebab-case.sh`
- Функции: `snake_case`
- Переменные: `UPPERCASE` для глобальных, `lowercase` для локальных

### Комментарии

```bash
#!/bin/bash
# Краткое описание модуля

function_name() {
    # Описание функции
    local var="value"
    # Комментарий к логике
}
```

### Сообщения

```bash
msg_inf "ℹ️  Информация"
msg_ok "✓ Успех"
msg_warn "⚠️  Предупреждение"
msg_err "❌ Ошибка"
```

## CI/CD

GitHub Actions проверяет:
- Синтаксис всех .sh файлов (shellcheck)
- Валидность JSON конфигов
- Bash syntax check

## Будущие улучшения

- [ ] Docker версия
- [ ] Ansible playbook
- [ ] Web UI для управления
- [ ] Централизованное логирование
- [ ] Prometheus метрики
- [ ] Автотесты
- [ ] Multi-language README

## Вклад в проект

При добавлении кода:

1. Следуйте структуре проекта
2. Комментируйте код
3. Обновляйте STRUCTURE.md
4. Проверяйте синтаксис: `shellcheck script.sh`
5. Тестируйте на чистой Ubuntu 24.04

---

**Архитектура:** Модульная, расширяемая, понятная  
**Вдохновение:** Unix philosophy - делай одно, делай хорошо
