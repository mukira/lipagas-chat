import json
import subprocess

# 1. Fetch current groups and edges from DB
bot_id = "cloiafj9e00091aqj6o9nfrww"
fetch_cmd = ["docker", "exec", "-i", "typebot-typebot-db-1", "psql", "-U", "postgres", "-d", "typebot", "-t", "-A", "-c", f"SELECT groups, edges FROM \"Typebot\" WHERE id = '{bot_id}'"]
output = subprocess.check_output(fetch_cmd).decode('utf-8').strip()

# Split by the last | or similar, or fetch them individually. Fetching individually is safer.
groups_cmd = ["docker", "exec", "-i", "typebot-typebot-db-1", "psql", "-U", "postgres", "-d", "typebot", "-t", "-A", "-c", f"SELECT groups FROM \"Typebot\" WHERE id = '{bot_id}'"]
groups_str = subprocess.check_output(groups_cmd).decode('utf-8').strip()

edges_cmd = ["docker", "exec", "-i", "typebot-typebot-db-1", "psql", "-U", "postgres", "-d", "typebot", "-t", "-A", "-c", f"SELECT edges FROM \"Typebot\" WHERE id = '{bot_id}'"]
edges_str = subprocess.check_output(edges_cmd).decode('utf-8').strip()

groups = json.loads(groups_str)
edges = json.loads(edges_str)

# 2. Modify groups
# A. Location group (id: clf6900635b9104409ad4c4ed) -> Add Item to Condition block
found_loc_group = False
for g in groups:
    if g.get("id") == "clf6900635b9104409ad4c4ed":
        found_loc_group = True
        for b in g.get("blocks", []):
            if b.get("id") == "cmc6zr5n1lkiztajvzkg9uy0r" and b.get("type") == "Condition":
                items = b.get("items", [])
                # Check if our item is already added
                if not any(item.get("id") == "c_item_loc_set" for item in items):
                    new_item = {
                        "id": "c_item_loc_set",
                        "content": {
                            "logicalOperator": "AND",
                            "comparisons": [
                                {
                                    "id": "c_comp_loc_set",
                                    "variableId": "c38gq5ykcvm9axzodrgpkh74s",
                                    "comparisonOperator": "Is set"
                                }
                            ]
                        },
                        "outgoingEdgeId": "c_edge_loc_set"
                    }
                    items.insert(0, new_item)
                    print("Added Location Is set check to Condition block.")
                else:
                    print("Location Is set check already exists in Condition block.")

if not found_loc_group:
    print("WARNING: Location group not found!")

# B. Check Saved Location group (id: cbpny37yztf7vo7zzyca2putp) -> Add Set variable block
found_saved_loc_group = False
for g in groups:
    if g.get("id") == "cbpny37yztf7vo7zzyca2putp":
        found_saved_loc_group = True
        blocks = g.get("blocks", [])
        # Check if our block exists, and set its outgoingEdgeId
        block_found = False
        for b in blocks:
            if b.get("id") == "c_set_variable_loc":
                b["outgoingEdgeId"] = "c_edge_set_loc_to_confirm"
                # Ensure options are correct too
                b["options"] = {
                    "type": "Custom",
                    "isExecutedOnClient": False,
                    "isCode": False,
                    "variableId": "c38gq5ykcvm9axzodrgpkh74s",
                    "expressionToEvaluate": "{{SavedLocation}}"
                }
                block_found = True
                print("Updated existing Set Variable block outgoingEdgeId.")
                break
        
        if not block_found:
            new_block = {
                "id": "c_set_variable_loc",
                "type": "Set variable",
                "outgoingEdgeId": "c_edge_set_loc_to_confirm",
                "options": {
                    "type": "Custom",
                    "isExecutedOnClient": False,
                    "isCode": False,
                    "variableId": "c38gq5ykcvm9axzodrgpkh74s",
                    "expressionToEvaluate": "{{SavedLocation}}"
                }
            }
            blocks.append(new_block)
            print("Added Set Variable block with outgoingEdgeId to Check Saved Location group.")

if not found_saved_loc_group:
    print("WARNING: Check Saved Location group not found!")

# 3. Modify edges
# A. Add new edge c_edge_loc_set
if not any(e.get("id") == "c_edge_loc_set" for e in edges):
    new_edge = {
        "id": "c_edge_loc_set",
        "to": {
            "groupId": "cl3c4ecb6b8bfe48fc9594695"
        },
        "from": {
            "itemId": "c_item_loc_set",
            "blockId": "cmc6zr5n1lkiztajvzkg9uy0r"
        }
    }
    edges.append(new_edge)
    print("Added edge c_edge_loc_set.")

# B. Add new edge c_edge_set_loc_to_confirm
if not any(e.get("id") == "c_edge_set_loc_to_confirm" for e in edges):
    new_edge = {
        "id": "c_edge_set_loc_to_confirm",
        "to": {
            "groupId": "cl3c4ecb6b8bfe48fc9594695"
        },
        "from": {
            "blockId": "c_set_variable_loc"
        }
    }
    edges.append(new_edge)
    print("Added edge c_edge_set_loc_to_confirm.")

# C. Modify edge ca6mclpws01i9f614s61yzt57
for e in edges:
    if e.get("id") == "ca6mclpws01i9f614s61yzt57":
        to_obj = e.get("to", {})
        if to_obj.get("groupId") == "cl3c4ecb6b8bfe48fc9594695" and "blockId" not in to_obj:
            to_obj["groupId"] = "cbpny37yztf7vo7zzyca2putp"
            to_obj["blockId"] = "c_set_variable_loc"
            print("Modified edge ca6mclpws01i9f614s61yzt57 to point to Set Variable block.")
        else:
            print("Edge ca6mclpws01i9f614s61yzt57 already modified or matches expected target.")

# 4. Generate SQL and update DB
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

with open("/root/presidential_bridge/update.sql", "w") as f:
    f.write(sql_content)

print("SQL file generated successfully.")

# Run the SQL file in docker
subprocess.check_call("docker exec -i typebot-typebot-db-1 psql -U postgres -d typebot < /root/presidential_bridge/update.sql", shell=True)
print("Database updated successfully.")
