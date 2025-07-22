from django.contrib import admin
from .models import User, WireGuardConfig, UserStatistics, ShadowsocksConfig

@admin.register(User)
class UserAdmin(admin.ModelAdmin):
    list_display = ['username', 'email', 'created_at']
    search_fields = ['username', 'email']

@admin.register(WireGuardConfig)
class WireGuardConfigAdmin(admin.ModelAdmin):
    list_display = ['user', 'endpoint', 'created_at']
    list_filter = ['created_at']

@admin.register(UserStatistics)
class UserStatisticsAdmin(admin.ModelAdmin):
    list_display = ['user', 'total_data_used', 'last_connection']

@admin.register(ShadowsocksConfig)
class ShadowsocksConfigAdmin(admin.ModelAdmin):
    list_display = ['server', 'port', 'method', 'created_at']
