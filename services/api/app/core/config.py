from typing import Any, Dict, List, Optional

from pydantic import AnyHttpUrl, EmailStr, validator
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    API_V1_STR: str = "/api/v1"
    SECRET_KEY: str = "YOUR_SECRET_KEY_HERE"  # Изменить на более безопасный в продакшене
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24 * 8  # 8 дней
    
    # База данных
    DB_TYPE: str = "postgresql"
    DB_HOST: str = "db"
    DB_PORT: str = "5432"
    DB_USER: str = "vpnuser"
    DB_PASSWORD: str = "password"
    DB_NAME: str = "vpnservice"
    
    @property
    def SQLALCHEMY_DATABASE_URI(self) -> str:
        return f"{self.DB_TYPE}://{self.DB_USER}:{self.DB_PASSWORD}@{self.DB_HOST}:{self.DB_PORT}/{self.DB_NAME}"
    
    # Настройки CORS
    BACKEND_CORS_ORIGINS: List[AnyHttpUrl] = []
    
    @validator("BACKEND_CORS_ORIGINS", pre=True)
    def assemble_cors_origins(cls, v: str | List[str]) -> List[str] | str:
        if isinstance(v, str) and not v.startswith("["):
            return [i.strip() for i in v.split(",")]
        elif isinstance(v, (list, str)):
            return v
        raise ValueError(v)
    
    # Настройки администратора
    ADMIN_USERNAME: str = "admin"
    ADMIN_PASSWORD: str = "password"  # Будет заменено при первом запуске
    ADMIN_EMAIL: EmailStr = "admin@example.com"
    
    # Настройки WireGuard
    WG_CONFIG_DIR: str = "/etc/wireguard"
    WG_INTERFACE: str = "wg0"
    WG_PORT: int = 51820
    WG_NETWORK: str = "10.8.0.0/24"
    WG_PRIVATE_KEY: Optional[str] = None
    WG_PUBLIC_KEY: Optional[str] = None
    
    # Настройки Shadowsocks
    SS_CONFIG_DIR: str = "/etc/shadowsocks-libev"
    SS_PORT: int = 8388
    SS_METHOD: str = "chacha20-ietf-poly1305"
    SS_PASSWORD: Optional[str] = None
    
    # Настройки Xray
    XRAY_CONFIG_DIR: str = "/etc/xray"
    XRAY_PORT: int = 443
    XRAY_UUID: Optional[str] = None
    
    # Настройки системы
    PROJECT_NAME: str = "VPN Service"
    SERVER_HOST: str = "vpn.routerus.ru"
    
    class Config:
        case_sensitive = True
        env_file = ".env"


settings = Settings()
