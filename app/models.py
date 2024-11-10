from django.db import models

class WireGuardConfig(models.Model):
    client_name = models.CharField(max_length=100, verbose_name='Имя клиента')
    public_key = models.CharField(max_length=500, verbose_name='Публичный ключ')
    private_key = models.CharField(max_length=500, verbose_name='Приватный ключ')
    ip_address = models.GenericIPAddressField(protocol='IPv4', verbose_name='IP-адрес')
    created_at = models.DateTimeField(auto_now_add=True, verbose_name='Дата создания')

    def __str__(self):
        return f'Конфигурация для клиента {self.client_name}'
