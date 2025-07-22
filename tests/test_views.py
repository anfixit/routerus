from django.test import TestCase
from django.urls import reverse

from app.services.models import User


class HomeViewTest(TestCase):
    def test_home_view(self):
        response = self.client.get(reverse("home"))
        self.assertEqual(response.status_code, 200)
        self.assertTemplateUsed(response, "index.html")


class CreateUserViewTest(TestCase):
    def test_create_user_view_get(self):
        response = self.client.get(reverse("create_user"))
        self.assertEqual(response.status_code, 200)
        self.assertTemplateUsed(response, "create_user.html")

    def test_create_user_view_post(self):
        response = self.client.post(
            reverse("create_user"),
            {"first_name": "John", "last_name": "Doe", "email": "john.doe@example.com"},
        )
        self.assertEqual(response.status_code, 302)  # Редирект после успешного создания
        self.assertTrue(User.objects.filter(email="john.doe@example.com").exists())


class UserListViewTest(TestCase):
    def setUp(self):
        self.user1 = User.objects.create(username="user1", email="user1@example.com")
        self.user2 = User.objects.create(username="user2", email="user2@example.com")

    def test_user_list_view(self):
        response = self.client.get(reverse("user_list"))
        self.assertEqual(response.status_code, 200)
        self.assertTemplateUsed(response, "users_list.html")
        self.assertContains(response, "user1")
        self.assertContains(response, "user2")
