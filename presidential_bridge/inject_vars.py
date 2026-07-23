import json
import subprocess
import string
import random

def random_id():
    return "var_" + "".join(random.choices(string.ascii_lowercase + string.digits, k=16))

bot_id = "cloiafj9e00091aqj6o9nfrww"
fetch_cmd = ["sudo", "docker", "exec", "-i", "unified-deployment-postgres-1", "psql", "-U", "postgres", "-d", "typebot", "-t", "-A", "-c", f"SELECT variables FROM \"Typebot\" WHERE id = '{bot_id}'"]
output = subprocess.check_output(fetch_cmd).decode('utf-8').strip()

variables = json.loads(output)

required_vars = [
    "dynamic_summary",
    "dynamic_summary_sw",
    "dynamic_summary_sh",
    "dynamic_btn_en",
    "dynamic_btn_sw",
    "dynamic_btn_sh"
]

existing_names = {v.get("name") for v in variables}
added = 0

for v_name in required_vars:
    if v_name not in existing_names:
        variables.append({
            "id": random_id(),
            "name": v_name,
            "isSessionVariable": True
        })
        added += 1

if added > 0:
    vars_json = json.dumps(variables).replace("'", "''")
    sql = f"""
    UPDATE "Typebot" SET variables = '{vars_json}'::jsonb WHERE id = '{bot_id}';
    UPDATE "PublicTypebot" SET variables = '{vars_json}'::jsonb WHERE "typebotId" = '{bot_id}';
    """
    with open("/home/mukira/lipagas-chat/presidential_bridge/update_vars.sql", "w") as f:
        f.write(sql)
    subprocess.check_call("sudo docker exec -i unified-deployment-postgres-1 psql -U postgres -d typebot < /home/mukira/lipagas-chat/presidential_bridge/update_vars.sql", shell=True)
    print(f"Successfully added {added} variables.")
else:
    print("Variables already exist.")
