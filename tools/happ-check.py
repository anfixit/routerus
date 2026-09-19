"""Подписка глазами Happ (XRAY_JSON): какие настоящие ноды сидят внутри каждого виртуального хоста-балансировщика."""
import sys, json, urllib.request
K, U = sys.argv[1:3]; FILT = sys.argv[3] if len(sys.argv) > 3 else ""
def api(p):
    r = urllib.request.Request(U + p, headers={"Authorization": "Bearer " + K}); return json.loads(urllib.request.urlopen(r, timeout=60).read())["response"]
users = api("/api/users?size=50&start=0")["users"]
# Служебный пользователь с самой полной подпиской: у части своих урезанный сквад.
cfgs = []
for x in ([x for x in users if x.get("tag") == "SVOI" and x["status"] == "ACTIVE"][:10] or users[:3]):
    try:
        raw = urllib.request.urlopen(urllib.request.Request(x["subscriptionUrl"], headers={"User-Agent": "Happ/5.6.0"}), timeout=60).read().decode()
        c = json.loads(raw); c = [c] if isinstance(c, dict) else c
        if len(c) > len(cfgs): cfgs, u = c, x
    except Exception: pass
if not cfgs: print("JSON-подписку получить не удалось"); sys.exit(1)
print("записей в JSON-подписке:", len(cfgs))
for c in cfgs:
    name = c.get("remarks") or c.get("name") or "?"
    if FILT and FILT not in name: continue
    outs = [o for o in c.get("outbounds", []) if o.get("tag", "").startswith("n-")]
    bal = c.get("routing", {}).get("balancers", [])
    addrs = [f'{o["settings"]["vnext"][0]["address"]}:{o["settings"]["vnext"][0]["port"]}' for o in outs if o.get("protocol") == "vless"]
    print(f"  {name}: {len(outs)} нод в балансировщике {[b.get('strategy',{}).get('type') for b in bal]}: {addrs}")
