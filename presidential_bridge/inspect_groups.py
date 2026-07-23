import json
import subprocess

cmd = ["docker", "exec", "-i", "typebot-typebot-db-1", "psql", "-U", "postgres", "-d", "typebot", "-t", "-A", "-c", "SELECT row_to_json(t) FROM (SELECT groups, edges, variables FROM \"Typebot\" WHERE id = 'cloiafj9e00091aqj6o9nfrww') t"]
res = subprocess.check_output(cmd).decode('utf-8').strip()
with open("typebot_dump.json", "w") as f:
    f.write(res)
print("Dumped to typebot_dump.json")
