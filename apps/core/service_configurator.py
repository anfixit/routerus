from .config import settings


def get_wireguard_config():
    return {
        "private_key": settings.WIREGUARD_PRIVATE_KEY,
        "public_key": settings.WIREGUARD_SERVER_PUBLIC_KEY,
        "server_ip": str(settings.WIREGUARD_SERVER_IP),
        "server_port": settings.WIREGUARD_SERVER_PORT,
        "peer_dns": settings.WIREGUARD_PEERDNS,
        "allowed_ips": settings.WIREGUARD_ALLOWEDIPS,
        "persistent_keepalive": settings.WIREGUARD_PERSISTENTKEEPALIVE,
    }


def get_shadowsocks_config():
    return {
        "server": str(settings.SHADOWSOCKS_SERVER),
        "port": settings.SHADOWSOCKS_PORT,
        "password": settings.SHADOWSOCKS_PASSWORD,
        "method": settings.SHADOWSOCKS_METHOD,
        "timeout": settings.SHADOWSOCKS_TIMEOUT,
    }


def get_xray_config():
    return {
        "log_level": settings.XRAY_LOG_LEVEL,
        "vless_port": settings.XRAY_VLESS_PORT,
        "uuid": settings.XRAY_UUID,
        "vless_network": settings.XRAY_VLESS_NETWORK,
        "vless_path": settings.XRAY_VLESS_PATH,
        "shadowsocks_port": settings.XRAY_SHADOWSOCKS_PORT,
        "shadowsocks_method": settings.XRAY_SHADOWSOCKS_METHOD,
        "shadowsocks_password": settings.XRAY_SHADOWSOCKS_PASSWORD,
        "wireguard_port": settings.XRAY_WIREGUARD_PORT,
        "wireguard_secret_key": settings.XRAY_WIREGUARD_SECRET_KEY,
        "wireguard_public_key": settings.XRAY_WIREGUARD_PUBLIC_KEY,
        "wireguard_address": str(settings.XRAY_WIREGUARD_ADDRESS),
    }
