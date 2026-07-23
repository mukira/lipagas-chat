import json
import subprocess

bot_id = "cloiafj9e00091aqj6o9nfrww"
correct_var_id = "cghuwhqgbrb3nre4d3wkon3ml"

def fetch_json(col):
    cmd = ["docker", "exec", "-i", "typebot-typebot-db-1", "psql", "-U", "postgres", "-d", "typebot", "-t", "-A", "-c", f"SELECT {col} FROM \"Typebot\" WHERE id = '{bot_id}'"]
    return json.loads(subprocess.check_output(cmd).decode('utf-8').strip())

groups = fetch_json("groups")

fixed = False
for g in groups:
    for b in g.get("blocks", []):
        if b.get("type") == "number input":
            opts = b.get("options", {})
            if opts.get("variableId") == "var_amount":
                opts["variableId"] = correct_var_id
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
    with open("/root/lipagas_bridge/fix_tokens_input_var.sql", "w") as f:
        f.write(sql_content)

    subprocess.check_call("docker exec -i typebot-typebot-db-1 psql -U postgres -d typebot < /root/lipagas_bridge/fix_tokens_input_var.sql", shell=True)
    print("Fixed Input Variable ID successfully!")
else:
    print("Could not find the target input block with var_amount!")
