import json
import subprocess
import uuid

bot_id = "cloiafj9e00091aqj6o9nfrww"
def fetch_json(col):
    cmd = ["docker", "exec", "-i", "typebot-typebot-db-1", "psql", "-U", "postgres", "-d", "typebot", "-t", "-A", "-c", f"SELECT {col} FROM \"Typebot\" WHERE id = '{bot_id}'"]
    return json.loads(subprocess.check_output(cmd).decode('utf-8').strip())

edges = fetch_json("edges")

# Retry item ID
retry_item_id = "c6a6hvdabmbbvd87bq3mi3rpu"
retry_block_id = "c3jgk7kksumhzdcjiw0uajmw5"

# Target group and block
target_group_id = "clf3000dce63e444c6ae165ac"
target_block_id = "cyo6ebzqeo6jvbq7lajfn591o"

# Check if edge already exists
edge_exists = False
for edge in edges:
    if "from" in edge and edge["from"].get("itemId") == retry_item_id:
        edge_exists = True
        break

if not edge_exists:
    new_edge_id = "edge_retry_" + uuid.uuid4().hex[:12]
    new_edge = {
        "id": new_edge_id,
        "from": {
            "itemId": retry_item_id,
            "blockId": retry_block_id
        },
        "to": {
            "groupId": target_group_id,
            "blockId": target_block_id
        }
    }
    edges.append(new_edge)
    
    edges_json_escaped = json.dumps(edges).replace("'", "''")
    
    sql_content = f"""
    UPDATE "Typebot"
    SET edges = '{edges_json_escaped}'::jsonb
    WHERE id = '{bot_id}';
    
    UPDATE "PublicTypebot"
    SET edges = '{edges_json_escaped}'::jsonb
    WHERE "typebotId" = '{bot_id}';
    """
    
    with open("/root/presidential_bridge/update_retry.sql", "w") as f:
        f.write(sql_content)
        
    subprocess.check_call("docker exec -i typebot-typebot-db-1 psql -U postgres -d typebot < /root/presidential_bridge/update_retry.sql", shell=True)
    print("Retry edge injected successfully.")
else:
    print("Retry edge already exists.")
