#!/bin/bash
# Ставит node_exporter: бинарник с GitHub, системный пользователь, unit, UFW только для сервера Prometheus.
#   sudo bash install-node-exporter.sh IP_PROMETHEUS [ПОРТ]
# Порт нужен нодам за NAT, где наружу проброшен ограниченный диапазон (по умолчанию 9100).
set -euo pipefail
V=1.9.1; KB="${1:?укажи IP сервера Prometheus}"; PORT="${2:-9100}"
if [[ -x /usr/local/bin/node_exporter ]] && /usr/local/bin/node_exporter --version 2>&1 | grep -q "version $V"; then echo "бинарник уже $V"; else
  cd /tmp && curl -fsSL -o ne.tgz "https://github.com/prometheus/node_exporter/releases/download/v$V/node_exporter-$V.linux-amd64.tar.gz"
  tar xzf ne.tgz && install -m755 node_exporter-$V.linux-amd64/node_exporter /usr/local/bin/node_exporter && rm -rf ne.tgz node_exporter-$V.linux-amd64
fi
id node_exporter >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin node_exporter
sed "s/__PORT__/$PORT/" > /etc/systemd/system/node_exporter.service <<'UNIT'
[Unit]
Description=Node Exporter
After=network.target

[Service]
Type=simple
User=node_exporter
Group=node_exporter
ExecStart=/usr/local/bin/node_exporter --web.listen-address=0.0.0.0:__PORT__
Restart=always
RestartSec=5
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload && systemctl enable --now node_exporter >/dev/null 2>&1; systemctl restart node_exporter
ufw status | grep -q "$PORT/tcp.*$KB" || ufw allow from $KB to any port $PORT proto tcp comment 'Prometheus' >/dev/null
sleep 1; echo "$(hostname): $(systemctl is-active node_exporter) $(curl -s -m3 localhost:$PORT/metrics | grep -c '^node_') метрик; ufw: $(ufw status | grep -c "$PORT/tcp.*$KB")"
