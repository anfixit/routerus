# WireGuard VPN Management System

**Описание (Description)**

Этот проект представляет собой систему управления VPN-сервером WireGuard с дополнительными механизмами маскировки и обфускации трафика для обхода блокировок. Система обеспечивает удобное управление VPN, маскирует трафик через Shadowsocks, а также использует Xray для обфускации на уровне HTTP/TLS.

## Системные требования
- Python 3.8+
- Django 3.2+
- Poetry 1.0+
- Git

## Основные компоненты проекта:

- **WireGuard**: Основная VPN-сеть, обеспечивающая шифрование и безопасную передачу данных.
- **Shadowsocks**: Сервис, добавляющий дополнительный слой маскировки для VPN-трафика, чтобы обойти ограничения и блокировки со стороны интернет-провайдеров.
- **Xray**: Программа для обфускации трафика, делающая его похожим на обычный веб-трафик, что затрудняет обнаружение VPN-соединений. Использует протокол VLESS для маскировки трафика.
- **Django**: Веб-фреймворк для управления VPN-конфигурациями через веб-интерфейс.

## Основные функции проекта:

- Добавление и удаление клиентов WireGuard через веб-интерфейс.
- Возможность настройки обфускации трафика.
- Управление конфигурациями WireGuard, Shadowsocks, и Xray через веб-интерфейс.

Цель проекта — создать удобный и безопасный инструмент для управления VPN-конфигурациями и обхода интернет-ограничений.

**Проект находится в разработке. Инструкции по настройке и запуску скриптов будут добавлены позже.**

## English

This project is a management system for a WireGuard VPN server with additional mechanisms for masking and obfuscating traffic to bypass censorship. The system is based on WireGuard for VPN connection, Shadowsocks for traffic masking, and Xray for HTTP/TLS-level obfuscation. The user interface is implemented using Django.

### Main components of the project:

- **WireGuard**: The primary VPN providing encryption and secure data transmission.
- **Shadowsocks**: A service that adds an extra layer of masking to the VPN traffic to bypass ISP restrictions and censorship.
- **Xray**: A tool for obfuscating traffic, making it look like regular web traffic, which makes it harder for VPN connections to be detected. Uses the VLESS protocol for traffic masking.
- **Django**: A web framework for managing VPN configurations via a web interface.

### Key features of the project:

- Add and remove WireGuard clients via a web interface.
- Option to enable/disable traffic obfuscation.
- Manage WireGuard, Shadowsocks, and Xray configurations via the web interface.

The goal of the project is to create a convenient and secure tool for managing VPN configurations and bypassing internet censorship.

**The project is currently under development. Instructions for configuration and running the scripts will be added later.**

---

## Quick Start

1. Clone the repository:
   ```bash
   git clone https://github.com/Anfikus/wg-manager.git
   ```
2. Navigate into the project directory:
   ```bash
   cd wg-manager
   ```
3. Set up your environment:
   ```bash
   python -m venv wg-manager-venv
   source wg-manager-venv/bin/activate
   ```
4. Install dependencies using Poetry:
   ```bash
   poetry install
   ```
5. Set environment variables:
   Make sure to create a `.env` file or set your environment variables as follows:
   ```env
   DEBUG=True
   SECRET_KEY=<ваш_секретный_ключ>
   ALLOWED_HOSTS=*
   ...
   ```
6. Run database migrations:
   ```bash
   python manage.py migrate
   ```
7. Run the application:
   ```bash
   python manage.py runserver
   ```

## Contributing

Contributions are welcome! Please fork the repository and create a pull request for review.

---

## License

MIT License. See `LICENSE` file for details.
