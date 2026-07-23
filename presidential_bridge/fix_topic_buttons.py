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

modified = False
for group in typebot.get("groups", []):
    for block in group.get("blocks", []):
        if block.get("type") == "choice input" and "items" in block:
            for item in block["items"]:
                content = item.get("content", "")
                if "Projects & Development" in content:
                    item["content"] = "🏗️ Projects & Dev"
                    modified = True
                elif "Economy & Opportunities" in content:
                    item["content"] = "💰 Economy & Opps"
                    modified = True
                # also let's check the submenu items just in case!
                elif "Projects Near My County" in content:
                    item["content"] = "📍 County Projects"
                    modified = True
                elif "Housing & Infrastructure" in content:
                    item["content"] = "🏠 Infrastructure"
                    modified = True
                elif "Farming & Agriculture" in content:
                    item["content"] = "🌱 Agriculture"
                    modified = True
                elif "Energy & Roads" in content:
                    item["content"] = "🔌 Energy & Roads"
                    modified = True
                elif "Business / Hustler Support" in content:
                    item["content"] = "💼 Hustler Support"
                    modified = True
                elif "Youth & Digital Opportunities" in content:
                    item["content"] = "💻 Youth & Digital"
                    modified = True
                elif "Key BETA Pillars & Policies" in content:
                    item["content"] = "📊 BETA Policies"
                    modified = True

if modified:
    groups_json = json.dumps(typebot["groups"]).replace("'", "''")
    sql_content = f"""
    UPDATE "Typebot"
    SET groups = '{groups_json}'::jsonb,
        "updatedAt" = NOW()
    WHERE id = '{BOT_ID}';

    UPDATE "PublicTypebot"
    SET groups = '{groups_json}'::jsonb,
        "updatedAt" = NOW()
    WHERE "typebotId" = '{BOT_ID}';
    """
    with open("/tmp/fix_buttons.sql", "w") as f:
        f.write(sql_content)
    print("Generated /tmp/fix_buttons.sql")
else:
    print("No modifications needed.")
