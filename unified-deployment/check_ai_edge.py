import os
import json
import psycopg2

DATABASE_URL = os.environ.get("DATABASE_URL", "postgresql://typebot:postgres_password@localhost:5432/typebot")

def check_edges():
    conn = psycopg2.connect(DATABASE_URL)
    cur = conn.cursor()
    
    cur.execute("SELECT edges FROM \"Typebot\" WHERE name = 'Presidential Bot';")
    row = cur.fetchone()
    
    if not row:
        print("Bot not found.")
        return
        
    edges = row[0]
    ask_ai_edge = [e for e in edges if e.get("id") == "edg_px1qzuxo18n5k69bq7e4"]
    
    if ask_ai_edge:
        print("Found edge:", json.dumps(ask_ai_edge[0], indent=2))
        
        # Verify the target block exists
        target_group_id = ask_ai_edge[0].get("to", {}).get("groupId")
        target_block_id = ask_ai_edge[0].get("to", {}).get("blockId")
        
        print(f"Target Group: {target_group_id}, Target Block: {target_block_id}")
        
        cur.execute("SELECT groups FROM \"Typebot\" WHERE name = 'Presidential Bot';")
        groups = cur.fetchone()[0]
        
        found = False
        for group in groups:
            for block in group.get("blocks", []):
                if block.get("id") == target_block_id:
                    print(f"Block {target_block_id} found in group '{group.get('title')}'")
                    found = True
                    break
        if not found:
            print(f"Block {target_block_id} NOT FOUND!")
            
    else:
        print("Edge edg_px1qzuxo18n5k69bq7e4 NOT FOUND in edges array!")

if __name__ == "__main__":
    check_edges()
