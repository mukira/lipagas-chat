import re

with open('/root/lipagas_bridge/lib/lipagas_bridge/meta_handler.ex', 'r') as f:
    content = f.read()

# Replace the body modification for order
old_code = """      put_in(body, ["entry", Access.at(0), "changes", Access.at(0), "value", "messages", Access.at(0)],
        Map.merge(message, %{"type" => "text", "text" => %{"body" => "Select Brand"}}))"""

new_code = """      modified_message = message
        |> Map.delete("order")
        |> Map.merge(%{"type" => "text", "text" => %{"body" => "Select Brand"}})
      put_in(body, ["entry", Access.at(0), "changes", Access.at(0), "value", "messages", Access.at(0)], modified_message)"""

content = content.replace(old_code, new_code)

with open('/root/lipagas_bridge/lib/lipagas_bridge/meta_handler.ex', 'w') as f:
    f.write(content)

