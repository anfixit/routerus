from unittest.mock import patch

from django.test import TestCase

from app.services.shadowsocks import ShadowsocksService
from app.services.wireguard import WireGuardService
from app.services.xray import XrayService


class WireGuardServiceTest(TestCase):
    def setUp(self):
        self.wireguard = WireGuardService(
            private_key="test_private_key",
            public_key="test_public_key",
            server_ip="10.0.0.1",
            server_port=51820,
            peer_dns="1.1.1.1",
            allowed_ips="0.0.0.0/0",
        )

    def test_create_config(self):
        with patch("builtins.open") as mock_open:
            self.wireguard.create_config()
            mock_open.assert_called_once()


class ShadowsocksServiceTest(TestCase):
    def setUp(self):
        self.shadowsocks = ShadowsocksService(
            server="127.0.0.1",
            port=8388,
            password="test_password",
            method="aes-256-gcm",
            timeout=300,
        )

    def test_create_config(self):
        with patch("json.dump") as mock_dump:
            self.shadowsocks.create_config()
            mock_dump.assert_called_once()


class XrayServiceTest(TestCase):
    def setUp(self):
        self.xray = XrayService()

    def test_start_service(self):
        with patch("subprocess.run") as mock_run:
            self.xray.start_service()
            mock_run.assert_called_once()
