import json
import subprocess

bot_id = "cloiafj9e00091aqj6o9nfrww"

def fetch_json(col):
    cmd = ["docker", "exec", "-i", "typebot-typebot-db-1", "psql", "-U", "postgres", "-d", "typebot", "-t", "-A", "-c", f"SELECT {col} FROM \"Typebot\" WHERE id = '{bot_id}'"]
    return json.loads(subprocess.check_output(cmd).decode('utf-8').strip())

groups = fetch_json("groups")

for g in groups:
    if "Tokens" in g.get("title", "") or "Cart" in g.get("title", ""):
        for b in g.get("blocks", []):
            if b.get("type") == "text":
                content = b.get("content", {})
                for rt in content.get("richText", []):
                    for child in rt.get("children", []):
                        if "ADD_TO_CART" in child.get("text", ""):
                            print(child.get("text"))
