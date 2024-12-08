from django.contrib import admin
from django.urls import path, include
from app.services import views

urlpatterns = [
    # Административная панель
    path('admin/', admin.site.urls),

    # Главная страница
    path('', views.home, name='home'),

    # Маршруты для пользователей
    path('users/create/', views.create_user, name='create_user'),
    path('users/list/', views.user_list, name='user_list'),

    # Другие модули можно подключать через include
    # path('wireguard/', include('app.services.wireguard_urls')),
]
