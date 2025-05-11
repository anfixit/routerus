from typing import Any, List, Optional

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.api.deps import get_db, get_current_admin_user, get_current_active_user
from app.crud import user
from app.models.user import User
from app.schemas.user import User as UserSchema, UserCreate, UserUpdate
from app.core.logging.logger import auth_logger

router = APIRouter()


@router.get("/", response_model=List[UserSchema])
def read_users(
    db: Session = Depends(get_db),
    skip: int = 0,
    limit: int = 100,
    current_user: User = Depends(get_current_admin_user),
) -> Any:
    """
    Получить список пользователей (только для администраторов)
    """
    users = user.get_multi(db, skip=skip, limit=limit)
    return users


@router.post("/", response_model=UserSchema)
def create_user(
    *,
    db: Session = Depends(get_db),
    user_in: UserCreate,
    current_user: User = Depends(get_current_admin_user),
) -> Any:
    """
    Создать нового пользователя (только для администраторов)
    """
    existing_user = user.get_by_username(db, username=user_in.username)
    if existing_user:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Пользователь с таким именем уже существует",
        )
    
    if user_in.email:
        existing_email = user.get_by_email(db, email=user_in.email)
        if existing_email:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Пользователь с таким email уже существует",
            )
    
    new_user = user.create(db, obj_in=user_in)
    auth_logger.log_audit(
        action="create_user",
        user_id=current_user.id,
        details={"created_user_id": new_user.id, "username": new_user.username}
    )
    return new_user


@router.get("/me", response_model=UserSchema)
def read_user_me(
    current_user: User = Depends(get_current_active_user),
) -> Any:
    """
    Получить информацию о текущем пользователе
    """
    return current_user


@router.put("/me", response_model=UserSchema)
def update_user_me(
    *,
    db: Session = Depends(get_db),
    user_in: UserUpdate,
    current_user: User = Depends(get_current_active_user),
) -> Any:
    """
    Обновить информацию о текущем пользователе
    """
    updated_user = user.update(db, db_obj=current_user, obj_in=user_in)
    auth_logger.log_audit(
        action="update_user_self",
        user_id=current_user.id,
        details={"updated_fields": [k for k, v in user_in.dict(exclude_unset=True).items()]}
    )
    return updated_user


@router.get("/{user_id}", response_model=UserSchema)
def read_user_by_id(
    user_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> Any:
    """
    Получить пользователя по ID
    """
    if user_id != current_user.id and not user.is_admin(current_user):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Недостаточно прав для выполнения операции",
        )
    
    db_user = user.get(db, id=user_id)
    if not db_user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Пользователь не найден",
        )
    
    return db_user


@router.put("/{user_id}", response_model=UserSchema)
def update_user(
    *,
    db: Session = Depends(get_db),
    user_id: int,
    user_in: UserUpdate,
    current_user: User = Depends(get_current_admin_user),
) -> Any:
    """
    Обновить пользователя (только для администраторов)
    """
    db_user = user.get(db, id=user_id)
    if not db_user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Пользователь не найден",
        )
    
    updated_user = user.update(db, db_obj=db_user, obj_in=user_in)
    auth_logger.log_audit(
        action="update_user",
        user_id=current_user.id,
        details={
            "updated_user_id": user_id,
            "updated_fields": [k for k, v in user_in.dict(exclude_unset=True).items()]
        }
    )
    return updated_user


@router.delete("/{user_id}", response_model=UserSchema)
def delete_user(
    *,
    db: Session = Depends(get_db),
    user_id: int,
    current_user: User = Depends(get_current_admin_user),
) -> Any:
    """
    Удалить пользователя (только для администраторов)
    """
    db_user = user.get(db, id=user_id)
    if not db_user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Пользователь не найден",
        )
    
    deleted_user = user.remove(db, id=user_id)
    auth_logger.log_audit(
        action="delete_user",
        user_id=current_user.id,
        details={"deleted_user_id": user_id, "username": db_user.username}
    )
    return deleted_user
