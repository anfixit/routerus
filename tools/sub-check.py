"""Берёт подписку служебного пользователя и печатает ссылки по подстроке домена: remark, порт, pbk, sni, fp, type."""
import sys, json, urllib.request, base64, urllib.parse
K, U, NEEDLE = sys.argv[1:4]
def get(p, raw=False, base=None):
    r = urllib.request.Request((base or U) + p, headers={"Authorization": "Bearer " + K, "User-Agent": "Happ/5.6"})
    d = urllib.request.urlopen(r, timeout=60).read()
    return d if raw else json.loads(d)["response"]
users = get("/api/users?size=50&start=0")["users"]
def pick_links(api_users):
    """Служебный пользователь с самой полной подпиской: у части своих урезанный сквад."""
    import base64 as _b
    best = (None, [])
    cands = [x for x in api_users if x.get("tag") == "SVOI" and x["status"] == "ACTIVE"][:10] or api_users[:3]
    for x in cands:
        try:
            raw = urllib.request.urlopen(urllib.request.Request(x["subscriptionUrl"], headers={"User-Agent": "v2rayNG/1.9"}), timeout=60).read().decode()
            try: ls = _b.b64decode(raw + "=" * (-len(raw) % 4)).decode().splitlines()
            except Exception: ls = raw.splitlines()
            ls = [l for l in ls if l.startswith("vless://")]
            if len(ls) > len(best[1]): best = (x, ls)
        except Exception: pass
    return best
u, links = pick_links(users)
print("пользователь:", u["username"], "tag:", u.get("tag"), "status:", u["status"])
print("всего ссылок:", len([l for l in links if l.startswith("vless://")]))
for l in links:
    if NEEDLE in l:
        p = urllib.parse.urlparse(l); q = urllib.parse.parse_qs(p.query)
        print(f'  {urllib.parse.unquote(p.fragment):32} {p.hostname}:{p.port} type={q.get("type")} pbk={q.get("pbk")} sni={q.get("sni")} fp={q.get("fp")} flow={q.get("flow")} path={q.get("path")} sid={q.get("sid")}')
