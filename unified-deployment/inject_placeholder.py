import os
import json
import psycopg2

DATABASE_URL = os.environ.get('DATABASE_URL', 'postgresql://postgres:typebot@localhost:5432/typebot')
conn = psycopg2.connect(DATABASE_URL)
cur = conn.cursor()

cur.execute("SELECT id, name, version, workspace_id, groups FROM \"Typebot\" WHERE name = 'presidential-bot'")
row = cur.fetchone()

if not row:
    print("presidential-bot not found")
    exit(1)

id, name, version, workspace_id, groups = row
print(f"Found bot: {name} v{version}")

updated = False
for group in groups:
    for block in group.get('blocks', []):
        if block.get('type') == 'text':
            content = block.get('content', {})
            rich_text = content.get('richText', [])
            for rt in rich_text:
                for child in rt.get('children', []):
                    text = child.get('text', '')
                    if "Tuongee! Which language do you prefer today?" in text or "Which of these languages do you like most?" in text:
                        if "{{NO_TRANSLATE}}" not in text:
                            child['text'] = "{{NO_TRANSLATE}}\n" + text
                            updated = True
                            print(f"Injected placeholder into: {text}")

if updated:
    cur.execute("UPDATE \"Typebot\" SET groups = %s WHERE id = %s", (json.dumps(groups), id))
    conn.commit()
    print("Successfully updated Typebot groups")
else:
    print("No blocks needed updating or already updated.")

cur.close()
conn.close()
