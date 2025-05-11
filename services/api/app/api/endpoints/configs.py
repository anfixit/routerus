from typing import Any, List, Optional
from datetime import datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException, status, Query, Body
from sqlalchemy.orm import Session

from app.api.deps import get_db, get_current_active_user, get_current_admin_user
from app.crud import vpn_config
from app.models.user import User
from app.models.config import VPNType
from app.schemas.config import VPNConfig, VPNConfigCreate, VPNConfigUpdate, VPNConfigWithQR
from app.core.logging.logger import vpn_logger

router = APIRouter()


@router.get("/", response_model=List[VPNConfig])
def read_configs(
    db: Session = Depends(get_db),
    skip: int = 0,
    limit: int = 100,
    current_user: User = Depends(get_current_active_user),
) -> Any:
    """
    Получить список VPN конфигураций.
    Администраторы видят все конфигурации, обычные пользователи - только свои.
    """
    if current_user.is_admin:
        configs = vpn_config.get_multi(db, skip=skip, limit=limit)
    else:
        configs = vpn_config.get_multi_by_user(
            db, user_id=current_user.id, skip=skip, limit=limit
        )
    return configs


@router.post("/wireguard", response_model=VPNConfigWithQR)
def create_wireguard_config(
    *,
    db: Session = Depends(get_db),
    name: str = Body(...),
    user_id: Optional[int] = Body(None),
    duration_days: Optional[int] = Body(None),
    current_user: User = Depends(get_current_active_user),
) -> Any:
    """
    Создать новую WireGuard конфигурацию.
    Администраторы могут создавать для любого пользователя, обычные пользователи - только для себя.
    """
    # Определяем для какого пользователя создается конфигурация
    target_user_id = user_id if current_user.is_admin and user_id else current_user.id
    
    # Если указана продолжительность в днях, вычисляем дату истечения
    expires_at = None
    if duration_days is not None and duration_days > 0:
        expires_at = datetime.utcnow() + timedelta(days=duration_days)
    
    # Создаем конфигурацию
    new_config = vpn_config.create_wireguard_config(
        db, user_id=target_user_id, name=name, expires_at=expires_at
    )
    
    vpn_logger.log_audit(
        action="create_wireguard_config",
        user_id=current_user.id,
        details={
            "config_id": new_config.id,
            "name": name,
            "user_id": target_user_id,
            "expires_at": expires_at.isoformat() if expires_at else None
        }
    )
    
    # Получаем QR-код для конфигурации
    import base64
    import json
    import qrcode
    from io import BytesIO
    
    # Создаем QR-код
    qr = qrcode.QRCode(
        version=1,
        error_correction=qrcode.constants.ERROR_CORRECT_L,
        box_size=10,
        border=4,
    )
    qr.add_data(new_config.config_data)
    qr.make(fit=True)
    
    img = qr.make_image(fill_color="black", back_color="white")
    buffer = BytesIO()
    img.save(buffer, format="PNG")
    qr_code_base64 = base64.b64encode(buffer.getvalue()).decode("utf-8")
    
    # Возвращаем объект с конфигурацией и QR-кодом
    return {
        **new_config.__dict__,
        "qr_code": qr_code_base64
    }


@router.post("/shadowsocks", response_model=VPNConfigWithQR)
def create_shadowsocks_config(
    *,
    db: Session = Depends(get_db),
    name: str = Body(...),
    user_id: Optional[int] = Body(None),
    duration_days: Optional[int] = Body(None),
    current_user: User = Depends(get_current_active_user),
) -> Any:
    """
    Создать новую Shadowsocks конфигурацию.
    Администраторы могут создавать для любого пользователя, обычные пользователи - только для себя.
    """
    # Определяем для какого пользователя создается конфигурация
    target_user_id = user_id if current_user.is_admin and user_id else current_user.id
    
    # Если указана продолжительность в днях, вычисляем дату истечения
    expires_at = None
    if duration_days is not None and duration_days > 0:
        expires_at = datetime.utcnow() + timedelta(days=duration_days)
    
    # Создаем конфигурацию
    new_config = vpn_config.create_shadowsocks_config(
        db, user_id=target_user_id, name=name, expires_at=expires_at
    )
    
    vpn_logger.log_audit(
        action="create_shadowsocks_config",
        user_id=current_user.id,
        details={
            "config_id": new_config.id,
            "name": name,
            "user_id": target_user_id,
            "expires_at": expires_at.isoformat() if expires_at else None
        }
    )
    
    # Получаем QR-код для конфигурации
    import base64
    import json
    import qrcode
    from io import BytesIO
    
    # Создаем URI для QR-кода
    config_data = json.loads(new_config.config_data)
    ss_uri = f"{config_data['method']}:{config_data['password']}@{config_data['server']}:{config_data['server_port']}"
    ss_uri_encoded = base64.urlsafe_b64encode(ss_uri.encode()).decode()
    ss_uri_full = f"ss://{ss_uri_encoded}#{config_data['remarks']}"
    
    # Создаем QR-код
    qr = qrcode.QRCode(
        version=1,
        error_correction=qrcode.constants.ERROR_CORRECT_L,
        box_size=10,
        border=4,
    )
    qr.add_data(ss_uri_full)
    qr.make(fit=True)
    
    img = qr.make_image(fill_color="black", back_color="white")
    buffer = BytesIO()
    img.save(buffer, format="PNG")
    qr_code_base64 = base64.b64encode(buffer.getvalue()).decode("utf-8")
    
    # Возвращаем объект с конфигурацией и QR-кодом
    return {
        **new_config.__dict__,
        "qr_code": qr_code_base64
    }


@router.post("/xray", response_model=VPNConfigWithQR)
def create_xray_config(
    *,
    db: Session = Depends(get_db),
    name: str = Body(...),
    user_id: Optional[int] = Body(None),
    duration_days: Optional[int] = Body(None),
    current_user: User = Depends(get_current_active_user),
) -> Any:
    """
    Создать новую Xray (VLESS) конфигурацию.
    Администраторы могут создавать для любого пользователя, обычные пользователи - только для себя.
    """
    # Определяем для какого пользователя создается конфигурация
    target_user_id = user_id if current_user.is_admin and user_id else current_user.id
    
    # Если указана продолжительность в днях, вычисляем дату истечения
    expires_at = None
    if duration_days is not None and duration_days > 0:
        expires_at = datetime.utcnow() + timedelta(days=duration_days)
    
    # Создаем конфигурацию
    new_config = vpn_config.create_xray_config(
        db, user_id=target_user_id, name=name, expires_at=expires_at
    )
    
    vpn_logger.log_audit(
        action="create_xray_config",
        user_id=current_user.id,
        details={
            "config_id": new_config.id,
            "name": name,
            "user_id": target_user_id,
            "expires_at": expires_at.isoformat() if expires_at else None
        }
    )
    
    # Получаем QR-код для конфигурации
    import base64
    import json
    import qrcode
    from io import BytesIO
    
    # Создаем URI для QR-кода
    config_data = json.loads(new_config.config_data)
    vless_link = f"vless://{new_config.uuid}@{config_data['outbounds'][0]['settings']['vnext'][0]['address']}:{config_data['outbounds'][0]['settings']['vnext'][0]['port']}?type=ws&security=tls&path=/ws&host={config_data['outbounds'][0]['streamSettings']['wsSettings']['headers']['Host']}&sni={config_data['outbounds'][0]['streamSettings']['tlsSettings']['serverName']}#{name}"
    
    # Создаем QR-код
    qr = qrcode.QRCode(
        version=1,
        error_correction=qrcode.constants.ERROR_CORRECT_L,
        box_size=10,
        border=4,
    )
    qr.add_data(vless_link)
    qr.make(fit=True)
    
    img = qr.make_image(fill_color="black", back_color="white")
    buffer = BytesIO()
    img.save(buffer, format="PNG")
    qr_code_base64 = base64.b64encode(buffer.getvalue()).decode("utf-8")
    
    # Возвращаем объект с конфигурацией и QR-кодом
    return {
        **new_config.__dict__,
        "qr_code": qr_code_base64
    }


@router.get("/{config_id}", response_model=VPNConfigWithQR)
def read_config(
    *,
    db: Session = Depends(get_db),
    config_id: int,
    current_user: User = Depends(get_current_active_user),
) -> Any:
    """
    Получить VPN конфигурацию по ID.
    Администраторы могут видеть любую конфигурацию, обычные пользователи - только свои.
    """
    config = vpn_config.get(db, id=config_id)
    if not config:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Конфигурация не найдена",
        )
    
    if not current_user.is_admin and config.user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Недостаточно прав для доступа к этой конфигурации",
        )
    
    # Получаем QR-код для конфигурации
    import base64
    import json
    import qrcode
    from io import BytesIO
    
    # Создаем QR-код в зависимости от типа VPN
    qr = qrcode.QRCode(
        version=1,
        error_correction=qrcode.constants.ERROR_CORRECT_L,
        box_size=10,
        border=4,
    )
    
    if config.vpn_type == VPNType.WIREGUARD:
        qr_data = config.config_data
    elif config.vpn_type == VPNType.SHADOWSOCKS:
        config_data = json.loads(config.config_data)
        ss_uri = f"{config_data['method']}:{config_data['password']}@{config_data['server']}:{config_data['server_port']}"
        ss_uri_encoded = base64.urlsafe_b64encode(ss_uri.encode()).decode()
        qr_data = f"ss://{ss_uri_encoded}#{config_data['remarks']}"
    elif config.vpn_type == VPNType.XRAY:
        config_data = json.loads(config.config_data)
        qr_data = f"vless://{config.uuid}@{config_data['outbounds'][0]['settings']['vnext'][0]['address']}:{config_data['outbounds'][0]['settings']['vnext'][0]['port']}?type=ws&security=tls&path=/ws&host={config_data['outbounds'][0]['streamSettings']['wsSettings']['headers']['Host']}&sni={config_data['outbounds'][0]['streamSettings']['tlsSettings']['serverName']}#{config.name}"
    
    qr.add_data(qr_data)
    qr.make(fit=True)
    
    img = qr.make_image(fill_color="black", back_color="white")
    buffer = BytesIO()
    img.save(buffer, format="PNG")
    qr_code_base64 = base64.b64encode(buffer.getvalue()).decode("utf-8")
    
    # Возвращаем объект с конфигурацией и QR-кодом
    return {
        **config.__dict__,
        "qr_code": qr_code_base64
    }


@router.put("/{config_id}", response_model=VPNConfig)
def update_config(
    *,
    db: Session = Depends(get_db),
    config_id: int,
    config_in: VPNConfigUpdate,
    current_user: User = Depends(get_current_active_user),
) -> Any:
    """
    Обновить VPN конфигурацию.
    Администраторы могут обновлять любую конфигурацию, обычные пользователи - только свои.
    """
    config = vpn_config.get(db, id=config_id)
    if not config:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Конфигурация не найдена",
        )
    
    if not current_user.is_admin and config.user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Недостаточно прав для обновления этой конфигурации",
        )
    
    updated_config = vpn_config.update(db, db_obj=config, obj_in=config_in)
    
    vpn_logger.log_audit(
        action="update_config",
        user_id=current_user.id,
        details={
            "config_id": config_id,
            "updated_fields": [k for k, v in config_in.dict(exclude_unset=True).items()]
        }
    )
    
    return updated_config


@router.delete("/{config_id}", response_model=VPNConfig)
def delete_config(
    *,
    db: Session = Depends(get_db),
    config_id: int,
    current_user: User = Depends(get_current_active_user),
) -> Any:
    """
    Удалить VPN конфигурацию.
    Администраторы могут удалять любую конфигурацию, обычные пользователи - только свои.
    """
    config = vpn_config.get(db, id=config_id)
    if not config:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Конфигурация не найдена",
        )
    
    if not current_user.is_admin and config.user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Недостаточно прав для удаления этой конфигурации",
        )
    
    config_info = {
        "id": config.id,
        "name": config.name,
        "vpn_type": config.vpn_type,
        "user_id": config.user_id
    }
    
    deleted_config = vpn_config.remove(db, id=config_id)
    
    vpn_logger.log_audit(
        action="delete_config",
        user_id=current_user.id,
        details=config_info
    )
    
    return deleted_config
