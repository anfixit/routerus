# routerus

> Автоматическое развёртывание ноды [Remnawave](https://remna.st) на Ubuntu 24.04

[![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04-orange?style=flat-square&logo=ubuntu)](https://ubuntu.com/)
[![Shell](https://img.shields.io/badge/Shell-Bash-green?style=flat-square&logo=gnu-bash)](https://www.gnu.org/software/bash/)
[![License](https://img.shields.io/badge/license-MIT-blue?style=flat-square)](LICENSE)

---

## Что это

Один скрипт — полностью готовая нода Remnawave. Интерактивный режим: скрипт сам генерирует ключи, выводит готовый JSON для Config Profile и объясняет каждый шаг.

## Быстрый старт

```bash
bash <(wget -qO- https://raw.githubusercontent.com/anfixit/routerus/main/deploy-remnanode.sh)
```

## Предварительные требования

Скрипт разворачивает **ноду**. Перед запуском нужна работающая **мастер-панель Remnawave** ([remna.st/docs](https://remna.st/docs)).

### Happ Routing (клиентская маршрутизация)

В панели: **Settings → Subscription settings → Happ Routing**

Определяет какие сайты идут напрямую (мимо VPN), какие через VPN, что блокируется. Российские сайты идут мимо VPN → видят российский IP → работают банки, госуслуги и т.д.

```json
{
  "Name": "AnfiVPN",
  "GlobalProxy": "true",
  "RouteOrder": "block-proxy-direct",
  "RemoteDNSType": "DoH",
  "RemoteDNSDomain": "https://8.8.8.8/dns-query",
  "RemoteDNSIP": "8.8.8.8",
  "DomesticDNSType": "DoH",
  "DomesticDNSDomain": "https://94.140.14.14/dns-query",
  "DomesticDNSIP": "94.140.14.14",
  "Geoipurl": "https://cdn.jsdelivr.net/gh/hydraponique/roscomvpn-geoip@release/geoip.dat",
  "Geositeurl": "https://cdn.jsdelivr.net/gh/hydraponique/roscomvpn-geosite@release/geosite.dat",
  "LastUpdated": "1774450000",
  "DnsHosts": {
    "lkfl2.nalog.ru": "213.24.64.175",
    "lknpd.nalog.ru": "213.24.64.181"
  },
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
    "geosite:torrent",
    "domain:google-analytics.com",
    "domain:googletagmanager.com",
    "domain:googletagservices.com",
    "domain:doubleclick.net",
    "domain:googlesyndication.com",
    "domain:googleadservices.com",
    "domain:scorecardresearch.com",
    "domain:quantserve.com",
    "domain:adnxs.com",
    "domain:moatads.com",
    "domain:firebase.io",
    "domain:crashlytics.com",
    "domain:app-measurement.com",
    "domain:appcenter.ms"
  ],
  "BlockIp": [],
  "DomainStrategy": "IPIfNonMatch",
  "FakeDNS": "false",
  "UseChunkFiles": "true"
}
```

> **DomesticDNS** использует AdGuard (94.140.14.14) — блокирует рекламу для российского трафика, идущего мимо VPN. BlockSites дублирует серверные правила для надёжности.

## Flow скрипта v1.4

```
Подключилась к серверу по SSH
         ↓
Запустила скрипт
         ↓
Ввела домены + имя профиля + порты
         ↓
Скрипт ставит пакеты + Docker + SSL + nginx
         ↓
Скрипт генерирует x25519 ключи
         ↓
  ┌─ Профиль уже есть?
  │   НЕТ → выводит готовый JSON → пауза → создай профиль в панели
  │   ДА  → говорит обновить privateKey → пауза
  └─→
         ↓
Создай ноду в панели → скопируй SECRET_KEY → вставь в скрипт
         ↓
Скрипт скачивает geo-файлы → запускает контейнер
         ↓
Node Exporter + fake site + UFW
         ↓
Нода Online ✓
```

## Фазы скрипта

| # | Фаза | Что делает |
|---|------|-----------|
| 0 | Проверки | root, Ubuntu 24.04, определение IP |
| 1 | Ввод | Домены, имя профиля, порты |
| 2 | Зависимости | apt, nginx-full, certbot, jq |
| 3 | Docker | get.docker.com + compose plugin |
| 4 | SSH | Смена порта (опционально) |
| 5 | SSL | Let's Encrypt для обоих доменов |
| 6 | nginx | Stream SNI routing (443 → 8443/7443/9443) |
| 7 | **Ключи** | **x25519 генерация + готовый JSON + пауза** |
| 8 | **SECRET_KEY** | **Создание ноды в панели + ввод ключа** |
| 9 | Geo-файлы | runetfreedom geosite.dat + geoip.dat |
| 10 | Нода | Docker compose up |
| 11 | Cron | Автообновление geo в 03:00 |
| 12 | Monitoring | Node Exporter v1.9.1 |
| 13 | Fake site | randomfakehtml или fallback |
| 14 | UFW | SSH, 80, 443, 9100 (master only) |
| 15 | Итог | Сводка параметров |

## Блокировка рекламы — 3 уровня

| Уровень | Что блокирует | Для какого трафика |
|---------|--------------|-------------------|
| **Сервер** (Config Profile) | category-ads-all + win-spy + 14 доменов | VPN-трафик (YouTube, Google, ...) |
| **Клиент** (Happ BlockSites) | category-ads + win-spy + 14 доменов | Весь трафик |
| **DNS** (AdGuard 94.140.14.14) | Рекламные домены на уровне резолвинга | Прямой трафик (.ru, yandex, vk, ...) |

## Архитектура nginx

```
Клиент → :443
           │
           ├─ SNI = sni-domain       → 127.0.0.1:8443  (Xray Reality)
           └─ SNI = conn-domain      → 127.0.0.1:7443  (HTTPS)

Reality fallback                     → 127.0.0.1:9443  (fake site)
```

## После скрипта

1. Панель → Nodes → нода **Online**?
2. Включи **Host visibility**
3. Профиль привязан к ноде?

## Бесплатные домены

| Сервис | Лимит | Особенности |
|--------|-------|-------------|
| ⭐ [duckdns.org](https://www.duckdns.org) | 5 | Вход через GitHub/Google |
| [dynu.com](https://www.dynu.com) | ∞ | IPv6 |
| [afraid.org](https://freedns.afraid.org) | 5 | 55k+ зон |
| [noip.com](https://www.noip.com) | 3 | Подтверждение раз/мес |

## Полезные команды

```bash
docker compose -C /opt/remnanode logs -f       # логи
docker compose -C /opt/remnanode restart       # перезапуск
/usr/local/bin/update-geo-dat.sh               # обновить geo
cat /var/log/remnanode/geo-update.log          # лог обновлений
```

## Credits

- [Remnawave](https://github.com/remnawave)
- [runetfreedom/russia-v2ray-rules-dat](https://github.com/runetfreedom/russia-v2ray-rules-dat) — geo-файлы на нодах
- [hydraponique](https://github.com/hydraponique/roscomvpn-geosite) — geo-файлы для Happ
- [mozaroc/x-ui-pro](https://github.com/mozaroc/x-ui-pro) — randomfakehtml
- [Prometheus Node Exporter](https://github.com/prometheus/node_exporter)

## License

MIT
