# WireGuard Maximum Obfuscation Setup

Полнофункциональное решение для развертывания WireGuard VPN с максимальной обфускацией трафика, веб-интерфейсом и поддержкой роутеров.

## 🌟 Особенности

- **Максимальная обфускация** с AmneziaWG
- **Веб-интерфейс** wg-easy для удобного управления
- **Автоматическая обфускация** всех создаваемых конфигов
- **Поддержка роутеров** (Keenetic и другие)
- **Блокировка рекламы** через AdGuard DNS
- **Множественные порты** для обхода блокировок
- **Дополнительная обфускация** через Cloak
- **Мониторинг и диагностика**

## 📁 Структура проекта

```
wireguard-obfuscation-setup/
├── scripts/
│   ├── install.sh                    # Основной скрипт установки
│   ├── wg-manager.sh                 # Скрипт управления
│   ├── router-config-generator.sh    # Генератор конфигов для роутеров
│   ├── config-template-setup.sh      # Настройка шаблонов
│   ├── router-optimization.sh        # Оптимизация для роутеров
│   └── diagnostics.sh               # Диагностика проблем
├── templates/
│   ├── client-obfuscated.conf        # Стандартный шаблон с обфускацией
│   ├── client-mobile.conf            # Оптимизированный для мобильных
│   ├── client-https-masked.conf      # Маскировка под HTTPS
│   └── client-custom.conf            # Пользовательский шаблон
├── docker/
│   ├── docker-compose.yml            # Docker Compose конфигурация
│   ├── Dockerfile.wg-easy           # Кастомный образ wg-easy
│   └── cloak/
│       └── config-template.json     # Шаблон конфигурации Cloak
├── systemd/
│   ├── wg-easy.service              # Systemd сервис для wg-easy
│   ├── wg-auto-obfuscate.service    # Автоматическая обфускация
│   └── wg-monitor.service           # Мониторинг подключений
├── config/
│   ├── server-config-template.conf  # Шаблон серверной конфигурации
│   ├── obfuscation-template.env     # Шаблон параметров обфускации
│   └── iptables-rules.sh            # Правила iptables
├── web/
│   └── stats.php                    # Веб-страница со статистикой
├── docs/
│   ├── INSTALLATION.md              # Подробная инструкция по установке
│   ├── ROUTER_SETUP.md              # Настройка роутеров
│   ├── TROUBLESHOOTING.md           # Решение проблем
│   └── SECURITY.md                  # Рекомендации по безопасности
├── examples/
│   ├── keenetic-setup-guide.md      # Пример настройки Keenetic
│   └── client-configs/              # Примеры клиентских конфигов
├── README.md                        # Основная документация
├── LICENSE                          # Лицензия
└── .gitignore                       # Исключения для git
```

## 🚀 Быстрый старт

### Автоматическая установка

```bash
# Клонирование репозитория
git clone https://github.com/yourusername/wireguard-obfuscation-setup.git
cd wireguard-obfuscation-setup

# Запуск установки
sudo ./scripts/install.sh
```

### Ручная настройка

1. **Подготовка системы**
   ```bash
   apt update && apt upgrade -y
   apt install -y curl wget docker.io docker-compose-plugin
   ```

2. **Настройка параметров**
   ```bash
   cp config/obfuscation-template.env config/obfuscation.env
   # Отредактируйте файл под свои нужды
   ```

3. **Запуск сервисов**
   ```bash
   ./scripts/wg-manager.sh start
   ```

## 🔧 Управление

### Основные команды

```bash
# Управление сервисом
./scripts/wg-manager.sh start|stop|restart|status

# Добавление обфускации во все конфиги
./scripts/wg-manager.sh add-obfuscation

# Создание конфига для роутера
./scripts/wg-manager.sh create-router-config

# Мониторинг подключений
./scripts/wg-manager.sh monitor

# Диагностика проблем
./scripts/wg-manager.sh diagnostics
```

### Генерация клиентских конфигов

```bash
# Стандартный обфускованный конфиг
./scripts/generate-config.sh client1 standard

# Мобильный конфиг (оптимизированный)
./scripts/generate-config.sh client2 mobile

# Маскировка под HTTPS
./scripts/generate-config.sh client3 https
```

## 🛠️ Конфигурация

### Основные настройки

Отредактируйте `config/obfuscation.env`:

```bash
# Параметры обфускации AmneziaWG
JC=5                    # Количество мусорных пакетов
JMIN=100               # Минимальный размер мусорного пакета
JMAX=1000              # Максимальный размер мусорного пакета
S1=86                  # Magic header 1
S2=92                  # Magic header 2
H1=1234567890          # Magic hash 1
H2=9876543210          # Magic hash 2
H3=1122334455          # Magic hash 3
H4=5544332211          # Magic hash 4

# Настройки сервера
SERVER_ENDPOINT=your-server.com
WG_EASY_PASSWORD=your-secure-password
WEB_PORT=51821

# DNS настройки (замените на ваши)
ADGUARD_DNS_HTTPS=https://your-adguard-dns.com/dns-query/your-id
ADGUARD_DNS_TLS=tls://your-id.your-adguard-dns.com
```

### Настройка AdGuard DNS

1. Зарегистрируйтесь на [AdGuard DNS](https://adguard-dns.io/)
2. Создайте профиль и получите персональные DNS адреса
3. Замените плейсхолдеры в конфигурации на ваши данные

## 📱 Клиентские приложения

### Рекомендуемые приложения для обфускации

- **AmneziaVPN** (все платформы) - https://amnezia.org/
  - Поддерживает все параметры обфускации
  - Автоматическое определение настроек

### Стандартные клиенты WireGuard

⚠️ **Внимание**: Стандартные клиенты WireGuard НЕ поддерживают параметры обфускации!

- Используйте только для базовых подключений
- Для максимальной защиты нужен AmneziaVPN

## 🏠 Настройка роутеров

### Поддерживаемые роутеры

- Keenetic (все модели с поддержкой WireGuard)
- OpenWrt
- ASUS (с поддержкой WireGuard)
- MikroTik

### Быстрая настройка для Keenetic

```bash
# Создание конфигурации для роутера
./scripts/wg-manager.sh create-router-config

# Следуйте инструкциям в выводе скрипта
```

Подробная инструкция: [docs/ROUTER_SETUP.md](docs/ROUTER_SETUP.md)

## 🔒 Безопасность

### Уровни защиты

1. **Базовый WireGuard** - для роутеров
2. **AmneziaWG обфускация** - для устройств
3. **Cloak маскировка** - дополнительный уровень
4. **Портовая маскировка** - имитация других протоколов

### Рекомендации

- Используйте сильные пароли
- Регулярно обновляйте ключи
- Мониторьте подключения
- Используйте разные конфиги для разных целей

Подробнее: [docs/SECURITY.md](docs/SECURITY.md)

## 📊 Мониторинг

### Веб-интерфейс

- **wg-easy**: `http://your-server:51821`
- **Статистика**: `http://your-server:8080/stats.php`

### Командная строка

```bash
# Просмотр активных подключений
wg show

# Мониторинг в реальном времени
./scripts/wg-manager.sh monitor

# Просмотр логов
./scripts/wg-manager.sh logs
```

## 🐛 Решение проблем

### Частые проблемы

1. **Подключение не работает**
   ```bash
   ./scripts/wg-manager.sh diagnostics
   ```

2. **Роутер не подключается**
   - Проверьте порты: 51820, 443, 53
   - Убедитесь, что публичный ключ добавлен на сервер
   - Попробуйте изменить MTU на 1280

3. **Обфускация не работает**
   - Убедитесь, что используете AmneziaVPN
   - Проверьте правильность параметров обфускации

Подробнее: [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)

## 📚 Документация

- [Установка](docs/INSTALLATION.md) - Подробная инструкция по установке
- [Настройка роутеров](docs/ROUTER_SETUP.md) - Конфигурация различных роутеров
- [Решение проблем](docs/TROUBLESHOOTING.md) - Диагностика и устранение неисправностей
- [Безопасность](docs/SECURITY.md) - Рекомендации по безопасности

## 🤝 Участие в разработке

1. Fork репозитория
2. Создайте feature branch
3. Внесите изменения
4. Создайте Pull Request

## 📄 Лицензия

MIT License - см. [LICENSE](LICENSE)

## ⚠️ Дисклеймер

Этот проект предназначен только для легального использования. Пользователи несут ответственность за соблюдение местного законодательства.

## 🙏 Благодарности

- [AmneziaVPN](https://amnezia.org/) - за обфускацию WireGuard
- [wg-easy](https://github.com/wg-easy/wg-easy) - за удобный веб-интерфейс
- [Cloak](https://github.com/cbeuw/Cloak) - за дополнительную обфускацию

---

**⭐ Поставьте звезду, если проект оказался полезным!**
