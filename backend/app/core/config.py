from pydantic_settings import BaseSettings
from pydantic import Field
from typing import List, Optional


class Settings(BaseSettings):
    """Конфигурация приложения"""

    # Основные настройки
    app_name: str = "Routerus V2"
    app_version: str = "2.0.0"
    debug: bool = Field(default=False, env="DEBUG")
    mode: str = Field(default="WEB_INTERFACE", env="MODE")

    # Сервер
    host: str = Field(default="0.0.0.0", env="HOST")
    port: int = Field(default=8000, env="PORT")

    # Безопасность
    jwt_secret: str = Field(..., env="JWT_SECRET")
    vpn_api_secret: str = Field(..., env="VPN_API_SECRET")
    admin_password: str = Field(..., env="ADMIN_PASSWORD")
    token_expire_seconds: int = Field(default=86400, env="TOKEN_EXPIRE_SECONDS")

    # База данных
    database_url: str = Field(default="sqlite:///./data/routerus.db", env="DATABASE_URL")

    # Redis
    redis_url: str = Field(default="redis://localhost:6379/0", env="REDIS_URL")

    # VPN серверы
    vpn_servers: str = Field(default="", env="VPN_SERVERS")
    vpn_server_ip: Optional[str] = Field(default=None, env="VPN_SERVER_IP")
    web_interface_url: Optional[str] = Field(default=None, env="WEB_INTERFACE_URL")

    # VPN конфигурация
    vless_port: int = Field(default=443, env="VLESS_PORT")
    vless_flow: str = Field(default="xtls-rprx-vision", env="VLESS_FLOW")

    # Reality настройки
    reality_dest: str = Field(default="www.microsoft.com:443", env="REALITY_DEST")
    reality_server_name: str = Field(default="www.microsoft.com", env="REALITY_SERVER_NAME")
    reality_sni: str = Field(default="www.microsoft.com", env="REALITY_SNI")
    reality_private_key: str = Field(default="", env="REALITY_PRIVATE_KEY")
    reality_public_key: str = Field(default="", env="REALITY_PUBLIC_KEY")
    reality_short_ids: str = Field(default="", env="REALITY_SHORT_IDS")

    # CORS
    cors_origins: str = Field(default="*", env="CORS_ORIGINS")

    # Логирование
    log_level: str = Field(default="INFO", env="LOG_LEVEL")
    log_max_size: str = Field(default="100MB", env="LOG_MAX_SIZE")
    log_backup_count: int = Field(default=5, env="LOG_BACKUP_COUNT")

    # Telegram
    telegram_bot_token: Optional[str] = Field(default=None, env="TELEGRAM_BOT_TOKEN")
    admin_chat_id: Optional[str] = Field(default=None, env="ADMIN_CHAT_ID")

    # Мониторинг
    prometheus_port: int = Field(default=9091, env="PROMETHEUS_PORT")

    # Лимиты
    max_connections_per_user: int = Field(default=3, env="MAX_CONNECTIONS_PER_USER")
    default_traffic_limit: int = Field(default=0, env="DEFAULT_TRAFFIC_LIMIT")
    inactive_user_cleanup_days: int = Field(default=90, env="INACTIVE_USER_CLEANUP_DAYS")

    # SSL
    letsencrypt_email: Optional[str] = Field(default=None, env="LETSENCRYPT_EMAIL")
    ssl_domains: Optional[str] = Field(default=None, env="SSL_DOMAINS")

    # Резервное копирование
    backup_path: str = Field(default="/opt/routerus/backups", env="BACKUP_PATH")
    backup_schedule: str = Field(default="0 2 * * *", env="BACKUP_SCHEDULE")
    backup_retention_days: int = Field(default=30, env="BACKUP_RETENTION_DAYS")

    # Свойства для удобства
    @property
    def is_web_interface(self) -> bool:
        return self.mode == "WEB_INTERFACE"

    @property
    def is_vpn_only(self) -> bool:
        return self.mode == "VPN_ONLY"

    @property
    def vpn_server_list(self) -> List[str]:
        if not self.vpn_servers:
            return []
        return [server.strip() for server in self.vpn_servers.split(",") if server.strip()]

    @property
    def reality_short_id_list(self) -> List[str]:
        if not self.reality_short_ids:
            return []
        return [sid.strip() for sid in self.reality_short_ids.split(",") if sid.strip()]

    @property
    def cors_origins_list(self) -> List[str]:
        if not self.cors_origins or self.cors_origins == "*":
            return ["*"]
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
        case_sensitive = False
        extra = "ignore"  # Игнорирует дополнительные поля из .env


def get_settings() -> Settings:
    """Возвращает настройки приложения"""
    return Settings()
