# Подробная инструкция по установке RouteRus VPN

## Системные требования

### Минимальные требования
- **ОС**: Ubuntu 20.04+ или Debian 11+
- **RAM**: 1 GB
- **Диск**: 2 GB свободного места
- **CPU**: 1 ядро
- **Сеть**: Публичный IP адрес

### Рекомендуемые требования
- **ОС**: Ubuntu 22.04 LTS
- **RAM**: 2 GB
- **Диск**: 5 GB свободного места
- **CPU**: 2 ядра
- **Сеть**: Статический IP или домен

## Быстрая установка

### Автоматическая установка (рекомендуется)

```bash
# 1. Клонирование репозитория
git clone https://github.com/yourusername/routerus-vpn.git
cd routerus-vpn

# 2. Быстрая установка
make install
```

### Пошаговая установка

```bash
# 1. Клонирование проекта
git clone https://github.com/yourusername/routerus-vpn.git
cd routerus-vpn

# 2. Настройка переменных окружения
make setup

# 3. Запуск сервисов
make start

# 4. Проверка статуса
make status
```

## Ручная установка

### 1. Подготовка системы

```bash
# Обновление системы
sudo apt update && sudo apt upgrade -y

# Установка Docker
sudo apt install -y docker.io docker-compose-plugin

# Добавление пользователя в группу docker
sudo usermod -aG docker $USER
newgrp docker

# Проверка установки
docker --version
docker compose version
```

### 2. Настройка проекта

```bash
# Клонирование
git clone https://github.com/yourusername/routerus-vpn.git
cd routerus-vpn

# Создание .env из шаблона
cp .env.example .env

# Редактирование конфигурации
nano .env
```

### 3. Настройка переменных окружения

Основные параметры в `.env`:

```bash
# Ваш сервер
SERVER_ENDPOINT=your-server.com

# Пароль веб-интерфейса
WG_EASY_PASSWORD=your-secure-password

# Порты
WEB_PORT=51821
WG_PORT=51820

# DNS серверы (AdGuard)
ADGUARD_DNS_IP1=94.140.14.14
ADGUARD_DNS_IP2=94.140.15.15

# Параметры обфускации (генерируются автоматически)
JC=5
JMIN=100
JMAX=1000
S1=86
S2=92
```

### 4. Запуск сервисов

```bash
# Запуск основных сервисов
docker compose up -d

# Запуск с Cloak (дополнительная обфускация)
docker compose --profile cloak up -d

# Проверка статуса
docker compose ps
```

## Настройка firewall

### UFW (Ubuntu/Debian)

```bash
# Базовые правила
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Разрешаем SSH
sudo ufw allow ssh

# Разрешаем WireGuard порты
sudo ufw allow 51820/udp
sudo ufw allow 51821/tcp

# Порты для обфускации
sudo ufw allow 443/udp
sudo ufw allow 53/udp
sudo ufw allow 993/udp

# Веб-статистика
sudo ufw allow 8080/tcp

# Cloak (если включен)
sudo ufw allow 8443/tcp

# Включаем firewall
sudo ufw --force enable
```

### iptables (альтернатива)

```bash
# Базовые правила
sudo iptables -F
sudo iptables -P INPUT DROP
sudo iptables -P FORWARD ACCEPT
sudo iptables -P OUTPUT ACCEPT

# Разрешаем loopback
sudo iptables -A INPUT -i lo -j ACCEPT

# Разрешаем установленные соединения
sudo iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# SSH
sudo iptables -A INPUT -p tcp --dport 22 -j ACCEPT

# WireGuard и веб-интерфейс
sudo iptables -A INPUT -p udp --dport 51820 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 51821 -j ACCEPT

# Порты обфускации
sudo iptables -A INPUT -p udp --dport 443 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 53 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 993 -j ACCEPT

# Сохранение правил
sudo iptables-save > /etc/iptables/rules.v4
```

## Настройка облачного провайдера

### DigitalOcean

1. Создайте Droplet с Ubuntu 22.04
2. Добавьте SSH ключ
3. В настройках Droplet откройте порты:
   - 51820/UDP (WireGuard)
   - 51821/TCP (веб-интерфейс)
   - 443/UDP, 53/UDP, 993/UDP (обфускация)

### AWS EC2

1. Создайте EC2 instance с Ubuntu 22.04
2. Настройте Security Group:
   ```
   SSH: 22/TCP from your IP
   WireGuard: 51820/UDP from 0.0.0.0/0
   Web: 51821/TCP from your IP
   Obfuscation: 443/UDP, 53/UDP, 993/UDP from 0.0.0.0/0
   ```

### Google Cloud Platform

1. Создайте VM instance с Ubuntu 22.04
2. Настройте firewall rules:
   ```bash
   gcloud compute firewall-rules create wireguard-allow \
     --allow udp:51820,tcp:51821,udp:443,udp:53,udp:993 \
     --source-ranges 0.0.0.0/0
   ```

## Проверка установки

### 1. Проверка Docker контейнеров

```bash
docker compose ps

# Должны быть запущены:
# - wg-easy-obfuscated
# - wg-stats
# - cloak-obfuscator (если включен)
```

### 2. Проверка портов

```bash
# Проверка открытых портов
ss -tulpn | grep -E "(51820|51821|8080)"

# Тест доступности веб-интерфейса
curl -I http://localhost:51821
```

### 3. Проверка WireGuard

```bash
# Проверка интерфейса WireGuard внутри контейнера
docker compose exec wg-easy wg show

# Просмотр логов
docker compose logs wg-easy
```

## Первоначальная настройка

### 1. Доступ к веб-интерфейсу

1. Откройте браузер
2. Перейдите на `http://your-server:51821`
3. Введите пароль из `.env` файла
4. Создайте первого клиента

### 2. Настройка AdGuard DNS

Если у вас есть персональный AdGuard DNS:

1. Войдите на [adguard-dns.io](https://adguard-dns.io)
2. Создайте устройство
3. Получите персональные DNS адреса
4. Обновите `.env` файл:
   ```bash
   ADGUARD_DNS_HTTPS=https://d.adguard-dns.com/dns-query/your-id
   ADGUARD_DNS_TLS=tls://your-id.d.adguard-dns.com
   ```
5. Перезапустите: `docker compose restart`

### 3. Настройка Cloak (опционально)

Для максимальной обфускации:

```bash
# Генерация Cloak конфигурации
./scripts/setup-cloak.sh

# Включение в .env
echo "CLOAK_ENABLED=true" >> .env

# Запуск с Cloak
docker compose --profile cloak up -d
```

## Обновление

### Автоматическое обновление

```bash
make update
```

### Ручное обновление

```bash
# Остановка сервисов
docker compose down

# Обновление кода
git pull

# Пересборка образов
docker compose build --no-cache

# Запуск обновленных сервисов
docker compose up -d
```

## Резервное копирование

### Создание бэкапа

```bash
make backup
```

### Ручное создание бэкапа

```bash
# Создание директории
mkdir -p backups

# Бэкап Docker volumes
docker run --rm -v routerus-vpn_wg_data:/data -v $(pwd)/backups:/backup alpine \
  tar czf /backup/wireguard-backup-$(date +%Y%m%d-%H%M%S).tar.gz -C /data .

# Бэкап конфигурации
cp .env backups/env-backup-$(date +%Y%m%d-%H%M%S).env
```

### Восстановление из бэкапа

```bash
make restore
```

## Устранение проблем при установке

### Docker не устанавливается

```bash
# Для старых версий Ubuntu
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
```

### Ошибки прав доступа

```bash
# Добавление пользователя в группу docker
sudo usermod -aG docker $USER
logout
# Войдите заново
```

### Порты заняты

```bash
# Проверка занятых портов
sudo netstat -tulpn | grep -E "(51820|51821)"

# Остановка конфликтующих сервисов
sudo systemctl stop apache2  # если порт 80 занят
sudo systemctl stop nginx    # если порт 80 занят
```

### Проблемы с DNS

```bash
# Проверка DNS
nslookup google.com 8.8.8.8

# Временное изменение DNS
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
```

## Следующие шаги

После успешной установки:

1. Прочитайте [ROUTER_SETUP.md](ROUTER_SETUP.md) для настройки роутеров
2. Изучите [SECURITY.md](SECURITY.md) для рекомендаций по безопасности
3. При проблемах см. [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
