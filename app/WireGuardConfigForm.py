from django import forms
import os

class WireGuardConfigForm(forms.Form):
    username = forms.CharField(max_length=100, label='Имя клиента')

    def save(self):
        username = self.cleaned_data['username']
        user_dir = f'/path/to/wg-manager/config/keys/{username}'
        os.makedirs(user_dir, exist_ok=True)

        # Генерация ключей WireGuard
        private_key = os.popen("wg genkey").read().strip()
        public_key = os.popen(f"echo {private_key} | wg pubkey").read().strip()

        # Сохранение ключей в директории
        with open(os.path.join(user_dir, 'private.key'), 'w') as priv_file:
            priv_file.write(private_key)
        with open(os.path.join(user_dir, 'public.key'), 'w') as pub_file:
            pub_file.write(public_key)

        # Генерация конфигурации WireGuard
        config_content = f"""
        [Interface]
        PrivateKey = {private_key}
        Address = 10.0.0.2/24
        DNS = 1.1.1.1

        [Peer]
        PublicKey = <SERVER_PUBLIC_KEY>
        Endpoint = your.server.ip:51820
        AllowedIPs = 0.0.0.0/0
        PersistentKeepalive = 21
        """

        with open(os.path.join(user_dir, 'wg0.conf'), 'w') as config_file:
            config_file.write(config_content)

        # Генерация QR-кода
        os.system(f"qrencode -t png -o {user_dir}/qrcode.png < {user_dir}/wg0.conf>")
