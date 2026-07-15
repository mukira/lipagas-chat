import json
import subprocess

bot_id = "cloiafj9e00091aqj6o9nfrww"

def fetch_json(col):
    cmd = ["docker", "exec", "-i", "typebot-typebot-db-1", "psql", "-U", "postgres", "-d", "typebot", "-t", "-A", "-c", f"SELECT {col} FROM \"Typebot\" WHERE id = '{bot_id}'"]
    return json.loads(subprocess.check_output(cmd).decode('utf-8').strip())

groups = fetch_json("groups")

fixed = False
for g in groups:
    for b in g.get("blocks", []):
        if b.get("type") == "text":
            rich_text = b.get("content", {}).get("richText", [])
            for p in rich_text:
                for c in p.get("children", []):
                    if "text" in c and "[ADD_TO_CART:{{var_amount}}|Gas Tokens]" in c["text"]:
                        c["text"] = c["text"].replace("{{var_amount}}", "{{Amount}}")
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
    with open("/root/lipagas_bridge/fix_tokens_amount.sql", "w") as f:
        f.write(sql_content)

    subprocess.check_call("docker exec -i typebot-typebot-db-1 psql -U postgres -d typebot < /root/lipagas_bridge/fix_tokens_amount.sql", shell=True)
    print("Fixed Amount variable!")
else:
    print("Could not find the target text!")
