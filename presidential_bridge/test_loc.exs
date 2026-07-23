defmodule PresidentialBridge.TestLoc do
  alias PresidentialBridge.Meta

  def test do
    payload = %{
      messaging_product: "whatsapp",
      to: "254112250250", # Use the number from the screenshot
      type: "interactive",
      interactive: %{
        type: "location_request_message",
        header: %{type: "image", image: %{link: "https://cdn.lipagas.co/bot/enter-location.jpg"}},
        body: %{text: "Test location request with image header"},
        action: %{name: "send_location"}
      }
    }
    
    IO.puts("Testing location_request_message with header...")
    resp = Meta.send_message(payload)
    IO.inspect(resp)
  end
end

PresidentialBridge.TestLoc.test()
