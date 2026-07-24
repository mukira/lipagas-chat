import os
import json
import psycopg2
from psycopg2.extras import RealDictCursor

DATABASE_URL = os.environ.get("DATABASE_URL", "postgresql://typebot:postgres_password@localhost:5432/typebot")

def check_broken_edges():
    conn = psycopg2.connect(DATABASE_URL)
    cur = conn.cursor(cursor_factory=RealDictCursor)
    
    cur.execute("SELECT groups, edges FROM \"Typebot\" WHERE name = 'Presidential Bot';")
    row = cur.fetchone()
    
    edges = {e['id']: e for e in row['edges']}
    groups = row['groups']
    
    broken_edge_ids = ["edg_a6100de8f82248daac1a", "edg_82b877a74fd74d358da7", "edg_6e45fe025a2c47c78770", "edg_588109819cf24b4cb4ac", "edg_e28bbf6ab1104a11ab15", "edg_px1qzuxo18n5k69bq7e4"]
    
    for edge_id in broken_edge_ids:
        print(f"Edge {edge_id}:")
        if edge_id in edges:
            print(f"  Target: {json.dumps(edges[edge_id].get('to'))}")
        
        # Find which block uses it
        for g in groups:
            for b in g.get('blocks', []):
                if b.get('outgoingEdgeId') == edge_id:
                    print(f"  Origin: Block {b['id']} in Group '{g.get('title')}'")
                if 'items' in b:
                    for item in b['items']:
                        if item.get('outgoingEdgeId') == edge_id:
                            print(f"  Origin: Item '{item.get('content')}' in block {b['id']} in Group '{g.get('title')}'")
                            
if __name__ == "__main__":
    check_broken_edges()
