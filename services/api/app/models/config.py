from typing import Optional

from sqlalchemy import Boolean, Column, Integer, String, ForeignKey, DateTime, Enum
from sqlalchemy.orm import relationship
import datetime
import enum

from app.models.base import Base


class VPNType(str, enum.Enum):
    WIREGUARD = "wireguard"
    SHADOWSOCKS = "shadowsocks"
    XRAY = "xray"


class VPNConfig(Base):
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, index=True, nullable=False)
    vpn_type = Column(Enum(VPNType), nullable=False)
    config_data = Column(String, nullable=False)  # JSON строка с конфигурацией
    private_key = Column(String)  # Для WireGuard
    public_key = Column(String)  # Для WireGuard
    password = Column(String)  # Для Shadowsocks
    uuid = Column(String)  # Для Xray
    ip_address = Column(String)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, default=datetime.datetime.utcnow)
    expires_at = Column(DateTime, nullable=True)
    last_connected = Column(DateTime, nullable=True)
    bytes_sent = Column(Integer, default=0)
    bytes_received = Column(Integer, default=0)
    
    # Связь с пользователем
    user_id = Column(Integer, ForeignKey("user.id"))
    user = relationship("User", back_populates="configs")
