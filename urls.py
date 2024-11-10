from django.contrib import admin
from django.urls import path, include

urlpatterns = [
    # Главная страница и маршруты для приложения `app`
    path('', include('app.urls')),  # Подключаем все URL из приложения `app`

    # Админка
    path('admin/', admin.site.urls),

    # Маршруты для управления пользователями
    path('users/', include('users.urls')),  # Подключаем маршруты из `users`

    # Маршруты для управления VPN-конфигурациями
    path('vpn/', include('vpn.urls')),  # Подключаем маршруты из `vpn`

    # Маршруты для управления системными настройками
    path('config/', include('config_manager.urls')),  # Подключаем маршруты из `config_manager`
]
