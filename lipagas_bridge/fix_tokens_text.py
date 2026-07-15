import json
import subprocess

bot_id = "cloiafj9e00091aqj6o9nfrww"

def fetch_json(col):
    cmd = ["docker", "exec", "-i", "typebot-typebot-db-1", "psql", "-U", "postgres", "-d", "typebot", "-t", "-A", "-c", f"SELECT {col} FROM \"Typebot\" WHERE id = '{bot_id}'"]
    return json.loads(subprocess.check_output(cmd).decode('utf-8').strip())

groups = fetch_json("groups")

fixed = False
for g in groups:
    if g.get("title") == "Add Tokens to Cart":
        for b in g.get("blocks", []):
            if b.get("type") == "text":
                content = b.get("content", {})
                for rt in content.get("richText", []):
                    for child in rt.get("children", []):
                        if "[ADD_TO_CART:{{var_amount}}|Gas Tokens]" in child.get("text", ""):
                            child["text"] = child["text"].replace("[ADD_TO_CART:{{var_amount}}|Gas Tokens]", "[ADD_TO_CART:{{Amount}}|Gas Tokens]")
                            fixed = True

if fixed:
    groups_json_escaped = json.dumps(groups).replace("'", "''")
    sql_content = f"""
UPDATE "Typebot"
SET groups = '{groups_json_escaped}'::jsonb
WHERE id = '{bot_id}';

UPDATE "PublicTypebot"
SET groups = '{groups_json_escaped}'::jsonb
WHERE "typebotId" = '{bot_id}';
"""
    with open("/root/lipagas_bridge/fix_tokens_text.sql", "w") as f:
        f.write(sql_content)

    subprocess.check_call("docker exec -i typebot-typebot-db-1 psql -U postgres -d typebot < /root/lipagas_bridge/fix_tokens_text.sql", shell=True)
    print("Fixed ADD_TO_CART variable successfully!")
else:
    print("Could not find ADD_TO_CART string to replace.")
