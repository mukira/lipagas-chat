import os
import json
import psycopg2

DATABASE_URL = os.environ.get('DATABASE_URL', 'postgresql://typebot:postgres_password@postgres:5432/typebot')
conn = psycopg2.connect(DATABASE_URL)
cur = conn.cursor()

typebot_id = "cmrxyzuid00011eqd86ujabc2"

for table in ["\"Typebot\"", "\"PublicTypebot\""]:
    if table == "\"Typebot\"":
        cur.execute(f"SELECT id, edges, groups FROM {table} WHERE id = %s", (typebot_id,))
    else:
        cur.execute(f"SELECT id, edges, groups FROM {table} WHERE \"typebotId\" = %s", (typebot_id,))
        
    rows = cur.fetchall()
    
    for row in rows:
        row_id, edges, groups = row
        
        target_group_id = None
        target_block_id = None
        
        for e in edges:
            if e.get("from", {}).get("itemId") == "itm_d2d47d2d549d48818c13":
                target_group_id = e.get("to", {}).get("groupId")
                target_block_id = e.get("to", {}).get("blockId")
                break
                
        print(f"[{table}] Target: Group {target_group_id}, Block {target_block_id}")
            
        choice_block = None
        for g in groups:
            for b in g.get("blocks", []):
                if b.get("type") == "Choice input" or b.get("type") == "choice input":
                    items = b.get("items", [])
                    if any(i.get("content") == "Meru" for i in items):
                        choice_block = b
                        break
            if choice_block:
                break
                
        if not choice_block:
            continue
            
        items = choice_block.get("items", [])
        
        changed = False
        for item in items:
            item_id = item.get("id")
            has_edge = any(e.get("from", {}).get("itemId") == item_id for e in edges)
            if not has_edge:
                new_edge_id = f"edg_fix_{item_id}"
                new_edge = {
                    "id": new_edge_id,
                    "from": {
                        "blockId": choice_block.get("id"),
                        "itemId": item_id
                    },
                    "to": {
                        "groupId": target_group_id
                    }
                }
                if target_block_id:
                    new_edge["to"]["blockId"] = target_block_id
                    
                edges.append(new_edge)
                item["outgoingEdgeId"] = new_edge_id
                changed = True
                print(f"[{table}] Added edge for {item.get('content')}")
                
        if changed:
            cur.execute(f"UPDATE {table} SET edges = %s, groups = %s WHERE id = %s", (json.dumps(edges), json.dumps(groups), row_id))
            print(f"[{table}] Updated in DB!")

conn.commit()
conn.close()
print("Done!")
