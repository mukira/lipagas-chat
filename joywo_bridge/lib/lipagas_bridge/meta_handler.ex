defmodule LipagasBridge.MetaHandler do
  @moduledoc """
  Handles incoming WhatsApp messages from Meta Graph API webhook.
  Routes to LipaGas, JoyWO, or Presidential bot based on phone_number_id.
  """
  alias LipagasBridge.{Config, Chatwoot, Meta}

  @lipagas_phone_id Config.phone_id()
  @joywo_phone_id   Config.joywo_phone_id()

  def handle(body) when is_map(body) do
    if body["object"] == "whatsapp_business_account" do
      change        = get_in(body, ["entry", Access.at(0), "changes", Access.at(0)]) || %{}
      value         = change["value"] || %{}
      message       = get_in(value, ["messages", Access.at(0)]) || %{}
      incoming_pid  = get_in(value, ["metadata", "phone_number_id"])
      contact_info  = get_in(value, ["contacts", Access.at(0)]) || %{}
      meta_name     = get_in(contact_info, ["profile", "name"]) || "Unknown"

      phone = is_map(message) && message["from"]
      if phone do
        text = extract_text(message)

        cond do
          # JoyWO bot on dedicated number
          incoming_pid == @joywo_phone_id ->
            LipagasBridge.JoywoHandler.handle(phone, message)

          # LipaGas main bot — forward order messages + forward to Chatwoot
          true ->
            if message["type"] == "interactive" and get_in(message, ["interactive", "type"]) == "nfm_reply" do
              LipagasBridge.LipagasHandler.handle_nfm_reply(phone, message)
            end
            # Forward to Chatwoot webhook (mutating order messages as needed)
            forward_to_chatwoot(body, message, phone)
        end
      end
    end
  end

  # ─── Extract text from any message type ──────────────────────────────

  defp extract_text(message) do
    case is_map(message) && message["type"] do
      "text"        -> get_in(message, ["text", "body"]) || ""
      "interactive" -> extract_interactive_text(message["interactive"])
      "location"    ->
        lat = get_in(message, ["location", "latitude"])
        lng = get_in(message, ["location", "longitude"])
        "https://maps.google.com/?q=#{lat},#{lng}"
      _ -> ""
    end
  end

  defp extract_interactive_text(%{"type" => "button_reply"} = i) do
    get_in(i, ["button_reply", "id"]) || get_in(i, ["button_reply", "title"]) || ""
  end
  defp extract_interactive_text(%{"type" => "list_reply"} = i) do
    get_in(i, ["list_reply", "id"]) || get_in(i, ["list_reply", "title"]) || ""
  end
  defp extract_interactive_text(_), do: ""

  # ─── Forward message to Chatwoot ─────────────────────────────────────

  defp forward_to_chatwoot(body, message, phone) do
    # Handle location messages — convert to text
    body = if message["type"] == "location" do
      location_data = message["location"] || %{}
      loc_name = location_data["name"]
      loc_address = location_data["address"]

      human_location = if is_binary(loc_name) and String.trim(loc_name) != "" do
        if is_binary(loc_address) and String.trim(loc_address) != "" do
          short_addr = loc_address
            |> String.split(",")
            |> Enum.map(&String.trim/1)
            |> Enum.reject(&(&1 == ""))
            |> Enum.take(1)
            |> Enum.join(", ")
          "#{String.trim(loc_name)}, #{short_addr}"
        else
          String.trim(loc_name)
        end
      else
        lat = location_data["latitude"]
        lng = location_data["longitude"]
        
        # Reverse Geocoding with Nominatim (Free Alternative to Google Maps)
        url = "https://nominatim.openstreetmap.org/reverse?format=json&lat=#{lat}&lon=#{lng}"
        headers = [{"User-Agent", "lipagas-bot/1.0"}]
        
        case LipagasBridge.HTTP.get(url, headers) do
          {:ok, %{status: 200, body: resp}} ->
            resp_map = if is_binary(resp), do: Jason.decode!(resp), else: resp
            address = resp_map["address"] || %{}
            parts = [
              resp_map["name"],
              address["road"],
              address["neighbourhood"],
              address["suburb"] || address["city_district"],
              address["city"] || address["town"] || address["village"]
            ]
            |> Enum.reject(&(&1 == nil or &1 == ""))
            |> Enum.uniq()
            |> Enum.take(2)
            
            if length(parts) > 0 do
              Enum.join(parts, ", ")
            else
              resp_map["display_name"] || ""
            end
          _ -> ""
        end
      end

      final_text = if human_location != "" do
        human_location
      else
        "Pinned Location"
      end

      modified_location = message
        |> Map.delete("location")
        |> Map.merge(%{"type" => "text", "text" => %{"body" => final_text}})
      put_in(body, ["entry", Access.at(0), "changes", Access.at(0), "value", "messages", Access.at(0)], modified_location)
    else
      body
    end

    # Handle catalog orders — calculate total and set "Select Brand"
    body = if message["type"] == "order" do
      process_order(message, phone)
      modified_message = message
        |> Map.delete("order")
        |> Map.merge(%{"type" => "text", "text" => %{"body" => "Select Brand"}})
      put_in(body, ["entry", Access.at(0), "changes", Access.at(0), "value", "messages", Access.at(0)], modified_message)
    else
      body
    end

    Chatwoot.forward_to_chatwoot(body)
  end

  # ─── Process a WhatsApp catalog order ────────────────────────────────

  defp process_order(message, phone) do
    order_items = get_in(message, ["order", "product_items"]) || []

    # Fetch live prices from Meta catalog
    catalog_data = fetch_catalog_data()

    {total, names, rids} = Enum.reduce(order_items, {0, [], []}, fn item, {tot, ns, rs} ->
      rid       = to_string(item["product_retailer_id"])
      qty       = String.to_integer(to_string(item["quantity"] || "1"))
      
      webhook_price = item["item_price"]
      product   = Map.get(catalog_data, rid, %{price: 1500, name: rid})
      
      unit_price = if webhook_price != nil and to_string(webhook_price) != "", do: parse_price(webhook_price), else: product.price
      
      product_name = product.name
      {tot + unit_price * qty,
       ns ++ ["#{product_name} (x#{qty}) @ KES #{round(unit_price)}"],
       rs ++ ["#{rid}:#{qty}:#{unit_price}"]}
    end)

    final_amount = round(total)
    final_label  = if names != [], do: Enum.join(names, ", "), else: "LipaGas Order"
    rids_str     = Enum.join(rids, ",")

    # Save to Chatwoot contact (Append to cart if already exists)
    case Chatwoot.search_contact(String.replace(phone, ~r/[^\d]/, "")) do
      {:ok, contact} when not is_nil(contact) ->
        contact_id = contact["id"]
        attrs = contact["custom_attributes"] || %{}
        
        is_fresh = attrs["order_state"] == "completed"
        prev_amount = if is_fresh, do: 0, else: parse_price(attrs["active_cart_amount"] || 0)
        prev_label  = if is_fresh, do: "", else: attrs["active_cart_label"] || ""
        prev_rids   = if is_fresh, do: "", else: attrs["active_cart_rids"] || ""

        new_amount = if prev_amount > 0, do: prev_amount + final_amount, else: final_amount
        
        new_label = cond do
          prev_label == "" or String.contains?(prev_label, "LipaGas Order") -> final_label
          true -> prev_label <> ", " <> final_label
        end

        new_rids = if prev_rids != "", do: prev_rids <> "," <> rids_str, else: rids_str

        new_attrs = %{
          active_cart_amount: new_amount,
          active_cart_label: new_label,
          active_cart_rids: new_rids
        }
        new_attrs = if is_fresh, do: Map.put(new_attrs, :order_state, "pending"), else: new_attrs
        
        Chatwoot.update_contact(contact_id, new_attrs)
        
        # Try to find the active conversation to post the note and update attributes
        case Chatwoot.get_contact_conversations(contact_id) do
          {:ok, convs} ->
            active_conv = Enum.find(convs, fn c -> c["status"] == "open" end) || List.first(convs)
            if active_conv do
              conv_id = active_conv["id"]
              Chatwoot.update_custom_attributes(conv_id, new_attrs)
              Chatwoot.post_note(conv_id, "CART_TOTAL:#{new_amount}|#{new_label}")
            end
          _ -> :ok
        end
      _ -> :ok
    end
  end

  defp fetch_catalog_data do
    url = "https://graph.facebook.com/v21.0/#{Config.catalog_id()}/products?fields=retailer_id,price,name&limit=250"
    case LipagasBridge.HTTP.get(url, [{"Authorization", "Bearer #{Config.meta_token()}"}]) do
      {:ok, %{status: 200, body: body}} ->
        (body["data"] || [])
        |> Enum.reduce(%{}, fn p, acc ->
          price = parse_price(p["price"])
          Map.put(acc, to_string(p["retailer_id"]), %{price: price, name: p["name"] || to_string(p["retailer_id"])})
        end)
      _ -> %{}
    end
  end

  defp parse_price(nil), do: 1500
  defp parse_price(price) do
    str = to_string(price) |> String.replace(~r/[^\d.]/, "")
    case Float.parse(str) do
      {f, _} -> round(f)
      :error ->
        case Integer.parse(str) do
          {i, _} -> i
          :error -> 1500
        end
    end
  end
end
