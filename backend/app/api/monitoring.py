from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from sqlalchemy import func, desc
from typing import List, Dict, Optional
import psutil
import logging
from datetime import datetime, timedelta
from pydantic import BaseModel

from ..core.database import get_db
from ..models.server import Server, ServerStats, ServerStatus
from ..models.user import AdminUser, VpnUser, UserStatus
from ..api.auth import get_current_user
from ..services.xray import get_xray_manager

router = APIRouter()
logger = logging.getLogger(__name__)


class SystemStats(BaseModel):
    """Системная статистика"""
    cpu_usage: float
    memory_usage: float
    disk_usage: float
    network_in: int
    network_out: int
    uptime: int
    load_average: List[float]


class DashboardStats(BaseModel):
    """Статистика для дашборда"""
    total_servers: int
    online_servers: int
    offline_servers: int
    total_users: int
    active_users: int
    suspended_users: int
    total_traffic_gb: float
    servers_load: Dict[str, float]


class ServerMetrics(BaseModel):
    """Метрики сервера"""
    server_id: int
    server_name: str
    server_ip: str
    status: ServerStatus
    cpu_usage: float
    memory_usage: float
    disk_usage: float
    active_connections: int
    total_users: int
    active_users: int
    uptime: int
    last_check: datetime


class TrafficStats(BaseModel):
    """Статистика трафика"""
    period: str
    total_gb: float
    upload_gb: float
    download_gb: float
    timestamp: datetime


@router.get("/dashboard", response_model=DashboardStats)
async def get_dashboard_stats(
    db: Session = Depends(get_db),
    current_user: AdminUser = Depends(get_current_user)
):
    """Получить статистику для главного дашборда"""

    # Статистика серверов
    total_servers = db.query(Server).count()
    online_servers = db.query(Server).filter(Server.status == ServerStatus.ONLINE).count()
    offline_servers = db.query(Server).filter(Server.status == ServerStatus.OFFLINE).count()

    # Статистика пользователей
    total_users = db.query(VpnUser).count()
    active_users = db.query(VpnUser).filter(
        VpnUser.is_active == True,
        VpnUser.status == UserStatus.ACTIVE
    ).count()
    suspended_users = db.query(VpnUser).filter(
        VpnUser.status == UserStatus.SUSPENDED
    ).count()

    # Общий трафик
    total_traffic_result = db.query(func.sum(VpnUser.total_traffic_gb)).scalar()
    total_traffic_gb = total_traffic_result or 0.0

    # Загрузка серверов
    servers_load = {}
    servers = db.query(Server).filter(Server.is_active == True).all()

    for server in servers:
        # Получаем последнюю статистику
        latest_stats = db.query(ServerStats).filter(
            ServerStats.server_id == server.id
        ).order_by(desc(ServerStats.timestamp)).first()

        if latest_stats:
            servers_load[server.name] = latest_stats.cpu_usage
        else:
            servers_load[server.name] = 0.0

    return DashboardStats(
        total_servers=total_servers,
        online_servers=online_servers,
        offline_servers=offline_servers,
        total_users=total_users,
        active_users=active_users,
        suspended_users=suspended_users,
        total_traffic_gb=total_traffic_gb,
        servers_load=servers_load
    )


@router.get("/system", response_model=SystemStats)
async def get_system_stats(
    current_user: AdminUser = Depends(get_current_user)
):
    """Получить системную статистику текущего сервера"""

    try:
        # CPU
        cpu_usage = psutil.cpu_percent(interval=1)

        # Память
        memory = psutil.virtual_memory()
        memory_usage = memory.percent

        # Диск
        disk = psutil.disk_usage('/')
        disk_usage = disk.percent

        # Сеть
        net_io = psutil.net_io_counters()
        network_in = net_io.bytes_recv
        network_out = net_io.bytes_sent

        # Uptime
        boot_time = psutil.boot_time()
        uptime = int(datetime.now().timestamp() - boot_time)

        # Load average
        try:
            load_avg = list(psutil.getloadavg())
        except AttributeError:
            # Windows не поддерживает getloadavg
            load_avg = [0.0, 0.0, 0.0]

        return SystemStats(
            cpu_usage=cpu_usage,
            memory_usage=memory_usage,
            disk_usage=disk_usage,
            network_in=network_in,
            network_out=network_out,
            uptime=uptime,
            load_average=load_avg
        )

    except Exception as e:
        logger.error(f"Ошибка получения системной статистики: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Ошибка получения системной статистики"
        )


@router.get("/servers", response_model=List[ServerMetrics])
async def get_servers_metrics(
    db: Session = Depends(get_db),
    current_user: AdminUser = Depends(get_current_user)
):
    """Получить метрики всех серверов"""

    servers = db.query(Server).filter(Server.is_active == True).all()
    metrics = []

    for server in servers:
        # Получаем последнюю статистику
        latest_stats = db.query(ServerStats).filter(
            ServerStats.server_id == server.id
        ).order_by(desc(ServerStats.timestamp)).first()

        # Считаем активных пользователей
        active_users_count = db.query(VpnUser).filter(
            VpnUser.server_id == server.id,
            VpnUser.is_active == True,
            VpnUser.status == UserStatus.ACTIVE
        ).count()

        if latest_stats:
            metrics.append(ServerMetrics(
                server_id=server.id,
                server_name=server.name,
                server_ip=server.ip,
                status=server.status,
                cpu_usage=latest_stats.cpu_usage,
                memory_usage=latest_stats.memory_usage,
                disk_usage=latest_stats.disk_usage,
                active_connections=latest_stats.active_connections,
                total_users=server.total_users,
                active_users=active_users_count,
                uptime=server.uptime,
                last_check=server.last_check
            ))
        else:
            # Если нет статистики, возвращаем базовые данные
            metrics.append(ServerMetrics(
                server_id=server.id,
                server_name=server.name,
                server_ip=server.ip,
                status=server.status,
                cpu_usage=0.0,
                memory_usage=0.0,
                disk_usage=0.0,
                active_connections=0,
                total_users=server.total_users,
                active_users=active_users_count,
                uptime=server.uptime,
                last_check=server.last_check or datetime.utcnow()
            ))

    return metrics


@router.get("/traffic", response_model=List[TrafficStats])
async def get_traffic_stats(
    period: str = "24h",
    server_id: Optional[int] = None,
    db: Session = Depends(get_db),
    current_user: AdminUser = Depends(get_current_user)
):
    """Получить статистику трафика"""

    # Определяем временной период
    if period == "1h":
        since = datetime.utcnow() - timedelta(hours=1)
        group_by = "hour"
    elif period == "24h":
        since = datetime.utcnow() - timedelta(hours=24)
        group_by = "hour"
    elif period == "7d":
        since = datetime.utcnow() - timedelta(days=7)
        group_by = "day"
    elif period == "30d":
        since = datetime.utcnow() - timedelta(days=30)
        group_by = "day"
    else:
        since = datetime.utcnow() - timedelta(hours=24)
        group_by = "hour"

    # Базовый запрос
    query = db.query(ServerStats).filter(ServerStats.timestamp >= since)

    if server_id:
        query = query.filter(ServerStats.server_id == server_id)

    # Группируем по времени
    if group_by == "hour":
        # Группировка по часам
        stats = query.order_by(ServerStats.timestamp).all()
    else:
        # Группировка по дням
        stats = query.order_by(ServerStats.timestamp).all()

    # Формируем результат
    traffic_data = []
    current_time = since

    # Простая группировка (можно улучшить)
    for stat in stats:
        traffic_data.append(TrafficStats(
            period=period,
            total_gb=float(stat.network_in + stat.network_out) / (1024**3),
            upload_gb=float(stat.network_out) / (1024**3),
            download_gb=float(stat.network_in) / (1024**3),
            timestamp=stat.timestamp
        ))

    return traffic_data[-100:]  # Возвращаем последние 100 записей


@router.get("/alerts")
async def get_alerts(
    db: Session = Depends(get_db),
    current_user: AdminUser = Depends(get_current_user)
):
    """Получить список алертов"""

    alerts = []

    # Проверяем серверы
    servers = db.query(Server).filter(Server.is_active == True).all()

    for server in servers:
        # Проверяем статус
        if server.status == ServerStatus.OFFLINE:
            alerts.append({
                "type": "error",
                "message": f"Сервер {server.name} ({server.ip}) недоступен",
                "timestamp": server.last_check,
                "server_id": server.id
            })

        # Проверяем последнюю статистику
        latest_stats = db.query(ServerStats).filter(
            ServerStats.server_id == server.id
        ).order_by(desc(ServerStats.timestamp)).first()

        if latest_stats:
            # Высокая загрузка CPU
            if latest_stats.cpu_usage > 80:
                alerts.append({
                    "type": "warning",
                    "message": f"Высокая загрузка CPU на сервере {server.name}: {latest_stats.cpu_usage:.1f}%",
                    "timestamp": latest_stats.timestamp,
                    "server_id": server.id
                })

            # Высокое использование памяти
            if latest_stats.memory_usage > 85:
                alerts.append({
                    "type": "warning",
                    "message": f"Высокое использование памяти на сервере {server.name}: {latest_stats.memory_usage:.1f}%",
                    "timestamp": latest_stats.timestamp,
                    "server_id": server.id
                })

            # Мало места на диске
            if latest_stats.disk_usage > 90:
                alerts.append({
                    "type": "error",
                    "message": f"Мало места на диске сервера {server.name}: {latest_stats.disk_usage:.1f}%",
                    "timestamp": latest_stats.timestamp,
                    "server_id": server.id
                })

        # Проверяем лимит пользователей
        if server.total_users >= server.max_users * 0.9:  # 90% от лимита
            alerts.append({
                "type": "warning",
                "message": f"Сервер {server.name} близок к лимиту пользователей: {server.total_users}/{server.max_users}",
                "timestamp": datetime.utcnow(),
                "server_id": server.id
            })

    # Сортируем алерты по времени (новые сначала)
    alerts.sort(key=lambda x: x["timestamp"], reverse=True)

    return {"alerts": alerts[:50]}  # Возвращаем последние 50 алертов


@router.post("/collect-stats")
async def collect_server_stats(
    db: Session = Depends(get_db),
    current_user: AdminUser = Depends(get_current_user)
):
    """Собрать статистику со всех серверов (ручной запуск)"""

    try:
        # Получаем системную статистику текущего сервера
        stats = await get_system_stats(current_user)

        # Если это VPN сервер, сохраняем статистику
        if hasattr(current_user, 'server_id'):
            server_stats = ServerStats(
                server_id=current_user.server_id,
                cpu_usage=stats.cpu_usage,
                memory_usage=stats.memory_usage,
                disk_usage=stats.disk_usage,
                network_in=stats.network_in,
                network_out=stats.network_out,
                active_connections=0,  # Получаем из Xray
                total_connections=0,
                timestamp=datetime.utcnow()
            )

            db.add(server_stats)
            db.commit()

        # Пытаемся получить статистику Xray
        xray_manager = get_xray_manager()
        xray_stats = await xray_manager.get_stats()

        return {
            "message": "Статистика собрана",
            "system_stats": stats.dict(),
            "xray_stats": xray_stats
        }

    except Exception as e:
        logger.error(f"Ошибка сбора статистики: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Ошибка сбора статистики"
        )


@router.get("/prometheus")
async def get_prometheus_metrics(
    db: Session = Depends(get_db),
    current_user: AdminUser = Depends(get_current_user)
):
    """Экспорт метрик в формате Prometheus"""

    metrics = []

    # Системные метрики
    try:
        stats = await get_system_stats(current_user)

        metrics.append(f"routerus_cpu_usage {stats.cpu_usage}")
        metrics.append(f"routerus_memory_usage {stats.memory_usage}")
        metrics.append(f"routerus_disk_usage {stats.disk_usage}")
        metrics.append(f"routerus_network_in {stats.network_in}")
        metrics.append(f"routerus_network_out {stats.network_out}")
        metrics.append(f"routerus_uptime {stats.uptime}")

    except Exception as e:
        logger.error(f"Ошибка получения системных метрик: {e}")

    # Метрики серверов
    servers = db.query(Server).filter(Server.is_active == True).all()

    for server in servers:
        server_label = f'{{server_name="{server.name}",server_ip="{server.ip}"}}'

        metrics.append(f"routerus_server_status{server_label} {1 if server.status == ServerStatus.ONLINE else 0}")
        metrics.append(f"routerus_server_users{server_label} {server.total_users}")
        metrics.append(f"routerus_server_uptime{server_label} {server.uptime}")

        # Активные пользователи
        active_users = db.query(VpnUser).filter(
            VpnUser.server_id == server.id,
            VpnUser.is_active == True,
            VpnUser.status == UserStatus.ACTIVE
        ).count()

        metrics.append(f"routerus_server_active_users{server_label} {active_users}")

    # Общие метрики
    total_servers = len(servers)
    online_servers = len([s for s in servers if s.status == ServerStatus.ONLINE])
    total_users = db.query(VpnUser).count()
    active_users = db.query(VpnUser).filter(
        VpnUser.is_active == True,
        VpnUser.status == UserStatus.ACTIVE
    ).count()

    metrics.append(f"routerus_total_servers {total_servers}")
    metrics.append(f"routerus_online_servers {online_servers}")
    metrics.append(f"routerus_total_users {total_users}")
    metrics.append(f"routerus_active_users {active_users}")

    return "\n".join(metrics) + "\n"
