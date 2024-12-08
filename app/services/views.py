from django.shortcuts import render, redirect
from django.http import HttpResponse
from django.db import IntegrityError
from .models import User
import logging

logger = logging.getLogger(__name__)

def home(request):
    """
    Главная страница.
    """
    logger.info("Home page accessed")
    return render(request, 'index.html')


def create_user(request):
    """
    Создание нового пользователя.
    """
    logger.info("Create user page accessed")
    if request.method == "POST":
        try:
            # Получение данных из формы
            first_name = request.POST.get("first_name", "").strip()
            last_name = request.POST.get("last_name", "").strip()
            email = request.POST.get("email", "").strip()

            if not first_name or not last_name or not email:
                logger.warning("Incomplete form submission")
                return HttpResponse("All fields are required!", status=400)

            # Проверка, существует ли пользователь
            if User.objects.filter(email=email).exists():
                logger.warning(f"User with email {email} already exists")
                return HttpResponse("User with this email already exists!", status=400)

            # Создание пользователя
            User.objects.create(username=f"{first_name} {last_name}", email=email)
            logger.info(f"User {first_name} {last_name} created successfully")
            return redirect("user_list")

        except IntegrityError as e:
            logger.error(f"Database integrity error: {e}")
            return HttpResponse("A database error occurred while creating the user!", status=500)
        except Exception as e:
            logger.error(f"Unexpected error: {e}")
            return HttpResponse("An unexpected error occurred!", status=500)

    return render(request, 'create_user.html')


def user_list(request):
    """
    Отображение списка всех пользователей.
    """
    logger.info("User list page accessed")
    try:
        users = User.objects.all()  # Получение списка всех пользователей
        return render(request, 'users_list.html', {'users': users})
    except Exception as e:
        logger.error(f"Error fetching user list: {e}")
        return HttpResponse("An error occurred while fetching user list!", status=500)
