import requests
import json
import uuid

API_KEY = "WCGihbMj8KWUS2jI9jBF44-BktZtrm4Vqz7XSsyT6as"
BOT_ID = "cmrxyzuid00011eqd86ujabc2"
URL = f"https://builder.lipagas.co/api/v1/typebots/{BOT_ID}"

headers = {
    "Authorization": f"Bearer {API_KEY}",
    "Content-Type": "application/json"
}

res = requests.get(URL, headers=headers)
typebot = res.json().get("typebot")

def cuid(prefix="cuid"):
    uid = str(uuid.uuid4()).replace("-", "")
    return (prefix + uid)[:25].ljust(25, "0")

onboarding_group = typebot["groups"][0]
ai_group_id = typebot["groups"][1]["id"]
ai_loop_first_block_id = typebot["groups"][1]["blocks"][0]["id"]

# The current structure has language -> topic choice directly.
# The user wants Topic to be:
# 3 Top Level Buttons:
# [ 🏗️ Projects & Development ]  [ 💰 Economy & Opportunities ]  [ 💬 Ask a Question ]

# Let's find the current topic choice block
topic_block_idx = None
for idx, block in enumerate(onboarding_group["blocks"]):
    if block.get("type") == "choice input":
        if "items" in block and len(block["items"]) > 0 and "Projects & Development" in block["items"][0].get("content", ""):
            topic_block_idx = idx
            break

if topic_block_idx is not None:
    topic_block = onboarding_group["blocks"][topic_block_idx]
    
    # Update the topic choice block to have the 3 top level buttons
    top_level_items = [
        {"id": cuid("itm_tl_prj"), "content": "🏗️ Projects & Development", "outgoingEdgeId": cuid("edg_tl_prj")},
        {"id": cuid("itm_tl_eco"), "content": "💰 Economy & Opportunities", "outgoingEdgeId": cuid("edg_tl_eco")},
        {"id": cuid("itm_tl_ask"), "content": "💬 Ask a Question", "outgoingEdgeId": cuid("edg_tl_ask")}
    ]
    topic_block["items"] = top_level_items
    
    # We need to remove the old topic edges
    typebot["edges"] = [e for e in typebot["edges"] if not (e.get("from", {}).get("blockId") == topic_block["id"])]
    
    # Now we need to create the sub-menus as new groups because a single choice block can only route.
    # Group: Submenu Projects
    grp_sub_prj_id = cuid("grp_sb_prj")
    blk_sub_prj_choice = {
        "id": cuid("blk_sub_prj"),
        "type": "choice input",
        "options": {"variableId": topic_block["options"]["variableId"]},
        "items": [
            {"id": cuid("itm_sp_1"), "content": "📍 Projects Near My County", "outgoingEdgeId": cuid("edg_sp_1")},
            {"id": cuid("itm_sp_2"), "content": "🏠 Housing & Infrastructure", "outgoingEdgeId": cuid("edg_sp_2")},
            {"id": cuid("itm_sp_3"), "content": "�� Farming & Agriculture", "outgoingEdgeId": cuid("edg_sp_3")},
            {"id": cuid("itm_sp_4"), "content": "🔌 Energy & Roads", "outgoingEdgeId": cuid("edg_sp_4")}
        ]
    }
    grp_sub_prj = {
        "id": grp_sub_prj_id,
        "title": "Projects Submenu",
        "graphCoordinates": {"x": 0, "y": 200},
        "blocks": [blk_sub_prj_choice]
    }
    
    # Group: Submenu Economy
    grp_sub_eco_id = cuid("grp_sb_eco")
    blk_sub_eco_choice = {
        "id": cuid("blk_sub_eco"),
        "type": "choice input",
        "options": {"variableId": topic_block["options"]["variableId"]},
        "items": [
            {"id": cuid("itm_se_1"), "content": "💼 Business / Hustler Support", "outgoingEdgeId": cuid("edg_se_1")},
            {"id": cuid("itm_se_2"), "content": "💻 Youth & Digital Opportunities", "outgoingEdgeId": cuid("edg_se_2")},
            {"id": cuid("itm_se_3"), "content": "📊 Key BETA Pillars & Policies", "outgoingEdgeId": cuid("edg_se_3")}
        ]
    }
    grp_sub_eco = {
        "id": grp_sub_eco_id,
        "title": "Economy Submenu",
        "graphCoordinates": {"x": 0, "y": 400},
        "blocks": [blk_sub_eco_choice]
    }
    
    # Group: Ask Question
    grp_ask_id = cuid("grp_ask")
    blk_ask_text = {
        "id": cuid("blk_ask_txt"),
        "type": "text",
        "content": {"richText": [{"id": cuid("p_"), "type": "p", "children": [{"text": "Go ahead, type your question and I'll get you a verified answer. 🇰🇪"}]}]}
    }
    # Then it needs to jump to AI Loop. Let's just make an edge from here to AI loop.
    grp_ask = {
        "id": grp_ask_id,
        "title": "Ask Question",
        "graphCoordinates": {"x": 0, "y": 600},
        "blocks": [blk_ask_text]
    }
    
    typebot["groups"].extend([grp_sub_prj, grp_sub_eco, grp_ask])
    
    # Edges from Topic block to submenus
    typebot["edges"].extend([
        {"id": top_level_items[0]["outgoingEdgeId"], "from": {"blockId": topic_block["id"], "itemId": top_level_items[0]["id"]}, "to": {"groupId": grp_sub_prj_id, "blockId": blk_sub_prj_choice["id"]}},
        {"id": top_level_items[1]["outgoingEdgeId"], "from": {"blockId": topic_block["id"], "itemId": top_level_items[1]["id"]}, "to": {"groupId": grp_sub_eco_id, "blockId": blk_sub_eco_choice["id"]}},
        {"id": top_level_items[2]["outgoingEdgeId"], "from": {"blockId": topic_block["id"], "itemId": top_level_items[2]["id"]}, "to": {"groupId": grp_ask_id, "blockId": blk_ask_text["id"]}}
    ])
    
    # Edges from submenus and ask to AI Loop
    for item in blk_sub_prj_choice["items"]:
        typebot["edges"].append({
            "id": item["outgoingEdgeId"],
            "from": {"blockId": blk_sub_prj_choice["id"], "itemId": item["id"]},
            "to": {"groupId": ai_group_id, "blockId": ai_loop_first_block_id}
        })
        
    for item in blk_sub_eco_choice["items"]:
        typebot["edges"].append({
            "id": item["outgoingEdgeId"],
            "from": {"blockId": blk_sub_eco_choice["id"], "itemId": item["id"]},
            "to": {"groupId": ai_group_id, "blockId": ai_loop_first_block_id}
        })
        
    # Edge from ask text block to AI loop
    edge_ask_ai_id = cuid("edg_ask_ai")
    typebot["edges"].append({
        "id": edge_ask_ai_id,
        "from": {"blockId": blk_ask_text["id"]},
        "to": {"groupId": ai_group_id, "blockId": ai_loop_first_block_id}
    })

# Generate SQL
groups_json_escaped = json.dumps(typebot["groups"]).replace("'", "''")
edges_json_escaped = json.dumps(typebot["edges"]).replace("'", "''")
variables_json_escaped = json.dumps(typebot["variables"]).replace("'", "''")

sql_content = f"""
UPDATE "Typebot"
SET groups = '{groups_json_escaped}'::jsonb,
    edges = '{edges_json_escaped}'::jsonb,
    variables = '{variables_json_escaped}'::jsonb,
    "updatedAt" = NOW()
WHERE id = '{BOT_ID}';

UPDATE "PublicTypebot"
SET groups = '{groups_json_escaped}'::jsonb,
    edges = '{edges_json_escaped}'::jsonb,
    variables = '{variables_json_escaped}'::jsonb,
    "updatedAt" = NOW()
WHERE "typebotId" = '{BOT_ID}';
"""

with open("/tmp/update_topic.sql", "w") as f:
    f.write(sql_content)

print("Generated /tmp/update_topic.sql")
