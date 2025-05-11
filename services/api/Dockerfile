FROM python:3.12-slim

WORKDIR /app

# Установка зависимостей
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Установка wireguard-tools, iptables и другие необходимые утилиты
RUN apt-get update && apt-get install -y --no-install-recommends     wireguard-tools     iptables     iproute2     procps     && apt-get clean     && rm -rf /var/lib/apt/lists/*

# Копирование кода приложения
COPY ./app /app/app

# Запуск с использованием Uvicorn
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--reload"]
