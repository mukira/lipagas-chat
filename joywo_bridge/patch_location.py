import re

with open('/root/lipagas_bridge/lib/lipagas_bridge/meta_handler.ex', 'r') as f:
    content = f.read()

# Replace the body modification for location
old_code = """      put_in(body, ["entry", Access.at(0), "changes", Access.at(0), "value", "messages", Access.at(0)],
        Map.merge(message, %{"type" => "text", "text" => %{"body" => map_url}}))"""

new_code = """      modified_location = message
        |> Map.delete("location")
        |> Map.merge(%{"type" => "text", "text" => %{"body" => map_url}})
      put_in(body, ["entry", Access.at(0), "changes", Access.at(0), "value", "messages", Access.at(0)], modified_location)"""

content = content.replace(old_code, new_code)

with open('/root/lipagas_bridge/lib/lipagas_bridge/meta_handler.ex', 'w') as f:
    f.write(content)

