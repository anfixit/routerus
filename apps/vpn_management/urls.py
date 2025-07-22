from django.urls import path
from . import views

app_name = 'vpn_management'

urlpatterns = [
    path("", views.home, name="home"),
    path("users/create/", views.create_user, name="create_user"),
    path("users/list/", views.user_list, name="user_list"),
]
