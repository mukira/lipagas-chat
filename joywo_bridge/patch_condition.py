import json
import subprocess
import uuid

bot_id = "cloiafj9e00091aqj6o9nfrww"
def fetch_json(col):
    cmd = ["docker", "exec", "-i", "typebot-typebot-db-1", "psql", "-U", "postgres", "-d", "typebot", "-t", "-A", "-c", f"SELECT {col} FROM \"Typebot\" WHERE id = '{bot_id}'"]
    return json.loads(subprocess.check_output(cmd).decode('utf-8').strip())

groups = fetch_json("groups")
edges = fetch_json("edges")

# 1. Target group ID
target_group_id = "cbpny37yztf7vo7zzyca2putp"

# 2. Find incoming edges to the target group that point to the group itself or the first block
incoming_edges = []
for e in edges:
    to_obj = e.get("to", {})
    if to_obj.get("groupId") == target_group_id and ("blockId" not in to_obj or to_obj.get("blockId") == "cglst6p1x725tf34tv2yvfyzv"):
        incoming_edges.append(e)

# 3. Create new groups
grp_check_cond_id = "grp_cond_" + uuid.uuid4().hex[:12]
blk_cond_id = "blk_cond_" + uuid.uuid4().hex[:12]
item_cond_true_id = "item_cond_" + uuid.uuid4().hex[:12]
edge_cond_true_id = "edge_true_" + uuid.uuid4().hex[:12]
edge_cond_false_id = "edge_false_" + uuid.uuid4().hex[:12]

grp_new_user_loc_id = "grp_new_loc_" + uuid.uuid4().hex[:12]
blk_new_user_text_id = "blk_text_" + uuid.uuid4().hex[:12]
blk_new_user_choice_id = "blk_choice_" + uuid.uuid4().hex[:12]
item_choice_id = "item_choice_" + uuid.uuid4().hex[:12]
edge_new_user_loc_id = "edge_new_loc_" + uuid.uuid4().hex[:12]

# Group: Condition Check
grp_check_cond = {
    "id": grp_check_cond_id,
    "title": "Check if Location Exists",
    "graphCoordinates": {"x": -1000, "y": -2200},
    "blocks": [
        {
            "id": blk_cond_id,
            "type": "Condition",
            "items": [
                {
                    "id": item_cond_true_id,
                    "content": {
                        "logicalOperator": "AND",
                        "comparisons": [
                            {
                                "id": "comp_" + uuid.uuid4().hex[:12],
                                "variableId": "czx1vosksjwfmt52egtx1jtj7", # SavedLocation
                                "comparisonOperator": "Is set"
                            }
                        ]
                    },
                    "outgoingEdgeId": edge_cond_true_id
                }
            ],
            "outgoingEdgeId": edge_cond_false_id
        }
    ]
}

# Group: New User Location Prompt
grp_new_user_loc = {
    "id": grp_new_user_loc_id,
    "title": "New User Location Prompt",
    "graphCoordinates": {"x": -600, "y": -2200},
    "blocks": [
        {
            "id": blk_new_user_text_id,
            "type": "text",
            "content": {
                "richText": [
                    {
                        "type": "p",
                        "children": [{"text": "Please enter your delivery location:"}]
                    }
                ]
            }
        },
        {
            "id": blk_new_user_choice_id,
            "type": "choice input",
            "items": [
                {
                    "id": item_choice_id,
                    "content": "✏️ Enter New Location",
                    "outgoingEdgeId": edge_new_user_loc_id
                }
            ],
            "options": {"isMultipleChoice": False}
        }
    ]
}

groups.append(grp_check_cond)
groups.append(grp_new_user_loc)

# 4. Create new edges
edges.append({
    "id": edge_cond_true_id,
    "to": {"groupId": target_group_id, "blockId": "cglst6p1x725tf34tv2yvfyzv"},
    "from": {"blockId": blk_cond_id, "itemId": item_cond_true_id}
})

edges.append({
    "id": edge_cond_false_id,
    "to": {"groupId": grp_new_user_loc_id, "blockId": blk_new_user_text_id},
    "from": {"blockId": blk_cond_id}
})

edges.append({
    "id": edge_new_user_loc_id,
    "to": {"groupId": "clf6900635b9104409ad4c4ed", "blockId": "chhmqjnkv90n8ako819y0a618"},
    "from": {"blockId": blk_new_user_choice_id, "itemId": item_choice_id}
})

# 5. Modify incoming edges to point to grp_check_cond
for e in incoming_edges:
    e["to"] = {"groupId": grp_check_cond_id, "blockId": blk_cond_id}
    print(f"Modified edge {e['id']} to point to Condition block.")

# 6. Save to DB
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

with open("/root/lipagas_bridge/update_condition.sql", "w") as f:
    f.write(sql_content)

subprocess.check_call("docker exec -i typebot-typebot-db-1 psql -U postgres -d typebot < /root/lipagas_bridge/update_condition.sql", shell=True)
print("Condition block injected successfully.")
