import os
import json
import psycopg2

DATABASE_URL = os.environ.get('DATABASE_URL', 'postgresql://typebot:postgres_password@postgres:5432/typebot')
conn = psycopg2.connect(DATABASE_URL)
cur = conn.cursor()
cur.execute("SELECT id, name, version, edges FROM \"Typebot\" WHERE name = 'presidential-bot'")
row = cur.fetchone()
edges = row[3]
kiswahili_edge = next((e for e in edges if e.get("from", {}).get("itemId") == "itm_d2d47d2d549d48818c13"), None)
print(json.dumps(kiswahili_edge, indent=2))
