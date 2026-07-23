import json
import subprocess

cmd = ["docker", "exec", "-i", "typebot-typebot-db-1", "psql", "-U", "postgres", "-d", "typebot", "-t", "-A", "-c", "SELECT groups, edges FROM \"Typebot\" WHERE id = 'cloiafj9e00091aqj6o9nfrww'"]
res = subprocess.check_output(cmd).decode('utf-8').strip()
data = json.loads(res)
groups = data.get("groups", [])
edges = data.get("edges", [])

target_group_id = None
for e in edges:
    if e.get("id") == "c0866d745659d4478906353ee":
        target_group_id = e.get("to", {}).get("groupId")
        print("Buy Gas Tokens goes to group:", target_group_id)

for g in groups:
    if g.get("id") == target_group_id:
        print(json.dumps(g, indent=2))
