import os
import json
import psycopg2

DATABASE_URL = os.environ.get("DATABASE_URL", "postgresql://typebot:postgres_password@localhost:5432/typebot")

def lint_bot():
    conn = psycopg2.connect(DATABASE_URL)
    cur = conn.cursor()
    
    cur.execute("SELECT id, groups, edges FROM \"Typebot\" WHERE name = 'Presidential Bot';")
    row = cur.fetchone()
    
    if not row:
        print("Bot not found.")
        return
        
    bot_id, groups, edges = row
    
    # Build maps
    valid_groups = {g['id'] for g in groups}
    valid_blocks = {}
    for g in groups:
        for b in g.get('blocks', []):
            valid_blocks[b['id']] = g['id']
            
    valid_edges = {e['id']: e for e in edges}
    
    errors = []
    
    # 1. Check all edges point to valid blocks
    for e in edges:
        to_group = e.get('to', {}).get('groupId')
        to_block = e.get('to', {}).get('blockId')
        
        if to_block and to_block not in valid_blocks:
            errors.append(f"Edge {e['id']} targets missing block {to_block}")
            
        if to_group and to_group not in valid_groups:
            errors.append(f"Edge {e['id']} targets missing group {to_group}")
            
    # 2. Check all outgoingEdgeId references
    for g in groups:
        for b in g.get('blocks', []):
            if 'outgoingEdgeId' in b and b['outgoingEdgeId']:
                edge_id = b['outgoingEdgeId']
                if edge_id not in valid_edges:
                    errors.append(f"Block {b['id']} in Group '{g.get('title')}' points to missing edge {edge_id}")
            
            if 'items' in b:
                for item in b['items']:
                    if 'outgoingEdgeId' in item and item['outgoingEdgeId']:
                        edge_id = item['outgoingEdgeId']
                        if edge_id not in valid_edges:
                            errors.append(f"Item '{item.get('content')}' in block {b['id']} points to missing edge {edge_id}")
                            
    if errors:
        print("FOUND ERRORS:")
        for err in errors:
            print("-", err)
    else:
        print("NO ERRORS FOUND. BOT IS FULLY INTACT.")
        
if __name__ == "__main__":
    lint_bot()
