import json
import subprocess
import tempfile

cmd = ["docker", "exec", "-i", "typebot-typebot-db-1", "psql", "-U", "postgres", "-d", "typebot", "-t", "-A", "-c", "SELECT groups FROM \"Typebot\" WHERE id = 'cloiafj9e00091aqj6o9nfrww'"]
res = subprocess.check_output(cmd).decode('utf-8').strip()
groups = json.loads(res)

for g in groups:
    if g.get("id") == "clf6900635b9104409ad4c4ed":
        for b in g.get("blocks", []):
            if b.get("id") == "cmc6zr5n1lkiztajvzkg9uy0r":
                for item in b.get("items", []):
                    if item.get("id") == "c_item_loc_set":
                        for comp in item.get("content", {}).get("comparisons", []):
                            if comp.get("id") == "c_comp_loc_set":
                                comp["comparisonOperator"] = "Is set"
                    if item.get("id") == "ccrsviorc8beklj45rk1zhux9":
                        for comp in item.get("content", {}).get("comparisons", []):
                            if comp.get("id") == "c0we4274q5270c61pxzv3qsnb":
                                comp["comparisonOperator"] = "Is set"

updated_json_str = json.dumps(groups)
psql_script = f"""
UPDATE "Typebot" SET groups = '{updated_json_str.replace("'", "''")}' WHERE id = 'cloiafj9e00091aqj6o9nfrww';
"""

with open("/root/lipagas_bridge/revert.sql", "w") as f:
    f.write(psql_script)

cmd = ["docker", "exec", "-i", "typebot-typebot-db-1", "psql", "-U", "postgres", "-d", "typebot", "-f", "-"]
with open("/root/lipagas_bridge/revert.sql", "rb") as f:
    subprocess.run(cmd, stdin=f, check=True)

print("Reverted!")
