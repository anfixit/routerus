from django.shortcuts import render
from django.http import HttpResponse

# Главная страница
def index(request):
    return render(request, 'index.html')

# Страница списка пользователей
def users_list(request):
    users = [
        {'name': 'Анфиса', 'email': 'anfi@example.com'},
        {'name': 'Замира', 'email': 'zami@example.com'},
    ]
    return render(request, 'users_list.html', {'users': users})

# Страница создания пользователя
def create_user(request):
    if request.method == 'POST':
        name = request.POST.get('name')
        email = request.POST.get('email')
        return HttpResponse(f'Создан пользователь: {name} ({email})')
    return render(request, 'create_user.html')
