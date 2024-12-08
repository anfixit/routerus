from django.test import TestCase
from app.services.models import User, WireGuardConfig

class UserModelTest(TestCase):
    def setUp(self):
        self.user = User.objects.create(username="testuser", email="test@example.com")

    def test_user_creation(self):
        self.assertEqual(self.user.username, "testuser")
        self.assertEqual(self.user.email, "test@example.com")

    def test_user_string_representation(self):
        self.assertEqual(str(self.user), "testuser")

class WireGuardConfigTest(TestCase):
    def setUp(self):
        self.user = User.objects.create(username="testuser", email="test@example.com")
        self.config = WireGuardConfig.objects.create(
            user=self.user,
            private_key="private_key_example",
            public_key="public_key_example",
            allowed_ips="0.0.0.0/0",
            endpoint="test.endpoint:51820"
        )

    def test_config_creation(self):
        self.assertEqual(self.config.user, self.user)
        self.assertEqual(self.config.allowed_ips, "0.0.0.0/0")
