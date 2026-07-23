import sys
import json
import subprocess
from collections import defaultdict, deque

if len(sys.argv) < 2:
    print("Usage: python3 format_typebot.py <bot_id>")
    sys.exit(1)

bot_id = sys.argv[1]

# 1. Fetch current groups, edges, and events from Postgres
def fetch_json_field(field):
    cmd = ["sudo", "docker", "exec", "-i", "unified-deployment-postgres-1", "psql", "-U", "typebot", "-d", "typebot", "-t", "-A", "-c", f"SELECT {field} FROM \"Typebot\" WHERE id = '{bot_id}'"]
    try:
        output = subprocess.check_output(cmd).decode('utf-8').strip()
        return json.loads(output) if output else []
    except Exception as e:
        print(f"Error fetching {field}: {e}")
        sys.exit(1)

groups = fetch_json_field("groups")
edges = fetch_json_field("edges")
events = fetch_json_field("events")

if not groups:
    print("No groups found or bot does not exist.")
    sys.exit(1)

# Build a map of group IDs to groups
group_map = {g['id']: g for g in groups}

# Identify starting groups from events (Start event)
start_group_ids = []
for event in events:
    if event.get("type") == "start":
        outgoing_edge_id = event.get("outgoingEdgeId")
        if outgoing_edge_id:
            # find edge
            for e in edges:
                if e.get("id") == outgoing_edge_id:
                    target_group_id = e.get("to", {}).get("groupId")
                    if target_group_id:
                        start_group_ids.append(target_group_id)

if not start_group_ids:
    # Fallback if no explicit start event edge found: just pick the first group
    start_group_ids = [groups[0]['id']]

# Build adjacency list: group_id -> set of connected group_ids
adj = defaultdict(set)
for e in edges:
    # Edges can connect blocks or items, but we only care about group to group transitions
    from_block_id = e.get("from", {}).get("blockId")
    to_group_id = e.get("to", {}).get("groupId")
    
    if from_block_id and to_group_id:
        # Find which group owns from_block_id
        from_group_id = None
        for g in groups:
            if any(b.get("id") == from_block_id for b in g.get("blocks", [])):
                from_group_id = g['id']
                break
        
        if from_group_id:
            adj[from_group_id].add(to_group_id)
            
# Assign depths using BFS
depths = {}
queue = deque([(g_id, 0) for g_id in start_group_ids])
while queue:
    curr_id, d = queue.popleft()
    if curr_id not in depths:
        depths[curr_id] = d
        for neighbor in adj[curr_id]:
            if neighbor not in depths:
                queue.append((neighbor, d + 1))

# Unreachable groups get placed at the end or below
max_depth = max(depths.values()) if depths else 0
for g in groups:
    if g['id'] not in depths:
        depths[g['id']] = max_depth + 1

# Group by depth
groups_by_depth = defaultdict(list)
for g in groups:
    groups_by_depth[depths[g['id']]].append(g)

# Assign coordinates
X_SPACING = 450
Y_SPACING = 300
START_X = 0
START_Y = 0

for d in sorted(groups_by_depth.keys()):
    layer_groups = groups_by_depth[d]
    # Simple top-to-bottom layout for siblings
    for i, g in enumerate(layer_groups):
        g['graphCoordinates'] = {
            'x': START_X + (d * X_SPACING),
            'y': START_Y + (i * Y_SPACING)
        }

# Save updated groups back to Postgres
updated_groups_json = json.dumps(groups).replace("'", "''")

update_cmd = ["sudo", "docker", "exec", "-i", "unified-deployment-postgres-1", "psql", "-U", "typebot", "-d", "typebot", "-c", f"UPDATE \"Typebot\" SET groups = '{updated_groups_json}'::jsonb WHERE id = '{bot_id}'"]
try:
    subprocess.check_call(update_cmd)
    
    # Also update PublicTypebot if it exists
    update_pub_cmd = ["sudo", "docker", "exec", "-i", "unified-deployment-postgres-1", "psql", "-U", "typebot", "-d", "typebot", "-c", f"UPDATE \"PublicTypebot\" SET groups = '{updated_groups_json}'::jsonb WHERE \"typebotId\" = '{bot_id}'"]
    subprocess.call(update_pub_cmd)
    
    print(f"Successfully laid out and spaced {len(groups)} blocks for bot {bot_id}!")
except Exception as e:
    print(f"Error updating DB: {e}")
    sys.exit(1)
