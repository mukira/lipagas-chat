import json
import uuid

def cuid(prefix="cuid"):
    uid = str(uuid.uuid4()).replace("-", "")
    return (prefix + uid)[:25].ljust(25, "0")

bot_state_path = "/home/mukira/.gemini/antigravity-ide/brain/865b4881-80e4-4340-aa9f-6a45f7df5e0e/scratch/bot_state_formatted.json"
output_sql_path = "/home/mukira/lipagas-chat/presidential_bridge/restore_bot.sql"

with open(bot_state_path, "r") as f:
    typebot = json.load(f)

# The greetings
greetings = [
    "Habari yako, {{display_name}}! 👋\n\nIt's me, William Ruto. I know you're busy, and I respect that. So let me be quick.\n\nThis is your direct line to what my government is doing for you, real projects, real money, real facts. No spin, no noise.\n\nWhat would you like to know today?",
    "Sasa, {{display_name}}! 🇰🇪\n\nYou know me, I came from nothing, a chicken seller from Sugoi. I understand what it means to hustle every day for your family.\n\nThat's exactly why I built this, so you can ask me anything, and I'll give you straight answers about what we're building for Kenya.\n\nWhat's on your mind?",
    "Habari za leo! 👋\n\nI'm here. Not my spokesperson. Not a press release. Me.\n\nI started this because I believe in you, {{display_name}}, and every Kenyan deserves direct, honest communication about what your government is doing.\n\nAsk me anything, projects, policies, or what's happening in your area. Facts only.",
    "Karibu sana, {{display_name}}. 🙏\n\nEvery morning I wake up thinking about one thing, how do I make sure the mwananchi's life is better than yesterday?\n\nThis is where that conversation happens. Whether you're a farmer, a trader, a student, or just a curious Kenyan, you belong here.\n\nWhat can I help you with today?",
    "Karibu, {{display_name}}! 👋\n\nKenya's story is being written right now, and you are part of it.\n\nWhether you're a hustler in Gikomba, a farmer in Rift Valley, a student in Kisumu, or a mama running a small business, this government is working for you.\n\nLet me show you what's being done. Ask me anything. 🇰🇪"
]

# Ensure greeting_index and display_name variables exist
variables = typebot.get("variables", [])
var_greeting_index_id = None
var_display_name_id = None

for v in variables:
    if v["name"] == "greeting_index":
        var_greeting_index_id = v["id"]
    if v["name"] == "display_name":
        var_display_name_id = v["id"]

if not var_greeting_index_id:
    var_greeting_index_id = cuid("var_grt_idx")
    variables.append({"id": var_greeting_index_id, "name": "greeting_index", "isSessionVariable": True})

if not var_display_name_id:
    var_display_name_id = cuid("var_disp_nm")
    variables.append({"id": var_display_name_id, "name": "display_name", "isSessionVariable": True})

typebot["variables"] = variables

groups = typebot.get("groups", [])
edges = typebot.get("edges", [])

target_group = None
greeting_block_index = -1
greeting_block_id = None

for g in groups:
    if g.get("title") == "Onboarding & Greeting":
        target_group = g
        blocks = g.get("blocks", [])
        for i, b in enumerate(blocks):
            if b.get("type") == "text":
                content = b.get("content", {})
                for p in content.get("richText", []):
                    for child in p.get("children", []):
                        if "{{Greeting}}" in child.get("text", ""):
                            greeting_block_index = i
                            greeting_block_id = b["id"]
                            break
        break

if target_group and greeting_block_index != -1:
    target_group["blocks"].pop(greeting_block_index)
    
    next_block_id = None
    if greeting_block_index < len(target_group["blocks"]):
        next_block_id = target_group["blocks"][greeting_block_index]["id"]
    
    router_group_id = cuid("grp_router")
    router_group = {
        "id": router_group_id,
        "title": "Greeting Router",
        "graphCoordinates": {"x": target_group["graphCoordinates"]["x"] - 400, "y": target_group["graphCoordinates"]["y"]},
        "blocks": []
    }
    
    cond_block_id = cuid("blk_cond")
    cond_block = {
        "id": cond_block_id,
        "type": "Condition",
        "items": []
    }
    
    for i, greeting in enumerate(greetings, 1):
        item_id = cuid("itm_cond")
        edge_id = cuid("edg_cond")
        
        cond_block["items"].append({
            "id": item_id,
            "content": {
                "logicalOperator": "AND",
                "comparisons": [
                    {
                        "id": cuid("comp"),
                        "variableId": var_greeting_index_id,
                        "comparisonOperator": "Equal to",
                        "value": str(i)
                    }
                ]
            },
            "outgoingEdgeId": edge_id
        })
        
        greet_grp_id = cuid("grp_gtext")
        greet_blk_id = cuid("blk_gtext")
        greet_edge_id = cuid("edg_gtext")
        
        greet_grp = {
            "id": greet_grp_id,
            "title": f"Greeting {i}",
            "graphCoordinates": {"x": router_group["graphCoordinates"]["x"] + 400, "y": router_group["graphCoordinates"]["y"] + (i-1)*150},
            "blocks": [
                {
                    "id": greet_blk_id,
                    "type": "text",
                    "content": {
                        "richText": [
                            {
                                "id": cuid("p_"),
                                "type": "p",
                                "children": [{"text": greeting}]
                            }
                        ]
                    },
                    "outgoingEdgeId": greet_edge_id
                }
            ]
        }
        groups.append(greet_grp)
        
        edges.append({
            "id": edge_id,
            "from": {"blockId": cond_block_id, "itemId": item_id},
            "to": {"groupId": greet_grp_id}
        })
        
        if next_block_id:
            edges.append({
                "id": greet_edge_id,
                "from": {"blockId": greet_blk_id},
                "to": {"groupId": target_group["id"], "blockId": next_block_id}
            })
    
    router_group["blocks"].append(cond_block)
    groups.append(router_group)
    
    for e in edges:
        if e.get("to", {}).get("groupId") == target_group["id"] and (not e["to"].get("blockId") or e["to"].get("blockId") == greeting_block_id):
            e["to"]["groupId"] = router_group_id
            e["to"].pop("blockId", None)

typebot["publicId"] = "presidential-bot"
typebot["workspaceId"] = "cmq5o6k9z00001nmd5apo7dr4"  

groups_json = json.dumps(typebot.get("groups", [])).replace("'", "''")
edges_json = json.dumps(typebot.get("edges", [])).replace("'", "''")
variables_json = json.dumps(typebot.get("variables", [])).replace("'", "''")
theme_json = json.dumps(typebot.get("theme", {})).replace("'", "''")
settings_json = json.dumps(typebot.get("settings", {})).replace("'", "''")
events_json = json.dumps(typebot.get("events", [])).replace("'", "''")

sql = f"""
INSERT INTO "Typebot" (
    id, "createdAt", "updatedAt", name, groups, variables, edges, theme, settings, "publicId", "workspaceId", "isArchived", "isClosed", version, events
) VALUES (
    'cmrxyzuid00011eqd86ujabc2', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, '{typebot['name']}', 
    '{groups_json}'::jsonb, '{variables_json}'::jsonb, '{edges_json}'::jsonb, '{theme_json}'::jsonb, '{settings_json}'::jsonb,
    'presidential-bot', '{typebot['workspaceId']}', false, false, '6', '{events_json}'::jsonb
) ON CONFLICT (id) DO UPDATE SET
    groups = EXCLUDED.groups,
    variables = EXCLUDED.variables,
    edges = EXCLUDED.edges,
    theme = EXCLUDED.theme,
    settings = EXCLUDED.settings,
    "publicId" = EXCLUDED."publicId",
    events = EXCLUDED.events,
    "updatedAt" = CURRENT_TIMESTAMP;

INSERT INTO "PublicTypebot" (
    id, "createdAt", "updatedAt", "typebotId", groups, variables, edges, theme, settings, version, events
) VALUES (
    'pub_cmrxyzuid00011eqd86ujabc2', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'cmrxyzuid00011eqd86ujabc2',
    '{groups_json}'::jsonb, '{variables_json}'::jsonb, '{edges_json}'::jsonb, '{theme_json}'::jsonb, '{settings_json}'::jsonb, '6', '{events_json}'::jsonb
) ON CONFLICT (id) DO UPDATE SET
    groups = EXCLUDED.groups,
    variables = EXCLUDED.variables,
    edges = EXCLUDED.edges,
    theme = EXCLUDED.theme,
    settings = EXCLUDED.settings,
    events = EXCLUDED.events,
    "updatedAt" = CURRENT_TIMESTAMP;
"""

with open(output_sql_path, "w") as f:
    f.write(sql)
print("Done writing SQL")
