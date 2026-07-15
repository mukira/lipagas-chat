import json
import subprocess

bot_id = "cloiafj9e00091aqj6o9nfrww"
def fetch_json(col):
    cmd = ["docker", "exec", "-i", "typebot-typebot-db-1", "psql", "-U", "postgres", "-d", "typebot", "-t", "-A", "-c", f"SELECT {col} FROM \"Typebot\" WHERE id = '{bot_id}'"]
    return json.loads(subprocess.check_output(cmd).decode('utf-8').strip())

groups = fetch_json("groups")
edges = fetch_json("edges")

block_to_fix = None
for group in groups:
    if group.get("title") == "Add Tokens to Cart":
        for block in group.get("blocks", []):
            try:
                text = block["content"]["richText"][0]["children"][0]["text"]
                if "[ADD_TO_CART:" in text:
                    block_to_fix = block
            except Exception:
                pass

if not block_to_fix:
    print("Block not found!")
    exit(1)

# Find the edge that originates from this block
edge_id = None
for edge in edges:
    if "from" in edge and edge["from"].get("blockId") == block_to_fix["id"]:
        edge_id = edge["id"]
        break

if not edge_id:
    print("No edge found originating from the block!")
    exit(1)

print(f"Found block {block_to_fix['id']} and edge {edge_id}")

# Add the missing property
block_to_fix["outgoingEdgeId"] = edge_id

# Save to DB
groups_json_escaped = json.dumps(groups).replace("'", "''")

sql_content = f"""
UPDATE "Typebot"
SET groups = '{groups_json_escaped}'::jsonb
WHERE id = '{bot_id}';

UPDATE "PublicTypebot"
SET groups = '{groups_json_escaped}'::jsonb
WHERE "typebotId" = '{bot_id}';
"""

with open("/root/lipagas_bridge/update_tokens_fix.sql", "w") as f:
    f.write(sql_content)

subprocess.check_call("docker exec -i typebot-typebot-db-1 psql -U postgres -d typebot < /root/lipagas_bridge/update_tokens_fix.sql", shell=True)
print("Tokens block fixed successfully.")
