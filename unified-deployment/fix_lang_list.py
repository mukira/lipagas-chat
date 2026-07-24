import os
import json
import psycopg2

DATABASE_URL = os.environ.get('DATABASE_URL', 'postgresql://typebot:postgres_password@postgres:5432/typebot')
conn = psycopg2.connect(DATABASE_URL)
cur = conn.cursor()

cur.execute("SELECT id, groups FROM \"Typebot\" WHERE name = 'Presidential Bot'")
row = cur.fetchone()

if row:
    bot_id, groups = row
    updated = False
    for group in groups:
        for block in group.get('blocks', []):
            if block.get('type') == 'text':
                content = block.get('content', {})
                rich_text = content.get('richText', [])
                for rt in rich_text:
                    for child in rt.get('children', []):
                        text = child.get('text', '')
                        if "Which of these languages do you prefer?" in text:
                            if "{{NO_TRANSLATE}}" not in text:
                                child['text'] = "{{NO_TRANSLATE}}\n" + text
                                updated = True
                                print(f"Fixed text block: {text}")

    if updated:
        cur.execute("UPDATE \"Typebot\" SET groups = %s WHERE id = %s", (json.dumps(groups), bot_id))
        conn.commit()
        print("Successfully updated Typebot groups")
    else:
        print("No update needed.")
cur.close()
conn.close()
