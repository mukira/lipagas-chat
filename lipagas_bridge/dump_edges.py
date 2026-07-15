import json
import subprocess

cmd = ["docker", "exec", "-i", "typebot-typebot-db-1", "psql", "-U", "postgres", "-d", "typebot", "-t", "-A", "-c", "SELECT row_to_json(t) FROM (SELECT groups, edges, variables FROM \"Typebot\" WHERE id = 'cloiafj9e00091aqj6o9nfrww') t"]
res = subprocess.check_output(cmd).decode('utf-8').strip()
data = json.loads(res)

groups = data.get("groups", [])
edges = data.get("edges", [])

def get_group_title(group_id):
    for g in groups:
        if g["id"] == group_id:
            return g.get("title", group_id)
    return group_id

for g in groups:
    if "PAYG" in g.get("title", ""):
        print("Group:", g["title"])
        for b in g.get("blocks", []):
            if "items" in b:
                for item in b["items"]:
                    print("  Button:", item.get("content"))
                    outgoing = item.get("outgoingEdgeId")
                    for e in edges:
                        if e["id"] == outgoing:
                            to_group = e.get("to", {}).get("groupId")
                            if to_group:
                                print("    -> goes to:", get_group_title(to_group))
            elif b.get("outgoingEdgeId"):
                outgoing = b.get("outgoingEdgeId")
                for e in edges:
                    if e["id"] == outgoing:
                        to_group = e.get("to", {}).get("groupId")
                        if to_group:
                            print("  Block -> goes to:", get_group_title(to_group))

