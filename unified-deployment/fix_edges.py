import os
import json
import psycopg2
import uuid

DATABASE_URL = os.environ.get("DATABASE_URL", "postgresql://typebot:postgres_password@localhost:5432/typebot")

def fix_db():
    conn = psycopg2.connect(DATABASE_URL)
    cur = conn.cursor()
    
    cur.execute("SELECT id, groups, edges FROM \"Typebot\" WHERE name = 'Presidential Bot';")
    row = cur.fetchone()
    if not row:
        print("Bot not found.")
        return
        
    bot_id, groups, edges = row
    
    # We need to find the Ask Question text block ID
    ask_question_txt_id = None
    for group in groups:
        if group.get('title') == 'Ask Question':
            for block in group.get('blocks', []):
                if block.get('type') == 'text':
                    ask_question_txt_id = block['id']
                    break
    
    print(f"Target Ask Question Text Block ID: {ask_question_txt_id}")
    
    if not ask_question_txt_id:
        print("Could not find target block.")
        return
        
    updated = False
    
    for group in groups:
        for block in group.get('blocks', []):
            if block.get('type') == 'text' and 'SEND_DOCUMENT' in json.dumps(block):
                if 'outgoingEdgeId' not in block:
                    new_edge_id = "edg_" + uuid.uuid4().hex[:20]
                    block['outgoingEdgeId'] = new_edge_id
                    
                    new_edge = {
                        "id": new_edge_id,
                        "from": {
                            "blockId": block['id']
                        },
                        "to": {
                            "groupId": "Ask Question", # Actually we just need to specify the blockId for safety
                            "blockId": ask_question_txt_id
                        }
                    }
                    edges.append(new_edge)
                    updated = True
                    print(f"Added edge from {block['id']} to {ask_question_txt_id}")
                    
    if updated:
        cur.execute("UPDATE \"Typebot\" SET groups = %s, edges = %s WHERE id = %s",
                   (json.dumps(groups), json.dumps(edges), bot_id))
        conn.commit()
        
        # also update PublicTypebot
        cur.execute("UPDATE \"PublicTypebot\" SET groups = %s, edges = %s WHERE \"typebotId\" = %s",
                   (json.dumps(groups), json.dumps(edges), bot_id))
        conn.commit()
        print("Database successfully updated.")
    else:
        print("No updates needed.")
        
    cur.close()
    conn.close()
                    
if __name__ == "__main__":
    fix_db()
