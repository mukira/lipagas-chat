import json

with open("bot_dump.json") as f:
    bot = json.load(f)

groups = bot.get("groups", [])
edges = bot.get("edges", [])

for g in groups:
    if g.get("id") == "grp_2b0554a47ef54af9a4a1":
        print("Group Schema:")
        print(json.dumps(g, indent=2))
        
print("Edge Schema (for English):")
for e in edges:
    if e.get("from", {}).get("itemId") == "itm_f9ae403d1497491f8483":
        print(json.dumps(e, indent=2))
