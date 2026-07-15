phone = "254723539760"
{:ok, contact} = LipagasBridge.Chatwoot.search_contact(phone)
LipagasBridge.Chatwoot.update_contact(contact["id"], %{
  active_cart_label: "6kg Gas Refill (x1)"
})
