<div align="center">

# routerus

**Автоматический деплой VPN-ноды на базе Remnawave + Xray-core за одну команду**

VLESS · Reality · steal_oneself · транспорт TCP/Vision, XHTTP или оба сразу

[![Shell](https://img.shields.io/badge/shell-bash-4EAA25?logo=gnubash&logoColor=white)](#)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04-E95420?logo=ubuntu&logoColor=white)](#требования)
[![Xray-core](https://img.shields.io/badge/Xray--core-26.6.27%2B-blue)](https://github.com/XTLS/Xray-core)
[![Remnawave](https://img.shields.io/badge/Remnawave-2.8.0%2B-6E56CF)](https://github.com/remnawave/panel)
[![ShellCheck](https://img.shields.io/badge/ShellCheck-passing-brightgreen?logo=gnu)](https://www.shellcheck.net/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

[Возможности](#возможности) · [Быстрый старт](#быстрый-старт) · [Как это работает](#как-это-работает) · [Настройка панели](#настройка-в-панели-remnawave) · [Обновление](#обновление-нод) · [FAQ](#faq)

</div>

---

## О проекте

`routerus` — интерактивный bash-скрипт, который на чистой Ubuntu 24.04
разворачивает готовую к работе VPN-ноду для [Remnawave Panel](https://github.com/remnawave/panel):
хардит систему, поднимает [Xray-core](https://github.com/XTLS/Xray-core) с
VLESS + Reality, маскирует ноду под легитимный сайт и печатает готовый JSON для
вставки в панель. Одна нода — один домен.

Скрипт **идемпотентен**: повторный запуск не ломает уже настроенную ноду, а на
живой ноде пропускает `apt upgrade`, чтобы не оборвать трафик.

## Возможности

- **VLESS + Reality** — TLS-маскировка без собственного сертификата; DPI и
  пробберы видят легитимный TLS-хендшейк.
- **Три режима транспорта** на выбор при запуске:
  - `tcp` (по умолчанию) — RAW + `xtls-rprx-vision`, полная совместимость с
    любым клиентом, включая podkop/Nikki на mihomo;
  - `xhttp` — `mode=packet-up`: дробит upload под API-запросы, устойчив к
    поведенческому DPI на мобильных сетях РФ;
  - `both` — оба inbound на одной ноде (`tcp:443` + `xhttp:<port>`) с общим
    `privateKey`; подписка отдаёт обе ссылки, podkop берёт tcp.
- **steal_oneself** — Reality `dest` указывает на собственный nginx на том же
  сервере: SNI резолвится на наш IP → настоящий сайт → всё легитимно.
- **Фейковый сайт** — генератор бизнес-лендинга, детерминированный от хэша
  домена (на ре-запуске не меняется — фингерпринт стабилен).
- **Хардинг из коробки** — SSH key-only на нестандартном порту с замаскированным
  `ssh.socket`, fail2ban, sysctl (BBR, TCP-буферы, SYN-flood protection), UFW,
  автообновления безопасности.
- **Безопасность секретов** — приватный ключ Reality не попадает в лог; лог,
  `.env` и `keys.txt` с правами `600`, фейк-сайт `644` (иначе nginx отдал бы 403).
- **Zero-downtime SSL** — выпуск и продление сертификата через webroot, nginx не
  гасится (fallback не проваливается при renewal).
- **Эксплуатация** — watchdog контейнера, автообновление geo-списков с
  валидацией целостности, ротация docker-логов, опциональный агент
  [Beszel](https://github.com/henrygd/beszel).

## Требования

| Компонент     | Версия / условие                              |
|---------------|-----------------------------------------------|
| ОС            | чистая Ubuntu 24.04+ с выделенным IPv4        |
| Домен         | A-запись указывает на IP сервера              |
| Remnawave     | Panel 2.8.0+                                   |
| Node / Xray   | Node 2.8.0+ (Xray-core 26.6.27 в образе)      |
| Права         | root на время установки                       |

## Быстрый старт

### 1. Домен

Купи домен (`.ru` от 129 ₽/год) и настрой DNS A-запись на IP сервера.

### 2. Запуск

```bash
ssh root@IP_СЕРВЕРА
bash <(wget -qO- https://raw.githubusercontent.com/anfixit/routerus/main/deploy-remnanode.sh)
```

Скрипт спросит: **домен**, **публичный SSH-ключ** (`cat ~/.ssh/id_ed25519.pub`),
**имя ноды**, **транспорт** (`tcp` по умолчанию — просто Enter; для `both` —
дополнительно порт xhttp).

Опциональные переменные окружения:

```bash
# пин образа для генерации ключей (по умолчанию :latest)
XRAY_KEYGEN_IMAGE=ghcr.io/xtls/xray-core:26.6.27 bash deploy.sh
# email для Let's Encrypt (по умолчанию регистрация без email)
CERTBOT_EMAIL=you@example.com bash deploy.sh
```

### 3. Настройка в панели

Скрипт печатает готовый JSON и пошаговый чек-лист (см.
[ниже](#настройка-в-панели-remnawave)). После ввода `SECRET_KEY` из панели
контейнер поднимается автоматически.

### 4. Проверка

```bash
ssh -p 2810 admin@IP_СЕРВЕРА     # из НОВОГО терминала — доступ жив?
# нода в панели зелёная? клиент → обнови подписку → пинг есть?
```

## Как это работает

```
Клиент (Happ / v2rayNG / podkop-Nikki на mihomo)
    │
    ▼
Xray :443  (VLESS + Reality + TCP/Vision | XHTTP)   [+ xhttp:<port> в режиме both]
    │
    ├── Reality-клиент ──────────► VPN-туннель ──► интернет
    │
    └── Не-Reality (DPI / проббер)
            │
            ▼
        nginx :8443  (настоящий сайт с SSL)  ← steal_oneself
```

Reality проверяет клиента по x25519-ключу и shortId. Легитимный трафик уходит в
туннель; всё остальное (DPI-зонды, случайные боты) Reality прозрачно
проксирует на локальный nginx с настоящим сайтом — сервер выглядит как обычный
веб-хостинг.

### Фазы установки

Скрипт выполняет 18 фаз (0–17): проверки окружения → ввод параметров →
зависимости и Docker → хардинг SSH → fail2ban → sysctl → nginx :80 + SSL
(webroot) → nginx-fallback :8443 → фейковый сайт → генерация ключей и JSON →
пауза на настройку панели → geo-файлы → запуск `remnawave-node` →
автообслуживание → watchdog → UFW → Beszel → итоговая сводка.

### Открываемые порты

| Порт    | Назначение                             |
|---------|----------------------------------------|
| 2810    | SSH (key-only)                         |
| 443     | Xray Reality (VLESS tcp/xhttp)         |
| `<port>`| Xray Reality XHTTP (только режим both) |
| 80      | HTTP-редирект + ACME challenge          |
| 8443    | nginx HTTPS-fallback                    |
| 2222    | Remnawave node API                     |
| 45876   | Beszel agent (опционально)             |

## Настройка в панели Remnawave

> Актуально для Panel 2.8.0. Учти изменения хостов в этой версии: единый `tag`
> заменён на массив `tags[]`; `allowInsecure` убран; фиксированные значения
> `fingerprint` больше не enum — это свободная строка (`chrome` по-прежнему
> валиден); ALPN поддерживает `h2`, `h3` и комбинации.

1. **Config Profiles → Create** — вставить JSON из вывода скрипта.
2. **Nodes → Create** — Address = IP сервера, Port `2222`, привязать профиль,
   включить все inbound, скопировать `SECRET_KEY` обратно в скрипт.
3. **Hosts → Create** — Address и SNI = домен, Fingerprint `chrome`:
   - **Flow задавать не нужно** — для VLESS + Reality + TCP панель добавляет
     `xtls-rprx-vision` автоматически;
   - `tcp`-хост: Port `443`, ALPN не задавать;
   - `xhttp`-хост: Port `443` (или `<port>` в режиме `both`), ALPN `h2`;
   - в режиме `both` создать **два** хоста — по одному на каждый inbound.
4. **Internal Squads → Default-Squad** — добавить все inbound ноды
   (без этого нода не попадёт в подписку).

> Проверь готовую ссылку подписки: для tcp-инбаунда в ней должно быть
> `&flow=xtls-rprx-vision`. Если flow не появился — в Config Profile поменяй
> `"network": "tcp"` на `"network": "raw"` (в Xray 26.x это одно и то же).

## Клиент и селективная маршрутизация

TCP + Vision выбран по умолчанию ради маршрутизации на роутере: ядро mihomo
(podkop / Nikki) парсит ссылку подписки Remnawave с `flow=xtls-rprx-vision`
без доработок.

> **Начиная с Panel/Node 2.8.0** Remnawave умеет генерировать XHTTP- и
> Hysteria2-подписки и для клиентов на ядре **Mihomo** (полный набор xmux,
> download-settings и padding). Если твоя сборка podkop собрана со свежим
> mihomo — XHTTP на роутере становится реально применим; проверяй на своей
> прошивке перед раскаткой на флот.

В режиме `both` подписка содержит и tcp-, и xhttp-ссылку — приложения (Happ)
видят обе, а роутер берёт tcp. Раскатка подписки на роутер и авто-выбор
быстрейшего сервера живут в отдельных инструментах (`podkop-sub`, `fleet_deploy`)
и в этот репозиторий не входят.

## Обновление нод

Ядро Xray живёт **внутри** docker-образа `remnawave/node`, а Reality-конфиг
хранится в панели, не на ноде. Поэтому при выходе новой версии ядра
(например, Node 2.8.0 → Xray-core 26.6.27) **полная пересборка не нужна** —
достаточно подтянуть свежий образ. Хардинг, geo, nginx и SSH не затрагиваются.

На каждой существующей ноде:

```bash
sudo bash <(wget -qO- https://raw.githubusercontent.com/anfixit/routerus/main/update-node.sh)
```

`update-node.sh` идемпотентен и неинтерактивен: держит `ssh.socket`
замаскированным (защита от воскрешения после `apt upgrade`), обновляет geo с
валидацией целостности, тянет свежий образ, пересоздаёт контейнер и проверяет,
что **реальный inbound-порт 443** слушает (панель мониторит только API-порт
2222 — нода может быть «зелёной» при мёртвом VPN-инбаунде).

## Эксплуатация

| Задача                    | Где                                           |
|---------------------------|-----------------------------------------------|
| Ключи Reality             | `/opt/remnanode/keys.txt` (chmod 600)         |
| Лог установки             | `/var/log/deploy-remnanode.log` (chmod 600)   |
| Обновление geo            | cron `0 3 * * *` → `update-geo.sh` (с валидацией) |
| Перезапуск при падении    | cron `*/5` → `watchdog.sh`                     |
| Обновление ядра/образа    | `update-node.sh`                               |
| Логи ноды                 | `docker logs remnawave-node`                   |

## Безопасность

- Приватный ключ Reality печатается только на терминал и никогда не пишется в
  лог-файл.
- Лог установки, `.env` и `keys.txt` создаются с правами `600`; фейк-сайт —
  `644` (иначе nginx-воркер отдаёт 403 и ломает маскировку).
- SSH: только по ключу, root запрещён, нестандартный порт, `ssh.socket`
  замаскирован, `sshd -t` перед рестартом (защита от локаута), fail2ban.
- SSL выпускается и продлевается через webroot без остановки nginx.
- Существующие `daemon.json` / `cli.ini` / `sshd_config` резервируются перед
  перезаписью.

Нашёл проблему безопасности? Не открывай публичный issue — см.
[SECURITY.md](SECURITY.md).

## FAQ

**Почему TCP по умолчанию, а не XHTTP?**
TCP + Vision совместим со всеми клиентами и стабилен. XHTTP (`packet-up`)
устойчивее к поведенческому DPI на мобильных сетях, но с частью клиентов на
mihomo исторически менее надёжен — хотя в Panel 2.8.0 поддержка Mihomo+XHTTP
уже появилась. Выбор остаётся за тобой при запуске.

**Зачем режим `both`?**
Одна нода отдаёт и tcp (для podkop/флота), и xhttp (для клиентов за жёстким
DPI) одновременно, с общим ключом.

**Не нашёл поле Flow в панели.**
Его там и нет. Remnawave добавляет `flow: xtls-rprx-vision` автоматически для
VLESS + Reality + TCP. Проверить можно в готовой ссылке подписки.

**Обновилось ядро — надо пересобирать ноды?**
Нет. Ядро внутри docker-образа; запусти `update-node.sh` — он подтянет новый
образ без повторного деплоя. Reality-конфиг и хардинг не тронутся.

**Можно ли запускать deploy повторно?**
Да, скрипт идемпотентен: пользователь, ключи, конфиги переиспользуются, `apt
upgrade` на живой ноде пропускается, geo и контейнер обновляются.

**Нода не появилась в клиенте.**
Проверь шаг 4 в панели — inbound должен быть добавлен в Internal Squad, иначе он
не попадёт в подписку.

## Версии

| Версия | Изменения                                                        |
|--------|------------------------------------------------------------------|
| v3.7   | Аудит: chmod фейк-сайта (фикс 403), `mask ssh.socket` (фикс падений SSH), zero-downtime SSL (webroot), валидация geo перед подменой, санитизация имени/портов, `apt upgrade` только при первичной установке, парсинг ключей под Xray 26.x, XHTTP `packet-up`. Новый `update-node.sh` |
| v3.6   | Режим транспорта `both` (tcp+xhttp на одной ноде), авто-открытие xhttp-порта в UFW |
| v3.5   | Аудит безопасности: лог `600`, ключи не в лог, hub-IP убран, `getent`, `backend=systemd`, бэкапы конфигов |
| v3.4   | Выбор транспорта tcp/xhttp; tcp использует flow Vision           |
| v3.1   | `NODE_PORT` в `.env`, geo до `docker up`, все `read` из `/dev/tty` |
| v3.0   | XHTTP + steal_oneself, один домен, Xray на 443                    |
| v2.0   | Полный хардинг, admin-user, fail2ban, sysctl                     |
| v1.0   | Первая версия                                                    |

## Вклад

PR и issue приветствуются. Перед отправкой:

- прогони [ShellCheck](https://www.shellcheck.net/): `shellcheck deploy-remnanode.sh update-node.sh` — должно быть без замечаний;
- проверь синтаксис: `bash -n deploy-remnanode.sh`;
- сохраняй идемпотентность и не пиши секреты в лог;
- держи стиль: фазовые функции, хелперы `ok/info/warn/die`, `set -euo pipefail`.

## Лицензия

[MIT](LICENSE) © anfixit

## Благодарности

- [Remnawave](https://github.com/remnawave/panel) — панель управления
- [XTLS/Xray-core](https://github.com/XTLS/Xray-core) — ядро
- [chika0801/Xray-examples](https://github.com/chika0801/Xray-examples) — референсные конфиги
- [runetfreedom/russia-v2ray-rules-dat](https://github.com/runetfreedom/russia-v2ray-rules-dat) — geo-файлы
- [henrygd/beszel](https://github.com/henrygd/beszel) — мониторинг
