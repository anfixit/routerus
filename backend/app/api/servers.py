from fastapi import APIRouter, Depends, HTTPException, status, BackgroundTasks
from sqlalchemy.orm import Session
from typing import List, Optional
import httpx
import asyncio
import logging
from datetime import datetime

from ..core.database import get_db
from ..core.security import generate_reality_keys, generate_short_ids
from ..models.server import (
    Server, ServerCreate, ServerUpdate, ServerResponse,
    ServerStats, ServerStatsResponse, ServerStatus
)
from ..models.user import AdminUser, VpnUser
from ..api.auth import get_current_user
from ..services.xray import get_xray_manager

router = APIRouter()
logger = logging.getLogger(__name__)


async def check_server_status(server_ip: str, port: int = 443) -> ServerStatus:
    """Проверка статуса VPN сервера"""
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            # Пытаемся подключиться к серверу
            response = await client.get(
                f"http://{server_ip}:8080/health",
                timeout=5.0
            )
            if response.status_code == 200:
                return ServerStatus.ONLINE
            else:
                return ServerStatus.OFFLINE
    except:
        # Если API недоступен, пробуем порт VPN
        try:
            async with httpx.AsyncClient(timeout=3.0) as client:
                await client.get(f"https://{server_ip}:{port}", verify=False)
                return ServerStatus.ONLINE
        except:
            return ServerStatus.OFFLINE


@router.get("/", response_model=List[ServerResponse])
async def get_servers(
    skip: int = 0,
    limit: int = 100,
    db: Session = Depends(get_db),
    current_user: AdminUser = Depends(get_current_user)
):
    """Получить список всех VPN серверов"""
    servers = db.query(Server).offset(skip).limit(limit).all()

    # Обновляем статус серверов асинхронно
    for server in servers:
        # Здесь можно добавить фоновую задачу для проверки статуса
        pass

    return servers


@router.post("/", response_model=ServerResponse)
async def create_server(
    server: ServerCreate,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: AdminUser = Depends(get_current_user)
):
    """Создать новый VPN сервер"""

    # Проверяем уникальность IP
    existing_server = db.query(Server).filter(Server.ip == server.ip).first()
    if existing_server:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Сервер с таким IP уже существует"
        )

    # Генерируем ключи Reality если не заданы
    private_key, public_key = generate_reality_keys()
    short_ids = generate_short_ids()

    # Создаем сервер
    db_server = Server(
        name=server.name,
        ip=server.ip,
        port=server.port,
        location=server.location,
        country_code=server.country_code,
        description=server.description,
        max_users=server.max_users,
        max_traffic_gb=server.max_traffic_gb,
        reality_dest=server.reality_dest,
        reality_server_name=server.reality_server_name,
        reality_private_key=private_key,
        reality_public_key=public_key,
        reality_short_ids=",".join(short_ids),
        status=ServerStatus.UNKNOWN
    )

    db.add(db_server)
    db.commit()
    db.refresh(db_server)

    # Проверяем статус сервера в фоне
    background_tasks.add_task(update_server_status, db_server.id, db)

    logger.info(f"Создан новый сервер: {server.name} ({server.ip})")

    return db_server


@router.get("/{server_id}", response_model=ServerResponse)
async def get_server(
    server_id: int,
    db: Session = Depends(get_db),
    current_user: AdminUser = Depends(get_current_user)
):
    """Получить информацию о сервере"""
    server = db.query(Server).filter(Server.id == server_id).first()

    if not server:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Сервер не найден"
        )

    return server


@router.put("/{server_id}", response_model=ServerResponse)
async def update_server(
    server_id: int,
    server_update: ServerUpdate,
    db: Session = Depends(get_db),
    current_user: AdminUser = Depends(get_current_user)
):
    """Обновить сервер"""
    server = db.query(Server).filter(Server.id == server_id).first()

    if not server:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Сервер не найден"
        )

    # Обновляем поля
    update_data = server_update.dict(exclude_unset=True)
    for field, value in update_data.items():
        setattr(server, field, value)

    server.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(server)

    logger.info(f"Обновлен сервер: {server.name}")

    return server


@router.delete("/{server_id}")
async def delete_server(
    server_id: int,
    db: Session = Depends(get_db),
    current_user: AdminUser = Depends(get_current_user)
):
    """Удалить сервер"""
    server = db.query(Server).filter(Server.id == server_id).first()

    if not server:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Сервер не найден"
        )

    # Проверяем есть ли пользователи на сервере
    users_count = db.query(VpnUser).filter(VpnUser.server_id == server_id).count()
    if users_count > 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"На сервере есть {users_count} пользователей. Сначала удалите их."
        )

    db.delete(server)
    db.commit()

    logger.info(f"Удален сервер: {server.name}")

    return {"message": "Сервер успешно удален"}


@router.post("/{server_id}/check-status")
async def check_server_status_endpoint(
    server_id: int,
    db: Session = Depends(get_db),
    current_user: AdminUser = Depends(get_current_user)
):
    """Проверить статус сервера"""
    server = db.query(Server).filter(Server.id == server_id).first()

    if not server:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Сервер не найден"
        )

    # Проверяем статус
    new_status = await check_server_status(server.ip, server.port)

    # Обновляем в БД
    server.status = new_status
    server.last_check = datetime.utcnow()
    db.commit()

    return {
        "server_id": server_id,
        "status": new_status,
        "checked_at": server.last_check
    }


@router.get("/{server_id}/stats", response_model=List[ServerStatsResponse])
async def get_server_stats(
    server_id: int,
    hours: int = 24,
    db: Session = Depends(get_db),
    current_user: AdminUser = Depends(get_current_user)
):
    """Получить статистику сервера"""
    server = db.query(Server).filter(Server.id == server_id).first()

    if not server:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Сервер не найден"
        )

    # Получаем статистику за последние N часов
    from datetime import timedelta
    since = datetime.utcnow() - timedelta(hours=hours)

    stats = db.query(ServerStats).filter(
        ServerStats.server_id == server_id,
        ServerStats.timestamp >= since
    ).order_by(ServerStats.timestamp.desc()).all()

    return stats


@router.post("/{server_id}/deploy")
async def get_deploy_command(
    server_id: int,
    db: Session = Depends(get_db),
    current_user: AdminUser = Depends(get_current_user)
):
    """Получить команду для развертывания сервера"""
    server = db.query(Server).filter(Server.id == server_id).first()

    if not server:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Сервер не найден"
        )

    # Генерируем команду развертывания
    deploy_command = f"curl -fsSL https://raw.githubusercontent.com/your-repo/routerus-v2/main/scripts/quick-deploy.sh | bash -s -- {server.ip}"

    return {
        "server_id": server_id,
        "server_ip": server.ip,
        "deploy_command": deploy_command,
        "instructions": [
            f"1. Подключитесь к серверу: ssh root@{server.ip}",
            "2. Выполните команду развертывания:",
            f"   {deploy_command}",
            "3. Дождитесь завершения установки (5-10 минут)",
            "4. Сервер будет готов к добавлению пользователей"
        ],
        "environment_variables": {
            "VPN_SERVER_IP": server.ip,
            "REALITY_PRIVATE_KEY": server.reality_private_key,
            "REALITY_PUBLIC_KEY": server.reality_public_key,
            "REALITY_SHORT_IDS": server.reality_short_ids
        }
    }


@router.post("/{server_id}/update-config")
async def update_server_config(
    server_id: int,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: AdminUser = Depends(get_current_user)
):
    """Обновить конфигурацию Xray на сервере"""
    server = db.query(Server).filter(Server.id == server_id).first()

    if not server:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Сервер не найден"
        )

    # Получаем всех активных пользователей сервера
    users = db.query(VpnUser).filter(
        VpnUser.server_id == server_id,
        VpnUser.is_active == True
    ).all()

    # Подготавливаем данные пользователей
    users_data = []
    for user in users:
        users_data.append({
            "vpn_uuid": user.vpn_uuid,
            "email": user.email
        })

    # Обновляем конфигурацию в фоне
    background_tasks.add_task(
        update_xray_config,
        server.ip,
        users_data,
        server.reality_private_key,
        server.reality_public_key,
        server.reality_short_ids.split(",") if server.reality_short_ids else []
    )

    return {"message": "Конфигурация сервера будет обновлена"}


async def update_server_status(server_id: int, db: Session):
    """Фоновая задача обновления статуса сервера"""
    try:
        server = db.query(Server).filter(Server.id == server_id).first()
        if server:
            status = await check_server_status(server.ip, server.port)
            server.status = status
            server.last_check = datetime.utcnow()
            db.commit()
    except Exception as e:
        logger.error(f"Ошибка обновления статуса сервера {server_id}: {e}")


async def update_xray_config(
    server_ip: str,
    users_data: List[dict],
    private_key: str,
    public_key: str,
    short_ids: List[str]
):
    """Фоновая задача обновления конфигурации Xray"""
    try:
        xray_manager = get_xray_manager()
        success = await xray_manager.update_server_config(users_data)

        if success:
            logger.info(f"Конфигурация сервера {server_ip} обновлена")
        else:
            logger.error(f"Ошибка обновления конфигурации сервера {server_ip}")

    except Exception as e:
        logger.error(f"Ошибка обновления конфигурации Xray для {server_ip}: {e}")
