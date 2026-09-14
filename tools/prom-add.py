"""prom-add.py NAME IP CC [EXPORTER_PORT] [XRAY_PORT] — идемпотентно добавляет ноду в jobs nodes и xray
файла prometheus.yml (путь в PROMETHEUS_YML, по умолчанию /opt/monitoring/prometheus/prometheus.yml).
После: promtool check config и docker kill -s HUP prometheus."""
import os
import sys, re
name, ip, cc = sys.argv[1:4]; ep = sys.argv[4] if len(sys.argv) > 4 else "9100"; xp = sys.argv[5] if len(sys.argv) > 5 else "443"
p = os.environ.get("PROMETHEUS_YML", "/opt/monitoring/prometheus/prometheus.yml"); s = open(p).read()
if f"node: '{name}'" in s or f"node: {name}" in s: print("уже есть"); sys.exit(0)
def add(job, block):
    global s
    m = re.search(rf"  - job_name: '{job}'\n(.*?)(?=\n  - job_name:|\Z)", s, re.S)
    sec = m.group(1)
    # вставить после последнего labels: в static_configs секции (до relabel_configs, если есть)
    idx = sec.rfind("        labels: {")
    end = sec.find("\n", idx) + 1
    s = s[:m.start(1)] + sec[:end] + block + sec[end:] + s[m.end(1):]
add("nodes", f"      - targets: ['{ip}:{ep}']\n        labels: {{node: '{name}', country: '{cc}'}}\n")
add("xray", f"      - targets: ['{ip}:{xp}']\n        labels: {{node: '{name}'}}\n")
open(p, "w").write(s); print("добавлено:", name)
