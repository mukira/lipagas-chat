import json
import subprocess
from collections import deque
import re

bot_id = "cloiafj9e00091aqj6o9nfrww"

def fetch_json(col):
    cmd = ["docker", "exec", "-i", "typebot-typebot-db-1", "psql", "-U", "postgres", "-d", "typebot", "-t", "-A", "-c", f"SELECT {col} FROM \"Typebot\" WHERE id = '{bot_id}'"]
    return json.loads(subprocess.check_output(cmd).decode('utf-8').strip())

try:
    groups = fetch_json("groups")
    edges = fetch_json("edges")
    events = fetch_json("events")
except Exception as e:
    print(f"Failed to fetch Typebot graph: {e}")
    exit(1)

def normalize(s):
    return s.strip().lower()

# Build lookups
group_dict = {g["id"]: g for g in groups}
edge_dict = {e["id"]: e for e in edges}

# Find start event
start_event = None
for ev in events:
    if ev.get("type") == "start":
        start_event = ev
        break

if not start_event:
    print("No start event found")
    exit(1)

start_edge_id = start_event.get("outgoingEdgeId")
if not start_edge_id:
    print("Start event has no outgoing edge")
    exit(1)

start_edge = edge_dict.get(start_edge_id)
if not start_edge:
    print("Start edge not found")
    exit(1)

paths = {}

def get_category(path):
    if not path:
        return "default"
    first = path[0].lower()
    if "business" in first:
        return "business"
    elif "gas" in first:
        return "retail"
    elif "token" in first:
        return "tokens"
    return "default"

# Queue items: (target_group_id, target_block_id, path_so_far, visited_edges)
q = deque()

to_obj = start_edge.get("to", {})
q.append((to_obj.get("groupId"), to_obj.get("blockId"), [], frozenset([start_edge_id])))

while q:
    gid, bid, current_path, path_visited = q.popleft()
    if not gid:
        continue
        
    group = group_dict.get(gid)
    if not group:
        continue
        
    blocks = group.get("blocks", [])
    if not blocks:
        continue
        
    # Find start block index
    start_idx = 0
    if bid:
        for i, b in enumerate(blocks):
            if b["id"] == bid:
                start_idx = i
                break
                
    # Traverse blocks sequentially
    for i in range(start_idx, len(blocks)):
        block = blocks[i]
        btype = block.get("type")
        
        # If it's a choice input, branch out
        if btype == "choice input":
            items = block.get("items", [])
            for item in items:
                content = item.get("content", "")
                if not content:
                    continue
                
                norm_content = normalize(content)
                new_path = current_path + [content]
                
                cat = get_category(new_path)
                if norm_content not in paths:
                    paths[norm_content] = {}
                
                # Keep shortest path for this category
                if cat not in paths[norm_content] or len(new_path) < len(paths[norm_content][cat]):
                    paths[norm_content][cat] = new_path
                # Keep shortest path for default
                if "default" not in paths[norm_content] or len(new_path) < len(paths[norm_content]["default"]):
                    paths[norm_content]["default"] = new_path
                    
                edge_id = item.get("outgoingEdgeId")
                if edge_id and edge_id not in path_visited:
                    new_visited = path_visited | {edge_id}
                    edge = edge_dict.get(edge_id)
                    if edge:
                        t = edge.get("to", {})
                        q.append((t.get("groupId"), t.get("blockId"), new_path, new_visited))
            
            # Choice input stops sequential execution unless there's a default edge?
            # Actually, choice input requires interaction, so we stop here.
            break
            
        elif btype == "Condition":
            # Follow condition edges
            items = block.get("items", [])
            for item in items:
                edge_id = item.get("outgoingEdgeId")
                if edge_id and edge_id not in path_visited:
                    new_visited = path_visited | {edge_id}
                    edge = edge_dict.get(edge_id)
                    if edge:
                        t = edge.get("to", {})
                        q.append((t.get("groupId"), t.get("blockId"), current_path, new_visited))
            
            # Default condition edge
            edge_id = block.get("outgoingEdgeId")
            if edge_id and edge_id not in path_visited:
                new_visited = path_visited | {edge_id}
                edge = edge_dict.get(edge_id)
                if edge:
                    t = edge.get("to", {})
                    q.append((t.get("groupId"), t.get("blockId"), current_path, new_visited))
                    
            break # Condition blocks jump
            
        else:
            # Other blocks
            edge_id = block.get("outgoingEdgeId")
            if edge_id:
                if edge_id not in path_visited:
                    new_visited = path_visited | {edge_id}
                    edge = edge_dict.get(edge_id)
                    if edge:
                        t = edge.get("to", {})
                        q.append((t.get("groupId"), t.get("blockId"), current_path, new_visited))
                break # Jumped out of sequential flow
            
# Save to paths.json
with open("/root/presidential_bridge/paths.json", "w") as f:
    json.dump(paths, f, indent=2)

print(f"Successfully generated paths.json with {len(paths)} button mappings.")
