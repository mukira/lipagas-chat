import json
with open("bot_dump.json") as f:
    d = json.load(f)
    g = [g for g in d["groups"] if g["id"] == "grp_ask9d5c99ed0bfd456683"][0]
    print(json.dumps(g, indent=2))
