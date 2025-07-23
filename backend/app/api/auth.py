from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.orm import Session
from datetime import datetime, timedelta
from pydantic import BaseModel

from ..core.database import get_db
from ..core.security import (
    create_access_token, verify_token, verify_password,
    get_password_hash, Token, TokenData
)
from ..models.user import AdminUser, AdminUserResponse

router = APIRouter()
security = HTTPBearer()


class LoginRequest(BaseModel):
    """Модель запроса авторизации"""
    username: str
    password: str


class LoginResponse(BaseModel):
    """Модель ответа авторизации"""
    access_token: str
    token_type: str
    expires_in: int
    user: AdminUserResponse


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    db: Session = Depends(get_db)
) -> AdminUser:
    """Получение текущего пользователя из токена"""
    token_data = verify_token(credentials.credentials)

    user = db.query(AdminUser).filter(
        AdminUser.username == token_data.username
    ).first()

    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Пользователь не найден"
        )

    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Неактивный пользователь"
        )

    return user


async def get_current_admin(
    current_user: AdminUser = Depends(get_current_user)
) -> AdminUser:
    """Проверка прав администратора"""
    if not current_user.is_superuser:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Недостаточно прав доступа"
        )
    return current_user


def authenticate_user(db: Session, username: str, password: str) -> AdminUser:
    """Аутентификация пользователя"""
    user = db.query(AdminUser).filter(AdminUser.username == username).first()

    if not user:
        return None

    if not verify_password(password, user.hashed_password):
        return None

    if not user.is_active:
        return None

    return user


@router.post("/login", response_model=LoginResponse)
async def login(
    login_data: LoginRequest,
    db: Session = Depends(get_db)
):
    """Авторизация пользователя"""
    user = authenticate_user(db, login_data.username, login_data.password)

    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Неверные учетные данные",
            headers={"WWW-Authenticate": "Bearer"},
        )

    # Обновляем время последнего входа
    user.last_login = datetime.utcnow()
    db.commit()

    # Создаем токен
    access_token_expires = timedelta(minutes=30)
    access_token = create_access_token(
        data={
            "sub": user.username,
            "user_id": user.id,
            "is_admin": user.is_superuser
        },
        expires_delta=access_token_expires
    )

    return LoginResponse(
        access_token=access_token,
        token_type="bearer",
        expires_in=1800,  # 30 минут
        user=AdminUserResponse.from_orm(user)
    )


@router.post("/refresh")
async def refresh_token(
    current_user: AdminUser = Depends(get_current_user)
):
    """Обновление токена"""
    access_token_expires = timedelta(minutes=30)
    access_token = create_access_token(
        data={
            "sub": current_user.username,
            "user_id": current_user.id,
            "is_admin": current_user.is_superuser
        },
        expires_delta=access_token_expires
    )

    return {
        "access_token": access_token,
        "token_type": "bearer",
        "expires_in": 1800
    }


@router.get("/me", response_model=AdminUserResponse)
async def get_me(current_user: AdminUser = Depends(get_current_user)):
    """Получение информации о текущем пользователе"""
    return AdminUserResponse.from_orm(current_user)


@router.post("/logout")
async def logout(current_user: AdminUser = Depends(get_current_user)):
    """Выход из системы"""
    # В реальном приложении здесь можно добавить токен в blacklist
    return {"message": "Успешный выход из системы"}


@router.post("/change-password")
async def change_password(
    old_password: str,
    new_password: str,
    current_user: AdminUser = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Смена пароля"""
    # Проверяем старый пароль
    if not verify_password(old_password, current_user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Неверный текущий пароль"
        )

    # Валидация нового пароля
    if len(new_password) < 8:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Пароль должен содержать минимум 8 символов"
        )

    # Обновляем пароль
    current_user.hashed_password = get_password_hash(new_password)
    current_user.updated_at = datetime.utcnow()
    db.commit()

    return {"message": "Пароль успешно изменен"}


@router.get("/verify")
async def verify_auth(current_user: AdminUser = Depends(get_current_user)):
    """Проверка действительности токена"""
    return {
        "valid": True,
        "user_id": current_user.id,
        "username": current_user.username,
        "is_admin": current_user.is_superuser
    }
