# routerus

Скрипт для развёртывания и управления инфраструктурой VPN-сервиса на базе [Remnawave Panel](https://github.com/remnawave/panel) + [Xray-core](https://github.com/XTLS/Xray-core).

## Архитектура

```
Клиент (Happ / v2rayNG / Hiddify)
    │
    ▼
Xray:443 (VLESS + Reality + XHTTP)
    │
    ├── Reality-клиент → VPN-туннель → интернет
    │
    └── Не-Reality (DPI / проббер)
            │
            ▼
        nginx:8443 (настоящий сайт с SSL)
```

**Протокол:** VLESS + Reality + XHTTP (steal_oneself)

**Почему именно так:**

- **XHTTP** — трафик неотличим от обычных HTTP-запросов. После массовой блокировки VLESS TCP 17.02.2026, XHTTP остался рабочим
- **Reality** — TLS-маскировка без собственного сертификата. Пробберы и DPI видят легитимный TLS-хендшейк
- **steal_oneself** — маскируемся под свой же nginx на том же сервере. SNI резолвится на наш IP → настоящий сайт → всё легитимно. Рекомендация RPRX (разработчик Reality)
- **Один домен на ноду** — упрощает настройку, дешевле, безопаснее

## Содержимое репозитория

```
routerus/
├── deploy-remnanode.sh    ← Deploy script v3.0
└── README.md
```

### deploy-remnanode.sh v3.0

Полностью автоматизированный деплой VPN-ноды на чистом Ubuntu 24.04.

**Что делает (17 фаз):**

1. Проверяет ОС и интернет
2. Спрашивает домен, SSH-ключ, имя ноды
3. Ставит Docker, nginx, certbot, fail2ban
4. Создаёт пользователя `admin` с SSH-ключом
5. Хардит SSH (порт 2810, key-only, root запрещён)
6. Настраивает fail2ban, sysctl (BBR, TCP buffers)
7. Получает SSL-сертификат (Let's Encrypt)
8. Настраивает nginx как HTTPS fallback на порту 8443
9. Разворачивает фейковый сайт
10. Генерирует x25519 ключи и выводит готовый JSON для Config Profile
11. Ждёт пока ты создашь Config Profile и Node в панели Remnawave
12. Запускает remnawave-node (Docker, `network_mode: host`)
13. Скачивает geo-файлы (runetfreedom) + cron автообновления
14. Настраивает Docker log rotation и автообновления безопасности
15. Ставит watchdog (проверка контейнера каждые 5 минут)
16. Настраивает UFW
17. Опционально ставит Beszel agent
18. Выводит чеклист для завершения настройки в панели

**Требования:**

- Чистый Ubuntu 24.04 VPS с выделенным IP
- Домен с A-записью на IP сервера
- Remnawave Panel (v2.7.2+ для XHTTP)
- Xray-core v25.3.6+ (в Docker-образе remnawave/node)

## Быстрый старт

### 1. Купи домен

На [reg.ru](https://reg.ru) — `.ru` от 129₽/год. Настрой DNS A-запись на IP сервера.

### 2. Запусти скрипт

```bash
ssh root@IP_СЕРВЕРА
bash <(wget -qO- https://raw.githubusercontent.com/anfixit/routerus/main/deploy-remnanode.sh)
```

Скрипт спросит:
- Домен
- Публичный SSH-ключ (`cat ~/.ssh/id_ed25519.pub`)
- Имя ноды (например `DE_natty_narwhal`)

### 3. Настрой в панели Remnawave

Скрипт выведет готовый JSON и пошаговую инструкцию:

1. **Config Profiles → Create** — вставить JSON
2. **Nodes → Create** — указать IP и порт 2222, привязать профиль
3. Ввести SECRET_KEY в скрипт → контейнер запустится
4. **Hosts → Create** — Address и SNI = домен, Port = 443
5. **Internal Squads → Default-Squad** — добавить inbound

### 4. Проверь

```bash
# SSH доступ (из нового терминала!)
ssh -p 2810 admin@IP_СЕРВЕРА

# Нода в панели — зелёная?
# Happ — обнови подписку → пинг есть?
```

## Отличия от v2.2

| | v2.2 | v3.0 |
|---|------|------|
| Транспорт | TCP | XHTTP |
| Домены | 2 (connection + SNI) | 1 (steal_oneself) |
| Порт 443 | nginx stream → SNI routing | Xray напрямую |
| nginx | stream router + 3 порта | fallback на 8443 |
| proxy_protocol | nginx → Xray | Xray → nginx (xver: 1) |
| Docker | bridge + port mapping | `network_mode: host` |
| Beszel | ручной | интерактивно в скрипте |
| Панель | инструкции в голове | чеклист в терминале |

## История версий

| Версия | Дата | Изменения |
|--------|------|-----------|
| v3.0 | 2026-04-23 | XHTTP + steal_oneself, один домен, Xray на 443, Beszel в скрипте |
| v2.2 | 2026-04-07 | 7 багфиксов: SNI map, proxy_protocol, x25519, SSH Ubuntu 24.04 |
| v2.0 | 2026-04-05 | Полный hardening, admin user, fail2ban, sysctl |
| v1.6 | 2026-04-01 | UFW node port, crontab pipefail, wget timeout |
| v1.4 | 2026-03-31 | Новый flow с keygen до SECRET_KEY |
| v1.0 | 2026-03-27 | Первая версия |

## Мониторинг

[Beszel](https://github.com/henrygd/beszel) — hub на отдельном сервере. Агенты на всех нодах (порт 45876). Deploy v3.0 предлагает установку агента интерактивно.

## Ссылки

- [Remnawave Panel](https://github.com/remnawave/panel)
- [Xray-core](https://github.com/XTLS/Xray-core)
- [XHTTP документация](https://xtls.github.io/en/config/transport.html)
- [chika0801/Xray-examples](https://github.com/chika0801/Xray-examples) — референсные конфиги
- [runetfreedom/russia-v2ray-rules-dat](https://github.com/runetfreedom/russia-v2ray-rules-dat) — geo-файлы
