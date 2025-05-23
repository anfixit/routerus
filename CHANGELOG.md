# Changelog

Все значительные изменения в проекте документируются в этом файле.

Формат основан на [Keep a Changelog](https://keepachangelog.com/),
и проект придерживается [Semantic Versioning](https://semver.org/).

## [0.1.0] - 2025-05-11

### Добавлено
- Базовая инфраструктура с использованием Docker и Docker Compose
- Настройка VPN-сервисов (WireGuard, Shadowsocks, Xray)
- Реализация многоуровневой обфускации трафика
- API на базе FastAPI для управления пользователями и конфигурациями
- Мониторинг с использованием Prometheus и Grafana
- Система алертов с интеграцией в Telegram
- Начальная версия веб-интерфейса

### Безопасность
- Настройка TLS-шифрования
- Защита API с использованием OAuth2 и JWT-токенов
- Хеширование паролей с использованием bcrypt
- Защита от DDoS-атак
- Защита от брутфорс-атак

## [Unreleased]

### Планируется
- Расширение функциональности веб-интерфейса
- Улучшение дашбордов Grafana
- Интеграция с платежными системами
- Автоматическое масштабирование на дополнительные серверы
- Интеграция с CDN для ускорения работы
