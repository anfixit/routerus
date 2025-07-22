from django import forms


class UserForm(forms.Form):
    name = forms.CharField(
        max_length=100,
        label="Name",
        widget=forms.TextInput(attrs={"class": "form-control"}),
    )
    email = forms.EmailField(
        label="Email", widget=forms.EmailInput(attrs={"class": "form-control"})
    )
    vpn_ip = forms.GenericIPAddressField(
        protocol="IPv4",
        label="VPN IP Address",
        widget=forms.TextInput(attrs={"class": "form-control"}),
    )

    # Валидация email
    def clean_email(self):
        email = self.cleaned_data.get("email")
        # Добавить проверку на уникальность email, если есть доступ к модели пользователей
        # Example: if User.objects.filter(email=email).exists():
        # raise ValidationError("Email already exists.")
        return email

    # Валидация IP-адреса
    def clean_vpn_ip(self):
        vpn_ip = self.cleaned_data.get("vpn_ip")
        # Проверить диапазон IP (пример: 192.168.1.0/24)
        # Example: if not valid_ip_range(vpn_ip):
        # raise ValidationError("IP address is not in the valid range.")
        return vpn_ip
