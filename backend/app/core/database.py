from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, Session
from sqlalchemy.pool import StaticPool
from typing import Generator
import os

from .config import get_settings

settings = get_settings()

# Создаем движок базы данных
if settings.database_url.startswith("sqlite"):
    # Для SQLite
    os.makedirs("data", exist_ok=True)
    engine = create_engine(
        settings.database_url,
        connect_args={
            "check_same_thread": False,
            "timeout": 20
        },
        poolclass=StaticPool,
        echo=settings.debug
    )
else:
    # Для PostgreSQL и других
    engine = create_engine(
        settings.database_url,
        echo=settings.debug
    )

# Создаем фабрику сессий
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# Базовый класс для моделей
Base = declarative_base()


def get_db() -> Generator[Session, None, None]:
    """Получение сессии базы данных"""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def create_tables():
    """Создание всех таблиц в базе данных"""
    Base.metadata.create_all(bind=engine)


def drop_tables():
    """Удаление всех таблиц из базы данных"""
    Base.metadata.drop_all(bind=engine)
