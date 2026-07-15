import json
import subprocess
import uuid

bot_id = "cloiafj9e00091aqj6o9nfrww"
def fetch_json(col):
    cmd = ["docker", "exec", "-i", "typebot-typebot-db-1", "psql", "-U", "postgres", "-d", "typebot", "-t", "-A", "-c", f"SELECT {col} FROM \"Typebot\" WHERE id = '{bot_id}'"]
    return json.loads(subprocess.check_output(cmd).decode('utf-8').strip())

groups = fetch_json("groups")
edges = fetch_json("edges")

# 1. Create new group
new_group_id = "grp_tokens_" + uuid.uuid4().hex[:12]
new_block_id = "blk_tokens_" + uuid.uuid4().hex[:12]
new_edge_id = "edge_tokens_" + uuid.uuid4().hex[:12]

new_group = {
    "id": new_group_id,
    "title": "Add Tokens to Cart",
    "graphCoordinates": {
        "x": 1244.98 + 350,
        "y": 912.84
    },
    "blocks": [
        {
            "id": new_block_id,
            "type": "text",
            "content": {
                "richText": [
                    {
                        "type": "p",
                        "children": [
                            {
                                "text": "[ADD_TO_CART:{{var_amount}}|Gas Tokens]"
                            }
                        ]
                    }
                ]
            }
        }
    ]
}

groups.append(new_group)

# 2. Redirect existing edge cmf55rh1h8663e6k50h8eyk51 to the new group
edge_found = False
for edge in edges:
    if edge["id"] == "cmf55rh1h8663e6k50h8eyk51":
        edge["to"] = {"groupId": new_group_id, "blockId": new_block_id}
        edge_found = True
        break

if not edge_found:
    print("Edge cmf55rh1h8663e6k50h8eyk51 not found!")
    exit(1)

# 3. Add new edge from new group to Cart Summary (cl3c4ecb6b8bfe48fc9594695)
new_edge = {
    "id": new_edge_id,
    "from": {
        "blockId": new_block_id
    },
    "to": {
        "groupId": "cl3c4ecb6b8bfe48fc9594695"
    }
}

edges.append(new_edge)

# 4. Save to DB
groups_json_escaped = json.dumps(groups).replace("'", "''")
edges_json_escaped = json.dumps(edges).replace("'", "''")

sql_content = f"""
UPDATE "Typebot"
SET groups = '{groups_json_escaped}'::jsonb,
    edges = '{edges_json_escaped}'::jsonb
WHERE id = '{bot_id}';

UPDATE "PublicTypebot"
SET groups = '{groups_json_escaped}'::jsonb,
    edges = '{edges_json_escaped}'::jsonb
WHERE "typebotId" = '{bot_id}';
"""

with open("/root/lipagas_bridge/update_tokens.sql", "w") as f:
    f.write(sql_content)

subprocess.check_call("docker exec -i typebot-typebot-db-1 psql -U postgres -d typebot < /root/lipagas_bridge/update_tokens.sql", shell=True)
print("Tokens patch injected successfully.")
