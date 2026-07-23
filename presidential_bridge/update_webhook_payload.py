import requests
import json

API_KEY = "WCGihbMj8KWUS2jI9jBF44-BktZtrm4Vqz7XSsyT6as"
BOT_ID = "cmrxyzuid00011eqd86ujabc2"
URL = f"https://builder.lipagas.co/api/v1/typebots/{BOT_ID}"

headers = {
    "Authorization": f"Bearer {API_KEY}",
    "Content-Type": "application/json"
}

res = requests.get(URL, headers=headers)
typebot = res.json().get("typebot")

# Let's find the variables first to get their IDs
var_initial = None
var_reply = None
var_name = None
var_news = None
var_lang = None
var_topic = None

for v in typebot.get("variables", []):
    name = v.get("name")
    vid = v.get("id")
    if name == "InitialMessage": var_initial = vid
    elif name == "Reply": var_reply = vid
    elif name == "user_name": var_name = vid
    elif name == "latest_news": var_news = vid
    elif name == "Language": var_lang = vid
    elif name == "Topic": var_topic = vid

# Find the webhook block in the AI Loop
ai_group = next((g for g in typebot["groups"] if g.get("title") == "Presidential AI"), None)
if ai_group:
    for block in ai_group["blocks"]:
        if block.get("type") == "webhook":
            # Update the webhook block to include the necessary payload and mappings
            block["options"] = {
                "webhookId": "cwebhook00001presidential00000",
                "url": "https://flow.lipagas.co/api/ai/proxy",
                "method": "POST",
                "headers": [{"key": "Content-Type", "value": "application/json"}],
                "body": json.dumps({
                    "user_name": "{{user_name}}",
                    "user_language": "{{Language}}",
                    "user_topic": "{{Topic}}",
                    "message": "{{InitialMessage}}",
                    "news": "{{latest_news}}"
                }),
                "responseVariableMapping": [
                    {
                        "id": "cmrulouid00011eqdmap00001",
                        "bodyPath": "reply",
                        "variableId": var_reply
                    }
                ]
            }

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

with open("/tmp/update_webhook.sql", "w") as f:
    f.write(sql_content)

print("Generated /tmp/update_webhook.sql")
