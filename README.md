# routerus

Deploy-скрипт для разворачивания VPN-нод на базе [Remnawave](https://github.com/remnawave) + VLESS Reality с полным hardening сервера.

## Что делает скрипт

Одной командой на чистом Ubuntu 24.04 поднимает готовую VPN-ноду:

**VPN:**
- remnawave-node (Docker) с VLESS + Reality
- nginx stream SNI routing (порт 443 → Xray / HTTPS / Reality fallback)
- SSL-сертификаты Let's Encrypt с автопродлением
- Geo-файлы (runetfreedom) для маршрутизации и блокировки рекламы
- Фейковый сайт для маскировки

**Безопасность:**
- Пользователь `admin` с sudo (root-логин отключён)
- SSH: нестандартный порт, только по ключу, пароли отключены
- fail2ban: защита SSH + nginx от брутфорса
- UFW: deny all, whitelist только нужных портов
- sysctl: BBR, SYN flood protection, TCP tuning, conntrack 262K
- Автоматические security-патчи (unattended-upgrades)

**Автоматизация:**
- Watchdog: проверка remnanode + nginx каждые 5 мин
- Geo-update: ежедневно в 03:00
- Docker prune: еженедельно
- Logrotate: ротация логов 4 недели
- Certbot auto-renew с nginx reload hook

## Быстрый старт

### Подготовка

1. Купить VPS (Ubuntu 24.04, минимум 1 CPU / 1 GB RAM)
2. Направить 2 домена на IP сервера (рекомендую [duckdns.org](https://www.duckdns.org)):
   - **Connection** — адрес подключения клиентов
   - **SNI** — домен для Reality маскировки
3. В панели Remnawave создать Config Profile и ноду → скопировать SECRET KEY
4. На своём компьютере подготовить SSH-ключ:
   ```bash
   # Проверить наличие ключа
   cat ~/.ssh/id_ed25519.pub
   
   # Если нет — сгенерировать
   ssh-keygen -t ed25519 -C "your@email.com"
   ```

### Установка

```bash
ssh root@IP_СЕРВЕРА
bash <(wget -qO- https://raw.githubusercontent.com/anfixit/routerus/main/deploy-remnanode.sh)
```

Скрипт интерактивно спросит: SECRET KEY, домены, SSH-ключ, порты.

### После установки

1. В панели Remnawave: Nodes → нода должна быть **Online**
2. Включить **Host visibility**
3. Обновить Config Profile (privateKey из вывода скрипта)
4. Подключение к серверу: `ssh admin@IP -p 2810`

## Архитектура ноды

```
Клиент → порт 443 → nginx stream (SNI routing)
  ├── SNI = connection-domain → Xray (8443) — VPN-трафик
  ├── SNI = sni-domain        → Reality fallback (9443) — фейковый сайт
  └── HTTPS-запрос            → nginx (7443) — фейковый сайт
```

DPI/провайдер видит обычный HTTPS к легитимному домену. Трафик неотличим от браузера.

## Маршрутизация и блокировка рекламы

Два уровня:

**Сервер** (Config Profile в Remnawave):
- Блокировка: `geosite:category-ads-all`, `geosite:win-spy`, явные рекламные домены
- DIRECT: торренты, приватные сети
- Блокировка: QUIC/HTTP3 (UDP 443), уязвимые UDP-порты

**Клиент** (Happ routing):
- Российские сайты (`geosite:category-ru`) → напрямую
- Реклама → блокировка
- Всё остальное → через VPN
- DNS: AdGuard 94.140.14.14 (блокирует рекламу для прямого трафика)

## Полезные команды

```bash
# Логи ноды
docker compose -C /opt/remnanode logs -f

# Перезапуск
docker compose -C /opt/remnanode restart

# Обновить geo-файлы вручную
sudo /usr/local/bin/update-geo-dat.sh

# Статус watchdog
cat /var/log/remnanode/watchdog.log

# fail2ban
sudo fail2ban-client status sshd

# Firewall
sudo ufw status
```

## Фазы скрипта

| # | Фаза | Описание |
|---|------|----------|
| 0 | Проверки | root, Ubuntu 24.04, определение IP |
| 1 | Параметры | SECRET KEY, домены, SSH-ключ, порты |
| 2 | Зависимости | nginx, certbot, fail2ban, jq и др. |
| 3 | Docker | Установка Docker + compose plugin |
| 4 | Admin user | Пользователь admin, sudo, SSH-ключ, docker-группа |
| 5 | SSH hardening | Порт 2810, key-only, root отключён |
| 6 | fail2ban | SSH + nginx brute-force protection |
| 7 | Kernel tuning | BBR, TCP buffers, SYN flood, conntrack |
| 8 | SSL | Let's Encrypt для обоих доменов |
| 9 | nginx | stream SNI routing (443 → 8443/7443/9443) |
| 10 | x25519 keygen | Генерация ключей Reality + пауза для панели |
| 11 | remnawave-node | docker-compose.yml + daemon.json |
| 12 | Geo-файлы | geosite.dat + geoip.dat + cron 03:00 |
| 13 | Node Exporter | Prometheus метрики (порт 9100) |
| 14 | Фейковый сайт | randomfakehtml для маскировки |
| 15 | Certbot timer | Автопродление SSL + nginx reload hook |
| 16 | Auto-updates | unattended-upgrades (security) |
| 17 | Watchdog | Проверка remnanode + nginx каждые 5 мин |
| 18 | Автоочистка | Docker prune + logrotate |
| 19 | UFW | Финальные правила файрвола |
| 20 | Итог | Сводка параметров и команд |

## Бесплатные DNS

| Сервис | Лимит | Особенности |
|--------|-------|-------------|
| [duckdns.org](https://www.duckdns.org) | 5 поддоменов | Вход через GitHub/Google (рекомендую) |
| [dynu.com](https://www.dynu.com) | ∞ | Поддержка IPv6, свои домены |
| [afraid.org](https://freedns.afraid.org) | 5 поддоменов | 55K+ доменных зон |
| [noip.com](https://www.noip.com) | 3 хоста | Подтверждение раз в 30 дней |

## Источники

- [Remnawave](https://github.com/remnawave) — панель и нода
- [runetfreedom/russia-v2ray-rules-dat](https://github.com/runetfreedom/russia-v2ray-rules-dat) — geo-файлы (сервер)
- [hydraponique](https://github.com/hydraponique/roscomvpn-geosite) — geo-файлы (Happ/клиент)
- [mozaroc/x-ui-pro](https://github.com/mozaroc/x-ui-pro) — randomfakehtml
- [Prometheus Node Exporter](https://github.com/prometheus/node_exporter)

## Лицензия

MIT
