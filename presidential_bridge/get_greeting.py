import json, subprocess
bot_id = "cmrxyzuid00011eqd86ujabc2"
cmd = ["sudo", "docker", "exec", "-i", "unified-deployment-postgres-1", "psql", "-U", "postgres", "-d", "typebot", "-t", "-A", "-c", f"SELECT groups FROM \"Typebot\" WHERE id = '{bot_id}'"]
groups = json.loads(subprocess.check_output(cmd).decode('utf-8').strip())

for g in groups:
    for b in g.get("blocks", []):
        if b.get("type") == "text":
            content = b.get("content", {}).get("html", "") or b.get("content", {}).get("richText", [])
            print(f"Group: {g.get('title')} - Block ID: {b.get('id')} - Content: {content}")
