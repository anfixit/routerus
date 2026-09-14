import sys, json, urllib.request
K, U = sys.argv[1:3]
def get(p):
    r = urllib.request.Request(U + p, headers={"Authorization": "Bearer " + K})
    return json.load(urllib.request.urlopen(r, timeout=60))["response"]
profs = get("/api/config-profiles")["configProfiles"]
inb = {i["uuid"]: (p["name"], i["tag"], i["port"]) for p in profs for i in p["inbounds"]}
for h in sorted(get("/api/hosts"), key=lambda h: (inb.get((h.get("inbound") or {}).get("configProfileInboundUuid"), ("?",))[0], h["remark"])):
    pi = inb.get((h.get("inbound") or {}).get("configProfileInboundUuid"), ("?", "?", "?"))
    kind = "VIRT" if "XRAY_BASE64" in (h.get("excludeFromSubscriptionTypes") or []) else "real"
    print(f'{kind} {pi[0]:12} {pi[1]:22} {h["remark"]:40} {h["address"]}:{h["port"]} sni={h.get("sni")} fp={h.get("fingerprint")} path={h.get("path")} alpn={h.get("alpn")} tags={h.get("tags")} uuid={h["uuid"][:8]}')
