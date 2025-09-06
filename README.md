# RouteRus VPN - Maximum Obfuscation Setup

<div align="center">

![RouteRus VPN Logo](https://img.shields.io/badge/RouteRus-VPN-blue?style=for-the-badge&logo=wireguard&logoColor=white)

**Полнофункциональное решение для развертывания WireGuard VPN с максимальной обфускацией трафика**

[![Version](https://img.shields.io/badge/version-1.0.0-green.svg?style=flat-square)](https://github.com/yourusername/routerus-vpn/releases)
[![Docker](https://img.shields.io/badge/docker-ready-blue.svg?style=flat-square&logo=docker)](https://www.docker.com/)
[![License](https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square)](LICENSE)
[![Documentation](https://img.shields.io/badge/docs-available-brightgreen.svg?style=flat-square)](docs/)

[![WireGuard](https://img.shields.io/badge/WireGuard-Core-orange.svg?style=flat-square&logo=wireguard)](https://www.wireguard.com/)
[![AmneziaWG](https://img.shields.io/badge/AmneziaWG-Obfuscation-red.svg?style=flat-square)](https://amnezia.org/)
[![AdGuard DNS](https://img.shields.io/badge/AdGuard-DNS-green.svg?style=flat-square)](https://adguard-dns.io/)
[![Cloak](https://img.shields.io/badge/Cloak-Steganography-purple.svg?style=flat-square)](https://github.com/cbeuw/Cloak)

[🚀 Быстрый старт](#-быстрый-старт) • [📖 Документация](docs/) • [🔧 Конфигурация](#-конфигурация) • [🤝 Поддержка](#-поддержка)

</div>

---

## 🌟 Особенности

<table>
<tr>
<td width="50%">

### 🔒 Максимальная безопасность
- **AmneziaWG обфускация** - VPN трафик неразличим от обычного
- **Cloak стеганография** - дополнительная маскировка
- **Множественные порты** - 443, 53, 993 для обхода блокировок
- **AdGuard DNS** - блокировка рекламы и трекеров

</td>
<td width="50%">

### ⚡ Простота использования
- **Docker развертывание** - одна команда `make install`
- **Веб-интерфейс** - wg-easy для управления клиентами
- **Автогенерация конфигов** - mobile, router, desktop
- **Интерактивная настройка** - все параметры через меню

</td>
</tr>
</table>

## 🎯 Поддерживаемые платформы

<div align="center">

| Платформа | Клиент | Статус | Примечания |
|-----------|---------|--------|------------|
| 📱 **Android/iOS** | AmneziaVPN | ✅ Полная поддержка | Обфускация + QR коды |
| 💻 **Windows/macOS/Linux** | AmneziaVPN | ✅ Полная поддержка | Максимальная производительность |
| 🏠 **Роутеры** | Встроенный WireGuard | ✅ Базовая поддержка | Keenetic, OpenWrt, ASUS, MikroTik |
| 🌐 **Веб-панель** | Любой браузер | ✅ Полная поддержка | Управление и мониторинг |

</div>

## 🛠️ Технологический стек

<div align="center">

### Основные технологии
![Docker](https://img.shields.io/badge/Docker-2496ED?style=for-the-badge&logo=docker&logoColor=white)
![WireGuard](https://img.shields.io/badge/WireGuard-88171A?style=for-the-badge&logo=wireguard&logoColor=white)
![Node.js](https://img.shields.io/badge/Node.js-339933?style=for-the-badge&logo=node.js&logoColor=white)
![Alpine Linux](https://img.shields.io/badge/Alpine_Linux-0D597F?style=for-the-badge&logo=alpine-linux&logoColor=white)

### Обфускация и безопасность
![AmneziaWG](https://img.shields.io/badge/AmneziaWG-FF6B6B?style=for-the-badge&logo=shield&logoColor=white)
![Cloak](https://img.shields.io/badge/Cloak-9B59B6?style=for-the-badge&logo=mask&logoColor=white)
![AdGuard](https://img.shields.io/badge/AdGuard_DNS-68BC71?style=for-the-badge&logo=adguard&logoColor=white)
![iptables](https://img.shields.io/badge/iptables-E74C3C?style=for-the-badge&logo=linux&logoColor=white)

</div>

## 🚀 Быстрый старт

### Автоматическое развертывание одной командой

```bash
# Клонирование репозитория
git clone https://github.com/yourusername/routerus-vpn.git
cd routerus-vpn

# Интерактивная установка с автоматической настройкой
make install

# Или поэтапно:
make setup    # Интерактивная настройка .env
make start    # Запуск всех сервисов
```

### Что происходит при установке?

1. **🔧 Автонастройка системы** - проверка Docker, установка зависимостей
2. **🌐 Определение внешнего IP** - автоматическое определение или ввод домена
3. **🔐 Генерация паролей** - безопасные пароли или ваши собственные
4. **🛡️ Настройка AdGuard DNS** - персональные серверы или публичные
5. **🎭 Параметры обфускации** - автогенерация или ручная настройка
6. **🚀 Запуск сервисов** - Docker Compose разворачивает всю инфраструктуру

## 📱 Клиентские приложения

### Для максимальной обфускации (рекомендуется)

<div align="center">

[![AmneziaVPN](https://img.shields.io/badge/Download-AmneziaVPN-FF6B6B?style=for-the-badge&logo=download&logoColor=white)](https://amnezia.org/)

**AmneziaVPN поддерживает все параметры обфускации RouteRus VPN**

</div>

| Платформа | Ссылка | Особенности |
|-----------|--------|-------------|
| 🍎 **iOS** | [App Store](https://apps.apple.com/app/amneziavpn/id1600480750) | Полная обфускация, быстрое подключение |
| 🤖 **Android** | [Google Play](https://play.google.com/store/apps/details?id=org.amnezia.vpn) | QR-коды, автоматическая настройка |
| 🪟 **Windows** | [GitHub Releases](https://github.com/amnezia-vpn/amnezia-client/releases) | Максимальная производительность |
| 🍎 **macOS** | [GitHub Releases](https://github.com/amnezia-vpn/amnezia-client/releases) | Нативная интеграция |
| 🐧 **Linux** | [GitHub Releases](https://github.com/amnezia-vpn/amnezia-client/releases) | AppImage, deb, rpm пакеты |

### Стандартные WireGuard клиенты

⚠️ **Внимание**: Стандартные клиенты НЕ поддерживают обфускацию, но работают для базового VPN

## 🏠 Настройка роутеров

RouteRus VPN поддерживает роутеры через стандартный WireGuard без обфускации:

<div align="center">

| Роутер | Поддержка | Инструкция |
|--------|-----------|------------|
| 🔶 **Keenetic** | ✅ Встроенная | [Настройка Keenetic](docs/ROUTER_SETUP.md#keenetic) |
| 🔷 **OpenWrt** | ✅ Встроенная | [Настройка OpenWrt](docs/ROUTER_SETUP.md#openwrt) |
| 🔸 **ASUS** | ✅ Через Merlin | [Настройка ASUS](docs/ROUTER_SETUP.md#asus) |
| 🟠 **MikroTik** | ✅ RouterOS v7+ | [Настройка MikroTik](docs/ROUTER_SETUP.md#mikrotik) |

</div>

```bash
# Создание конфигурации для роутера
make generate-router

# Следуйте инструкциям в выводе скрипта
```

## 🔧 Конфигурация

### Основные настройки

RouteRus VPN настраивается через файл `.env`:

```bash
# Скопируйте пример и отредактируйте
cp .env.example .env
nano .env
```

<details>
<summary>📋 Основные параметры конфигурации</summary>

```bash
# Сервер
SERVER_ENDPOINT=your-server.com
WG_EASY_PASSWORD=your-secure-password
WEB_PORT=51821

# AdGuard DNS (персональные или публичные)
ADGUARD_DNS_IP1=94.140.14.14
ADGUARD_DNS_IP2=94.140.15.15
ADGUARD_DNS_HTTPS=https://dns.adguard-dns.com/dns-query

# Обфускация AmneziaWG
JC=5                    # Количество мусорных пакетов
JMIN=100               # Минимальный размер
JMAX=1000              # Максимальный размер
S1=86                  # Magic header 1
S2=92                  # Magic header 2

# Cloak (дополнительная обфускация)
CLOAK_ENABLED=true
```

</details>

## 📊 Мониторинг и управление

### Веб-интерфейсы

- **🎛️ Панель управления**: `http://your-server:51821`
- **📈 Статистика**: `http://your-server:8080`

### Команды управления

```bash
make status     # Проверить статус всех сервисов
make logs       # Просмотр логов
make monitor    # Мониторинг в реальном времени
make restart    # Перезапуск сервисов
make backup     # Создать бэкап конфигураций
make help       # Все доступные команды
```

## 🔒 Безопасность

### Уровни защиты

1. **🛡️ WireGuard шифрование** - современная криптография
2. **🎭 AmneziaWG обфускация** - маскировка VPN трафика
3. **🔍 Cloak стеганография** - дополнительная маскировка
4. **🌐 Портовая маскировка** - имитация HTTPS, DNS, IMAPS
5. **🚫 AdGuard DNS** - блокировка рекламы и трекеров

### Рекомендации

- 🔐 Используйте сильные пароли (генерируются автоматически)
- 🔄 Регулярно обновляйте ключи обфускации
- 📊 Мониторьте подключения через веб-панель
- 🏠 Используйте разные конфиги для разных целей

**📖 Подробнее**: [Рекомендации по безопасности](docs/SECURITY.md)

## 🐛 Решение проблем

### Автоматическая диагностика

```bash
make diagnostics    # Полная проверка системы
make test-dns      # Тестирование DNS
make check-ports   # Проверка доступности портов
```

### Частые проблемы

<details>
<summary>🔧 Подключение не работает</summary>

1. Проверьте статус сервисов: `make status`
2. Запустите диагностику: `make diagnostics`
3. Проверьте логи: `make logs`
4. Убедитесь, что используете AmneziaVPN для обфускованных конфигов

</details>

<details>
<summary>🏠 Роутер не подключается</summary>

1. Используйте конфигурацию без обфускации
2. Проверьте порты: 51820, 443, 53
3. Попробуйте изменить MTU на 1280
4. Убедитесь, что публичный ключ добавлен на сервер

</details>

**📖 Полное руководство**: [Решение проблем](docs/TROUBLESHOOTING.md)

## 📚 Документация

- 📖 [Подробная установка](docs/INSTALLATION.md)
- 🏠 [Настройка роутеров](docs/ROUTER_SETUP.md)
- 🔒 [Безопасность](docs/SECURITY.md)
- 🐛 [Решение проблем](docs/TROUBLESHOOTING.md)

## 🤝 Поддержка

### Сообщество

- 💬 [GitHub Discussions](https://github.com/yourusername/routerus-vpn/discussions) - вопросы и обсуждения
- 🐛 [Issues](https://github.com/yourusername/routerus-vpn/issues) - баги и предложения
- 📧 Email: support@routerus.example

### Участие в разработке

1. 🍴 Fork репозитория
2. 🌿 Создайте feature branch (`git checkout -b feature/amazing-feature`)
3. 💾 Закоммитьте изменения (`git commit -m 'Add amazing feature'`)
4. 📤 Push в branch (`git push origin feature/amazing-feature`)
5. 🔀 Создайте Pull Request

## 📄 Лицензия

Этот проект распространяется под лицензией MIT. См. [LICENSE](LICENSE) для подробностей.

## 🙏 Благодарности

RouteRus VPN построен на плечах гигантов:

- [🔸 WireGuard](https://www.wireguard.com/) - современный VPN протокол
- [🔸 AmneziaWG](https://amnezia.org/) - обфускация WireGuard трафика
- [🔸 wg-easy](https://github.com/wg-easy/wg-easy) - удобный веб-интерфейс
- [🔸 Cloak](https://github.com/cbeuw/Cloak) - стеганографическая обфускация
- [🔸 AdGuard DNS](https://adguard-dns.io/) - блокировка рекламы и трекеров

## ⚠️ Дисклеймер

RouteRus VPN предназначен только для легального использования. Пользователи несут ответственность за соблюдение местного законодательства и условий использования интернет-провайдеров.

---

<div align="center">

**⭐ Поставьте звезду, если проект оказался полезным!**

[![GitHub stars](https://img.shields.io/github/stars/yourusername/routerus-vpn?style=social)](https://github.com/yourusername/routerus-vpn/stargazers)
[![GitHub forks](https://img.shields.io/github/forks/yourusername/routerus-vpn?style=social)](https://github.com/yourusername/routerus-vpn/network/members)

</div>
