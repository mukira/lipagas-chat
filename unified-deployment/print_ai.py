import os, json, psycopg2
conn = psycopg2.connect(os.environ.get('DATABASE_URL', 'postgresql://typebot:postgres_password@localhost:5432/typebot'))
cur = conn.cursor()
cur.execute("SELECT groups, edges FROM \"Typebot\" WHERE name = 'Presidential Bot';")
groups, edges = cur.fetchone()
ai_group = next(g for g in groups if g.get('title') == 'Presidential AI')
print(json.dumps(ai_group, indent=2))
for e in edges:
    if e['id'] == 'edg_793c059e35594f1eb348':
        print("\nFound edge:")
        print(json.dumps(e, indent=2))
