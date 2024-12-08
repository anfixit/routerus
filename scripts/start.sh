#!/bin/bash

set -e

LOG_FILE="/var/log/wg-manager/start.log"
exec >> $LOG_FILE 2>&1

echo "[$(date +"%Y-%m-%d %H:%M:%S")] Starting WireGuard Manager..."

# 1. Запуск Loki
echo "Starting Loki..."
docker run -d \
  --name=loki \
  -p 3100:3100 \
  -v /var/log/loki:/loki \
  -v /path/to/loki-config.yml:/etc/loki/local-config.yaml \
  grafana/loki:latest -config.file=/etc/loki/local-config.yaml

# 2. Запуск Promtail
echo "Starting Promtail..."
docker run -d \
  --name=promtail \
  -p 9080:9080 \
  -v /var/log:/var/log \
  -v /path/to/promtail-config.yml:/etc/promtail/config.yml \
  grafana/promtail:latest -config.file=/etc/promtail/config.yml

# 3. Запуск Nginx
echo "Starting Nginx..."
sudo nginx -c /path/to/nginx.conf

# 4. Запуск Shadowsocks
echo "Starting Shadowsocks..."
ssserver -c /path/to/shadowsocks.json --daemon

# 5. Запуск Xray
echo "Starting Xray..."
xray -config /path/to/xray.json &

# 6. Запуск Gunicorn
echo "Starting Gunicorn..."
gunicorn wg_manager.wsgi:application --bind 0.0.0.0:8000 --workers 3 &

# 7. Загрузка и очистка логов через Dropbox
echo "Uploading and cleaning logs via Dropbox..."
/path/to/scripts/dropbox_uploader.sh

# Финальное сообщение
echo "[$(date +"%Y-%m-%d %H:%M:%S")] All services started successfully."
