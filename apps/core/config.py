from typing import List
from pydantic import IPvAnyAddress, conint, validator
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    DEBUG: bool = False
    SECRET_KEY: str
    ALLOWED_HOSTS: List[str]

    DB_NAME: str
    DB_USER: str
    DB_PASSWORD: str
    DB_HOST: str = "localhost"
    DB_PORT: int = 5432

    WIREGUARD_PRIVATE_KEY: str
    WIREGUARD_SERVER_PUBLIC_KEY: str
    WIREGUARD_SERVER_IP: IPvAnyAddress
    WIREGUARD_SERVER_PORT: conint(gt=0, lt=65536) = 51820
    WIREGUARD_PEERDNS: str = "1.1.1.1"
    WIREGUARD_ALLOWEDIPS: str = "0.0.0.0/0,::/0"
    WIREGUARD_PERSISTENTKEEPALIVE: conint(gt=0, lt=65536) = 25

    SHADOWSOCKS_SERVER: IPvAnyAddress
    SHADOWSOCKS_PORT: conint(gt=0, lt=65536)
    SHADOWSOCKS_PASSWORD: str
    SHADOWSOCKS_METHOD: str = "chacha20-ietf-poly1305"
    SHADOWSOCKS_TIMEOUT: conint(gt=0, lt=3600) = 300

    XRAY_LOG_LEVEL: str = "info"
    XRAY_VLESS_PORT: conint(gt=0, lt=65536) = 443
    XRAY_UUID: str
    XRAY_VLESS_NETWORK: str = "ws"
    XRAY_VLESS_PATH: str = "/vless"
    XRAY_SHADOWSOCKS_PORT: conint(gt=0, lt=65536) = 8388
    XRAY_SHADOWSOCKS_METHOD: str = "chacha20-ietf-poly1305"
    XRAY_SHADOWSOCKS_PASSWORD: str
    XRAY_WIREGUARD_PORT: conint(gt=0, lt=65536) = 51820
    XRAY_WIREGUARD_SECRET_KEY: str
    XRAY_WIREGUARD_PUBLIC_KEY: str
    XRAY_WIREGUARD_ADDRESS: IPvAnyAddress

    class Config:
        env_file = "/opt/routerus/.env"
        env_file_encoding = "utf-8"

    @validator("ALLOWED_HOSTS", pre=True)
    def split_allowed_hosts(cls, v):
        if isinstance(v, str):
            return [h.strip() for h in v.split(",") if h.strip()]
        return v


settings = Settings()
