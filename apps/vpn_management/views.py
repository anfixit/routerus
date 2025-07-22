from django.shortcuts import render, redirect
from django.contrib import messages
from django.http import JsonResponse
from rest_framework.decorators import api_view
from rest_framework.response import Response

from .models import User, WireGuardConfig
from .forms import UserForm
from apps.services.service_manager import ServiceManager


def home(request):
    """Главная страница с информацией о системе"""
    context = {
        'total_users': User.objects.count(),
        'active_configs': WireGuardConfig.objects.count(),
        'title': 'Routerus VPN Management System'
    }
    return render(request, 'vpn_management/index.html', context)


def create_user(request):
    """Создание нового пользователя VPN"""
    if request.method == 'POST':
        form = UserForm(request.POST)
        if form.is_valid():
            user = form.save()
            messages.success(request, f'Пользователь {user.username} успешно создан!')
            return redirect('vpn_management:user_list')
    else:
        form = UserForm()

    return render(request, 'vpn_management/create_user.html', {'form': form})


def user_list(request):
    """Список всех пользователей"""
    users = User.objects.all().order_by('-created_at')
    return render(request, 'vpn_management/users_list.html', {'users': users})


@api_view(['GET'])
def service_status(request):
    """API endpoint для проверки статуса сервисов"""
    try:
        manager = ServiceManager()
        status = {}
        for service_name in manager.services.keys():
            service = manager.services[service_name]
            status[service_name] = {
                'active': service.is_active() if hasattr(service, 'is_active') else False,
                'name': service_name.title()
            }
        return Response({'status': 'success', 'services': status})
    except Exception as e:
        return Response({'status': 'error', 'message': str(e)}, status=500)


@api_view(['POST'])
def restart_service(request, service_name):
    """API endpoint для перезапуска сервиса"""
    try:
        manager = ServiceManager()
        if service_name in manager.services:
            manager.stop_service(service_name)
            manager.start_service(service_name)
            return Response({'status': 'success', 'message': f'Сервис {service_name} перезапущен'})
        else:
            return Response({'status': 'error', 'message': 'Сервис не найден'}, status=404)
    except Exception as e:
        return Response({'status': 'error', 'message': str(e)}, status=500)
