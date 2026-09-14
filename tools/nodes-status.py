import sys, json, urllib.request
K, U = sys.argv[1:3]
r = urllib.request.Request(U + "/api/nodes", headers={"Authorization": "Bearer " + K})
nodes = json.load(urllib.request.urlopen(r, timeout=60))["response"]
for n in sorted(nodes, key=lambda x: x["name"]):
    print(f'{n["name"]:14} {n["address"]:16} conn={str(n["isConnected"]):5} online={n.get("usersOnline")} xray={n.get("xrayVersion")} msg={n.get("lastStatusMessage")}')
