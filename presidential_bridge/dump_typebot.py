import json, subprocess

bot_id = "cmrxyzuid00011eqd86ujabc2"
cmd = ["sudo", "docker", "exec", "-i", "unified-deployment-postgres-1", "psql", "-U", "postgres", "-d", "typebot", "-t", "-A", "-c", f"SELECT row_to_json(t) FROM \"Typebot\" t WHERE id = '{bot_id}'"]
bot = json.loads(subprocess.check_output(cmd).decode('utf-8').strip())

with open("bot_dump.json", "w") as f:
    json.dump(bot, f, indent=2)

print("Dumped bot to bot_dump.json")
