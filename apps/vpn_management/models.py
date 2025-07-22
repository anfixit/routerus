from django.core.exceptions import ValidationError
from django.db import models


# Модель для пользователей
class User(models.Model):
    username = models.CharField(max_length=150, unique=True)
    email = models.EmailField(unique=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return self.username


# Модель для конфигураций WireGuard
class WireGuardConfig(models.Model):
    user = models.ForeignKey(
        User, on_delete=models.CASCADE, related_name="wireguard_configs"
    )
    private_key = models.CharField(max_length=255)
    public_key = models.CharField(max_length=255)
    allowed_ips = models.CharField(max_length=255, default="0.0.0.0/0, ::/0")
    endpoint = models.CharField(max_length=255, default="wg.proanfi.ru:51820")
    dns = models.CharField(max_length=255, default="1.1.1.1")
    persistent_keepalive = models.PositiveIntegerField(default=25)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"WireGuard Config for {self.user.username}"

    # Метод для генерации конфигурации WireGuard
    def generate_config(self):
        return f"[Interface]\nPrivateKey = {self.private_key}\n..."


# Модель для статистики пользователей
class UserStatistics(models.Model):
    user = models.OneToOneField(
        User, on_delete=models.CASCADE, related_name="statistics"
    )
    total_data_used = models.BigIntegerField(default=0)  # В байтах
    last_connection = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"Statistics for {self.user.username}"


# Модель для Dropbox настроек
class DropboxSettings(models.Model):
    user = models.OneToOneField(
        User, on_delete=models.CASCADE, related_name="dropbox_settings"
    )
    access_token = models.CharField(max_length=255)
    app_key = models.CharField(max_length=100)
    app_secret = models.CharField(max_length=100)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"Dropbox Settings for {self.user.username}"


# Модель для Shadowsocks настроек
class ShadowsocksConfig(models.Model):
    server = models.GenericIPAddressField(default="213.148.10.128")
    port = models.PositiveIntegerField(default=8388)
    password = models.CharField(max_length=255)
    method = models.CharField(max_length=50, default="chacha20-ietf-poly1305")
    timeout = models.PositiveIntegerField(default=300)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"Shadowsocks Config on {self.server}:{self.port}"

    # Валидация порта
    def clean(self):
        if not (1 <= self.port <= 65535):
            raise ValidationError("Port must be in the range 1-65535.")


# Модель для Xray настроек
class XrayConfig(models.Model):
    uuid = models.CharField(max_length=36, unique=True)
    log_level = models.CharField(max_length=10, default="info")
    vless_port = models.PositiveIntegerField(default=443)
    vless_network = models.CharField(max_length=10, default="ws")
    vless_path = models.CharField(max_length=255, default="/vless")
    shadowsocks_port = models.PositiveIntegerField(default=8388)
    shadowsocks_method = models.CharField(
        max_length=50, default="chacha20-ietf-poly1305"
    )
    shadowsocks_password = models.CharField(max_length=255)
    wireguard_port = models.PositiveIntegerField(default=51820)
    wireguard_secret_key = models.CharField(max_length=255)
    wireguard_public_key = models.CharField(max_length=255)
    wireguard_address = models.GenericIPAddressField(default="213.148.10.128")
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"Xray Config for UUID {self.uuid}"

    # Валидация порта
    def clean(self):
        if not (1 <= self.vless_port <= 65535):
            raise ValidationError("Port must be in the range 1-65535.")
