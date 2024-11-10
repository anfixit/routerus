from django.contrib import admin
from django.urls import path, include
from app import views

urlpatterns = [
    # Главная страница и другие маршруты для приложения `app`
    path('', views.index, name='index'),
    path('configs/', views.config_list, name='config_list'),
    path('create/', views.create_config, name='create_config'),
    path('success/', views.success, name='success'),
    path('shadowsocks/', views.show_shadowsocks_config, name='show_shadowsocks_config'),
    path('xray/', views.show_xray_config, name='show_xray_config'),

    # Админка
    path('admin/', admin.site.urls),

    # Маршруты для управления пользователями
    path('users/', include('users.urls')),

    # Подключаем все URL из приложения `app`
    path('app/', include('app.urls')),
]
