import os, json, psycopg2

DATABASE_URL = os.environ.get("DATABASE_URL", "postgresql://typebot:postgres_password@localhost:5432/typebot")

def update_groups(groups):
    updated = False
    for group in groups:
        for block in group.get('blocks', []):
            if block.get('type') == 'webhook':
                if block.get('options', {}).get('webhookId') == 'wh_ai_proxy_75cb70ee45ae':
                    block['options']['webhookId'] = 'cmrulouid00011eqdwhk00001'
                    updated = True
    return updated, groups

def main():
    conn = psycopg2.connect(DATABASE_URL)
    cur = conn.cursor()
    
    # Update Typebot
    cur.execute("SELECT id, groups FROM \"Typebot\" WHERE name = 'Presidential Bot';")
    row = cur.fetchone()
    if row:
        bot_id, groups = row
        updated, new_groups = update_groups(groups)
        if updated:
            cur.execute("UPDATE \"Typebot\" SET groups = %s WHERE id = %s", (json.dumps(new_groups), bot_id))
            print("Updated Typebot")
            
    # Update PublicTypebot
    cur.execute("SELECT id, groups FROM \"PublicTypebot\" WHERE \"typebotId\" = %s;", (bot_id,))
    row = cur.fetchone()
    if row:
        pub_id, groups = row
        updated, new_groups = update_groups(groups)
        if updated:
            cur.execute("UPDATE \"PublicTypebot\" SET groups = %s WHERE id = %s", (json.dumps(new_groups), pub_id))
            print("Updated PublicTypebot")
            
    conn.commit()
    cur.close()
    conn.close()

if __name__ == "__main__":
    main()
