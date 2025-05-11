from fastapi import APIRouter, Request
from prometheus_client import Counter, Gauge, Histogram
import prometheus_client
import time

# Определение метрик
HTTP_REQUEST_COUNT = Counter(
    "http_request_count",
    "Count of HTTP requests received",
    ["method", "endpoint", "status_code"]
)

HTTP_REQUEST_DURATION = Histogram(
    "http_request_duration_seconds",
    "Duration of HTTP requests in seconds",
    ["method", "endpoint"]
)

ACTIVE_USERS = Gauge(
    "vpn_active_users",
    "Number of active VPN users"
)

CONFIG_COUNT = Gauge(
    "vpn_config_count",
    "Number of VPN configurations",
    ["type"]
)

# Маршрутизатор для метрик
metrics_router = APIRouter()


@metrics_router.get("")
async def metrics():
    return prometheus_client.generate_latest()


class PrometheusMiddleware:
    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            return await self.app(scope, receive, send)

        request = Request(scope, receive)
        method = request.method
        path = request.url.path
        
        start_time = time.time()
        
        # Обработка запроса
        status_code = 500  # По умолчанию
        
        async def wrapped_send(message):
            nonlocal status_code
            if message["type"] == "http.response.start":
                status_code = message["status"]
            await send(message)
        
        try:
            await self.app(scope, receive, wrapped_send)
        finally:
            duration = time.time() - start_time
            
            # Исключаем метрики из статистики
            if not path.startswith("/metrics"):
                HTTP_REQUEST_COUNT.labels(method, path, status_code).inc()
                HTTP_REQUEST_DURATION.labels(method, path).observe(duration)
