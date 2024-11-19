from django.urls import path
from . import views

urlpatterns = [
    path('', views.index, name='index'),
    path('users/', views.users_list, name='users_list'),
    path('create-user/', views.create_user, name='create_user'),
]
