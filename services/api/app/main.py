from fastapi import FastAPI, Depends, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import HTMLResponse, RedirectResponse

from app.api.v1 import api_router
from app.core.config import settings
from app.core.metrics import metrics_router, PrometheusMiddleware
from app.models import Base
from app.core.database import engine

# Создание таблиц в базе данных при первом запуске
Base.metadata.create_all(bind=engine)

# Создание приложения FastAPI
app = FastAPI(
    title=settings.PROJECT_NAME,
    openapi_url=f"{settings.API_V1_STR}/openapi.json",
    version="0.1.0",
)

# Добавление middleware для CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # В продакшене заменить на конкретные домены
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Добавление middleware для Prometheus метрик
app.add_middleware(PrometheusMiddleware)

# Включение маршрутов для метрик Prometheus
app.include_router(metrics_router, prefix="/metrics", tags=["metrics"])

# Включение API маршрутов версии 1
app.include_router(api_router, prefix=settings.API_V1_STR)

# Корневой маршрут
@app.get("/", response_class=HTMLResponse)
async def root():
    return RedirectResponse(url="/admin")

# Маршрут для административной панели (временная заглушка)
@app.get("/admin", response_class=HTMLResponse)
async def admin():
    html_content = """
    <!DOCTYPE html>
    <html>
    <head>
        <title>RouteRus VPN Admin</title>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
        <style>
            body { padding-top: 20px; }
            .container { max-width: 800px; }
        </style>
    </head>
    <body>
        <div class="container">
            <h1 class="mb-4">RouteRus VPN Admin Panel</h1>
            <p>Здесь будет полноценная административная панель.</p>
            <p>Пока вы можете использовать API напрямую:</p>
            <ul>
                <li><a href="/docs">API Documentation</a></li>
                <li><a href="/grafana">Grafana Dashboards</a></li>
            </ul>
        </div>
        <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
    </body>
    </html>
    """
    return HTMLResponse(content=html_content)

# Маршрут для проверки работоспособности
@app.get("/health")
async def health_check():
    return {"status": "healthy"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
