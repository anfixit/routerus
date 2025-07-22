from django.test import TestCase

from app.services.forms import UserForm


class UserFormTest(TestCase):
    def test_form_valid_data(self):
        form = UserForm(
            data={
                "name": "John Doe",
                "email": "john.doe@example.com",
                "vpn_ip": "192.168.1.1",
            }
        )
        self.assertTrue(form.is_valid())

    def test_form_missing_data(self):
        form = UserForm(data={})
        self.assertFalse(form.is_valid())
        self.assertEqual(len(form.errors), 3)  # Все поля обязательны
