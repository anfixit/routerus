# routerus 🦆

> Автоматическое развёртывание ноды [Remnawave](https://remna.st) на Ubuntu 24.04

[![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04-orange?style=flat-square&logo=ubuntu)](https://ubuntu.com/)
[![Shell](https://img.shields.io/badge/Shell-Bash-green?style=flat-square&logo=gnu-bash)](https://www.gnu.org/software/bash/)
[![License](https://img.shields.io/badge/license-MIT-blue?style=flat-square)](LICENSE)

---

## Что это

Один скрипт — полностью готовая нода Remnawave. Интерактивный режим: скрипт сам спрашивает всё необходимое и объясняет где это взять.

## Предварительные требования

Этот скрипт разворачивает **ноду**. Перед запуском у тебя должна быть работающая **мастер-панель Remnawave** с выполненными базовыми настройками.

### Что должно быть готово в панели

**1. Мастер-панель Remnawave**

Устанавливается отдельно на выделенный VPS. Официальная документация: [remna.st/docs](https://remna.st/docs). После установки нужны рабочий URL панели и URL подписок.

**2. Happ Routing**

В панели: **Settings → Subscription settings → Happ Routing**

Настраивает клиентскую маршрутизацию — какие сайты идут напрямую, какие через VPN, что блокируется. Используй конфигуратор панели с этим JSON (геофайлы от [hydraponique](https://github.com/hydraponique/roscomvpn-geosite), проверено работает с Happ):

```json
{
  "Name": "AnfiVPN",
  "GlobalProxy": "true",
  "UseChunkFiles": "true",
  "RemoteDns": "8.8.8.8",
  "DomesticDns": "77.88.8.8",
  "RemoteDNSType": "DoH",
  "RemoteDNSDomain": "https://8.8.8.8/dns-query",
  "RemoteDNSIP": "8.8.8.8",
  "DomesticDNSType": "DoH",
  "DomesticDNSDomain": "https://77.88.8.8/dns-query",
  "DomesticDNSIP": "77.88.8.8",
  "Geoipurl": "https://cdn.jsdelivr.net/gh/hydraponique/roscomvpn-geoip@release/geoip.dat",
  "Geositeurl": "https://cdn.jsdelivr.net/gh/hydraponique/roscomvpn-geosite@release/geosite.dat",
  "DnsHosts": {
    "lkfl2.nalog.ru": "213.24.64.175",
    "lknpd.nalog.ru": "213.24.64.181"
  },
  "RouteOrder": "block-proxy-direct",
  "DirectSites": [
    "geosite:private",
    "geosite:category-ru",
    "geosite:microsoft",
    "geosite:apple",
    "geosite:google-play",
    "geosite:epicgames",
    "geosite:steam",
    "geosite:origin",
    "geosite:twitch",
    "geosite:pinterest"
  ],
  "DirectIp": [
    "geoip:private",
    "geoip:direct"
  ],
  "ProxySites": [
    "geosite:youtube",
    "geosite:telegram",
    "geosite:github",
    "geosite:twitch-ads"
  ],
  "ProxyIp": [],
  "BlockSites": [
    "geosite:category-ads",
    "geosite:win-spy",
    "geosite:torrent"
  ],
  "BlockIp": [],
  "DomainStrategy": "IPIfNonMatch",
  "FakeDNS": "false"
}
```

**3. Config Profile с блокировкой рекламы**

В панели: **Config Profiles → создай профиль**

Шаблон профиля (подставь свои `privateKey` и `serverNames` после генерации ключей на ноде):

```json
{
  "log": { "loglevel": "warning" },
  "dns": {
    "servers": [
      {
        "address": "https://94.140.14.14/dns-query",
        "domains": [],
        "skipFallback": false
      },
      "localhost"
    ]
  },
  "inbounds": [
    {
      "tag": "СТРАНА_название",
      "port": 8443,
      "protocol": "vless",
      "settings": { "clients": [], "decryption": "none" },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "tcpSettings": { "acceptProxyProtocol": true },
        "realitySettings": {
          "dest": "127.0.0.1:9443",
          "show": false,
          "xver": 0,
          "shortIds": ["", "a1", "bc23", "def456", "1234abcd", "ab1234567890", "abcd12345678abcd"],
          "privateKey": "ТВОЙ_ПРИВАТНЫЙ_КЛЮЧ",
          "serverNames": ["твой-sni-домен.duckdns.org"]
        }
      }
    }
  ],
  "outbounds": [
    {"tag": "DIRECT", "protocol": "freedom"},
    {"tag": "BLOCK",  "protocol": "blackhole"}
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "protocol": ["bittorrent"],
        "outboundTag": "DIRECT"
      },
      {
        "type": "field",
        "domain": [
          "geosite:category-ads-all",
          "geosite:win-spy",
          "domain:doubleclick.net",
          "domain:googlesyndication.com",
          "domain:googleadservices.com",
          "domain:google-analytics.com",
          "domain:analytics.yandex.ru",
          "domain:mc.yandex.ru",
          "domain:crashlytics.com",
          "domain:app-measurement.com",
          "domain:appcenter.ms"
        ],
        "outboundTag": "BLOCK"
      },
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "DIRECT"
      }
    ]
  }
}
```

> **Про DNS-блокировку рекламы:** секция `dns` с AdGuard (`94.140.14.14`) блокирует рекламные домены на уровне DNS-резолвинга для всего трафика клиента — включая российские сайты которые идут напрямую. Серверные правила `geosite:category-ads-all` дополнительно блокируют рекламу для трафика через ноду. Два уровня защиты.

> **Про торренты:** `bittorrent → DIRECT` на сервере означает что торрент-трафик не расходует трафик ноды — он уходит напрямую. Сайты торрент-трекеров блокируются клиентским Happ routing (`geosite:torrent`).

**4. Создать ноду в панели → получить SECRET KEY**

В панели: **Nodes → Add node**

1. Имя ноды — формат `СТРАНА_название`, например `DE_mynode`, `NL_amsterdam`
2. Порт: `2222`
3. Нажми **«Important information»** → скопируй **SECRET KEY** (строка `eyJ...`)

> **Config Profile создаётся позже** — скрипт сам сгенерирует Reality ключи (`privateKey` / `publicKey`) и выведет их на экран с паузой. В этот момент ты создаёшь Config Profile в панели, вставляешь ключи — и продолжаешь установку.

Теперь можно запускать скрипт на сервере.

---

## Запуск скрипта

```bash
bash <(wget -qO- https://raw.githubusercontent.com/anfixit/routerus/main/deploy-remnanode.sh)
```

Скрипт полностью интерактивен. Последовательно спросит:

```
SECRET KEY         : eyJ...    ← берёшь из панели (шаг 4 выше)
Connection domain  : mynode.duckdns.org
SNI domain         : mynode-sni.duckdns.org
Node port          : 2222
SSH port           : (Enter = оставить 22, или новый порт)
Master IP          : IP мастер-сервера (для Node Exporter)
```

Подтверждаешь параметры — скрипт делает всё остальное сам (~5-10 минут).

## Где взять бесплатные домены

Нужно два разных поддомена, оба направленных на IP нового сервера:

```
mynode.duckdns.org      → IP сервера   (connection domain)
mynode-sni.duckdns.org  → IP сервера   (SNI domain для Reality)
```

| Сервис | Лимит | Особенности |
|---|---|---|
| ⭐ [duckdns.org](https://www.duckdns.org) | 5 | Вход через GitHub/Google — рекомендую |
| [dynu.com](https://www.dynu.com) | Много | IPv6, поддержка своих доменов |
| [afraid.org](https://freedns.afraid.org) | 5 | 55 000+ доменных зон |
| [noip.com](https://www.noip.com) | 3 | Подтверждение раз в 30 дней |

## Что делает скрипт

| Фаза | Что устанавливается |
|---|---|
| Зависимости | apt update/upgrade, curl, wget, nginx, certbot |
| Docker | Установка через get.docker.com с compose plugin |
| SSH | Опциональная смена порта |
| SSL | Let's Encrypt через certbot standalone для обоих доменов |
| nginx | Stream SNI routing: `443 → 8443` (Xray) / `7443` (HTTPS) |
| **Генерация ключей** | **x25519 PrivateKey/PublicKey + пауза для создания Config Profile** |
| remnawave-node | Docker compose, `NET_ADMIN`, `ulimits 1048576` |
| geosite/geoip | runetfreedom, монтируются в контейнер, cron обновление в 03:00 |
| Node Exporter | Prometheus метрики, доступны только с IP мастера |
| Fake site | Случайный HTML-шаблон вместо заглушки nginx |
| UFW | Только 22/80/443 + порт ноды + Node Exporter с мастера |

## Архитектура nginx

```
Клиент → :443
           │
           ├─ SNI = sni-domain       → 127.0.0.1:8443  (Xray / Reality)
           └─ SNI = conn-domain      → 127.0.0.1:7443  (HTTPS + fake site)

Reality fallback                     → 127.0.0.1:9443
```

## После запуска скрипта

| Действие | Где |
|---|---|
| Убедиться что нода **Online** | Панель → Nodes |
| Включить **Host visibility** | Nodes → настройки ноды |
| Привязать **Config Profile** | Nodes → настройки ноды |

Если нода не Online:
```bash
docker compose -C /opt/remnanode logs -f
```

## Полезные команды

```bash
# Логи ноды
docker compose -C /opt/remnanode logs -f

# Перезапуск
docker compose -C /opt/remnanode restart

# Обновить geosite/geoip вручную (автоматически каждую ночь в 03:00)
/usr/local/bin/update-geo-dat.sh

# Лог автообновлений
cat /var/log/remnanode/geo-update.log
```

## Структура репозитория

```
routerus/
└── deploy-remnanode.sh   # Скрипт развёртывания ноды
```

## Credits

- [Remnawave](https://github.com/remnawave) — панель и нода
- [runetfreedom/russia-v2ray-rules-dat](https://github.com/runetfreedom/russia-v2ray-rules-dat) — geosite/geoip для нод
- [hydraponique/roscomvpn-geosite](https://github.com/hydraponique/roscomvpn-geosite) — geosite для Happ клиента
- [hydraponique/roscomvpn-routing](https://github.com/hydraponique/roscomvpn-routing) — Happ routing
- [lifeindarkside/Remnawave-Routing-update](https://github.com/lifeindarkside/Remnawave-Routing-update) — автообновление Happ routing в панели
- [mozaroc/x-ui-pro](https://github.com/mozaroc/x-ui-pro) — randomfakehtml.sh
- [Prometheus Node Exporter](https://github.com/prometheus/node_exporter)

## License

MIT
