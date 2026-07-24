import os
import json
import psycopg2
from psycopg2.extras import RealDictCursor

DATABASE_URL = os.environ.get("DATABASE_URL", "postgresql://typebot:postgres_password@localhost:5432/typebot")

def dump_groups():
    conn = psycopg2.connect(DATABASE_URL)
    cur = conn.cursor(cursor_factory=RealDictCursor)
    
    cur.execute("SELECT groups FROM \"Typebot\" WHERE name = 'Presidential Bot';")
    row = cur.fetchone()
    if not row:
        return
        
    for group in row['groups']:
        print(f"Group: {group.get('title')} (ID: {group.get('id')})")
        for block in group.get('blocks', []):
            if block.get('type') == 'set variable' or block.get('type') == 'webhook':
                print(f"  Block ID: {block.get('id')} - Type: {block.get('type')}")
                if 'options' in block:
                    print(f"    Options: {json.dumps(block['options'])[:200]}")
            elif block.get('type') == 'text' or block.get('type') == 'text input':
                print(f"  Block ID: {block.get('id')} - Type: {block.get('type')}")

if __name__ == "__main__":
    dump_groups()
