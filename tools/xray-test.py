"""Клиентская проверка ноды: берёт ссылки подписки по подстроке, для каждой поднимает xray в docker и ходит через него наружу.
Запуск на сервере с docker: python3 xray-test.py KEY URL NEEDLE"""
import sys, json, urllib.request, urllib.parse, base64, subprocess, tempfile, os, time
K, U, NEEDLE = sys.argv[1:4]
def api(p):
    r = urllib.request.Request(U + p, headers={"Authorization": "Bearer " + K}); return json.loads(urllib.request.urlopen(r, timeout=60).read())["response"]
users = api("/api/users?size=50&start=0")["users"]
u = next((x for x in users if x.get("tag") == "SVOI" and x["status"] == "ACTIVE"), users[0])
raw = urllib.request.urlopen(urllib.request.Request(u["subscriptionUrl"], headers={"User-Agent": "v2rayNG/1.9"}), timeout=60).read().decode()
try: links = base64.b64decode(raw + "=" * (-len(raw) % 4)).decode().split("\n")
except Exception: links = raw.split("\n")
IMG = "ghcr.io/xtls/xray-core:latest"
for l in links:
    if NEEDLE not in l or not l.startswith("vless://"): continue
    p = urllib.parse.urlparse(l); q = {k: v[0] for k, v in urllib.parse.parse_qs(p.query).items()}
    name = urllib.parse.unquote(p.fragment)
    ss = {"network": q.get("type", "tcp"), "security": "reality",
          "realitySettings": {"serverName": q.get("sni"), "publicKey": q.get("pbk"), "shortId": q.get("sid", ""), "fingerprint": q.get("fp", "chrome"), "spiderX": q.get("spx", "/")}}
    if q.get("type") == "xhttp":
        ss["xhttpSettings"] = {"path": q.get("path", "/"), "mode": q.get("mode", "auto")}
        if q.get("host"): ss["xhttpSettings"]["host"] = q["host"]
    user = {"id": p.username, "encryption": "none"}
    if q.get("flow"): user["flow"] = q["flow"]
    cfg = {"log": {"loglevel": "warning"},
           "inbounds": [{"listen": "0.0.0.0", "port": 1080, "protocol": "socks", "settings": {"udp": False}}],
           "outbounds": [{"protocol": "vless", "settings": {"vnext": [{"address": p.hostname, "port": p.port, "users": [user]}]}, "streamSettings": ss}]}
    d = tempfile.mkdtemp(); os.chmod(d, 0o755); json.dump(cfg, open(d + "/config.json", "w")); os.chmod(d + "/config.json", 0o644)
    cname = "xraytest"
    subprocess.run(["docker", "rm", "-f", cname], capture_output=True)
    subprocess.run(["docker", "run", "-d", "--name", cname, "-p", "127.0.0.1:1080:1080", "-v", d + ":/etc/xray:ro", IMG, "run", "-c", "/etc/xray/config.json"], capture_output=True)
    time.sleep(3)
    r = subprocess.run(["curl", "-s", "-m", "20", "--socks5-hostname", "127.0.0.1:1080", "https://api.ipify.org"], capture_output=True, text=True)
    r2 = subprocess.run(["curl", "-s", "-m", "20", "-o", "/dev/null", "-w", "%{http_code} %{time_total}s", "--socks5-hostname", "127.0.0.1:1080", "https://www.google.com/generate_204"], capture_output=True, text=True)
    logs = subprocess.run(["docker", "logs", cname], capture_output=True, text=True); logs = (logs.stdout + logs.stderr)[-400:]
    ok = r.stdout.strip() == p.hostname_ip if False else bool(r.stdout.strip())
    print(f'{name:32} {p.hostname}:{p.port} type={q.get("type")} -> внешний IP через ноду: {r.stdout.strip() or "НЕТ"}; google_204: {r2.stdout}')
    if not r.stdout.strip(): print("   лог xray:", logs.replace("\n", " | "))
    subprocess.run(["docker", "rm", "-f", cname], capture_output=True)
