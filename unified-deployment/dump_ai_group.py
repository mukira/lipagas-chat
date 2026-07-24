import os
import json
import psycopg2

DATABASE_URL = os.environ.get("DATABASE_URL", "postgresql://typebot:postgres_password@localhost:5432/typebot")

def dump_ai_group():
    conn = psycopg2.connect(DATABASE_URL)
    cur = conn.cursor()
    
    cur.execute("SELECT groups, webhooks FROM \"Typebot\" WHERE name = 'Presidential Bot';")
    row = cur.fetchone()
    groups = row[0]
    webhooks = row[1] if len(row) > 1 else None
    
    print("WEBHOOKS:", json.dumps(webhooks, indent=2))
    
    for g in groups:
        if g['id'] == 'cmrulouid00011eqdgrp00001':
            print("GROUP Presidential AI:")
            print(json.dumps(g, indent=2))
            
if __name__ == "__main__":
    dump_ai_group()
