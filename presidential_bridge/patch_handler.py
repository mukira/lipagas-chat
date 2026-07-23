import re

with open('/root/presidential_bridge/lib/presidential_bridge/presidential_handler.ex', 'r') as f:
    content = f.read()

old_code = """              build_and_send(phone, combined_text, image_url, input, conv_id)
              PresidentialBridge.Session.set_session(conv_id, new_session_id)
            end"""

new_code = """              build_and_send(phone, combined_text, image_url, input, conv_id)
              PresidentialBridge.Session.set_session(conv_id, new_session_id)
              next_choices = PresidentialBridge.Typebot.get_active_choices(input)
              PresidentialBridge.Session.set_active_choices(conv_id, next_choices)
              PresidentialBridge.Chatwoot.update_custom_attributes(conv_id, %{
                typebotSessionId: new_session_id,
                activeChoices: Jason.encode!(next_choices)
              })
            end"""

content = content.replace(old_code, new_code)

with open('/root/presidential_bridge/lib/presidential_bridge/presidential_handler.ex', 'w') as f:
    f.write(content)

