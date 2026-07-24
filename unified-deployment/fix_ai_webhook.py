import os
import json
import psycopg2
import uuid
import datetime

DATABASE_URL = os.environ.get("DATABASE_URL", "postgresql://typebot:postgres_password@localhost:5432/typebot")

def fix_webhook():
    conn = psycopg2.connect(DATABASE_URL)
    cur = conn.cursor()
    
    cur.execute("SELECT id, groups FROM \"Typebot\" WHERE name = 'Presidential Bot';")
    row = cur.fetchone()
    
    if not row:
        print("Bot not found.")
        return
        
    bot_id, groups = row
    
    webhook_id = "wh_ai_proxy_" + uuid.uuid4().hex[:12]
    
    # 1. Insert Webhook
    now = datetime.datetime.utcnow()
    cur.execute("""
        INSERT INTO "Webhook" (id, url, method, "queryParams", headers, body, "typebotId", "createdAt", "updatedAt")
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
    """, (
        webhook_id,
        "http://presidential-bridge:4000/api/ai/proxy",
        "POST",
        json.dumps([]),
        json.dumps([]),
        None,
        bot_id,
        now,
        now
    ))
    
    # 2. Update the webhook block
    updated = False
    for group in groups:
        for block in group.get('blocks', []):
            if block['id'] == 'cmrulouid00011eqdblk00001':
                if 'webhookId' not in block['options']:
                    block['options']['webhookId'] = webhook_id
                    updated = True
                    print(f"Assigned webhookId {webhook_id} to block cmrulouid00011eqdblk00001")
                    
    if updated:
        cur.execute("UPDATE \"Typebot\" SET groups = %s WHERE id = %s", (json.dumps(groups), bot_id))
        cur.execute("UPDATE \"PublicTypebot\" SET groups = %s WHERE \"typebotId\" = %s", (json.dumps(groups), bot_id))
        conn.commit()
        print("Webhook injected and database updated successfully.")
    else:
        print("Webhook already assigned?")
        conn.rollback()
        
    cur.close()
    conn.close()

if __name__ == "__main__":
    fix_webhook()
