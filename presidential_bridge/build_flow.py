import json

def cuid(prefix="cuid"):
    import uuid
    uid = str(uuid.uuid4()).replace("-", "")
    return (prefix + uid)[:25].ljust(25, "0")

# Load V2 backup
with open("/tmp/backup_bot.json", "r") as f:
    typebot = json.load(f)

# Variables
var_initial = "cmrulouid00011eqdvar00001"
var_reply = "cmrulouid00011eqdvar00002"
var_name = "cmrulouid00011eqdvar00003"
var_news = "cmrulouid00011eqdvar00004"
var_greeting = cuid("var_grt")
var_lang = cuid("var_lng")
var_topic = cuid("var_top")

# Ensure variables exist
existing_var_ids = [v["id"] for v in typebot.get("variables", [])]
for v_id, v_name in [(var_greeting, "Greeting"), (var_lang, "Language"), (var_topic, "Topic")]:
    if v_id not in existing_var_ids:
        typebot.setdefault("variables", []).append({
            "id": v_id,
            "name": v_name,
            "isSessionVariable": True
        })

# New Group 1: Onboarding
grp_onboard_id = cuid("grp_onbd")
blk_ask_name = {
    "id": cuid("blk_asknm"),
    "type": "text",
    "content": {"richText": [{"id": cuid("p_"), "type": "p", "children": [{"text": "Welcome to Presidential Updates. Before we begin, what is your name?"}]}]}
}
blk_input_name = {
    "id": cuid("blk_in_nm"),
    "type": "text input",
    "options": {"variableId": var_name, "labels": {"placeholder": "Type your name...", "button": "Send"}}
}
blk_webhook_greet = {
    "id": cuid("blk_wh_grt"),
    "type": "webhook",
    "options": {
        "webhookId": "cwebhook00001presidential00000",
        "url": "https://flow.lipagas.co/api/ai/greeting",
        "method": "POST",
        "headers": [{"key": "Content-Type", "value": "application/json"}],
        "body": "{\"user_name\":\"{{user_name}}\"}",
        "responseVariableMapping": [{"id": cuid("map_grt"), "bodyPath": "greeting", "variableId": var_greeting}]
    }
}
blk_show_greet = {
    "id": cuid("blk_sh_grt"),
    "type": "text",
    "content": {"richText": [{"id": cuid("p_"), "type": "p", "children": [{"text": "{{Greeting}}"}]}]}
}
blk_ask_lang = {
    "id": cuid("blk_ask_lg"),
    "type": "text",
    "content": {"richText": [{"id": cuid("p_"), "type": "p", "children": [{"text": "Which language do you prefer?"}]}]}
}

# The language choice options
lang_choices = [
    {"id": cuid("itm_lg_en"), "content": "🇬🇧 English"},
    {"id": cuid("itm_lg_sw"), "content": "🇰🇪 Swahili"},
    {"id": cuid("itm_lg_sh"), "content": "Sheng"}
]

blk_choice_lang = {
    "id": cuid("blk_ch_lg"),
    "type": "choice input",
    "options": {"variableId": var_lang},
    "items": lang_choices
}

blk_ask_topic = {
    "id": cuid("blk_ask_tp"),
    "type": "text",
    "content": {"richText": [{"id": cuid("p_"), "type": "p", "children": [{"text": "Sawa, {{user_name}}! 👍 What area are you interested in?"}]}]}
}

topic_choices = [
    {"id": cuid("itm_tp_1"), "content": "🏗️ Projects & Development"},
    {"id": cuid("itm_tp_2"), "content": "💰 Economy & Hustler Fund"},
    {"id": cuid("itm_tp_3"), "content": "🎓 Education & CBC"},
    {"id": cuid("itm_tp_4"), "content": "🏥 Health & SHIF"},
    {"id": cuid("itm_tp_5"), "content": "🌱 Agriculture & Fertilizer"}
]

blk_choice_topic = {
    "id": cuid("blk_ch_tp"),
    "type": "choice input",
    "options": {"variableId": var_topic},
    "items": topic_choices
}

grp_onboard = {
    "id": grp_onboard_id,
    "title": "Onboarding & Greeting",
    "graphCoordinates": {"x": -400, "y": 0},
    "blocks": [
        blk_ask_name,
        blk_input_name,
        blk_webhook_greet,
        blk_show_greet,
        blk_ask_lang,
        blk_choice_lang,
        blk_ask_topic,
        blk_choice_topic
    ]
}

# Add Group
groups = typebot.get("groups", [])
# Find AI Loop group (from V2 backup, it's groups[0])
ai_group_id = groups[0]["id"]
ai_loop_first_block_id = groups[0]["blocks"][0]["id"]

groups.insert(0, grp_onboard)
typebot["groups"] = groups

# Update edges
edges = typebot.get("edges", [])
# Remove old start edge
edges = [e for e in edges if "eventId" not in e.get("from", {})]

# New start edge -> Onboarding group
edges.append({
    "id": cuid("edg_start"),
    "from": {"eventId": typebot["events"][0]["id"]},
    "to": {"groupId": grp_onboard_id, "blockId": blk_ask_name["id"]}
})

# All language items point to ask_topic
for lang_item in lang_choices:
    lang_item["outgoingEdgeId"] = cuid("edg_lg_" + lang_item["id"][-4:])
    edges.append({
        "id": lang_item["outgoingEdgeId"],
        "from": {"blockId": blk_choice_lang["id"], "itemId": lang_item["id"]},
        "to": {"groupId": grp_onboard_id, "blockId": blk_ask_topic["id"]}
    })

# All topic items point to AI Loop webhook
for top_item in topic_choices:
    top_item["outgoingEdgeId"] = cuid("edg_tp_" + top_item["id"][-4:])
    edges.append({
        "id": top_item["outgoingEdgeId"],
        "from": {"blockId": blk_choice_topic["id"], "itemId": top_item["id"]},
        "to": {"groupId": ai_group_id, "blockId": ai_loop_first_block_id}
    })

typebot["edges"] = edges

import json
groups_json_escaped = json.dumps(typebot["groups"]).replace("'", "''")
edges_json_escaped = json.dumps(typebot["edges"]).replace("'", "''")
variables_json_escaped = json.dumps(typebot["variables"]).replace("'", "''")

sql_content = f"""
UPDATE "Typebot"
SET groups = '{groups_json_escaped}'::jsonb,
    edges = '{edges_json_escaped}'::jsonb,
    variables = '{variables_json_escaped}'::jsonb,
    "updatedAt" = NOW()
WHERE id = 'cmrxyzuid00011eqd86ujabc2';

UPDATE "PublicTypebot"
SET groups = '{groups_json_escaped}'::jsonb,
    edges = '{edges_json_escaped}'::jsonb,
    variables = '{variables_json_escaped}'::jsonb,
    "updatedAt" = NOW()
WHERE "typebotId" = 'cmrxyzuid00011eqd86ujabc2';
"""

with open("/tmp/update_v2.sql", "w") as f:
    f.write(sql_content)

print("Generated /tmp/update_v2.sql")
