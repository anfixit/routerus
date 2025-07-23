from fastapi import APIRouter, Depends, HTTPException, status, BackgroundTasks
from sqlalchemy.orm import Session
from typing import List, Optional
import logging
from datetime import datetime

from ..core.database import get_db
from ..core.security import generate_vpn_user_id
from ..models.server import Server
from ..models.user import (
    VpnUser, VpnUserCreate, VpnUserUpdate, VpnUserResponse,
    VpnUserConfig, UserConnection, UserConnectionResponse,
    AdminUser, UserStatus
)
from ..api.auth import get_current_user
from ..services.xray import get_xray_manager

router = APIRouter()
logger = logging.getLogger(__name__)


@router.get("/", response_model=List[VpnUserResponse])
async def get_users(
    skip: int = 0,
    limit: int = 100,
    server_id: Optional[int] = None,
    status_filter: Optional[UserStatus] = None,
    search: Optional[str] = None,
    db: Session = Depends(get_db),
    current_user: AdminUser = Depends(get_current_user)
):
    """Получить список пользователей VPN"""

    query = db.query(VpnUser)

    # Фильтры
    if server_id:
        query = query.filter(VpnUser.server_id == server_id)

    if status_filter:
        query = query.filter(VpnUser.status == status_filter)

    if search:
        query = query.filter(
            VpnUser.email.contains(search) |
            VpnUser.name.contains(search)
        )

    users = query.offset(skip).limit(limit).all()

    return users


@router.post("/", response_model=VpnUserResponse)
async def create_user(
    user: VpnUserCreate,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: AdminUser = Depends(get_current_user)
):
    """Создать нового пользователя VPN"""

    # Проверяем существование сервера
    server = db.query(Server).filter(Server.id == user.server_id).first()
    if not server:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Сервер не найден"
        )

    # Проверяем лимит пользователей на сервере
    users_count = db.query(VpnUser).filter(
        VpnUser.server_id == user.server_id,
        VpnUser.is_active == True
    ).count()

    if users_count >= server.max_users:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Достигнут лимит пользователей на сервере ({server.max_users})"
        )

    # Проверяем уникальность email на сервере
    existing_user = db.query(VpnUser).filter(
        VpnUser.email == user.email,
        VpnUser.server_id == user.server_id
    ).first()

    if existing_user:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Пользователь с таким email уже существует на данном сервере"
        )

    # Генерируем UUID для VPN
    vpn_uuid = generate_vpn_user_id()

    # Создаем пользователя
    db_user = VpnUser(
        email=user.email,
        name=user.name,
        vpn_uuid=vpn_uuid,
        server_id=user.server_id,
        traffic_limit_gb=user.traffic_limit_gb,
        max_connections=user.max_connections,
        expires_at=user.expires_at,
        notes=user.notes,
        status=UserStatus.ACTIVE
    )

    db.add(db_user)
    db.commit()
    db.refresh(db_user)

    # Генерируем конфигурацию VPN в фоне
    background_tasks.add_task(
        generate_user_config,
        db_user.id,
        server.ip,
        db
    )

    # Обновляем статистику сервера
    server.total_users = users_count + 1
    db.commit()

    logger.info(f"Создан пользователь VPN: {user.email} на сервере {server.name}")

    return db_user


@router.get("/{user_id}", response_model=VpnUserResponse)
async def get_user(
    user_id: int,
    db: Session = Depends(get_db),
    current_user: AdminUser = Depends(get_current_user)
):
    """Получить информацию о пользователе"""

    user = db.query(VpnUser).filter(VpnUser.id == user_id).first()

    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Пользователь не найден"
        )

    return user


@router.put("/{user_id}", response_model=VpnUserResponse)
async def update_user(
    user_id: int,
    user_update: VpnUserUpdate,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: AdminUser = Depends(get_current_user)
):
    """Обновить пользователя"""

    user = db.query(VpnUser).filter(VpnUser.id == user_id).first()

    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Пользователь не найден"
        )

    # Обновляем поля
    update_data = user_update.dict(exclude_unset=True)
    for field, value in update_data.items():
        setattr(user, field, value)

    user.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(user)

    # Если изменился статус, обновляем конфигурацию сервера
    if 'status' in update_data or 'is_active' in update_data:
        background_tasks.add_task(update_server_config, user.server_id, db)

    logger.info(f"Обновлен пользователь VPN: {user.email}")

    return user


@router.delete("/{user_id}")
async def delete_user(
    user_id: int,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: AdminUser = Depends(get_current_user)
):
    """Удалить пользователя"""

    user = db.query(VpnUser).filter(VpnUser.id == user_id).first()

    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Пользователь не найден"
        )

    server_id = user.server_id
    user_email = user.email

    db.delete(user)
    db.commit()

    # Обновляем конфигурацию сервера
    background_tasks.add_task(update_server_config, server_id, db)

    # Обновляем статистику сервера
    server = db.query(Server).filter(Server.id == server_id).first()
    if server:
        active_users = db.query(VpnUser).filter(
            VpnUser.server_id == server_id,
            VpnUser.is_active == True
        ).count()
        server.total_users = active_users
        db.commit()

    logger.info(f"Удален пользователь VPN: {user_email}")

    return {"message": "Пользователь успешно удален"}


@router.get("/{user_id}/config", response_model=VpnUserConfig)
async def get_user_config(
    user_id: int,
    db: Session = Depends(get_db),
    current_user: AdminUser = Depends(get_current_user)
):
    """Получить конфигурацию пользователя для подключения"""

    user = db.query(VpnUser).filter(VpnUser.id == user_id).first()

    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Пользователь не найден"
        )

    server = db.query(Server).filter(Server.id == user.server_id).first()

    # Если конфигурация не сгенерирована, создаем её
    if not user.config_url or not user.qr_code:
        xray_manager = get_xray_manager()

        try:
            config_url, qr_code = await xray_manager.add_user({
                "vpn_uuid": user.vpn_uuid,
                "email": user.email
            })

            user.config_url = config_url
            user.qr_code = qr_code
            db.commit()

        except Exception as e:
            logger.error(f"Ошибка генерации конфигурации для пользователя {user_id}: {e}")
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Ошибка генерации конфигурации"
            )

    return VpnUserConfig(
        vpn_uuid=user.vpn_uuid,
        config_url=user.config_url,
        qr_code=user.qr_code,
        server_ip=server.ip,
        server_name=server.name
    )


@router.post("/{user_id}/regenerate-config")
async def regenerate_user_config(
    user_id: int,
    db: Session = Depends(get_db),
    current_user: AdminUser = Depends(get_current_user)
):
    """Перегенерировать конфигурацию пользователя"""

    user = db.query(VpnUser).filter(VpnUser.id == user_id).first()

    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Пользователь не найден"
        )

    # Генерируем новый UUID
    user.vpn_uuid = generate_vpn_user_id()

    # Генерируем новую конфигурацию
    xray_manager = get_xray_manager()

    try:
        config_url, qr_code = await xray_manager.add_user({
            "vpn_uuid": user.vpn_uuid,
            "email": user.email
        })

        user.config_url = config_url
        user.qr_code = qr_code
        user.updated_at = datetime.utcnow()

        db.commit()

        logger.info(f"Перегенерирована конфигурация для пользователя: {user.email}")

        return {
            "message": "Конфигурация успешно перегенерирована",
            "new_uuid": user.vpn_uuid
        }

    except Exception as e:
        logger.error(f"Ошибка перегенерации конфигурации для пользователя {user_id}: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Ошибка перегенерации конфигурации"
        )


@router.get("/{user_id}/connections", response_model=List[UserConnectionResponse])
async def get_user_connections(
    user_id: int,
    limit: int = 50,
    db: Session = Depends(get_db),
    current_user: AdminUser = Depends(get_current_user)
):
    """Получить историю подключений пользователя"""

    user = db.query(VpnUser).filter(VpnUser.id == user_id).first()

    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Пользователь не найден"
        )

    connections = db.query(UserConnection).filter(
        UserConnection.user_id == user_id
    ).order_by(UserConnection.connected_at.desc()).limit(limit).all()

    return connections


@router.post("/{user_id}/suspend")
async def suspend_user(
    user_id: int,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: AdminUser = Depends(get_current_user)
):
    """Приостановить пользователя"""

    user = db.query(VpnUser).filter(VpnUser.id == user_id).first()

    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Пользователь не найден"
        )

    user.status = UserStatus.SUSPENDED
    user.updated_at = datetime.utcnow()
    db.commit()

    # Обновляем конфигурацию сервера
    background_tasks.add_task(update_server_config, user.server_id, db)

    logger.info(f"Приостановлен пользователь: {user.email}")

    return {"message": "Пользователь приостановлен"}


@router.post("/{user_id}/activate")
async def activate_user(
    user_id: int,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: AdminUser = Depends(get_current_user)
):
    """Активировать пользователя"""

    user = db.query(VpnUser).filter(VpnUser.id == user_id).first()

    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Пользователь не найден"
        )

    user.status = UserStatus.ACTIVE
    user.is_active = True
    user.updated_at = datetime.utcnow()
    db.commit()

    # Обновляем конфигурацию сервера
    background_tasks.add_task(update_server_config, user.server_id, db)

    logger.info(f"Активирован пользователь: {user.email}")

    return {"message": "Пользователь активирован"}


async def generate_user_config(user_id: int, server_ip: str, db: Session):
    """Фоновая задача генерации конфигурации пользователя"""
    try:
        user = db.query(VpnUser).filter(VpnUser.id == user_id).first()
        if not user:
            return

        xray_manager = get_xray_manager()
        config_url, qr_code = await xray_manager.add_user({
            "vpn_uuid": user.vpn_uuid,
            "email": user.email
        })

        user.config_url = config_url
        user.qr_code = qr_code
        db.commit()

        logger.info(f"Сгенерирована конфигурация для пользователя: {user.email}")

    except Exception as e:
        logger.error(f"Ошибка генерации конфигурации для пользователя {user_id}: {e}")


async def update_server_config(server_id: int, db: Session):
    """Фоновая задача обновления конфигурации сервера"""
    try:
        # Получаем всех активных пользователей сервера
        users = db.query(VpnUser).filter(
            VpnUser.server_id == server_id,
            VpnUser.is_active == True,
            VpnUser.status == UserStatus.ACTIVE
        ).all()

        # Подготавливаем данные пользователей
        users_data = []
        for user in users:
            users_data.append({
                "vpn_uuid": user.vpn_uuid,
                "email": user.email
            })

        # Обновляем конфигурацию Xray
        xray_manager = get_xray_manager()
        await xray_manager.update_server_config(users_data)

        logger.info(f"Обновлена конфигурация сервера {server_id}")

    except Exception as e:
        logger.error(f"Ошибка обновления конфигурации сервера {server_id}: {e}")
