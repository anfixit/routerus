# routerus

> Автоматическое развёртывание ноды [Remnawave](https://remna.st) на Ubuntu 24.04

---

## Быстрый старт

```bash
bash <(wget -qO- https://raw.githubusercontent.com/anfixit/routerus/main/deploy-remnanode.sh)
```

## Требования

- Ubuntu 24.04, root-доступ
- Работающая панель Remnawave на отдельном VPS
- Два домена (бесплатно: [duckdns.org](https://www.duckdns.org))

## Flow скрипта v1.5

```
SSH на новый сервер
         ↓
Запуск скрипта → ввод доменов, имени профиля, портов
         ↓
Установка: пакеты → Docker → SSL → nginx
         ↓
Генерация x25519 ключей → вывод готового JSON для Config Profile
         ↓
  Профиль есть? → НЕТ → выводит JSON → пауза → создай в панели
                  ДА  → обнови privateKey → пауза
         ↓
Создай ноду в панели → скопируй SECRET_KEY → вставь в скрипт
         ↓
Geo-файлы → контейнер → cron → Node Exporter → fake site → UFW
         ↓
Нода Online → выполни чеклист в панели (5 шагов)
```

## Чеклист после деплоя (ВСЕ ШАГИ ОБЯЗАТЕЛЬНЫЕ)

| # | Где | Что сделать |
|---|-----|-------------|
| 1 | Nodes | Убедись что нода **Online** (зелёный) |
| 2 | Nodes → нода | Включи **Host visibility** |
| 3 | Hosts | Создай хост: инбаунд = имя профиля, адрес = connection domain, порт = 443, SNI = sni domain |
| 4 | **Internal Squads** → Default-Squad | **Добавь инбаунд новой ноды** ⚠️ без этого нода НЕ появится в подписках |
| 5 | Клиент (Happ/v2rayNG) | Обнови подписку вручную |

## Happ Routing (клиентская маршрутизация)

Панель → Settings → Subscription settings → Happ Routing

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
    "geosite:private", "geosite:category-ru", "geosite:microsoft",
    "geosite:apple", "geosite:google-play", "geosite:epicgames",
    "geosite:steam", "geosite:origin", "geosite:twitch", "geosite:pinterest"
  ],
  "DirectIp": ["geoip:private", "geoip:direct"],
  "ProxySites": ["geosite:youtube", "geosite:telegram", "geosite:github", "geosite:twitch-ads"],
  "ProxyIp": [],
  "BlockSites": [
    "geosite:category-ads", "geosite:win-spy", "geosite:torrent",
    "domain:google-analytics.com", "domain:googletagmanager.com",
    "domain:googletagservices.com", "domain:doubleclick.net",
    "domain:googlesyndication.com", "domain:googleadservices.com",
    "domain:scorecardresearch.com", "domain:quantserve.com",
    "domain:adnxs.com", "domain:moatads.com", "domain:firebase.io",
    "domain:crashlytics.com", "domain:app-measurement.com", "domain:appcenter.ms"
  ],
  "BlockIp": [],
  "DomainStrategy": "IPIfNonMatch",
  "FakeDNS": "false",
  "UseChunkFiles": "true"
}
```

## Блокировка рекламы — 3 уровня

| Уровень | Что | Для какого трафика |
|---------|-----|--------------------|
| Сервер (Config Profile) | category-ads-all + win-spy + 14 доменов | VPN-трафик |
| Клиент (Happ BlockSites) | category-ads + win-spy + 14 доменов | Весь трафик |
| DNS (AdGuard 94.140.14.14) | Рекламные домены | Прямой трафик (.ru, yandex, vk) |

## Архитектура nginx

```
Клиент → :443
           ├─ SNI = sni-domain    → :8443 (Xray Reality)
           └─ SNI = conn-domain   → :7443 (HTTPS)
Reality fallback                  → :9443 (fake site)
```

## Команды

```bash
docker logs remnanode --tail=20                    # логи
cd /opt/remnanode && docker compose restart         # перезапуск
/usr/local/bin/update-geo-dat.sh                   # обновить geo
cat /var/log/remnanode/geo-update.log              # лог обновлений
```

## Бесплатные домены

| Сервис | Лимит |
|--------|-------|
| ⭐ [duckdns.org](https://www.duckdns.org) | 5 поддоменов |
| [dynu.com](https://www.dynu.com) | ∞ |
| [afraid.org](https://freedns.afraid.org) | 5 |
| [noip.com](https://www.noip.com) | 3 (подтверждение раз/мес) |

## Credits

- [Remnawave](https://github.com/remnawave) — панель и нода
- [runetfreedom](https://github.com/runetfreedom/russia-v2ray-rules-dat) — geo-файлы на нодах
- [hydraponique](https://github.com/hydraponique/roscomvpn-geosite) — geo-файлы для Happ
- [mozaroc/x-ui-pro](https://github.com/mozaroc/x-ui-pro) — randomfakehtml
- [Prometheus Node Exporter](https://github.com/prometheus/node_exporter)
