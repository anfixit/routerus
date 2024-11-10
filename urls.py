from django.urls import path
from . import views

urlpatterns = [
    path('', views.index, name='index'),
    path('configs/', views.config_list, name='config_list'),
    path('create/', views.create_config, name='create_config'),
    path('success/', views.success, name='success'),
    path('shadowsocks/', views.show_shadowsocks_config, name='show_shadowsocks_config'),
    path('xray/', views.show_xray_config, name='show_xray_config'),
]
