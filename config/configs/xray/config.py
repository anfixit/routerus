import os
import re

def validate_xray_config(config):
    """
    Проверяет корректность конфигурации Xray.
    """
    if not (1 <= config["inbounds"][0]["port"] <= 65535):
        raise ValueError(f"Порт {config['inbounds'][0]['port']} вне диапазона 1–65535.")
    uuid_regex = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$", re.IGNORECASE)
    if not uuid_regex.match(config["inbounds"][0]["settings"]["clients"][0]["id"]):
        raise ValueError(f"UUID {config['inbounds'][0]['settings']['clients'][0]['id']} невалиден.")

# Конфигурация Xray
XRAY_CONFIG = {
    "log": {
        "loglevel": os.getenv("XRAY_LOG_LEVEL", "info"),
        "access": os.getenv("XRAY_ACCESS_LOG", "/var/log/xray/access.log"),
        "error": os.getenv("XRAY_ERROR_LOG", "/var/log/xray/error.log"),
    },
    "inbounds": [
        {
            "port": int(os.getenv("XRAY_PORT", 8388)),
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": os.getenv("XRAY_VLESS_ID", "your_vless_id"),
                        "flow": "xtls-rprx-direct",
                        "level": 0,
                        "email": os.getenv("XRAY_EMAIL", "test@example.com"),
                    }
                ]
            },
            "streamSettings": {
                "network": os.getenv("XRAY_NETWORK", "ws"),
                "wsSettings": {"path": os.getenv("XRAY_WS_PATH", "/vless")},
            },
        }
    ],
    "outbounds": [{"protocol": "freedom", "settings": {}}],
}

# Валидация конфигурации
try:
    validate_xray_config(XRAY_CONFIG)
except ValueError as e:
    raise SystemExit(f"Ошибка в конфигурации Xray: {e}")
