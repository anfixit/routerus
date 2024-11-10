from django import forms
from .models import WireGuardConfig

class WireGuardConfigForm(forms.ModelForm):
    class Meta:
        model = WireGuardConfig
        fields = ['client_name', 'public_key', 'private_key', 'ip_address']
        labels = {
            'client_name': 'Имя клиента',
            'public_key': 'Публичный ключ',
            'private_key': 'Приватный ключ',
            'ip_address': 'IP-адрес',
        }
    
    def save(self, commit=True):
        instance = super().save(commit=False)
        # Создаем директорию для клиента
        import os
        user_dir = f'/opt/wg-manager/config/keys/{instance.client_name}'
        os.makedirs(user_dir, exist_ok=True)

        # Сохраняем ключи в файлы
        with open(os.path.join(user_dir, 'private.key'), 'w') as priv_file:
            priv_file.write(instance.private_key)
        with open(os.path.join(user_dir, 'public.key'), 'w') as pub_file:
            pub_file.write(instance.public_key)

        # Сохраняем конфигурацию WireGuard
        config_content = f"""
        [Interface]
        PrivateKey = {instance.private_key}
        Address = {instance.ip_address}
        DNS = 1.1.1.1

        [Peer]
        PublicKey = <SERVER_PUBLIC_KEY>
        Endpoint = your.server.ip:51820
        AllowedIPs = 0.0.0.0/0
        PersistentKeepalive = 21
        """
        with open(os.path.join(user_dir, 'wg0.conf'), 'w') as config_file:
            config_file.write(config_content)

        # Генерация QR-кода для подключения через мобильное приложение WireGuard
        os.system(f"qrencode -t png -o {user_dir}/qrcode.png < {user_dir}/wg0.conf>")

        if commit:
            instance.save()
        return instance
