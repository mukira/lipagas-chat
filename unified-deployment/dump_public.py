import os, json, psycopg2
conn = psycopg2.connect(os.environ.get('DATABASE_URL', 'postgresql://typebot:postgres_password@localhost:5432/typebot'))
cur = conn.cursor()
cur.execute("SELECT groups, edges FROM \"PublicTypebot\" WHERE \"typebotId\" = (SELECT id FROM \"Typebot\" WHERE name = 'Presidential Bot');")
groups, edges = cur.fetchone()
with open('/tmp/groups.json', 'w') as f:
    json.dump({"groups": groups, "edges": edges}, f, indent=2)
