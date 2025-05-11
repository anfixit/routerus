from fastapi import APIRouter

from app.api.endpoints import auth, users, configs, metrics

api_router = APIRouter()
api_router.include_router(auth.router, prefix="/auth", tags=["auth"])
api_router.include_router(users.router, prefix="/users", tags=["users"])
api_router.include_router(configs.router, prefix="/configs", tags=["configs"])
api_router.include_router(metrics.router, prefix="/metrics", tags=["metrics"])
