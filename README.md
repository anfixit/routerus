
# WireGuard Manager (wg-manager)

**WireGuard Manager** — это система управления VPN, которая интегрируется с Shadowsocks и Xray для обеспечения гибкой настройки и дополнительной обфускации.

## Возможности
- Создание и управление конфигурациями WireGuard.
- Интеграция с Shadowsocks для маскировки трафика.
- Обфускация с использованием Xray (VLESS/WS/TLS).
- Веб-интерфейс для управления пользователями и конфигурациями.
- Логирование с использованием Loki и Promtail.

## Установка

### Предварительные требования
- Python 3.12
- Docker и Docker Compose
- PostgreSQL

### Шаги установки
1. Клонируйте репозиторий:
    ```
    git clone https://github.com/Anfikus/wg-manager.git
    cd wg-manager
    ```

2. Установите зависимости:
    ```
    poetry install
    ```

3. Настройте `.env` файл:
    Скопируйте пример:
    ```
    cp config/.env.example config/.env
    ```
    И заполните переменные окружения.

4. Запустите приложение:
    ```
    docker-compose up -d
    ```

5. Доступ к приложению:
    Перейдите на [http://localhost:8000](http://localhost:8000).

## Примеры использования
### Создание конфигурации клиента
1. Откройте веб-интерфейс.
2. Выберите «Добавить клиента».
3. Заполните данные клиента и сохраните.
4. Скачайте или просмотрите конфигурацию.

## FAQ
### Что делать при сбое запуска?
- Проверьте логи приложения:
    ```
    docker logs wg-manager
    ```
- Убедитесь, что все зависимости установлены.

### Как добавить новый ключ WireGuard?
1. Используйте интерфейс или CLI для добавления.
2. Убедитесь, что ключ уникален.

## Автоматический запуск

### Настройка systemd
Для обеспечения автоматического запуска после перезагрузки:
1. Создайте файл `/etc/systemd/system/wg-manager.service`:
   ```
   sudo nano /etc/systemd/system/wg-manager.service
   ```

2. Вставьте следующую конфигурацию:
   ```ini
   [Unit]
   Description=WireGuard Manager Application
   After=network.target

   [Service]
   Type=forking
   User=your_user
   Group=your_group
   WorkingDirectory=/path/to/your/app
   ExecStart=/bin/ /path/to/your/app/scripts/start.sh
   ExecStop=/bin/ /path/to/your/app/scripts/stop.sh
   Restart=always
   RestartSec=5

   [Install]
   WantedBy=multi-user.target
   ```

3. Активируйте сервис:
   ```
   sudo systemctl enable wg-manager
   ```

4. Перезагрузите сервер и проверьте:
   ```
   sudo reboot
   ```

### Ручной запуск и остановка
Для запуска вручную:
```
sudo systemctl start wg-manager
```

Для остановки:
```
sudo systemctl stop wg-manager
```

## Лицензия
Данный проект распространяется под лицензией MIT. См. [LICENSE](LICENSE) для получения дополнительной информации.
