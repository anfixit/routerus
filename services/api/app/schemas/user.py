from typing import Optional
from datetime import datetime
from pydantic import BaseModel, EmailStr

from app.schemas.base import BaseSchema


# Общие свойства
class UserBase(BaseModel):
    username: str
    email: Optional[EmailStr] = None
    full_name: Optional[str] = None
    is_active: Optional[bool] = True
    is_admin: bool = False


# Свойства для создания пользователя
class UserCreate(UserBase):
    password: str


# Свойства для обновления пользователя
class UserUpdate(BaseModel):
    username: Optional[str] = None
    email: Optional[EmailStr] = None
    full_name: Optional[str] = None
    password: Optional[str] = None
    is_active: Optional[bool] = None


# Свойства для вывода пользователя (получения из БД)
class User(UserBase, BaseSchema):
    id: int
    created_at: datetime
