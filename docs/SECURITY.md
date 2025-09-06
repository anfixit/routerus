# Рекомендации по безопасности RouteRus VPN

## Общие принципы безопасности

### Уровни защиты RouteRus VPN

1. **Базовый WireGuard** - современное шифрование с отличной производительностью
2. **AmneziaWG обфускация** - маскировка VPN трафика под обычный интернет-трафик
3. **Cloak маскировка** - дополнительный уровень обфускации под HTTPS
4. **Портовая маскировка** - использование стандартных портов (443, 53, 993)
5. **DNS фильтрация** - блокировка трекеров и вредоносных доменов через AdGuard

## Настройка безопасного сервера

### Безопасность операционной системы

```bash
# Обновление системы
sudo apt update && sudo apt upgrade -y

# Настройка автоматических обновлений безопасности
sudo apt install unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades

# Настройка SSH (если используете)
sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sudo systemctl restart ssh
```

### Настройка firewall

```bash
# Строгие правила UFW
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Только необходимые порты
sudo ufw allow from YOUR_IP to any port 22    # SSH только с вашего IP
sudo ufw allow 51820/udp                      # WireGuard
sudo ufw allow 443/udp                        # Обфускация HTTPS
sudo ufw allow 53/udp                         # Обфускация DNS

# НЕ открывайте веб-интерфейс для всех
# Используйте SSH туннель или ограничьте по IP
sudo ufw allow from YOUR_IP to any port 51821 # Веб-интерфейс

sudo ufw --force enable
```

### Безопасная настройка Docker

```bash
# Ограничение ресурсов в docker-compose.yml
services:
  wg-easy:
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 512M
        reservations:
          memory: 256M
    security_opt:
      - no-new-privileges:true
    read_only: false  # WireGuard требует записи
    user: "1000:1000"  # Непривилегированный пользователь
```

## Управление ключами и паролями

### Генерация безопасных паролей

```bash
# Для веб-интерфейса (минимум 16 символов)
openssl rand -base64 24

# Для системных аккаунтов
pwgen -s 32 1

# Проверка сложности пароля
echo "your_password" | cracklib-check
```

### Ротация ключей WireGuard

```bash
# Автоматическая ротация каждые 30 дней
# В .env файле
AUTO_KEY_ROTATION_DAYS=30

# Ручная ротация ключей сервера
docker compose exec wg-easy wg genkey > new_private.key
cat new_private.key | docker compose exec -T wg-easy wg pubkey > new_public.key

# ВНИМАНИЕ: После смены ключей сервера все клиенты нужно обновить!
```

### Безопасное хранение конфигураций

```bash
# Шифрование конфигураций клиентов
gpg --symmetric --cipher-algo AES256 client.conf

# Безопасное удаление
shred -vfz -n 3 old_config.conf

# Временные конфигурации (автоудаление через 24 часа)
echo "0 0 * * * find /tmp -name '*.conf' -mtime +1 -delete" | crontab -
```

## Сетевая безопасность

### Настройка нескольких портов

```bash
# В docker-compose.yml добавьте дополнительные порты
ports:
  - "51820:51820/udp"  # Основной
  - "443:51820/udp"    # HTTPS маскировка
  - "53:51820/udp"     # DNS маскировка
  - "993:51820/udp"    # IMAPS маскировка
  - "4500:51820/udp"   # IPSec маскировка
```

### Защита от DPI (Deep Packet Inspection)

```bash
# Максимальная обфускация AmneziaWG
JC=10           # Больше мусорных пакетов
JMIN=50         # Переменный размер
JMAX=1500       # Максимальная вариативность
S1=123          # Уникальные magic headers
S2=456
H1=9876543210   # Уникальные hash значения
H2=1234567890
H3=5555666677
H4=8888999900

# Включение Cloak для двойной обфускации
CLOAK_ENABLED=true
```

### Настройка обхода блокировок

```bash
# Использование CDN (Cloudflare)
# Направьте домен через Cloudflare с проксированием

# Маскировка под веб-сервер
# Настройте nginx с реальным сайтом на 80/443
# WireGuard на нестандартном порту

# Смена IP адресов
# Используйте несколько серверов в разных локациях
```

## Безопасность клиентов

### Рекомендуемые клиентские приложения

**Для максимальной безопасности:**
- **AmneziaVPN** - поддерживает все функции обфускации
- **Проверенные сборки WireGuard** - только с официальных сайтов

**НЕ рекомендуется:**
- Сторонние приложения неизвестного происхождения
- Модифицированные клиенты с неизвестными изменениями

### Настройка kill switch

```ini
# В клиентской конфигурации
[Interface]
PostUp = iptables -I OUTPUT ! -o %i -m mark ! --mark $(wg show %i fwmark) -m addrtype ! --dst-type LOCAL -j REJECT
PreDown = iptables -D OUTPUT ! -o %i -m mark ! --mark $(wg show %i fwmark) -m addrtype ! --dst-type LOCAL -j REJECT

# Или используйте встроенный kill switch в AmneziaVPN
```

### DNS leak protection

```ini
# Принудительное использование VPN DNS
[Interface]
DNS = 94.140.14.14, 94.140.15.15
PostUp = echo 'nameserver 94.140.14.14' > /etc/resolv.conf
PostUp = echo 'nameserver 94.140.15.15' >> /etc/resolv.conf
```

## Мониторинг и аудит

### Логирование подключений

```bash
# Включение логирования в .env
ENABLE_LOGGING=true
LOG_LEVEL=info

# Мониторинг подключений
docker compose logs wg-easy | grep "handshake"

# Анализ трафика
docker compose exec wg-easy wg show all dump
```

### Обнаружение подозрительной активности

```bash
# Мониторинг необычных подключений
#!/bin/bash
# /usr/local/bin/monitor-vpn.sh

LOGFILE="/var/log/wireguard-monitor.log"

# Проверка количества одновременных подключений
CONNECTIONS=$(docker compose exec wg-easy wg show wg0 | grep peer | wc -l)
if [ $CONNECTIONS -gt 50 ]; then
    echo "$(date): WARNING: Too many connections: $CONNECTIONS" >> $LOGFILE
fi

# Проверка трафика
TRAFFIC=$(docker compose exec wg-easy wg show wg0 transfer | awk '{sum+=$3} END {print sum}')
if [ $TRAFFIC -gt 100000000000 ]; then  # 100GB
    echo "$(date): WARNING: High traffic: $TRAFFIC bytes" >> $LOGFILE
fi
```

### Автоматические уведомления

```bash
# Уведомления о новых подключениях
# Добавьте в crontab
*/5 * * * * /usr/local/bin/monitor-vpn.sh

# Уведомления по email при подозрительной активности
echo "High VPN activity detected" | mail -s "VPN Alert" admin@yourdomain.com
```

## Защита от утечек

### Проверка на утечки

```bash
# Проверка IP адреса
curl ifconfig.me

# Проверка DNS
nslookup google.com

# Проверка WebRTC утечек (в браузере)
# Используйте https://ipleak.net/
```

### Предотвращение утечек

```ini
# IPv6 отключение (если не используется)
[Interface]
PostUp = sysctl -w net.ipv6.conf.all.disable_ipv6=1
PreDown = sysctl -w net.ipv6.conf.all.disable_ipv6=0

# Блокировка локальных сетей
AllowedIPs = 0.0.0.0/1, 128.0.0.0/1
```

### Настройка браузера

```javascript
// Отключение WebRTC в Firefox
// about:config -> media.peerconnection.enabled = false

// Отключение геолокации
// about:config -> geo.enabled = false

// Использование DoH только через VPN DNS
// about:config -> network.trr.uri = https://dns.adguard-dns.com/dns-query
```

## Реагирование на инциденты

### При компрометации сервера

1. **Немедленные действия:**
```bash
# Остановка всех сервисов
docker compose down

# Смена всех паролей
# Перегенерация всех ключей
# Уведомление всех пользователей
```

2. **Анализ логов:**
```bash
# Поиск подозрительной активности
grep -i "failed\|error\|unauthorized" /var/log/auth.log
docker compose logs | grep -i "error\|fail"
```

3. **Восстановление:**
```bash
# Полная переустановка системы
# Восстановление из проверенного бэкапа
# Обновление всех клиентских конфигураций
```

### При обнаружении блокировки

1. **Диагностика:**
```bash
# Проверка доступности портов
nmap -p 51820,443,53,993 your-server.com

# Тест разных протоколов
curl -v --connect-timeout 5 your-server.com:443
```

2. **Смена стратегии:**
```bash
# Активация Cloak
CLOAK_ENABLED=true

# Смена портов
WG_PORT=4500  # IPSec порт
WG_PORT=1194  # OpenVPN порт

# Смена IP/домена сервера
```

## Юридические аспекты

### Соблюдение законодательства

- **Используйте VPN только в законных целях**
- **Соблюдайте местное законодательство**
- **Не используйте для нарушения авторских прав**
- **Ведите минимально необходимые логи**

### Защита персональных данных

```bash
# Минимизация логирования
LOG_LEVEL=warn  # Только ошибки и предупреждения

# Автоматическое удаление старых логов
find /var/log -name "*.log" -mtime +7 -delete

# Шифрование дисков
cryptsetup luksFormat /dev/sdX
```

### Политика отсутствия логов

```bash
# Отключение логирования соединений
ENABLE_LOGGING=false

# RAM диски для временных данных
mount -t tmpfs -o size=512M tmpfs /tmp/vpn-temp

# Автоматическая очистка при перезагрузке
```

## Рекомендации по развертыванию

### Выбор юрисдикции

**Рекомендуемые страны:**
- Швейцария, Исландия, Нидерланды
- Страны без соглашений о взаимной правовой помощи
- Провайдеры с политикой no-logs

**Избегайте:**
- 5/9/14 Eyes альянс
- Страны с обязательным хранением данных
- Юрисдикции с цензурой интернета

### Распределенная архитектура

```bash
# Несколько серверов в разных локациях
# Автоматическое переключение при блокировке
# Load balancing между серверами

# Пример для 3 серверов
SERVER1_ENDPOINT=server1.yourdomain.com
SERVER2_ENDPOINT=server2.yourdomain.com
SERVER3_ENDPOINT=server3.yourdomain.com
```

## Заключение

RouteRus VPN обеспечивает высокий уровень безопасности при правильной настройке. Ключевые принципы:

1. **Многоуровневая защита** - не полагайтесь только на один метод
2. **Регулярные обновления** - поддерживайте систему актуальной
3. **Мониторинг** - отслеживайте подозрительную активность
4. **Минимизация логов** - храните минимум данных
5. **Готовность к инцидентам** - имейте план реагирования

При соблюдении этих рекомендаций RouteRus VPN обеспечит максимальную безопасность и приватность вашего интернет-трафика.
