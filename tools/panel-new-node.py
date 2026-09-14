"""Заводит новую ноду в панели Remnawave одним прогоном.

Аргументы: KEY URL ИМЯ IP СТРАНА ДОМЕН НОМЕР_В_СТРАНЕ ФАЙЛ_ПРОФИЛЯ ПРОВАЙДЕР ДАТА_ОПЛАТЫ [NODE_PORT] [SNI]
Пример: panel-new-node.py $K $U toolvps-nl 31.77.100.91 NL tool-nl.ru 3 profile.json ToolVPS 2026-10-05

Сквад берётся по имени из переменной SQUAD_NAME (по умолчанию Default-Squad).
Шаги: профиль из JSON ноды → нода → SECRET_KEY (печатается в stdout последним) →
два хоста с тегами балансировщика (TCP Reality = 🌐 CC_MOB, XHTTP = 🛜 CC_WIFI),
исключённые из XRAY_JSON → входы в Default-Squad → привязка к биллингу.
Идемпотентно: что уже есть, пропускается.
"""
import sys, json, urllib.request, urllib.error

K, U, NAME, IP, CC, DOMAIN, NUM, PROFILE_FILE, PROVIDER, BILL_DATE = sys.argv[1:11]
NODE_PORT = int(sys.argv[11]) if len(sys.argv) > 11 else 2222
SNI = sys.argv[12] if len(sys.argv) > 12 else DOMAIN
FLAG = {"DE": "🇩🇪 Германия", "NL": "🇳🇱 Нидерланды", "US": "🇺🇸 США", "AT": "🇦🇹 Австрия",
        "FI": "🇫🇮 Финляндия", "KZ": "🇰🇿 Казахстан", "SE": "🇸🇪 Швеция", "PL": "🇵🇱 Польша", "EE": "🇪🇪 Эстония"}
import os
SQUAD_NAME = os.environ.get("SQUAD_NAME", "Default-Squad")

def req(method, path, data=None):
    r = urllib.request.Request(U + path, method=method,
        headers={"Authorization": "Bearer " + K, "Content-Type": "application/json"},
        data=json.dumps(data).encode() if data is not None else None)
    try:
        with urllib.request.urlopen(r, timeout=60) as resp:
            return resp.status, json.loads(resp.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:600]

def must(st, res, what):
    if st not in (200, 201):
        print(f"ОШИБКА {what}: {st} {res}"); sys.exit(1)
    return res["response"]

# 1. профиль
profiles = must(*req("GET", "/api/config-profiles"), "список профилей")["configProfiles"]
prof = next((p for p in profiles if p["name"] == NAME), None)
if prof:
    print(f"профиль {NAME}: уже есть")
else:
    cfg = json.load(open(PROFILE_FILE))
    prof = must(*req("POST", "/api/config-profiles", {"name": NAME, "config": cfg}), "создание профиля")
    print(f"профиль {NAME}: создан")
inbounds = {i["tag"]: i for i in prof["inbounds"]}
tcp = next((i for t, i in inbounds.items() if t.endswith("_tcp")), None)
xhttp = next((i for t, i in inbounds.items() if t.endswith("_xhttp")), None)
if not tcp or not xhttp:
    print("в профиле нет пары *_tcp / *_xhttp:", list(inbounds)); sys.exit(1)
print(f"входы: {tcp['tag']} :{tcp['port']}, {xhttp['tag']} :{xhttp['port']}")

# 2. нода
nodes = must(*req("GET", "/api/nodes"), "список нод")
node = next((n for n in nodes if n["name"] == NAME), None)
if node:
    print(f"нода {NAME}: уже есть")
else:
    body = {"name": NAME, "address": IP, "port": NODE_PORT, "countryCode": CC,
            "isTrafficTrackingActive": False, "trafficLimitBytes": 0, "notifyPercent": 0, "trafficResetDay": 1,
            "consumptionMultiplier": 1,
            "configProfile": {"activeConfigProfileUuid": prof["uuid"], "activeInbounds": [tcp["uuid"], xhttp["uuid"]]}}
    node = must(*req("POST", "/api/nodes", body), "создание ноды")
    print(f"нода {NAME}: создана")

# 3. хосты
hosts = must(*req("GET", "/api/hosts"), "список хостов")
have = {h["remark"] for h in hosts}
base = f"{FLAG.get(CC, CC)}-{NUM}"
plan = [
    (f"{base} 🌐⚡", tcp, tcp["port"], None, None, f"{CC}_MOB"),
    (f"{base} 🛜⚡", xhttp, xhttp["port"], "/api/v1/update", "h2", f"{CC}_WIFI"),
]
for remark, ib, port, path, alpn, tag in plan:
    if remark in have:
        print(f"хост {remark}: уже есть"); continue
    body = {"inbound": {"configProfileUuid": prof["uuid"], "configProfileInboundUuid": ib["uuid"]},
            "remark": remark, "address": DOMAIN, "port": port, "sni": SNI, "fingerprint": "firefox",
            "path": path, "alpn": alpn, "isDisabled": False, "tags": [tag],
            "excludeFromSubscriptionTypes": ["XRAY_JSON"]}
    body = {k: v for k, v in body.items() if v is not None}
    must(*req("POST", "/api/hosts", body), f"создание хоста {remark}")
    print(f"хост {remark}: создан, тег {tag}, порт {port}")

# 4. сквад: полный список входов + новые (PATCH заменяет список, а не дополняет)
squads = must(*req("GET", "/api/internal-squads"), "список сквадов")["internalSquads"]
SQUAD = next((q["uuid"] for q in squads if q["name"] == SQUAD_NAME), None)
if not SQUAD:
    print("сквад не найден:", SQUAD_NAME, "есть:", [q["name"] for q in squads]); sys.exit(1)
sq = must(*req("GET", f"/api/internal-squads/{SQUAD}"), "сквад")
cur = [i["uuid"] for i in sq["inbounds"]]
need = [u for u in (tcp["uuid"], xhttp["uuid"]) if u not in cur]
if need:
    must(*req("PATCH", "/api/internal-squads", {"uuid": SQUAD, "inbounds": cur + need}), "обновление сквада")
    print(f"сквад: добавлено входов {len(need)}, всего {len(cur) + len(need)}")
else:
    print(f"сквад: входы уже на месте ({len(cur)})")

# 5. биллинг
bill = must(*req("GET", "/api/infra-billing/nodes"), "биллинг")
if any((b.get("node") or {}).get("name") == NAME or b.get("name") == NAME for b in bill.get("billingNodes", [])):
    print("биллинг: нода уже привязана")
else:
    provs = must(*req("GET", "/api/infra-billing/providers"), "провайдеры")["providers"]
    pv = next((p for p in provs if p["name"] == PROVIDER), None)
    avail = {n["name"]: n["uuid"] for n in bill.get("availableBillingNodes", [])}
    if pv and NAME in avail:
        must(*req("POST", "/api/infra-billing/nodes", {"name": NAME, "providerUuid": pv["uuid"], "nodeUuid": avail[NAME],
                  "nextBillingAt": BILL_DATE + "T00:00:00.000Z"}), "привязка биллинга")
        print(f"биллинг: {NAME} → {PROVIDER}, оплата до {BILL_DATE}")
    else:
        print("биллинг: провайдер или нода не найдены", bool(pv), NAME in avail)

# 6. ключ ноды — последней строкой, чтобы забрать в .env
kg = must(*req("GET", "/api/keygen"), "keygen")
print("SECRET_KEY=" + kg["secretKey"])
