from django.shortcuts import render, redirect
from django.http import HttpResponse
from .utils import load_shadowsocks_config, load_xray_config, load_wireguard_config
from .forms import WireGuardConfigForm
import os

# Главная страница

def index(request):
    return render(request, 'index.html')

# Список конфигураций WireGuard

def config_list(request):
    wireguard_config = load_wireguard_config()
    # Здесь можно добавить логику для отображения списка конфигураций
    return render(request, 'config_list.html', {'config': wireguard_config})

# Создание новой конфигурации WireGuard

def create_config(request):
    if request.method == 'POST':
        form = WireGuardConfigForm(request.POST)
        if form.is_valid():
            form.save()
            return redirect('success')
    else:
        form = WireGuardConfigForm()
    return render(request, 'create_config.html', {'form': form})

# Обработчик успешного создания конфигурации

def success(request):
    return render(request, 'success.html')

# Генерация и отображение конфигурации Shadowsocks

def show_shadowsocks_config(request):
    shadowsocks_config = load_shadowsocks_config()
    return render(request, 'request_config.html', {'config': shadowsocks_config})

# Генерация и отображение конфигурации Xray

def show_xray_config(request):
    xray_config = load_xray_config()
    return render(request, 'request_config.html', {'config': xray_config})
