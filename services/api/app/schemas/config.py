from typing import Optional, List
from datetime import datetime
from pydantic import BaseModel

from app.models.config import VPNType
from app.schemas.base import BaseSchema


# Общие свойства
class VPNConfigBase(BaseModel):
    name: str
    vpn_type: VPNType
    is_active: bool = True


# Свойства для создания конфигурации
class VPNConfigCreate(VPNConfigBase):
    user_id: int
    expires_at: Optional[datetime] = None


# Свойства для обновления конфигурации
class VPNConfigUpdate(BaseModel):
    name: Optional[str] = None
    is_active: Optional[bool] = None
    expires_at: Optional[datetime] = None


# Свойства для вывода конфигурации (получения из БД)
class VPNConfig(VPNConfigBase, BaseSchema):
    id: int
    user_id: int
    ip_address: Optional[str] = None
    created_at: datetime
    expires_at: Optional[datetime] = None
    last_connected: Optional[datetime] = None
    bytes_sent: int = 0
    bytes_received: int = 0


# Дополнительная схема для представления конфигурации с QR-кодом
class VPNConfigWithQR(VPNConfig):
    config_data: str
    qr_code: Optional[str] = None  # Base64-encoded QR code image
