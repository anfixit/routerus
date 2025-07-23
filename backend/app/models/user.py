from sqlalchemy import Column, Integer, String, DateTime, Boolean, Text, Float, ForeignKey
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from datetime import datetime
from typing import Optional
from pydantic import BaseModel, Field, EmailStr
from enum import Enum

from ..core.database import Base


class UserStatus(str, Enum):
    """Статусы пользователя VPN"""
    ACTIVE = "active"
    INACTIVE = "inactive"
    SUSPENDED = "suspended"
    EXPIRED = "expired"


class VpnUser(Base):
    """Модель пользователя VPN"""
    __tablename__ = "vpn_users"

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String(255), nullable=False, index=True)
    name = Column(String(100), nullable=True)

    # VPN конфигурация
    vpn_uuid = Column(String(36), unique=True, nullable=False, index=True)
    server_id = Column(Integer, ForeignKey("servers.id"), nullable=False)

    # Статус и лимиты
    status = Column(String(20), default=UserStatus.ACTIVE)
    traffic_limit_gb = Column(Float, default=0)  # 0 = без лимита
    used_traffic_gb = Column(Float, default=0.0)
    max_connections = Column(Integer, default=3)
    current_connections = Column(Integer, default=0)

    # Статистика
    total_traffic_gb = Column(Float, default=0.0)
    last_connection = Column(DateTime, nullable=True)
    connection_count = Column(Integer, default=0)

    # Время жизни
    expires_at = Column(DateTime, nullable=True)

    # Конфигурация клиента
    config_url = Column(Text, nullable=True)  # VLESS URL
    qr_code = Column(Text, nullable=True)     # Base64 QR код

    # Мета информация
    notes = Column(Text, nullable=True)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, default=func.now())
    updated_at = Column(DateTime, default=func.now(), onupdate=func.now())

    # Связи
    server = relationship("Server", back_populates="users")
    connections = relationship("UserConnection", back_populates="user", cascade="all, delete-orphan")


class UserConnection(Base):
    """История подключений пользователя"""
    __tablename__ = "user_connections"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("vpn_users.id"), nullable=False, index=True)

    # Информация о подключении
    ip_address = Column(String(45), nullable=True)
    user_agent = Column(String(255), nullable=True)
    country = Column(String(100), nullable=True)

    # Трафик за сессию
    bytes_sent = Column(Integer, default=0)
    bytes_received = Column(Integer, default=0)

    # Время сессии
    connected_at = Column(DateTime, default=func.now())
    disconnected_at = Column(DateTime, nullable=True)
    duration_seconds = Column(Integer, default=0)

    # Связи
    user = relationship("VpnUser", back_populates="connections")


class AdminUser(Base):
    """Модель администратора"""
    __tablename__ = "admin_users"

    id = Column(Integer, primary_key=True, index=True)
    username = Column(String(50), unique=True, nullable=False, index=True)
    email = Column(String(255), unique=True, nullable=False, index=True)
    hashed_password = Column(String(255), nullable=False)

    # Права доступа
    is_active = Column(Boolean, default=True)
    is_superuser = Column(Boolean, default=False)

    # Мета информация
    full_name = Column(String(100), nullable=True)
    last_login = Column(DateTime, nullable=True)
    created_at = Column(DateTime, default=func.now())
    updated_at = Column(DateTime, default=func.now(), onupdate=func.now())


# Pydantic модели для API
class VpnUserBase(BaseModel):
    """Базовая модель пользователя VPN"""
    email: EmailStr = Field(..., description="Email пользователя")
    name: Optional[str] = Field(None, max_length=100)
    traffic_limit_gb: float = Field(default=0, ge=0)
    max_connections: int = Field(default=3, ge=1, le=10)
    expires_at: Optional[datetime] = None
    notes: Optional[str] = None


class VpnUserCreate(VpnUserBase):
    """Модель для создания пользователя VPN"""
    server_id: int = Field(..., description="ID сервера")


class VpnUserUpdate(BaseModel):
    """Модель для обновления пользователя VPN"""
    name: Optional[str] = None
    status: Optional[UserStatus] = None
    traffic_limit_gb: Optional[float] = None
    max_connections: Optional[int] = None
    expires_at: Optional[datetime] = None
    notes: Optional[str] = None
    is_active: Optional[bool] = None


class VpnUserResponse(BaseModel):
    """Модель ответа пользователя VPN"""
    id: int
    email: str
    name: Optional[str]
    vpn_uuid: str
    server_id: int

    status: UserStatus
    traffic_limit_gb: float
    used_traffic_gb: float
    max_connections: int
    current_connections: int

    total_traffic_gb: float
    last_connection: Optional[datetime]
    connection_count: int
    expires_at: Optional[datetime]

    config_url: Optional[str]

    notes: Optional[str]
    is_active: bool
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class VpnUserConfig(BaseModel):
    """Конфигурация пользователя для подключения"""
    vpn_uuid: str
    config_url: str
    qr_code: str
    server_ip: str
    server_name: str


class UserConnectionResponse(BaseModel):
    """Модель подключения пользователя"""
    id: int
    ip_address: Optional[str]
    user_agent: Optional[str]
    country: Optional[str]
    bytes_sent: int
    bytes_received: int
    connected_at: datetime
    disconnected_at: Optional[datetime]
    duration_seconds: int

    class Config:
        from_attributes = True


class AdminUserBase(BaseModel):
    """Базовая модель администратора"""
    username: str = Field(..., min_length=3, max_length=50)
    email: EmailStr
    full_name: Optional[str] = None
    is_active: bool = True
    is_superuser: bool = False


class AdminUserCreate(AdminUserBase):
    """Модель для создания администратора"""
    password: str = Field(..., min_length=8)


class AdminUserUpdate(BaseModel):
    """Модель для обновления администратора"""
    email: Optional[EmailStr] = None
    full_name: Optional[str] = None
    password: Optional[str] = None
    is_active: Optional[bool] = None
    is_superuser: Optional[bool] = None


class AdminUserResponse(BaseModel):
    """Модель ответа администратора"""
    id: int
    username: str
    email: str
    full_name: Optional[str]
    is_active: bool
    is_superuser: bool
    last_login: Optional[datetime]
    created_at: datetime

    class Config:
        from_attributes = True
