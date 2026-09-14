"""Берёт подписку служебного пользователя и печатает ссылки по подстроке домена: remark, порт, pbk, sni, fp, type."""
import sys, json, urllib.request, base64, urllib.parse
K, U, NEEDLE = sys.argv[1:4]
def get(p, raw=False, base=None):
    r = urllib.request.Request((base or U) + p, headers={"Authorization": "Bearer " + K, "User-Agent": "Happ/5.6"})
    d = urllib.request.urlopen(r, timeout=60).read()
    return d if raw else json.loads(d)["response"]
users = get("/api/users?size=50&start=0")["users"]
u = next((x for x in users if x.get("tag") == "SVOI" and x["status"] == "ACTIVE"), users[0])
print("пользователь:", u["username"], "tag:", u.get("tag"), "status:", u["status"])
sub = u["subscriptionUrl"]
raw = urllib.request.urlopen(urllib.request.Request(sub, headers={"User-Agent": "v2rayNG/1.9"}), timeout=60).read().decode()
try: links = base64.b64decode(raw + "=" * (-len(raw) % 4)).decode().split("\n")
except Exception: links = raw.split("\n")
print("всего ссылок:", len([l for l in links if l.startswith("vless://")]))
for l in links:
    if NEEDLE in l:
        p = urllib.parse.urlparse(l); q = urllib.parse.parse_qs(p.query)
        print(f'  {urllib.parse.unquote(p.fragment):32} {p.hostname}:{p.port} type={q.get("type")} pbk={q.get("pbk")} sni={q.get("sni")} fp={q.get("fp")} flow={q.get("flow")} path={q.get("path")} sid={q.get("sid")}')
