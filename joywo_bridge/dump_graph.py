import json
import subprocess

bot_id = "cloiafj9e00091aqj6o9nfrww"
cmd = ["docker", "exec", "-i", "typebot-typebot-db-1", "psql", "-U", "postgres", "-d", "typebot", "-t", "-A", "-c", f"SELECT groups, edges FROM \"Typebot\" WHERE id = '{bot_id}'"]
output = subprocess.check_output(cmd).decode('utf-8').strip()
groups_str, edges_str = output.split('\n')
groups = json.loads(groups_str)
edges = json.loads(edges_str)

for g in groups:
    # Check for "usual spot" text
    for b in g.get("blocks", []):
        if b.get("type") == "text":
            content = json.dumps(b.get("content", {}))
            if "usual spot" in content.lower():
                print(f"Found 'usual spot' in group {g.get('title')}: {content}")
        
        # Check for choice inputs
        if b.get("type") == "choice input":
            for item in b.get("items", []):
                if "new location" in item.get("content", "").lower():
                    print(f"Found '{item.get('content')}' button in block {b.get('id')}. Edge ID: {item.get('outgoingEdgeId')}")
                    # Find where this edge points
                    for e in edges:
                        if e.get("id") == item.get("outgoingEdgeId"):
                            print(f"  -> Edge points to block {e['to'].get('blockId')} in group {e['to'].get('groupId')}")
