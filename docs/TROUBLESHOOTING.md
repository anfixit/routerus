# Решение проблем RouteRus VPN

## Диагностика проблем

### Автоматическая диагностика

```bash
# Запуск полной диагностики
./scripts/wg-manager.sh diagnostics

# Проверка статуса сервисов
make status

# Просмотр логов
make logs
```

## Проблемы с установкой

### Docker не устанавливается

**Симптомы:**
- Команда `docker` не найдена
- Ошибки при установке docker.io

**Решение:**
```bash
# Для Ubuntu/Debian
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Добавление пользователя в группу docker
sudo usermod -aG docker $USER
newgrp docker

# Проверка установки
docker --version
```

### Ошибки прав доступа

**Симптомы:**
- `permission denied while trying to connect to the Docker daemon`
- `Got permission denied while trying to connect to the Docker daemon socket`

**Решение:**
```bash
# Добавление в группу docker
sudo usermod -aG docker $USER

# Перезагрузка сессии
logout
# Войдите заново

# Альтернатива - перезапуск Docker
sudo systemctl restart docker
```

### Порты уже заняты

**Симптомы:**
- `Port 51821 is already in use`
- `bind: address already in use`

**Диагностика:**
```bash
# Проверка занятых портов
sudo netstat -tulpn | grep -E "(51820|51821|8080)"
sudo ss -tulpn | grep -E "(51820|51821|8080)"
```

**Решение:**
```bash
# Остановка конфликтующих сервисов
sudo systemctl stop apache2
sudo systemctl stop nginx
sudo systemctl stop lighttpd

# Изменение портов в .env
WEB_PORT=52821
STATS_PORT=8081
```

## Проблемы с подключением

### Клиент не подключается

**Симптомы:**
- Timeout при подключении
- Handshake failed
- No response from server

**Диагностика:**
```bash
# Проверка статуса сервера
docker compose exec wg-easy wg show

# Проверка портов на сервере
sudo ss -tulpn | grep 51820

# Тест доступности порта
telnet your-server.com 51820
```

**Решение:**

1. **Проверьте firewall:**
```bash
# UFW
sudo ufw status
sudo ufw allow 51820/udp

# iptables
sudo iptables -L -n | grep 51820
sudo iptables -A INPUT -p udp --dport 51820 -j ACCEPT
```

2. **Проверьте облачный firewall:**
   - AWS Security Groups
   - DigitalOcean Firewall
   - Google Cloud Firewall Rules

3. **Попробуйте альтернативные порты:**
```bash
# В клиентском конфиге измените порт на 443
Endpoint = your-server.com:443
```

### Handshake успешен, но интернет не работает

**Симптомы:**
- WireGuard показывает подключение
- Handshake присутствует
- Веб-сайты не загружаются

**Диагностика:**
```bash
# Проверка маршрутизации
ip route

# Проверка DNS
nslookup google.com
dig @8.8.8.8 google.com

# Проверка IP
curl ifconfig.me
```

**Решение:**

1. **Проверьте IP forwarding:**
```bash
# На сервере
docker compose exec wg-easy cat /proc/sys/net/ipv4/ip_forward
# Должно быть 1

# Если 0, то включите:
echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

2. **Проверьте iptables правила:**
```bash
# Внутри контейнера wg-easy
docker compose exec wg-easy iptables -t nat -L POSTROUTING
# Должно быть правило MASQUERADE
```

3. **Проверьте DNS в конфиге:**
```ini
[Interface]
DNS = 94.140.14.14, 94.140.15.15
```

### Медленная скорость подключения

**Симптомы:**
- Очень низкая скорость загрузки/выгрузки
- Высокий ping
- Timeouts при загрузке сайтов

**Диагностика:**
```bash
# Тест скорости
speedtest-cli

# Проверка MTU
ping -M do -s 1472 your-server.com

# Мониторинг ресурсов сервера
docker stats
```

**Решение:**

1. **Оптимизация MTU:**
```ini
# В клиентском конфиге попробуйте разные значения
MTU = 1280  # Для проблемных сетей
MTU = 1420  # Стандартное значение
MTU = 1500  # Максимальное для Ethernet
```

2. **Проверьте загрузку сервера:**
```bash
# CPU и память
top
htop

# Дисковая активность
iotop

# Сетевая активность
iftop
```

3. **Смена локации сервера:**
   - Выберите сервер ближе к вашему местоположению
   - Используйте сервер с лучшими характеристиками

## Проблемы с обфускацией

### AmneziaWG параметры не работают

**Симптомы:**
- Конфиг не импортируется в AmneziaVPN
- Стандартные WireGuard клиенты игнорируют обфускацию
- Ошибки при подключении с обфускацией

**Решение:**

1. **Используйте правильный клиент:**
   - ❌ Стандартный WireGuard клиент НЕ поддерживает обфускацию
   - ✅ Скачайте AmneziaVPN с [amnezia.org](https://amnezia.org)

2. **Проверьте параметры обфускации:**
```ini
# Правильный формат
Jc = 5
Jmin = 100
Jmax = 1000
S1 = 86
S2 = 92
H1 = 1234567890
H2 = 9876543210
H3 = 1122334455
H4 = 5544332211
```

3. **Сгенерируйте новые параметры:**
```bash
# Пересоздание конфигурации с новыми параметрами
./scripts/wg-manager.sh create-client mobile client-new
```

### Cloak не работает

**Симптомы:**
- Не удается подключиться через Cloak
- Ошибки при запуске Cloak контейнера

**Диагностика:**
```bash
# Проверка статуса Cloak
docker compose logs cloak

# Проверка портов Cloak
ss -tulpn | grep -E "(8443|8080)"
```

**Решение:**

1. **Перегенерируйте Cloak конфигурацию:**
```bash
./scripts/setup-cloak.sh
```

2. **Проверьте переменные окружения:**
```bash
# В .env файле
CLOAK_ENABLED=true
```

3. **Запустите с Cloak профилем:**
```bash
docker compose --profile cloak up -d
```

## Проблемы с роутерами

### Роутер не подключается к серверу

**Симптомы:**
- Роутер показывает "подключение..."
- Нет handshake на сервере
- Интернет через роутер не работает

**Диагностика:**
```bash
# На сервере проверьте peer
docker compose exec wg-easy wg show

# Проверьте добавлен ли публичный ключ роутера
```

**Решение:**

1. **Добавьте роутер на сервер:**
   - Войдите в веб-интерфейс wg-easy
   - Создайте нового клиента с именем роутера
   - Используйте публичный ключ из конфигурации роутера

2. **Проверьте настройки роутера:**
```ini
# MTU для роутеров
MTU = 1420

# Без PersistentKeepalive
# PersistentKeepalive = 0 (или уберите строку)

# Endpoint
Endpoint = your-server.com:51820
```

3. **Попробуйте другой порт:**
```ini
# Вместо 51820 попробуйте 443
Endpoint = your-server.com:443
```

### Только некоторые устройства работают через VPN

**Симптомы:**
- Роутер подключен к VPN
- Некоторые устройства идут через VPN, другие нет
- Непостоянная работа VPN

**Решение:**

1. **Проверьте маршрутизацию на роутере:**
   - Убедитесь что VPN подключение имеет приоритет
   - Проверьте что трафик идет через WireGuard интерфейс

2. **Для Keenetic:**
   - "Интернет" → "Подключения"
   - Установите приоритет WireGuard выше основного подключения

3. **Проверьте DNS на роутере:**
   - Установите AdGuard DNS: 94.140.14.14, 94.140.15.15
   - Отключите DNS провайдера

## Проблемы с DNS и блокировкой рекламы

### Реклама не блокируется

**Симптомы:**
- Реклама показывается на сайтах
- Трекеры работают
- AdGuard статистика не показывает блокировки

**Диагностика:**
```bash
# Проверка используемых DNS
nslookup doubleclick.net
nslookup ads.google.com

# Должны возвращать заблокированные IP
```

**Решение:**

1. **Проверьте DNS в конфигурации:**
```ini
[Interface]
DNS = 94.140.14.14, 94.140.15.15
```

2. **Принудительно используйте DNS:**
   - В настройках сетевого адаптера
   - Отключите DNS over HTTPS в браузере

3. **Проверьте персональные AdGuard DNS:**
   - Войдите в dashboard AdGuard DNS
   - Убедитесь что устройство активно
   - Проверьте статистику блокировок

### DNS не работает

**Симптомы:**
- Сайты не открываются по доменам
- Работает только по IP адресам
- Ошибки resolving host

**Решение:**

1. **Проверьте DNS серверы:**
```bash
# Тест разных DNS
nslookup google.com 8.8.8.8
nslookup google.com 94.140.14.14
```

2. **Смените DNS в конфиге:**
```ini
# Вместо AdGuard используйте Google DNS
DNS = 8.8.8.8, 8.8.4.4

# Или Cloudflare
DNS = 1.1.1.1, 1.0.0.1
```

3. **Очистите DNS кеш:**
```bash
# Windows
ipconfig /flushdns

# macOS
sudo dscacheutil -flushcache

# Linux
sudo systemctl restart systemd-resolved
```

## Проблемы с веб-интерфейсом

### Не открывается wg-easy

**Симптомы:**
- Страница не загружается
- Connection refused
- Timeout при обращении к веб-интерфейсу

**Диагностика:**
```bash
# Проверка контейнера wg-easy
docker compose ps
docker compose logs wg-easy

# Проверка порта
curl -I http://localhost:51821
```

**Решение:**

1. **Перезапустите контейнер:**
```bash
docker compose restart wg-easy
```

2. **Проверьте порт в .env:**
```bash
# Убедитесь что порт не занят
WEB_PORT=51821
```

3. **Проверьте firewall:**
```bash
sudo ufw allow 51821/tcp
```

### Неверный пароль

**Симптомы:**
- Веб-интерфейс просит пароль
- Пароль из .env не подходит

**Решение:**

1. **Проверьте пароль в .env:**
```bash
grep WG_EASY_PASSWORD .env
```

2. **Перегенерируйте пароль:**
```bash
# Создайте новый пароль
openssl rand -base64 16

# Обновите .env
WG_EASY_PASSWORD=новый_пароль

# Перезапустите
docker compose restart wg-easy
```

### Веб-статистика не работает

**Симптомы:**
- Страница статистики не загружается
- Показывает ошибки PHP

**Решение:**

1. **Проверьте контейнер статистики:**
```bash
docker compose logs stats
```

2. **Перезапустите контейнер:**
```bash
docker compose restart stats
```

## Проблемы производительности

### Высокое потребление CPU

**Диагностика:**
```bash
# Мониторинг контейнеров
docker stats

# Системные ресурсы
top
htop
```

**Решение:**

1. **Ограничьте ресурсы контейнеров:**
```yaml
# В docker-compose.yml
services:
  wg-easy:
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 512M
```

2. **Оптимизируйте параметры обфускации:**
```bash
# Уменьшите количество мусорных пакетов
JC=3
JMIN=50
JMAX=500
```

### Проблемы с памятью

**Симптомы:**
- Контейнеры падают с OOM
- Система зависает

**Решение:**

1. **Ограничьте память:**
```yaml
services:
  wg-easy:
    deploy:
      resources:
        limits:
          memory: 256M
```

2. **Увеличьте swap:**
```bash
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

## Логи и мониторинг

### Полезные команды для диагностики

```bash
# Все логи
make logs

# Логи конкретного сервиса
docker compose logs wg-easy
docker compose logs stats
docker compose logs cloak

# Системные логи
sudo journalctl -f
sudo dmesg | tail

# Статистика WireGuard
docker compose exec wg-easy wg show

# Мониторинг ресурсов
docker stats --no-stream
```

### Включение детального логирования

```bash
# В .env файле
LOG_LEVEL=debug
ENABLE_LOGGING=true

# Перезапуск для применения
docker compose restart
```

## Получение помощи

### Создание отчета о проблеме

```bash
# Соберите информацию для отчета
echo "=== System Info ===" > debug-report.txt
uname -a >> debug-report.txt
docker --version >> debug-report.txt

echo "=== Container Status ===" >> debug-report.txt
docker compose ps >> debug-report.txt

echo "=== WireGuard Status ===" >> debug-report.txt
docker compose exec wg-easy wg show >> debug-report.txt

echo "=== Logs ===" >> debug-report.txt
docker compose logs --tail=50 >> debug-report.txt
```

### Сброс к заводским настройкам

```bash
# ВНИМАНИЕ: Удаляет ВСЕ данные!
make clean

# Или вручную
docker compose down -v
docker system prune -f
rm -f .env
```

Если проблема не решена, создайте issue на GitHub с подробным описанием и файлом debug-report.txt.
