from fastapi import FastAPI, HTTPException, Depends, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from fastapi.security import HTTPBearer
from fastapi.responses import JSONResponse
from contextlib import asynccontextmanager
import logging
import uvicorn
from pathlib import Path

# Импорты проекта
from .core.config import get_settings
from .core.database import create_tables, engine
from .core.security import get_password_hash
from .models.user import AdminUser
from .models.server import Server
from .api import auth, servers, users, monitoring

# Настройка логирования
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)

settings = get_settings()


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Управление жизненным циклом приложения"""
    logger.info(f"🚀 Запуск {settings.app_name} v{settings.app_version}")
    logger.info(f"📋 Режим работы: {settings.mode}")

    # Создание таблиц БД
    create_tables()

    # Создание директорий
    Path("data").mkdir(exist_ok=True)
    Path("logs").mkdir(exist_ok=True)

    # Создание администратора по умолчанию
    await create_default_admin()

    if settings.is_vpn_only:
        logger.info("🔒 VPN сервер готов к работе")
    else:
        logger.info("🌐 Веб-интерфейс готов к работе")

    yield

    logger.info("⏹️ Остановка сервера")


async def create_default_admin():
    """Создает администратора по умолчанию"""
    try:
        from sqlalchemy.orm import Session
        from .core.database import SessionLocal

        db = SessionLocal()

        # Проверяем, есть ли уже администратор
        admin = db.query(AdminUser).filter(AdminUser.username == "admin").first()

        if not admin:
            # Создаем администратора
            admin = AdminUser(
                username="admin",
                email="admin@routerus.local",
                hashed_password=get_password_hash(settings.admin_password),
                full_name="System Administrator",
                is_active=True,
                is_superuser=True
            )

            db.add(admin)
            db.commit()

            logger.info("✅ Создан администратор по умолчанию (admin)")

        db.close()

    except Exception as e:
        logger.error(f"❌ Ошибка создания администратора: {e}")


# Создание FastAPI приложения
app = FastAPI(
    title=settings.app_name,
    version=settings.app_version,
    description="Система управления VPN серверами с VLESS+Reality",
    docs_url="/api/docs" if settings.debug else None,
    redoc_url="/api/redoc" if settings.debug else None,
    lifespan=lifespan
)

# Middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.add_middleware(
    TrustedHostMiddleware,
    allowed_hosts=["*"] if settings.debug else ["localhost", "127.0.0.1"]
)

# Security
security = HTTPBearer()

# Подключение роутеров
app.include_router(auth.router, prefix="/api/auth", tags=["Аутентификация"])
app.include_router(servers.router, prefix="/api/servers", tags=["Серверы"])
app.include_router(users.router, prefix="/api/users", tags=["Пользователи"])
app.include_router(monitoring.router, prefix="/api/monitoring", tags=["Мониторинг"])


# Основные эндпоинты
@app.get("/")
async def root():
    """Главная страница API"""
    return {
        "message": f"🚀 {settings.app_name} v{settings.app_version}",
        "mode": settings.mode,
        "status": "running",
        "docs": "/api/docs" if settings.debug else "disabled"
    }


@app.get("/health")
async def health_check():
    """Проверка здоровья API"""
    try:
        # Проверяем подключение к БД
        from sqlalchemy import text
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))

        return {
            "status": "healthy",
            "version": settings.app_version,
            "mode": settings.mode,
            "database": "connected",
            "timestamp": "2024-01-01T00:00:00Z"
        }
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Service unhealthy"
        )


@app.get("/api/info")
async def api_info():
    """Информация об API"""
    from .models.server import Server
    from .models.user import VpnUser
    from .core.database import SessionLocal

    try:
        db = SessionLocal()

        servers_count = db.query(Server).count()
        users_count = db.query(VpnUser).count()
        active_users = db.query(VpnUser).filter(VpnUser.is_active == True).count()

        db.close()

        return {
            "app_name": settings.app_name,
            "version": settings.app_version,
            "mode": settings.mode,
            "statistics": {
                "servers_count": servers_count,
                "users_count": users_count,
                "active_users": active_users
            },
            "features": {
                "vpn_server": settings.is_vpn_only,
                "web_interface": settings.is_web_interface,
                "monitoring": True,
                "telegram_bot": bool(settings.telegram_bot_token)
            }
        }
    except Exception as e:
        logger.error(f"API info error: {e}")
        return {"error": "Unable to fetch info"}


# Обработчики ошибок
@app.exception_handler(404)
async def not_found_handler(request, exc):
    return JSONResponse(
        status_code=404,
        content={"detail": "Endpoint not found"}
    )


@app.exception_handler(500)
async def internal_error_handler(request, exc):
    logger.error(f"Internal server error: {exc}")
    return JSONResponse(
        status_code=500,
        content={"detail": "Internal server error"}
    )


# Запуск сервера
if __name__ == "__main__":
    uvicorn.run(
        "app.main:app",
        host=settings.host,
        port=settings.port,
        reload=settings.debug,
        log_level=settings.log_level.lower(),
        access_log=settings.debug
    )
