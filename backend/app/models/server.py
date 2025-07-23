from sqlalchemy import Column, Integer, String, DateTime, Boolean, Text, Float, ForeignKey
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from datetime import datetime
from typing import Optional
from pydantic import BaseModel, Field
from enum import Enum

from ..core.database import Base


class ServerStatus(str, Enum):
    """Статусы VPN сервера"""
    ONLINE = "online"
    OFFLINE = "offline"
    UNKNOWN = "unknown"
    MAINTENANCE = "maintenance"


class Server(Base):
    """Модель VPN сервера"""
    __tablename__ = "servers"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(100), nullable=False, index=True)
    ip = Column(String(45), nullable=False, unique=True, index=True)  # IPv4/IPv6
    port = Column(Integer, default=443)
    location = Column(String(100), nullable=False)
    country_code = Column(String(2), nullable=True)  # ISO код страны

    # Статус и мониторинг
    status = Column(String(20), default=ServerStatus.UNKNOWN)
    last_check = Column(DateTime, default=func.now())
    uptime = Column(Integer, default=0)  # секунды

    # Конфигурация Reality
    reality_dest = Column(String(255), default="www.microsoft.com:443")
    reality_server_name = Column(String(255), default="www.microsoft.com")
    reality_private_key = Column(Text, nullable=True)
    reality_public_key = Column(Text, nullable=True)
    reality_short_ids = Column(Text, nullable=True)  # JSON array as string

    # Статистика
    total_users = Column(Integer, default=0)
    active_users = Column(Integer, default=0)
    total_traffic_gb = Column(Float, default=0.0)

    # Лимиты
    max_users = Column(Integer, default=1000)
    max_traffic_gb = Column(Float, default=0)  # 0 = без лимита

    # Мета информация
    description = Column(Text, nullable=True)
    tags = Column(Text, nullable=True)  # JSON array as string
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, default=func.now())
    updated_at = Column(DateTime, default=func.now(), onupdate=func.now())

    # Связи
    users = relationship("VpnUser", back_populates="server", cascade="all, delete-orphan")
    stats = relationship("ServerStats", back_populates="server", cascade="all, delete-orphan")


class ServerStats(Base):
    """Статистика сервера по времени"""
    __tablename__ = "server_stats"

    id = Column(Integer, primary_key=True, index=True)
    server_id = Column(Integer, ForeignKey("servers.id"), nullable=False, index=True)

    # Системные метрики
    cpu_usage = Column(Float, default=0.0)
    memory_usage = Column(Float, default=0.0)
    disk_usage = Column(Float, default=0.0)
    network_in = Column(Integer, default=0)  # bytes
    network_out = Column(Integer, default=0)  # bytes

    # VPN метрики
    active_connections = Column(Integer, default=0)
    total_connections = Column(Integer, default=0)

    # Время записи
    timestamp = Column(DateTime, default=func.now(), index=True)

    # Связи
    server = relationship("Server", back_populates="stats")


# Pydantic модели для API
class ServerBase(BaseModel):
    """Базовая модель сервера"""
    name: str = Field(..., min_length=1, max_length=100)
    ip: str = Field(..., description="IP адрес сервера")
    port: int = Field(default=443, ge=1, le=65535)
    location: str = Field(..., min_length=1, max_length=100)
    country_code: Optional[str] = Field(None, min_length=2, max_length=2)
    description: Optional[str] = None
    max_users: int = Field(default=1000, ge=1)
    max_traffic_gb: float = Field(default=0, ge=0)


class ServerCreate(ServerBase):
    """Модель для создания сервера"""
    reality_dest: Optional[str] = "www.microsoft.com:443"
    reality_server_name: Optional[str] = "www.microsoft.com"


class ServerUpdate(BaseModel):
    """Модель для обновления сервера"""
    name: Optional[str] = None
    location: Optional[str] = None
    description: Optional[str] = None
    max_users: Optional[int] = None
    max_traffic_gb: Optional[float] = None
    is_active: Optional[bool] = None


class ServerResponse(BaseModel):
    """Модель ответа сервера"""
    id: int
    name: str
    ip: str
    port: int
    location: str
    country_code: Optional[str]
    status: ServerStatus
    last_check: datetime
    uptime: int

    total_users: int
    active_users: int
    total_traffic_gb: float

    max_users: int
    max_traffic_gb: float

    reality_public_key: Optional[str]

    description: Optional[str]
    is_active: bool
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class ServerStatsResponse(BaseModel):
    """Модель статистики сервера"""
    cpu_usage: float
    memory_usage: float
    disk_usage: float
    network_in: int
    network_out: int
    active_connections: int
    total_connections: int
    timestamp: datetime

    class Config:
        from_attributes = True


class ServerMonitoring(BaseModel):
    """Модель для мониторинга сервера"""
    server_id: int
    status: ServerStatus
    uptime: int
    stats: ServerStatsResponse
    last_check: datetime
