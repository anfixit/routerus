from datetime import datetime, timedelta
from typing import Optional, Union, Any
from jose import jwt, JWTError
from passlib.context import CryptContext
from passlib.hash import bcrypt
from fastapi import HTTPException, status
from pydantic import BaseModel

from .config import get_settings

settings = get_settings()

# Контекст для хеширования паролей
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# Алгоритм JWT
ALGORITHM = "HS256"


class Token(BaseModel):
    """Модель токена"""
    access_token: str
    token_type: str
    expires_in: int


class TokenData(BaseModel):
    """Данные токена"""
    username: Optional[str] = None
    user_id: Optional[int] = None
    is_admin: bool = False


def create_access_token(
    data: dict,
    expires_delta: Optional[timedelta] = None
) -> str:
    """Создание JWT токена доступа"""
    to_encode = data.copy()

    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        expire = datetime.utcnow() + timedelta(seconds=settings.token_expire_seconds)

    to_encode.update({
        "exp": expire,
        "iat": datetime.utcnow(),
        "type": "access"
    })

    encoded_jwt = jwt.encode(to_encode, settings.jwt_secret, algorithm=ALGORITHM)
    return encoded_jwt


def verify_token(token: str) -> TokenData:
    """Проверка и декодирование JWT токена"""
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Недействительные учетные данные",
        headers={"WWW-Authenticate": "Bearer"},
    )

    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=[ALGORITHM])
        username: str = payload.get("sub")
        user_id: int = payload.get("user_id")
        is_admin: bool = payload.get("is_admin", False)

        if username is None:
            raise credentials_exception

        token_data = TokenData(
            username=username,
            user_id=user_id,
            is_admin=is_admin
        )
        return token_data

    except JWTError:
        raise credentials_exception


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Проверка пароля"""
    return pwd_context.verify(plain_password, hashed_password)


def get_password_hash(password: str) -> str:
    """Хеширование пароля"""
    return pwd_context.hash(password)


def verify_api_key(api_key: str) -> bool:
    """Проверка API ключа для межсерверного общения"""
    return api_key == settings.vpn_api_secret


def create_api_token(server_id: str, expires_delta: Optional[timedelta] = None) -> str:
    """Создание токена для API между серверами"""
    to_encode = {
        "server_id": server_id,
        "type": "api",
        "sub": f"server_{server_id}"
    }

    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        expire = datetime.utcnow() + timedelta(hours=24)

    to_encode.update({
        "exp": expire,
        "iat": datetime.utcnow()
    })

    encoded_jwt = jwt.encode(to_encode, settings.vpn_api_secret, algorithm=ALGORITHM)
    return encoded_jwt


def verify_api_token(token: str) -> dict:
    """Проверка API токена"""
    try:
        payload = jwt.decode(token, settings.vpn_api_secret, algorithms=[ALGORITHM])
        if payload.get("type") != "api":
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Недействительный тип токена"
            )
        return payload
    except JWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Недействительный API токен"
        )


def generate_vpn_user_id() -> str:
    """Генерация UUID для пользователя VPN"""
    import uuid
    return str(uuid.uuid4())


def generate_reality_keys() -> tuple[str, str]:
    """Генерация пары ключей для Reality протокола"""
    import secrets
    import base64

    private_key = secrets.token_bytes(32)
    public_key = secrets.token_bytes(32)

    private_b64 = base64.b64encode(private_key).decode()
    public_b64 = base64.b64encode(public_key).decode()

    return private_b64, public_b64


def generate_short_ids(count: int = 3) -> list[str]:
    """Генерация коротких ID для Reality"""
    import secrets
    return [secrets.token_hex(8) for _ in range(count)]
