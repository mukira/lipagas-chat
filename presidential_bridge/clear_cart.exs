Application.ensure_all_started(:httpoison)

phone = "254723539760"

case PresidentialBridge.Chatwoot.search_contact(phone) do
  {:ok, contact} when not is_nil(contact) ->
    attrs = %{active_cart_amount: 0, active_cart_label: "", active_cart_rids: ""}
    
    # Clear contact profile
    PresidentialBridge.Chatwoot.update_contact(contact["id"], attrs)
    
    # Clear active conversation
    case PresidentialBridge.Chatwoot.get_contact_conversations(contact["id"]) do
      {:ok, [conv | _]} ->
        PresidentialBridge.Chatwoot.update_custom_attributes(conv["id"], attrs)
        PresidentialBridge.Chatwoot.post_note(conv["id"], "CART_TOTAL:0|")
        IO.puts("Successfully scrubbed cart for #{phone}")
      _ ->
        IO.puts("Contact found, but no conversations.")
    end
  _ ->
    IO.puts("Contact not found.")
end
