from typing import Any, Dict

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.api.deps import get_db, get_current_admin_user
from app.models.user import User
from app.models.config import VPNType
from app.core.metrics import ACTIVE_USERS, CONFIG_COUNT

router = APIRouter()


@router.get("/")
def get_metrics(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_admin_user),
) -> Dict[str, Any]:
    """
    Получить основные метрики системы (только для администраторов)
    """
    # Запрос к базе данных для получения актуальных данных
    from app.models.user import User
    from app.models.config import VPNConfig
    import sqlalchemy as sa
    
    # Количество активных пользователей
    active_users_count = db.query(sa.func.count(User.id)).filter(User.is_active == True).scalar()
    
    # Количество конфигураций по типам
    wireguard_count = db.query(sa.func.count(VPNConfig.id)).filter(
        VPNConfig.vpn_type == VPNType.WIREGUARD, 
        VPNConfig.is_active == True
    ).scalar()
    
    shadowsocks_count = db.query(sa.func.count(VPNConfig.id)).filter(
        VPNConfig.vpn_type == VPNType.SHADOWSOCKS, 
        VPNConfig.is_active == True
    ).scalar()
    
    xray_count = db.query(sa.func.count(VPNConfig.id)).filter(
        VPNConfig.vpn_type == VPNType.XRAY, 
        VPNConfig.is_active == True
    ).scalar()
    
    # Обновление Prometheus метрик
    ACTIVE_USERS.set(active_users_count)
    CONFIG_COUNT.labels(type="wireguard").set(wireguard_count)
    CONFIG_COUNT.labels(type="shadowsocks").set(shadowsocks_count)
    CONFIG_COUNT.labels(type="xray").set(xray_count)
    
    # Возвращаем метрики в формате JSON
    return {
        "active_users": active_users_count,
        "active_configs": {
            "wireguard": wireguard_count,
            "shadowsocks": shadowsocks_count,
            "xray": xray_count,
            "total": wireguard_count + shadowsocks_count + xray_count
        }
    }
