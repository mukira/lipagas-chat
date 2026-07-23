phone = "254723539760"
{:ok, contact} = PresidentialBridge.Chatwoot.search_contact(phone)
PresidentialBridge.Chatwoot.update_contact(contact["id"], %{
  active_cart_label: "6kg Gas Refill (x1)"
})
