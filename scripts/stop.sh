#!/bin/bash
set -e

# Параметры
LOG_FILE="/var/log/wg-manager/stop.log"

exec >> $LOG_FILE 2>&1
echo "[$(date +"%Y-%m-%d %H:%M:%S")] Stopping WireGuard Manager..."

# 1. Остановка Shadowsocks
echo "Stopping Shadowsocks..."
pkill -f "ssserver" || echo "Shadowsocks already stopped."

# 2. Остановка Xray
echo "Stopping Xray..."
pkill -f "xray" || echo "Xray already stopped."

# 3. Остановка Gunicorn
echo "Stopping Gunicorn..."
pkill -f "gunicorn" || echo "Gunicorn already stopped."

# 4. Остановка Nginx
echo "Stopping Nginx..."
sudo nginx -s quit || echo "Nginx already stopped."

echo "[$(date +"%Y-%m-%d %H:%M:%S")] All services stopped successfully."
