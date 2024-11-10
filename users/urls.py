from django.urls import path
from . import views

urlpatterns = [
    # Маршруты для управления пользователями
    path('profile/', views.edit_profile, name='edit_profile'),
    path('profile/success/', views.profile_success, name='profile_success'),
]
