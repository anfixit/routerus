import os
import sys
from sqlalchemy.orm import Session

# Добавляем корневую директорию проекта в PYTHONPATH
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.core.config import settings
from app.core.database import SessionLocal
from app.crud.user import user
from app.schemas.user import UserCreate


def init_db() -> None:
    """Инициализация начальных данных в базе."""
    db = SessionLocal()
    try:
        # Проверяем, существует ли администратор
        admin_user = user.get_by_username(db, username=settings.ADMIN_USERNAME)
        
        # Если администратор не существует, создаем его
        if not admin_user:
            print(f"Creating admin user: {settings.ADMIN_USERNAME}")
            admin_user_in = UserCreate(
                username=settings.ADMIN_USERNAME,
                email=settings.ADMIN_EMAIL,
                full_name="Admin User",
                password=settings.ADMIN_PASSWORD,
                is_admin=True,
            )
            user.create(db, obj_in=admin_user_in)
            print("Admin user created successfully")
        else:
            print(f"Admin user {settings.ADMIN_USERNAME} already exists")
    finally:
        db.close()


if __name__ == "__main__":
    print("Initializing database...")
    init_db()
    print("Database initialization completed")
