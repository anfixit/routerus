from datetime import timedelta
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session

from app.api.deps import get_db, get_current_user
from app.core.config import settings
from app.core.security import create_access_token
from app.crud import user
from app.schemas.token import Token
from app.models.user import User

router = APIRouter()


@router.post("/login/access-token", response_model=Token)
def login_access_token(
    db: Session = Depends(get_db), form_data: OAuth2PasswordRequestForm = Depends()
) -> Any:
    """
    OAuth2 совместимый токен логина, получение access token для пользователя
    """
    authenticated_user = user.authenticate(
        db, username=form_data.username, password=form_data.password
    )
    if not authenticated_user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Неверное имя пользователя или пароль",
        )
    elif not user.is_active(authenticated_user):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Неактивный пользователь",
        )
    
    access_token_expires = timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    return {
        "access_token": create_access_token(
            authenticated_user.id, expires_delta=access_token_expires
        ),
        "token_type": "bearer",
    }


@router.get("/login/test-token", response_model=dict)
def test_token(current_user: User = Depends(get_current_user)) -> Any:
    """
    Тест валидности токена
    """
    return {"username": current_user.username, "msg": "Токен действителен"}
