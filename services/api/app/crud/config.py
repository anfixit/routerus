from typing import List, Optional, Dict, Any, Union
from datetime import datetime

from sqlalchemy.orm import Session

from app.crud.base import CRUDBase
from app.models.config import VPNConfig, VPNType
from app.schemas.config import VPNConfigCreate, VPNConfigUpdate
from app.vpn.wireguard import wireguard_manager
from app.vpn.shadowsocks import shadowsocks_manager
from app.vpn.xray import xray_manager


class CRUDVPNConfig(CRUDBase[VPNConfig, VPNConfigCreate, VPNConfigUpdate]):
    def get_multi_by_user(
        self, db: Session, *, user_id: int, skip: int = 0, limit: int = 100
    ) -> List[VPNConfig]:
        return (
            db.query(self.model)
            .filter(VPNConfig.user_id == user_id)
            .offset(skip)
            .limit(limit)
            .all()
        )
    
    def get_all_active(self, db: Session) -> List[VPNConfig]:
        return db.query(self.model).filter(VPNConfig.is_active == True).all()
    
    def create_wireguard_config(
        self, db: Session, *, user_id: int, name: str, expires_at: Optional[datetime] = None
    ) -> VPNConfig:
        # Получаем все существующие wireguard конфигурации для правильного назначения IP
        existing_configs = [
            {
                "ip_address": config.ip_address,
                "vpn_type": config.vpn_type
            }
            for config in db.query(VPNConfig).filter(VPNConfig.vpn_type == VPNType.WIREGUARD).all()
        ]
        
        # Создаем конфигурацию WireGuard
        wg_config = wireguard_manager.create_client_config(name, existing_configs)
        
        # Создаем запись в базе данных
        db_obj = VPNConfig(
            name=name,
            vpn_type=VPNType.WIREGUARD,
            config_data=wg_config["config_data"],
            private_key=wg_config["private_key"],
            public_key=wg_config["public_key"],
            ip_address=wg_config["ip_address"],
            user_id=user_id,
            expires_at=expires_at,
            is_active=True
        )
        
        db.add(db_obj)
        db.commit()
        db.refresh(db_obj)
        
        # Обновляем серверную конфигурацию
        self._update_server_configs(db)
        
        return db_obj
    
    def create_shadowsocks_config(
        self, db: Session, *, user_id: int, name: str, expires_at: Optional[datetime] = None
    ) -> VPNConfig:
        # Создаем конфигурацию Shadowsocks
        ss_config = shadowsocks_manager.create_client_config(name)
        
        # Создаем запись в базе данных
        db_obj = VPNConfig(
            name=name,
            vpn_type=VPNType.SHADOWSOCKS,
            config_data=ss_config["config_data"],
            password=ss_config["password"],
            port=ss_config["port"],
            user_id=user_id,
            expires_at=expires_at,
            is_active=True
        )
        
        db.add(db_obj)
        db.commit()
        db.refresh(db_obj)
        
        # Обновляем серверную конфигурацию
        self._update_server_configs(db)
        
        return db_obj
    
    def create_xray_config(
        self, db: Session, *, user_id: int, name: str, expires_at: Optional[datetime] = None
    ) -> VPNConfig:
        # Создаем конфигурацию Xray
        xray_config = xray_manager.create_client_config(name)
        
        # Создаем запись в базе данных
        db_obj = VPNConfig(
            name=name,
            vpn_type=VPNType.XRAY,
            config_data=xray_config["config_data"],
            uuid=xray_config["uuid"],
            user_id=user_id,
            expires_at=expires_at,
            is_active=True
        )
        
        db.add(db_obj)
        db.commit()
        db.refresh(db_obj)
        
        # Обновляем серверную конфигурацию
        self._update_server_configs(db)
        
        return db_obj
    
    def update(
        self, db: Session, *, db_obj: VPNConfig, obj_in: Union[VPNConfigUpdate, Dict[str, Any]]
    ) -> VPNConfig:
        updated = super().update(db, db_obj=db_obj, obj_in=obj_in)
        
        # Обновляем серверную конфигурацию, если изменился статус активности
        if isinstance(obj_in, dict) and "is_active" in obj_in:
            self._update_server_configs(db)
        elif hasattr(obj_in, "is_active") and obj_in.is_active is not None:
            self._update_server_configs(db)
            
        return updated
    
    def remove(self, db: Session, *, id: int) -> VPNConfig:
        obj = super().remove(db, id=id)
        
        # Обновляем серверную конфигурацию после удаления
        self._update_server_configs(db)
        
        return obj
    
    def _update_server_configs(self, db: Session) -> None:
        """Обновляет серверные конфигурации для всех VPN сервисов."""
        # Получаем все активные конфигурации
        all_configs = db.query(VPNConfig).all()
        
        # Группируем конфигурации по типу
        wireguard_configs = []
        shadowsocks_configs = []
        xray_configs = []
        
        for config in all_configs:
            if config.vpn_type == VPNType.WIREGUARD:
                wireguard_configs.append({
                    "vpn_type": config.vpn_type,
                    "public_key": config.public_key,
                    "ip_address": config.ip_address,
                    "is_active": config.is_active
                })
            elif config.vpn_type == VPNType.SHADOWSOCKS:
                shadowsocks_configs.append({
                    "vpn_type": config.vpn_type,
                    "port": config.port,
                    "password": config.password,
                    "is_active": config.is_active
                })
            elif config.vpn_type == VPNType.XRAY:
                xray_configs.append({
                    "vpn_type": config.vpn_type,
                    "uuid": config.uuid,
                    "is_active": config.is_active
                })
        
        # Обновляем конфигурации серверов
        wireguard_manager.update_server_config(wireguard_configs)
        shadowsocks_manager.update_server_config(shadowsocks_configs)
        xray_manager.update_server_config(xray_configs)


vpn_config = CRUDVPNConfig(VPNConfig)
