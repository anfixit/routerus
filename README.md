<div align="center">

# routerus

**Автоматический деплой VPN-ноды на базе Remnawave + Xray-core за одну команду**

VLESS · Reality · steal_oneself · транспорт TCP/Vision или XHTTP на выбор

[![Shell](https://img.shields.io/badge/shell-bash-4EAA25?logo=gnubash&logoColor=white)](#)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04-E95420?logo=ubuntu&logoColor=white)](#требования)
[![Xray-core](https://img.shields.io/badge/Xray--core-25.3.6%2B-blue)](https://github.com/XTLS/Xray-core)
[![Remnawave](https://img.shields.io/badge/Remnawave-2.7.2%2B-6E56CF)](https://github.com/remnawave/panel)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

[Возможности](#возможности) · [Быстрый старт](#быстрый-старт) · [Как это работает](#как-это-работает) · [Настройка панели](#настройка-в-панели-remnawave) · [FAQ](#faq)

</div>

---

## О проекте

`routerus` — интерактивный bash-скрипт, который на чистой Ubuntu 24.04
разворачивает готовую к работе VPN-ноду для [Remnawave Panel](https://github.com/remnawave/panel):
хардит систему, поднимает [Xray-core](https://github.com/XTLS/Xray-core) с
VLESS + Reality, маскирует ноду под легитимный сайт и печатает готовый JSON для
вставки в панель. Одна нода — один домен.

Скрипт **идемпотентен**: повторный запуск не ломает уже настроенную ноду.

## Возможности

- **VLESS + Reality** — TLS-маскировка без собственного сертификата; DPI и
  пробберы видят легитимный TLS-хендшейк.
- **Транспорт на выбор** — `tcp` + `xtls-rprx-vision` (по умолчанию, полная
  совместимость с любым клиентом, включая podkop/Nikki на mihomo) или `xhttp`
  (маскировка под HTTP-запросы для обхода блокировки VLESS TCP).
- **steal_oneself** — Reality `dest` указывает на собственный nginx на том же
  сервере: SNI резолвится на наш IP → настоящий сайт → всё легитимно.
- **Фейковый сайт** — встроенный генератор случайных бизнес-лендингов, без
  внешних скачиваний и палёных шаблонов.
- **Хардинг из коробки** — SSH key-only на нестандартном порту, fail2ban,
  sysctl (BBR, TCP-буферы, SYN-flood protection), UFW, автообновления
  безопасности.
- **Безопасность секретов** — приватный ключ Reality не попадает в лог; лог с
  правами `600`; `.env` и `keys.txt` с правами `600`.
- **Эксплуатация** — watchdog контейнера, автообновление geo-списков
  (runetfreedom), ротация docker-логов, опциональный агент
  [Beszel](https://github.com/henrygd/beszel) для мониторинга.

## Требования

| Компонент     | Версия / условие                              |
|---------------|-----------------------------------------------|
| ОС            | чистая Ubuntu 24.04+ с выделенным IPv4        |
| Домен         | A-запись указывает на IP сервера              |
| Remnawave     | Panel 2.7.2+ (2.7.2+ для XHTTP)               |
| Xray-core     | 25.3.6+ (в Docker-образе `remnawave/node`)    |
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
**имя ноды**, **транспорт** (`tcp` по умолчанию — просто Enter).

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
Xray :443  (VLESS + Reality + TCP/Vision | XHTTP)
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
зависимости и Docker → хардинг SSH → fail2ban → sysctl → SSL (Let's Encrypt) →
nginx-fallback → фейковый сайт → генерация ключей и JSON → пауза на настройку
панели → geo-файлы → запуск `remnawave-node` → автообслуживание → watchdog →
UFW → Beszel → итоговая сводка.

### Открываемые порты

| Порт  | Назначение                    |
|-------|-------------------------------|
| 2810  | SSH (key-only)                |
| 443   | Xray Reality (VLESS)          |
| 80    | HTTP-редирект + certbot       |
| 8443  | nginx HTTPS-fallback          |
| 2222  | Remnawave node API            |
| 45876 | Beszel agent (опционально)    |

## Настройка в панели Remnawave

1. **Config Profiles → Create** — вставить JSON из вывода скрипта.
2. **Nodes → Create** — Address = IP сервера, Port `2222`, привязать профиль,
   скопировать `SECRET_KEY` обратно в скрипт.
3. **Hosts → Create** — Address и SNI = домен, Port `443`, Fingerprint `chrome`:
   - транспорт `tcp` → **Flow:** `xtls-rprx-vision`;
   - транспорт `xhttp` → **Flow** пустой, **ALPN:** `h2`.
4. **Internal Squads → Default-Squad** — добавить inbound ноды
   (без этого нода не попадёт в подписку).

## Клиент и селективная маршрутизация

TCP + Vision выбран по умолчанию именно ради маршрутизации на роутере: ядро
mihomo (podkop / Nikki) парсит ссылку подписки Remnawave с
`flow=xtls-rprx-vision` без доработок. Раскатка подписки на роутер и авто-выбор
быстрейшего сервера живут в отдельных инструментах (`podkop-sub`,
`fleet_deploy`) и в этот репозиторий не входят.

## Эксплуатация

| Задача                    | Где                                           |
|---------------------------|-----------------------------------------------|
| Ключи Reality             | `/opt/remnanode/keys.txt` (chmod 600)         |
| Лог установки             | `/var/log/deploy-remnanode.log` (chmod 600)   |
| Обновление geo            | cron `0 3 * * *` → `update-geo.sh`            |
| Перезапуск при падении    | cron `*/5` → `watchdog.sh`                     |
| Логи ноды                 | `docker logs remnawave-node`                   |

## Безопасность

- Приватный ключ Reality печатается только на терминал и никогда не пишется в
  лог-файл.
- Лог установки, `.env` и `keys.txt` создаются с правами `600`.
- SSH: только по ключу, root запрещён, нестандартный порт, fail2ban.
- Существующие `daemon.json` / `cli.ini` резервируются перед перезаписью.

Нашёл проблему безопасности? Не открывай публичный issue — напиши приватно
(см. [SECURITY.md](SECURITY.md), если добавишь его).

## FAQ

**Почему TCP по умолчанию, а не XHTTP?**
TCP + Vision совместим со всеми клиентами и стабилен; XHTTP полезен только когда
провайдер режет VLESS TCP на 443, и с частью клиентов (в т.ч. mihomo) менее
надёжен. Выбор остаётся за тобой при запуске.

**Можно ли запускать повторно?**
Да. Скрипт идемпотентен: пользователь, ключи, конфиги переиспользуются, geo и
контейнер обновляются.

**Нода не появилась в клиенте.**
Проверь шаг 4 в панели — inbound должен быть добавлен в Internal Squad, иначе он
не попадёт в подписку.

## Версии

| Версия | Изменения                                                        |
|--------|------------------------------------------------------------------|
| v3.5   | Аудит безопасности: лог `600`, ключи не в лог, hub-IP убран, `getent`, `backend=systemd`, бэкапы конфигов |
| v3.4   | Выбор транспорта tcp/xhttp; tcp использует flow Vision           |
| v3.1   | `NODE_PORT` в `.env`, geo до `docker up`, все `read` из `/dev/tty` |
| v3.0   | XHTTP + steal_oneself, один домен, Xray на 443                    |
| v2.0   | Полный хардинг, admin-user, fail2ban, sysctl                     |
| v1.0   | Первая версия                                                    |

## Благодарности

- [Remnawave](https://github.com/remnawave/panel) — панель управления
- [XTLS/Xray-core](https://github.com/XTLS/Xray-core) — ядро
- [chika0801/Xray-examples](https://github.com/chika0801/Xray-examples) — референсные конфиги
- [runetfreedom/russia-v2ray-rules-dat](https://github.com/runetfreedom/russia-v2ray-rules-dat) — geo-файлы
- [henrygd/beszel](https://github.com/henrygd/beszel) — мониторинг

## Лицензия

[MIT](LICENSE) © anfixit
