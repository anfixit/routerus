#!/usr/bin/env python3
"""
Routerus V2 - FastAPI Backend
Управление VPN серверами через REST API
"""

from fastapi import FastAPI, HTTPException, Depends, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.staticfiles import StaticFiles
from fastapi.responses import HTMLResponse, StreamingResponse
from pydantic import BaseModel, Field
from typing import List, Optional, Dict, Any
import httpx
import qrcode
import io
import base64
import json
import os
import uuid
import asyncio
import psutil
from datetime import datetime, timedelta
import logging

# Настройка логирования
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# FastAPI приложение
app = FastAPI(
    title="Routerus V2 API",
    description="Управление VPN серверами с VLESS+Reality",
    version="2.0.0",
    docs_url="/api/docs",
    redoc_url="/api/redoc"
)

# CORS для React фронтенда
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # В продакшене указать конкретные домены
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Безопасность (простая для начала)
security = HTTPBearer()

# =============================================================================
# МОДЕЛИ ДАННЫХ
# =============================================================================

class ServerCreate(BaseModel):
    name: str = Field(..., description="Название сервера")
    ip: str = Field(..., description="IP адрес сервера")
    location: str = Field(..., description="Местоположение")
    description: Optional[str] = Field(None, description="Описание")

class ServerResponse(BaseModel):
    id: str
    name: str
    ip: str
    location: str
    status: str  # online, offline, unknown
    users_count: int
    created_at: datetime
    last_check: Optional[datetime]

class UserCreate(BaseModel):
    email: str = Field(..., description="Email пользователя")
    name: Optional[str] = Field(None, description="Имя пользователя")
    server_id: str = Field(..., description="ID сервера")

class UserResponse(BaseModel):
    id: str
    email: str
    name: Optional[str]
    server_id: str
    config_url: str
    created_at: datetime
    last_connection: Optional[datetime]

class ServerStats(BaseModel):
    cpu_usage: float
    memory_usage: float
    disk_usage: float
    network_in: int
    network_out: int
    connections: int
    uptime: int

class DeployCommand(BaseModel):
    command: str
    server_ip: str
    instructions: List[str]

# =============================================================================
# ВРЕМЕННОЕ ХРАНИЛИЩЕ (в продакшене - база данных)
# =============================================================================

# Временные данные
servers_db: Dict[str, Dict] = {}
users_db: Dict[str, Dict] = {}
stats_db: Dict[str, Dict] = {}

# =============================================================================
# УТИЛИТЫ
# =============================================================================

def generate_vless_config(server_ip: str, user_id: str, email: str) -> Dict:
    """Генерирует VLESS конфигурацию для пользователя"""
    # Используем генератор из VPN сервера
    config = {
        "server_ip": server_ip,
        "server_port": 443,
        "user_id": user_id,
        "email": email,
        "protocol": "vless",
        "security": "reality",
        "sni": "www.microsoft.com",
        "flow": "xtls-rprx-vision"
    }
    return config

def generate_vless_url(config: Dict) -> str:
    """Генерирует VLESS URL из конфигурации"""
    import urllib.parse

    base_url = f"vless://{config['user_id']}@{config['server_ip']}:{config['server_port']}"

    params = {
        "type": "tcp",
        "security": config['security'],
        "sni": config['sni'],
        "fp": "chrome",
        "flow": config['flow']
    }

    query_string = urllib.parse.urlencode(params)
    full_url = f"{base_url}?{query_string}#{urllib.parse.quote(config['email'])}"

    return full_url

def generate_qr_code(text: str) -> str:
    """Генерирует QR код и возвращает base64 строку"""
    qr = qrcode.QRCode(version=1, box_size=10, border=5)
    qr.add_data(text)
    qr.make(fit=True)

    img = qr.make_image(fill_color="black", back_color="white")

    # Конвертируем в base64
    buffer = io.BytesIO()
    img.save(buffer, format='PNG')
    img_str = base64.b64encode(buffer.getvalue()).decode()

    return f"data:image/png;base64,{img_str}"

async def check_server_status(server_ip: str) -> str:
    """Проверяет статус VPN сервера"""
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            # Пытаемся подключиться к порту 443
            response = await client.get(f"https://{server_ip}", verify=False)
            return "online"
    except:
        return "offline"

def get_system_stats() -> ServerStats:
    """Получает статистику системы"""
    cpu = psutil.cpu_percent(interval=1)
    memory = psutil.virtual_memory().percent
    disk = psutil.disk_usage('/').percent

    # Сетевая статистика
    net_io = psutil.net_io_counters()

    return ServerStats(
        cpu_usage=cpu,
        memory_usage=memory,
        disk_usage=disk,
        network_in=net_io.bytes_recv,
        network_out=net_io.bytes_sent,
        connections=len(psutil.net_connections()),
        uptime=int(datetime.now().timestamp() - psutil.boot_time())
    )

# =============================================================================
# API ЭНДПОИНТЫ
# =============================================================================

@app.get("/", response_class=HTMLResponse)
async def root():
    """Главная страница с редиректом на React"""
    return """
    <html>
        <head><title>Routerus V2</title></head>
        <body>
            <h1>🚀 Routerus V2 API</h1>
            <p>Backend работает! Фронтенд будет доступен после сборки React.</p>
            <ul>
                <li><a href="/api/docs">📚 API Документация</a></li>
                <li><a href="/api/stats">📊 Статистика системы</a></li>
                <li><a href="/api/servers">🖥️ Список серверов</a></li>
            </ul>
        </body>
    </html>
    """

# СЕРВЕРЫ
@app.get("/api/servers", response_model=List[ServerResponse])
async def get_servers():
    """Получить список всех VPN серверов"""
    servers = []
    for server_id, server_data in servers_db.items():
        # Проверяем статус сервера
        status = await check_server_status(server_data["ip"])

        servers.append(ServerResponse(
            id=server_id,
            name=server_data["name"],
            ip=server_data["ip"],
            location=server_data["location"],
            status=status,
            users_count=len([u for u in users_db.values() if u["server_id"] == server_id]),
            created_at=server_data["created_at"],
            last_check=datetime.now()
        ))

    return servers

@app.post("/api/servers", response_model=ServerResponse)
async def create_server(server: ServerCreate):
    """Создать новый VPN сервер"""
    server_id = str(uuid.uuid4())

    server_data = {
        "id": server_id,
        "name": server.name,
        "ip": server.ip,
        "location": server.location,
        "description": server.description,
        "created_at": datetime.now()
    }

    servers_db[server_id] = server_data

    # Проверяем статус
    status = await check_server_status(server.ip)

    return ServerResponse(
        id=server_id,
        name=server.name,
        ip=server.ip,
        location=server.location,
        status=status,
        users_count=0,
        created_at=server_data["created_at"],
        last_check=datetime.now()
    )

@app.get("/api/servers/{server_id}/deploy")
async def get_deploy_command(server_id: str):
    """Получить команду для развертывания сервера"""
    if server_id not in servers_db:
        raise HTTPException(status_code=404, detail="Сервер не найден")

    server = servers_db[server_id]

    # Генерируем команду развертывания
    deploy_command = f"curl -fsSL https://your-domain.ru/deploy/{server_id} | bash"

    return DeployCommand(
        command=deploy_command,
        server_ip=server["ip"],
        instructions=[
            f"1. Подключитесь к серверу: ssh root@{server['ip']}",
            "2. Выполните команду развертывания:",
            f"   {deploy_command}",
            "3. Дождитесь завершения установки (2-3 минуты)",
            "4. Сервер будет готов к добавлению пользователей"
        ]
    )

# ПОЛЬЗОВАТЕЛИ
@app.get("/api/users", response_model=List[UserResponse])
async def get_users():
    """Получить список всех пользователей"""
    users = []
    for user_id, user_data in users_db.items():
        users.append(UserResponse(
            id=user_id,
            email=user_data["email"],
            name=user_data["name"],
            server_id=user_data["server_id"],
            config_url=user_data["config_url"],
            created_at=user_data["created_at"],
            last_connection=user_data.get("last_connection")
        ))

    return users

@app.post("/api/users", response_model=UserResponse)
async def create_user(user: UserCreate):
    """Создать нового пользователя VPN"""
    # Проверяем существование сервера
    if user.server_id not in servers_db:
        raise HTTPException(status_code=404, detail="Сервер не найден")

    user_id = str(uuid.uuid4())
    server = servers_db[user.server_id]

    # Генерируем конфигурацию
    config = generate_vless_config(server["ip"], user_id, user.email)
    config_url = generate_vless_url(config)

    user_data = {
        "id": user_id,
        "email": user.email,
        "name": user.name,
        "server_id": user.server_id,
        "config_url": config_url,
        "created_at": datetime.now()
    }

    users_db[user_id] = user_data

    return UserResponse(
        id=user_id,
        email=user.email,
        name=user.name,
        server_id=user.server_id,
        config_url=config_url,
        created_at=user_data["created_at"],
        last_connection=None
    )

@app.get("/api/users/{user_id}/qr")
async def get_user_qr(user_id: str):
    """Получить QR код для пользователя"""
    if user_id not in users_db:
        raise HTTPException(status_code=404, detail="Пользователь не найден")

    user = users_db[user_id]
    qr_code = generate_qr_code(user["config_url"])

    return {"qr_code": qr_code, "config_url": user["config_url"]}

# СТАТИСТИКА
@app.get("/api/stats", response_model=ServerStats)
async def get_stats():
    """Получить статистику сервера"""
    return get_system_stats()

@app.get("/api/health")
async def health_check():
    """Проверка здоровья API"""
    return {
        "status": "ok",
        "timestamp": datetime.now(),
        "version": "2.0.0",
        "servers_count": len(servers_db),
        "users_count": len(users_db)
    }

# WEBSOCKET для реального времени
@app.websocket("/api/ws")
async def websocket_endpoint(websocket):
    """WebSocket для обновлений в реальном времени"""
    await websocket.accept()
    try:
        while True:
            # Отправляем статистику каждые 5 секунд
            stats = get_system_stats()
            await websocket.send_json({
                "type": "stats",
                "data": stats.dict()
            })
            await asyncio.sleep(5)
    except:
        logger.info("WebSocket connection closed")

# =============================================================================
# ЗАПУСК
# =============================================================================

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8000,
        reload=True,
        log_level="info"
    )
