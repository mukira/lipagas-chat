import os
import json
import psycopg2

DATABASE_URL = os.environ.get("DATABASE_URL", "postgresql://typebot:postgres_password@localhost:5432/typebot")

def dump_ai_block():
    conn = psycopg2.connect(DATABASE_URL)
    cur = conn.cursor()
    
    cur.execute("SELECT groups FROM \"Typebot\" WHERE name = 'Presidential Bot';")
    groups = cur.fetchone()[0]
    
    for g in groups:
        for b in g.get('blocks', []):
            if b['id'] == 'cmrulouid00011eqdblk00001':
                print(json.dumps(b, indent=2))
                
if __name__ == "__main__":
    dump_ai_block()
