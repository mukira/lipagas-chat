import json

with open("bot_dump.json") as f:
    bot = json.load(f)

groups = bot.get("groups", [])
edges = bot.get("edges", [])

target_group = None

for g in groups:
    if g.get("title") == "Onboarding & Greeting":
        target_group = g
        break

if target_group:
    for b in target_group.get("blocks", []):
        print(f"Block: {b['id']}, type: {b.get('type')}")
        if b.get("type").lower() == "choice input":
            for item in b.get("items", []):
                print(f"  Item: {item['id']} -> {item.get('content')}")
            for e in edges:
                if e.get("from", {}).get("blockId") == b['id']:
                    print(f"  Edge from {e['from'].get('itemId')} -> Block {e.get('to', {}).get('blockId')} in Group {e.get('to', {}).get('groupId')}")

