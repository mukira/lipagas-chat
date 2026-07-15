import re

with open('/root/lipagas_bridge/lib/lipagas_bridge/lipagas_handler.ex', 'r') as f:
    content = f.read()

old_code = """              build_and_send(phone, combined_text, image_url, input, conv_id)
              LipagasBridge.Session.set_session(conv_id, new_session_id)
            end"""

new_code = """              build_and_send(phone, combined_text, image_url, input, conv_id)
              LipagasBridge.Session.set_session(conv_id, new_session_id)
              next_choices = LipagasBridge.Typebot.get_active_choices(input)
              LipagasBridge.Session.set_active_choices(conv_id, next_choices)
              LipagasBridge.Chatwoot.update_custom_attributes(conv_id, %{
                typebotSessionId: new_session_id,
                activeChoices: Jason.encode!(next_choices)
              })
            end"""

content = content.replace(old_code, new_code)

with open('/root/lipagas_bridge/lib/lipagas_bridge/lipagas_handler.ex', 'w') as f:
    f.write(content)

