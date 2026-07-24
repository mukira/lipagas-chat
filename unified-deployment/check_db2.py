import os
import json
import psycopg2
from psycopg2.extras import RealDictCursor

DATABASE_URL = os.environ.get("DATABASE_URL", "postgresql://typebot:postgres_password@localhost:5432/typebot")

def check_db():
    conn = psycopg2.connect(DATABASE_URL)
    cur = conn.cursor(cursor_factory=RealDictCursor)
    
    cur.execute("SELECT id, groups FROM \"Typebot\" WHERE name = 'Presidential Bot';")
    row = cur.fetchone()
    
    if not row:
        print("Bot not found.")
        return
        
    for group in row['groups']:
        if group.get('title') in ['Manifesto Doc', 'Scorecard Doc', 'Ask Question']:
            print(f"--- Group: {group.get('title')} ---")
            for block in group.get('blocks', []):
                print(json.dumps(block, indent=2))
                    
if __name__ == "__main__":
    check_db()
