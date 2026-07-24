import json, subprocess

bot_id = "cmrxyzuid00011eqd86ujabc2"

cmd = ["sudo", "docker", "exec", "-i", "unified-deployment-postgres-1", "psql", "-U", "postgres", "-d", "typebot", "-t", "-A", "-c", f"SELECT row_to_json(t) FROM \"Typebot\" t WHERE id = '{bot_id}'"]
bot = json.loads(subprocess.check_output(cmd).decode('utf-8').strip())

groups = bot.get("groups", [])
greetings = []

for g in groups:
    title = g.get("title", "")
    # Check if the title has something like 'Greeting', 'Sheng', 'Kiswahili', 'English'
    if "greeting" in title.lower() or "sheng" in title.lower() or "kiswahili" in title.lower() or "english" in title.lower():
        for b in g.get("blocks", []):
            if b.get("type") == "text":
                content = b.get("content", {}).get("richText", [])
                text_vals = []
                for p in content:
                    for child in p.get("children", []):
                        if "text" in child:
                            text_vals.append(child["text"])
                if text_vals:
                    greetings.append(f"### Group: {title}\n**Text:**\n" + "\n".join(text_vals) + "\n")

with open("greetings_report.md", "w") as f:
    f.write("# Hardcoded Greetings in Typebot\n\n")
    f.write("\n---\n".join(greetings))

print("Greetings extracted successfully!")
