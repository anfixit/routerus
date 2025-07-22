# routerus Project 🌐🚀

routerus — это проект для управления VPN (WireGuard), Shadowsocks и Xray сервисами через Python и Django. Проект предлагает веб-интерфейс, автоматическую загрузку логов в Dropbox, а также интеграцию с Promtail/Loki для удобного логирования. Всё это делает управление VPN максимально простым и гибким! 🎉

## Особенности ✨

- Управление WireGuard через Python: Генерация конфигураций и управление интерфейсом без прямого редактирования `wg-quick` или `.conf` файлов.
- Динамическая настройка: Все параметры берутся из переменных окружения (`.env`), без ручного редактирования конфигов.
- Автоматизация запуска:  
  Используйте `start.sh` и `stop.sh` для запуска/остановки всех сервисов или Django management-команды (`servicestart`, `servicestop`, `servicestatus`, `servicestatus_service`) для удобного управления через `manage.py`.
- Переносимость: Возможен запуск в Docker-контейнерах, минимальные зависимости.
- Логирование:  
  Логи отправляются в Dropbox, собираются Promtail и анализируются Loki. Логи в JSON-формате, с ротацией.
- Веб-интерфейс (Django): Управление пользователями, генерация клиентских конфигураций, REST API для добавления клиентов — всё доступно в удобном веб-интерфейсе.

## Структура проекта 🗂

.
├── app
│   ├── core
│   │   ├── config.py               # Pydantic настройки
│   │   ├── logging.py              # Настройки логирования
│   │   └── service_configurator.py # Единый интерфейс для конфигураций сервисов
│   ├── management
│   │   └── commands
│   │       ├── servicestart.py
│   │       ├── servicestop.py
│   │       ├── servicestatus.py
│   │       └── servicestatus_service.py
│   ├── services
│   │   ├── service_manager.py      # Класс ServiceManager для управления сервисами
│   │   ├── wireguard/
│   │   ├── shadowsocks/
│   │   ├── xray/
│   │   └── dropbox/
│   ├── templates
│   └── ... (модели, вьюхи, статические файлы)
├── config                          # Доп. конфиги (nginx, loki, promtail)
├── scripts                         # Скрипты start.sh, stop.sh и т.д.
└── tests                           # Тесты

## Настройка 🛠

### Установка зависимостей

pip install --upgrade pip
pip install poetry
poetry install --no-dev

### ENV переменные

Создайте файл `.env` в `/opt/routerus/.env` (или другом пути, указанном в config.py):

DEBUG=False
SECRET_KEY="your-secret-key"
ALLOWED_HOSTS="your_server_ip_or_domain,yoursite.ru,localhost,127.0.0.1"

DB_NAME="wg_manager_db"
DB_USER="wg_user"
DB_PASSWORD="password"
DB_HOST="localhost"
DB_PORT=5432

DROPBOX_ACCESS_TOKEN="your_dropbox_token"
DROPBOX_APP_KEY="your_app_key"
DROPBOX_APP_SECRET="your_app_secret"

SHADOWSOCKS_SERVER="your_server_ip"
SHADOWSOCKS_PORT=8388
SHADOWSOCKS_PASSWORD="strongpassword"
SHADOWSOCKS_METHOD="chacha20-ietf-poly1305"
SHADOWSOCKS_TIMEOUT=300

XRAY_UUID="5db36724-4e3c-4669-8e6d-488d2815dd8a"
# И другие переменные для Xray и WireGuard

### Применение миграций

python manage.py migrate

### Запуск

- Запуск всех сервисов:
bash scripts/start.sh

- Остановка всех сервисов:
bash scripts/stop.sh

- Через Django-команды:
python manage.py servicestart
python manage.py servicestop
python manage.py servicestatus
python manage.py servicestatus_service wireguard

### Веб-интерфейс

Запустите Django-сервер (например, gunicorn):

gunicorn config.wsgi:application --bind 0.0.0.0:8000

После этого веб-интерфейс будет доступен по адресу:
http://your_server:8000

## Логирование 📝

- Логи пишутся в /var/log/routerus/app.log (JSON-формат, с ротацией).
- Логи дублируются в консоль.
- Используйте Promtail для отправки логов в Loki для более удобного анализа.

## Docker 🐳

В проекте есть docker-compose.yml. Запуск контейнеров:

docker-compose up --build

## Тестирование ✅

Тесты расположены в каталоге tests. Запуск тестов:

python manage.py test

В дальнейшем планируется добавить больше интеграционных тестов и линтеры (flake8, black) для проверки качества кода.

## CI/CD ⚙️

При необходимости можно добавить GitHub Actions или GitLab CI для автоматического тестирования и деплоя при каждом коммите.

## Авторы и Контакты ✉️

Поддержка: anfisa.kov@yahoo.com
