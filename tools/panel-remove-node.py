"""Выводит ноды из панели Remnawave: слепок → перевесить виртуальные хосты балансировщика
на живые ноды той же страны → хосты → ноды → профили → сверка сквада и биллинга.

    panel-remove-node.py KEY URL имя1[,имя2,...]          # только показать, что будет затронуто
    panel-remove-node.py KEY URL имя1[,имя2,...] apply    # выполнить

Слепок удаляемого кладётся в ~/backup-profiles/. Виртуальный хост (исключён из
XRAY_BASE64) принадлежит inbound'у ноды; если её удалить, страна пропадёт из
JSON-подписки, поэтому такие хосты перевешиваются на другой настоящий хост с тем же тегом.
"""
import sys, os, json, urllib.request, urllib.error, datetime
K, U = sys.argv[1:3]
NAMES = set(sys.argv[3].split(","))
DRY = not (len(sys.argv) > 4 and sys.argv[4] == "apply")
def req(method, path, data=None):
    r = urllib.request.Request(U + path, method=method,
        headers={"Authorization": "Bearer " + K, "Content-Type": "application/json"},
        data=json.dumps(data).encode() if data is not None else None)
    try:
        with urllib.request.urlopen(r, timeout=60) as resp:
            return resp.status, json.loads(resp.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:400]
def get(p): 
    st, r = req("GET", p); assert st == 200, (p, st, r); return r["response"]
nodes = get("/api/nodes"); hosts = get("/api/hosts"); profs = get("/api/config-profiles")["configProfiles"]
SQUAD_NAME = os.environ.get("SQUAD_NAME", "Default-Squad")
SQUAD = next(q["uuid"] for q in get("/api/internal-squads")["internalSquads"] if q["name"] == SQUAD_NAME)
sq = get(f"/api/internal-squads/{SQUAD}")
tn = [n for n in nodes if n["name"] in NAMES]
tp = [p for p in profs if p["name"] in NAMES]
tp_inb = {i["uuid"] for p in tp for i in p["inbounds"]}
th = [h for h in hosts if (h.get("inbound") or {}).get("configProfileInboundUuid") in tp_inb]
snap = {"when": datetime.datetime.now().isoformat(), "nodes": tn, "profiles": tp, "hosts": th, "squad_inbounds": [i["uuid"] for i in sq["inbounds"]]}
import os; fn = os.path.expanduser("~/backup-profiles") + f"/before-delete-{"_".join(sorted(NAMES))}-{datetime.date.today()}.json"
os.makedirs(os.path.expanduser("~/backup-profiles"), exist_ok=True); json.dump(snap, open(fn, "w"), ensure_ascii=False, indent=1)
print("слепок:", fn)
print("ноды:", [n["name"] for n in tn]); print("профили:", [p["name"] for p in tp]); print("хосты:", [h["remark"] for h in th])

# 0. виртуальные хосты балансировщика, висящие на входах удаляемых нод, перевешиваем на живые ноды той же страны
def find_real(tag):
    return next(h for h in hosts if tag in (h.get("tags") or []) and "XRAY_JSON" in (h.get("excludeFromSubscriptionTypes") or [])
                and (h.get("inbound") or {}).get("configProfileInboundUuid") not in tp_inb)
virt = [h for h in th if "XRAY_BASE64" in (h.get("excludeFromSubscriptionTypes") or [])]
for v in virt:
    tag = v["tags"][0]; r = find_real(tag)
    print(f"перевесить {v['remark']} [{tag}] -> вход {r['inbound']['configProfileInboundUuid'][:8]} ({r['remark']}, {r['address']}:{r['port']})")
    if not DRY:
        st, res = req("PATCH", "/api/hosts", {"uuid": v["uuid"], "inbound": {"configProfileUuid": r["inbound"]["configProfileUuid"],
                      "configProfileInboundUuid": r["inbound"]["configProfileInboundUuid"]}, "address": r["address"], "port": r["port"]})
        print("   PATCH", st, "" if st == 200 else res)
th = [h for h in th if h not in virt]
if DRY: print("dry-run, ничего не удаляю; добавь аргумент apply"); sys.exit(0)
for h in th:
    st, r = req("DELETE", f"/api/hosts/{h['uuid']}"); print("хост", h["remark"], st)
for n in tn:
    st, r = req("DELETE", f"/api/nodes/{n['uuid']}"); print("нода", n["name"], st)
for p in tp:
    st, r = req("DELETE", f"/api/config-profiles/{p['uuid']}"); print("профиль", p["name"], st, "" if st in (200,204) else r)
sq2 = get(f"/api/internal-squads/{SQUAD}")
left = [i["uuid"] for i in sq2["inbounds"] if i["uuid"] in tp_inb]
print("сквад: входов", len(sq2["inbounds"]), "остатков удалённых:", len(left))
b = get("/api/infra-billing/nodes")
print("биллинг, осталось привязок:", [x.get("name") or (x.get("node") or {}).get("name") for x in b.get("billingNodes", []) if ((x.get("node") or {}).get("name") or x.get("name")) in NAMES])
