from django.shortcuts import render, redirect
from .forms import WireGuardConfigForm
from .models import WireGuardConfig

def index(request):
    return render(request, 'index.html')

def request_config(request):
    if request.method == 'POST':
        form = WireGuardConfigForm(request.POST)
        if form.is_valid():
            form.save()
            return redirect('success')
    else:
        form = WireGuardConfigForm()
    return render(request, 'request_config.html', {'form': form})

def create_config(request):
    if request.method == 'POST':
        form = WireGuardConfigForm(request.POST)
        if form.is_valid():
            form.save()
            return redirect('config_list')
    else:
        form = WireGuardConfigForm()
    return render(request, 'create_config.html', {'form': form})

def config_list(request):
    configs = WireGuardConfig.objects.all()
    return render(request, 'config_list.html', {'configs': configs})

def success(request):
    return render(request, 'success.html')
