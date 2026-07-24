import os
import json
import psycopg2

DATABASE_URL = os.environ.get("DATABASE_URL", "postgresql://typebot:postgres_password@localhost:5432/typebot")

def fix_variable_id():
    conn = psycopg2.connect(DATABASE_URL)
    cur = conn.cursor()
    
    cur.execute("SELECT id, groups FROM \"Typebot\" WHERE name = 'Presidential Bot';")
    row = cur.fetchone()
    
    if not row:
        print("Bot not found.")
        return
        
    bot_id, groups = row
    
    updated = False
    for group in groups:
        if group['id'] == 'grp_7lx1xt1spslkgbysewhg':
            for block in group.get('blocks', []):
                if block['id'] == 'blk_in_ask_q_3382eab231':
                    if 'options' not in block:
                        block['options'] = {}
                    if 'variableId' not in block['options']:
                        block['options']['variableId'] = 'cmrulouid00011eqdvar00001'
                        updated = True
                        print("Added variableId to blk_in_ask_q_3382eab231")
                        
    if updated:
        cur.execute("UPDATE \"Typebot\" SET groups = %s WHERE id = %s", (json.dumps(groups), bot_id))
        cur.execute("UPDATE \"PublicTypebot\" SET groups = %s WHERE \"typebotId\" = %s", (json.dumps(groups), bot_id))
        conn.commit()
        print("Database updated successfully.")
    else:
        print("Variable ID already present?")
        conn.rollback()
        
    cur.close()
    conn.close()

if __name__ == "__main__":
    fix_variable_id()
