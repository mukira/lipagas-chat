phone = "254723539760"
{:ok, contact} = LipagasBridge.Chatwoot.search_contact(phone)
{:ok, [conv | _]} = LipagasBridge.Chatwoot.get_contact_conversations(contact["id"])
{:ok, msgs} = LipagasBridge.Chatwoot.get_conversation_messages(conv["id"])
IO.puts "First msg ID: #{List.first(msgs)["id"]}, created_at: #{List.first(msgs)["created_at"]}"
IO.puts "Last msg ID: #{List.last(msgs)["id"]}, created_at: #{List.last(msgs)["created_at"]}"
