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

# Find the onboarding group (groups[0])
onboarding_group = typebot["groups"][0]

# Find the language choice input block
for block in onboarding_group["blocks"]:
    if block.get("type") == "choice input":
        # We assume the first choice input is language, let's verify by checking content
        if "items" in block and len(block["items"]) > 0 and "English" in block["items"][0].get("content", ""):
            # Update the language choices with the specific text requested by the user
            block["items"] = [
                {
                    "id": cuid("itm_lg_en"),
                    "content": "🇬🇧 English",
                    "outgoingEdgeId": cuid("edg_lg_en")
                },
                {
                    "id": cuid("itm_lg_sw"),
                    "content": "🇰🇪 Kiswahili",
                    "outgoingEdgeId": cuid("edg_lg_sw")
                },
                {
                    "id": cuid("itm_lg_sh"),
                    "content": "😎 Sheng",
                    "outgoingEdgeId": cuid("edg_lg_sh")
                }
            ]
            
            # Now we must update edges for these new items
            # First, find the target block ID for these edges (which is the topic ask block)
            # The topic ask block is the one right after the language choice block
            idx = onboarding_group["blocks"].index(block)
            target_block_id = onboarding_group["blocks"][idx+1]["id"]
            
            # Remove old language edges
            typebot["edges"] = [e for e in typebot["edges"] if not (e.get("from", {}).get("blockId") == block["id"])]
            
            # Add new edges
            for item in block["items"]:
                typebot["edges"].append({
                    "id": item["outgoingEdgeId"],
                    "from": {"blockId": block["id"], "itemId": item["id"]},
                    "to": {"groupId": onboarding_group["id"], "blockId": target_block_id}
                })
            break


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

with open("/tmp/update_lang.sql", "w") as f:
    f.write(sql_content)

print("Generated /tmp/update_lang.sql")
