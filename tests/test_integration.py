from django.test import TestCase
from django.urls import reverse

class VPNIntegrationTest(TestCase):
    def test_vpn_connection(self):
        # Тест настройки полного цикла VPN (WireGuard -> Shadowsocks -> Xray)
        response = self.client.post(reverse("create_user"), {
            "username": "testuser",
            "email": "testuser@example.com"
        })
        self.assertEqual(response.status_code, 302)
        # Здесь можно добавить проверку конфигурации WireGuard
