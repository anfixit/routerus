import os

def validate_shadowsocks_config(config):
    """
    Проверяет корректность конфигурации Shadowsocks.
    """
    if not (1 <= config["server_port"] <= 65535):
        raise ValueError(f"Порт {config['server_port']} вне диапазона 1–65535.")
    if len(config["password"]) < 8:
        raise ValueError("Пароль должен содержать не менее 8 символов.")
    supported_methods = ["chacha20-ietf-poly1305", "aes-256-gcm", "aes-128-gcm"]
    if config["method"] not in supported_methods:
        raise ValueError(f"Метод шифрования {config['method']} не поддерживается.")

# Конфигурация Shadowsocks
SHADOWSOCKS_CONFIG = {
    "server": os.getenv("SHADOWSOCKS_SERVER", "0.0.0.0"),
    "server_port": int(os.getenv("SHADOWSOCKS_PORT", 8388)),
    "password": os.getenv("SHADOWSOCKS_PASSWORD", "strongpassword"),
    "timeout": int(os.getenv("SHADOWSOCKS_TIMEOUT", 300)),
    "method": os.getenv("SHADOWSOCKS_METHOD", "chacha20-ietf-poly1305"),
    "fast_open": os.getenv("SHADOWSOCKS_FAST_OPEN", "false").lower() == "true",
}

# Валидация конфигурации
try:
    validate_shadowsocks_config(SHADOWSOCKS_CONFIG)
except ValueError as e:
    raise SystemExit(f"Ошибка в конфигурации Shadowsocks: {e}")
