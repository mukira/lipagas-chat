import json

with open("paths.json", "r") as f:
    paths = json.load(f)

# Fix corrupted keys
fixed_paths = {}
for k, v in paths.items():
    new_k = k.replace("️ clear cart", "🗑️ clear cart")
    
    # Fix corrupted values
    new_v = {}
    for scope, p_list in v.items():
        new_v[scope] = [p.replace("I need Gas ", "I need Gas 🔥") if p == "I need Gas " else p for p in p_list]
    
    fixed_paths[new_k] = new_v

# Also ensure specific keys exist correctly
if "🗑️ clear cart" not in fixed_paths and "\u26f9\ufe0f clear cart" not in fixed_paths:
    fixed_paths["🗑️ clear cart"] = {
        "retail": ["I need Gas 🔥"],
        "default": ["I need Gas 🔥"],
        "business": ["For Business 🏢"]
    }
    
if "🛒 add another item" in fixed_paths:
    fixed_paths["🛒 add another item"]["default"] = ["I need Gas 🔥"]

with open("paths.json", "w") as f:
    json.dump(fixed_paths, f, indent=2, ensure_ascii=False)

