import os
import json
from pathlib import Path

# Чтение списка пиров из JSON-файла или переменной окружения
def load_peers(peers_file="peers.json"):
    peers_path = Path(peers_file)
    if peers_path.exists():
        try:
            with peers_path.open() as f:
                return json.load(f)
        except Exception as e:
            raise ValueError(f"Ошибка при чтении файла {peers_file}: {e}")
    return [
        {
            "public_key": os.getenv("WG_PEER_PUBLIC_KEY", ""),
            "allowed_ips": os.getenv("WG_PEER_ALLOWED_IPS", "0.0.0.0/0"),
            "endpoint": os.getenv("WG_PEER_ENDPOINT", "your_vpn_endpoint"),
            "persistent_keepalive": int(os.getenv("WG_PEER_KEEPALIVE", 25)),
        }
    ]

# Конфигурация WireGuard
WIREGUARD_CONFIG = {
    "interface": {
        "private_key": os.getenv("WG_PRIVATE_KEY", "your_private_key"),
        "address": os.getenv("WG_ADDRESS", "10.0.0.1/24"),
        "dns": os.getenv("WG_DNS", "1.1.1.1,8.8.8.8"),
        "mtu": int(os.getenv("WG_MTU", 1420)),
    },
    "peers": load_peers(),
}
