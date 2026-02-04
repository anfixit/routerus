# RouteRus

<div align="center">

![RouteRus](https://img.shields.io/badge/RouteRus-3X--UI%20Pro-blue?style=for-the-badge)
[![Version](https://img.shields.io/badge/version-1.0.0-green.svg?style=flat-square)](https://github.com/anfixit/routerus/releases)
[![License](https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square)](LICENSE)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04-orange.svg?style=flat-square&logo=ubuntu)](https://ubuntu.com/)

**Автоматическая установка 3X-UI Pro с продвинутой маршрутизацией и REALITY**

[🚀 Установка](#-установка) • [✨ Особенности](#-особенности) • [📖 Документация](#-документация) • [🤝 Благодарности](#-благодарности)

</div>

---

## 🎯 Что это?

RouteRus — полностью автоматизированный скрипт для развертывания 3X-UI панели с:
- ✅ VLESS + REALITY протокол (полная маскировка)
- ✅ Всё на порту 443 (панель + подключения)
- ✅ Блокировка рекламы и трекеров
- ✅ Split-routing для российских сайтов
- ✅ Автоматический SSL от Let's Encrypt
- ✅ Фикс Telegram бота (правильные VLESS ссылки)

## ✨ Особенности

### 🔒 Безопасность
- **REALITY маскировка** - VPN выглядит как обычный HTTPS
- **Фейковый сайт** - дополнительная маскировка
- **UFW firewall** - только 22, 80, 443 порты
- **Nginx reverse proxy** - защита панели
- **Случайные пути** - дополнительная безопасность

### ⚡ Умная маршрутизация

**Блокируется** (опционально):
- 🚫 Реклама: Google Analytics, Yandex Metrika, Facebook Pixel
- 🚫 QUIC/HTTP3: UDP 443 для не-российских IP
- 🚫 Уязвимые порты: UDP 135, 137, 138, 139

**Идёт напрямую** (без VPN, опционально):
- 🇷🇺 Российские домены: .ru, .su, .рф
- 🇷🇺 Российские сервисы: Яндекс, ВКонтакте, Steam, Сбербанк
- 🇷🇺 Российские IP (по GeoIP)
- 🌐 Локальные сети
- 📦 BitTorrent трафик

**Идёт через VPN**:
- 🌍 Всё остальное

## 🚀 Установка

### Требования
- Ubuntu 24.04 (свежая установка)
- Root доступ
- 2 домена (бесплатные с [DuckDNS](https://www.duckdns.org))

### Получение доменов

1. Регистрация на [DuckDNS.org](https://www.duckdns.org)
2. Создание 2 поддоменов:
   ```
   mypanel.duckdns.org    → IP вашего сервера
   myreality.duckdns.org  → IP вашего сервера
   ```
3. Ожидание 1-2 минуты (DNS)

### Установка одной командой

```bash
sudo su -c "bash <(wget -qO- https://raw.githubusercontent.com/anfixit/routerus/main/quick-install.sh)"
```

### Интерактивная установка

Скрипт задаст вопросы:
```
Enter panel subdomain: mypanel.duckdns.org
Enter REALITY subdomain: myreality.duckdns.org
Enable ad blocking? (y/n) [default: y]: y
Enable RU routing? (y/n) [default: y]: y
Block QUIC? (y/n) [default: y]: y
```

### Автоматическая установка

```bash
sudo su -c "bash <(wget -qO- https://raw.githubusercontent.com/anfixit/routerus/main/quick-install.sh) \
  -subdomain mypanel.duckdns.org \
  -reality_domain myreality.duckdns.org \
  -enable_adblock y \
  -enable_ru_routing y \
  -enable_quic_block y"
```

### После установки

Скрипт выдаст:
```
╔═══════════════════════════════════════════════════╗
║     RouteRus Installation Complete! 🚀            ║
╚═══════════════════════════════════════════════════╝

📋 PANEL ACCESS:
   URL:      https://mypanel.duckdns.org/xT8nQ4vLp9/
   Username: xT8nQ4vLp9
   Password: mK3rP6wN8z

🔐 DOMAINS:
   Panel:    mypanel.duckdns.org
   REALITY:  myreality.duckdns.org

⚙️  ROUTING:
   Ad blocking:   ✓ ENABLED
   RU routing:    ✓ ENABLED
   QUIC block:    ✓ ENABLED
```

**⚠️ СОХРАНИТЕ ЭТИ ДАННЫЕ!**

## 📖 Документация

### Создание REALITY inbound

В панели 3X-UI:

1. **Inbounds** → **Add Inbound**
2. **Настройки**:
   - Protocol: `vless`
   - Port: `8443` ⚠️ **ОБЯЗАТЕЛЬНО**
   - Transmission: `tcp`
   - Security: `reality`
3. **TCP Settings**:
   - ✅ Enable **Proxy Protocol**
4. **External Proxy**:
   - Domain: `mypanel.duckdns.org` (ваш panel domain)
   - Port: `443`
5. **REALITY Settings**:
   - Dest: `myreality.duckdns.org:9443` (ваш reality domain)
   - SNI: `myreality.duckdns.org`
   - Generate certificates
6. **Save**

### Telegram бот

1. **Settings** → **Telegram Bot**
2. Создать бота через [@BotFather](https://t.me/botfather)
3. Вставить Bot Token
4. Добавить Telegram ID (через [@userinfobot](https://t.me/userinfobot))
5. Save

✅ **Фикс уже применён!** Бот будет генерировать правильные ссылки с вашим доменом.

### Управление

```bash
x-ui              # Главное меню
x-ui start        # Запустить
x-ui stop         # Остановить
x-ui restart      # Перезапустить
x-ui status       # Статус
x-ui update       # Обновить
```

### Изменение SSH порта (рекомендуется)

```bash
nano /etc/ssh/sshd_config
# Изменить: Port 22 → Port 2222

ufw allow 2222/tcp
ufw reload
systemctl restart ssh

# Подключение:
ssh root@server -p 2222
```

## 🔧 Кастомизация роутинга

Конфигурация: `/etc/x-ui/routing/config.json`

```bash
nano /etc/x-ui/routing/config.json
systemctl restart x-ui
```

## 🐛 Troubleshooting

### Подключение не работает

```bash
systemctl status x-ui nginx
journalctl -u x-ui -f
tail -f /var/log/nginx/error.log
```

### Telegram бот неправильные ссылки

```bash
sqlite3 /etc/x-ui/x-ui.db "SELECT key, value FROM settings WHERE key LIKE '%Domain%';"
```

### REALITY не подключается

Чеклист:
- ✅ Port = `8443`
- ✅ Proxy Protocol включен
- ✅ External Proxy: domain + port 443
- ✅ Dest = `reality_domain:9443`
- ✅ SNI = reality domain
- ✅ Сертификаты сгенерированы

## 📚 Дополнительно

### VPN клиенты (VLESS + REALITY)
- 📱 [v2rayNG](https://github.com/2dust/v2rayNG) - Android
- 🍎 [FoXray](https://apps.apple.com/app/foxray/id6448898396) - iOS
- 💻 [v2rayN](https://github.com/2dust/v2rayN) - Windows
- 🍎 [V2Box](https://apps.apple.com/app/v2box-v2ray-client/id6446814690) - macOS
- 🐧 [Qv2ray](https://github.com/Qv2ray/Qv2ray) - Linux

### Полезные ссылки
- 🌐 [DuckDNS](https://www.duckdns.org) - бесплатные домены
- 🔐 [Let's Encrypt](https://letsencrypt.org/) - SSL сертификаты
- 📖 [3X-UI Docs](https://github.com/MHSanaei/3x-ui)
- 📖 [Xray Docs](https://xtls.github.io/)

## 🤝 Благодарности

RouteRus создан на основе работы замечательных людей:

<table>
<tr>
<td align="center" width="50%">

### [@crazy_day_admin](https://t.me/crazy_day_admin)

**Автор x-ui-pro**

Создал базовую автоматизацию:
- Nginx reverse proxy
- SSL автоматизация
- REALITY настройка
- Фейковый сайт
- Подписки

📚 [Telegram](https://t.me/crazy_day_admin)  
💬 [Чат](https://t.me/crazyops_chat)

</td>
<td align="center" width="50%">

### [@Corvus-Malus](https://github.com/Corvus-Malus)

**Автор роутинга**

Разработал систему маршрутизации:
- Блокировка рекламы
- Split-routing для РФ
- QUIC блокировка
- GeoIP/GeoSite правила
- BitTorrent оптимизация

📦 Файл `05_routing.json`

</td>
</tr>
</table>

### Используемые проекты

- [3X-UI by MHSanaei](https://github.com/MHSanaei/3x-ui) - Веб-панель
- [Xray-core by XTLS](https://github.com/XTLS/Xray-core) - VPN ядро
- [REALITY Protocol](https://github.com/XTLS/REALITY) - Обфускация
- [v2ray-rules-dat](https://github.com/Loyalsoldier/v2ray-rules-dat) - GeoIP/GeoSite

## 📄 Лицензия

MIT License. См. [LICENSE](LICENSE)

## ⚠️ Дисклеймер

Только для легального использования. Пользователи несут ответственность за соблюдение законов.

## 🆘 Поддержка

- 💬 [GitHub Discussions](https://github.com/anfixit/routerus/discussions)
- 🐛 [Issues](https://github.com/anfixit/routerus/issues)
- 📧 [Telegram: @crazy_day_admin](https://t.me/crazy_day_admin)

## 🚀 Roadmap

### Готово
- [x] Автоматическая установка
- [x] REALITY поддержка
- [x] Продвинутый роутинг
- [x] Блокировка рекламы
- [x] Фикс Telegram бота
- [x] SSL автоматизация
- [x] BBR оптимизация

### Планируется
- [ ] WebSocket inbound
- [ ] Cloudflare интеграция (non-REALITY)
- [ ] Web UI для роутинга
- [ ] Автобэкап
- [ ] Monitoring dashboard
- [ ] Multi-server
- [ ] Docker версия

---

<div align="center">

**⭐ Поставьте звезду, если проект полезен!**

[![GitHub stars](https://img.shields.io/github/stars/anfixit/routerus?style=social)](https://github.com/anfixit/routerus/stargazers)

**Сделано с ❤️ для свободного интернета**

</div>
