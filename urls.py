from django.contrib import admin
from django.urls import path
from app import views  # Импорт views из вашего приложения

urlpatterns = [
    path('admin/', admin.site.urls),
    path('', views.index, name='home'),  # Главная страница
    path('request-config/', views.request_config, name='request_config'),  # Страница запроса конфигурации
    path('create-config/', views.create_config, name='create_config'),  # Страница создания конфигурации
    path('config-list/', views.config_list, name='config_list'),  # Страница списка конфигураций
    path('success/', views.success, name='success'),  # Страница успеха
]
