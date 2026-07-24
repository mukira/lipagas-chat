import os
import json
import psycopg2

DATABASE_URL = os.environ.get('DATABASE_URL', 'postgresql://typebot:postgres_password@postgres:5432/typebot')
conn = psycopg2.connect(DATABASE_URL)
cur = conn.cursor()

cur.execute("SELECT groups FROM \"Typebot\" WHERE name = 'Presidential Bot'")
row = cur.fetchone()

if row:
    groups = row[0]
    for group in groups:
        for block in group.get('blocks', []):
            if block.get('type') == 'choice input':
                print(f"CHOICE INPUT BLOCK: {json.dumps(block, indent=2)}")

cur.close()
conn.close()
