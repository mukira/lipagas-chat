import json
import subprocess
import uuid

bot_id = "cloiafj9e00091aqj6o9nfrww"
target_group_id = "clf6900635b9104409ad4c4ed" # Location Group
target_block_id = "chhmqjnkv90n8ako819y0a618" # [LOCATION_PROMPT] Block (bypass condition loop)

cmd_g = ["docker", "exec", "-i", "typebot-typebot-db-1", "psql", "-U", "postgres", "-d", "typebot", "-t", "-A", "-c", f"SELECT groups FROM \"Typebot\" WHERE id = '{bot_id}'"]
groups_str = subprocess.check_output(cmd_g).decode('utf-8').strip()
groups = json.loads(groups_str)

cmd_e = ["docker", "exec", "-i", "typebot-typebot-db-1", "psql", "-U", "postgres", "-d", "typebot", "-t", "-A", "-c", f"SELECT edges FROM \"Typebot\" WHERE id = '{bot_id}'"]
edges_str = subprocess.check_output(cmd_e).decode('utf-8').strip()
edges = json.loads(edges_str)

modified = False

for g in groups:
    for b in g.get("blocks", []):
        if b.get("type") == "choice input":
            for item in b.get("items", []):
                content = item.get("content", "").lower()
                if "new location" in content:
                    current_edge_id = item.get("outgoingEdgeId")
                    edge = next((e for e in edges if e.get("id") == current_edge_id), None)
                    
                    if not edge or edge.get("to", {}).get("blockId") != target_block_id:
                        if edge:
                            # Update existing edge
                            edge["to"]["groupId"] = target_group_id
                            edge["to"]["blockId"] = target_block_id
                            print(f"Updated existing edge {edge['id']} to point to correct Location block")
                        else:
                            # Create new edge
                            new_edge_id = "edge_new_loc_" + str(uuid.uuid4())[:8]
                            item["outgoingEdgeId"] = new_edge_id
                            edges.append({
                                "id": new_edge_id,
                                "from": {
                                    "blockId": b.get("id"),
                                    "itemId": item.get("id")
                                },
                                "to": {
                                    "groupId": target_group_id,
                                    "blockId": target_block_id
                                }
                            })
                            print(f"Created new edge {new_edge_id} connecting '{item.get('content')}' to Location block")
                        modified = True

if modified:
    edges_escaped = json.dumps(edges).replace("'", "''")
    groups_escaped = json.dumps(groups).replace("'", "''")
    
    sql = f"""
    UPDATE "Typebot" SET edges = '{edges_escaped}'::jsonb, groups = '{groups_escaped}'::jsonb WHERE id = '{bot_id}';
    UPDATE "PublicTypebot" SET edges = '{edges_escaped}'::jsonb, groups = '{groups_escaped}'::jsonb WHERE "typebotId" = '{bot_id}';
    """
    with open("/root/presidential_bridge/fix_all_missing_edges.sql", "w") as f:
        f.write(sql)
    
    subprocess.check_call("docker exec -i typebot-typebot-db-1 psql -U postgres -d typebot < /root/presidential_bridge/fix_all_missing_edges.sql", shell=True)
    print("Database updated successfully!")
else:
    print("No orphaned or misconfigured buttons found.")
