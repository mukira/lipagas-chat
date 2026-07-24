import json

with open("bot_dump.json") as f:
    bot = json.load(f)

groups = bot.get("groups", [])
edges = bot.get("edges", [])

target_group = None
choice_block = None

for g in groups:
    if g.get("title") == "Onboarding & Greeting":
        target_group = g
        break

if target_group:
    print(f"Found Group: {target_group['id']} at {target_group.get('graphCoordinates')}")
    for b in target_group.get("blocks", []):
        if b.get("type") == "Choice input":
            choice_block = b
            print(f"Found Choice Block: {b['id']}")
            for item in b.get("items", []):
                print(f"  Item: {item['id']} -> {item.get('content')}")
            
            # Find edges originating from this block
            print("Edges:")
            for e in edges:
                if e.get("from", {}).get("blockId") == b['id']:
                    print(f"  Edge from {e['from'].get('itemId')} -> Block {e.get('to', {}).get('blockId')} in Group {e.get('to', {}).get('groupId')}")

