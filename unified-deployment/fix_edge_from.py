import os
import json
import psycopg2

DATABASE_URL = os.environ.get("DATABASE_URL", "postgresql://typebot:postgres_password@localhost:5432/typebot")

def main():
    conn = psycopg2.connect(DATABASE_URL)
    cur = conn.cursor()
    
    cur.execute("SELECT id, edges FROM \"Typebot\" WHERE name = 'Presidential Bot';")
    row = cur.fetchone()
    if not row:
        return
        
    bot_id, edges = row
    updated = False
    
    for edge in edges:
        if edge['id'] == 'edg_793c059e35594f1eb348':
            if 'groupId' not in edge['from']:
                edge['from']['groupId'] = 'grp_7lx1xt1spslkgbysewhg'
                updated = True
                print("Added from.groupId to edge!")
                
    if updated:
        cur.execute("UPDATE \"Typebot\" SET edges = %s WHERE id = %s", (json.dumps(edges), bot_id))
        cur.execute("UPDATE \"PublicTypebot\" SET edges = %s WHERE \"typebotId\" = %s", (json.dumps(edges), bot_id))
        conn.commit()
        print("Updated edges in DB.")
    else:
        print("No update needed.")
        
    cur.close()
    conn.close()

if __name__ == "__main__":
    main()
