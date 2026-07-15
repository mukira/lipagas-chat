defmodule LipagasBridge.JoywoHandler do
  @moduledoc """
  Handles all messages for the JoyWO bot (dedicated WhatsApp number).
  Translated from the handleJoywoMessage function in bridge.js.
  """
  alias LipagasBridge.{Config, Meta, Session, Typebot, Mpesa}

  @reset_keywords ~w(reset hi hello start joy menu back)

  def handle(phone, message) when is_map(message) do
    Task.start(fn -> do_handle(phone, message) end)
  end
  def handle(_, _), do: :skip

  defp do_handle(phone, message) do
    cart = Session.get_joywo_cart(phone)

    # Handle WhatsApp catalog order (cart submission)
    if message["type"] == "order" do
      handle_cart_order(phone, message)
      return()
    end

    {incoming_msg, button_id} = extract_message(message)
    if incoming_msg == "", do: return()

    IO.puts("[JoyWO] Message from #{phone}: \"#{incoming_msg}\"")
    msg_lower = String.downcase(String.trim(incoming_msg))

    # Reset on keywords
    if msg_lower in @reset_keywords or button_id in ["joy_go_back", "tb_back"] do
      Session.delete_joywo_session(phone)
      Session.delete_joywo_cart(phone)
      Session.delete_joywo_tb_state(phone)
    end

    # Table Banking flow
    cond do
      incoming_msg == "🏦 Table Banking" ->
        Session.set_joywo_tb_state(phone, %{"state" => "AWAITING_TB_ID"})
        Meta.send_joywo_text(phone, "Please enter your ID number to access Table Banking:")

      (tb = Session.get_joywo_tb_state(phone)) && tb["state"] == "AWAITING_TB_ID" ->
        handle_tb_id_input(phone, msg_lower)

      button_id in ["tb_loan", "tb_meetings"] ->
        Meta.send_joywo_text(phone, "This feature is coming soon!")

      button_id == "joy_add_more" ->
        Meta.send_joywo_text(phone, "Please continue browsing the catalog.")

      button_id == "joy_pay" ->
        Session.set_joywo_cart(phone, Map.put(cart, "state", "AWAITING_ID"))
        Meta.send_joywo_text(phone, "Please enter your ID number:")

      cart["state"] == "AWAITING_ID" ->
        handle_id_input(phone, msg_lower, cart)

      cart["state"] == "CONFIRM_PAYMENT" ->
        handle_payment_confirmation(phone, button_id, cart)

      cart["state"] == "AWAITING_PAYMENT_NUMBER" ->
        handle_payment_number(phone, msg_lower, cart)

      cart["state"] == "AWAITING_MPESA" ->
        Meta.send_joywo_text(phone, "We are waiting for your M-Pesa payment confirmation. Please check your phone for the prompt.")

      true ->
        handle_typebot(phone, incoming_msg)
    end
  rescue
    e -> IO.puts("[JoyWO] Error: #{inspect(e)}")
  end

  # ─── Helper to avoid deep nesting ─────────────────────────────────────

  defp return(), do: :ok

  # ─── Extract message text and button_id ───────────────────────────────

  defp extract_message(message) do
    case is_map(message) && message["type"] do
      "text" ->
        {get_in(message, ["text", "body"]) || "", ""}
      "interactive" ->
        case message["interactive"]["type"] do
          "button_reply" ->
            title = get_in(message, ["interactive", "button_reply", "title"]) || ""
            id    = get_in(message, ["interactive", "button_reply", "id"])    || ""
            {title, id}
          "list_reply" ->
            title = get_in(message, ["interactive", "list_reply", "title"]) || ""
            {title, ""}
          "nfm_reply" ->
            handle_flow_response(message)
            {"", ""}
          _ -> {"", ""}
        end
      _ -> {"", ""}
    end
  end

  # ─── Handle WhatsApp Flow (NFM reply) ────────────────────────────────

  defp handle_flow_response(message) do
    flow_token    = get_in(message, ["interactive", "nfm_reply", "flow_token"]) || ""
    response_json = get_in(message, ["interactive", "nfm_reply", "response_json"]) || "{}"
    flow_response = Jason.decode!(response_json)

    is_create_group = flow_response["flow_type"] == "create_group" or String.starts_with?(flow_token, "create_group_")
    is_payg_reg     = flow_response["flow_type"] == "payg_reg" or String.starts_with?(flow_token, "payg_reg_")

    cond do
      is_payg_reg ->
        # Just log it — no hardcoded image per frontend priority rule
        IO.puts("[JoyWO] PAYG Registration received: #{inspect(flow_response)}")

      is_create_group ->
        handle_create_group(flow_response, message["from"])

      true ->
        handle_join_group(flow_response, message["from"])
    end
  end

  defp handle_create_group(r, phone) do
    group_name   = r["group_name"] || ""
    creator_name = r["creator_name"] || ""
    Meta.send_joywo_text(phone, "✅ Group *\"#{group_name}\"* has been created successfully!\n\nYou will be notified once it's approved. Welcome aboard! 🎉")
  end

  defp handle_join_group(r, phone) do
    name       = r["name"] || ""
    group_name = r["group_name"] || ""
    Meta.send_joywo_text(phone, "🎉 Thank you *#{name}*, your registration to JoyWO group *\"#{group_name}\"* is successful!")
  end

  # ─── Handle catalog order ──────────────────────────────────────────────

  defp handle_cart_order(phone, message) do
    items = get_in(message, ["order", "product_items"]) || []
    total = Enum.reduce(items, 0, fn i, acc ->
      acc + String.to_integer(to_string(i["item_price"] || "0")) * String.to_integer(to_string(i["quantity"] || "1"))
    end)
    Session.set_joywo_cart(phone, %{"state" => "CART_VIEW", "items" => items, "total" => total})

    # Trigger Typebot frontend block for Cart Checkout
    slug = Config.joywo_typebot_slug()
    case Typebot.start_chat(slug, %{"SystemEvent" => "CART_ORDER", "CartTotal" => to_string(total), "Phone" => phone}) do
      {:ok, session_id, messages, input} ->
        {combined_text, image_url} = Typebot.parse_messages(messages)
        if combined_text != "" do
          payload = build_joywo_payload(phone, combined_text, image_url, input)
          if payload, do: Meta.send_joywo_message(payload)
          Session.set_joywo_session(phone, session_id)
        end
      _ -> :ok
    end
  end

  # ─── Table Banking ID input ───────────────────────────────────────────

  defp handle_tb_id_input(phone, msg_lower) do
    id_number = String.replace(msg_lower, ~r/\D/, "")
    if id_number == "" do
      Meta.send_joywo_text(phone, "Please enter a valid numeric ID number:")
    else
      Meta.send_joywo_text(phone, "Verifying your ID, please wait...")
      Session.delete_joywo_tb_state(phone)
      
      # Trigger Typebot frontend block for Table Banking Main
      slug = Config.joywo_typebot_slug()
      case Typebot.start_chat(slug, %{"SystemEvent" => "TB_MAIN", "Phone" => phone}) do
        {:ok, session_id, messages, input} ->
          {combined_text, image_url} = Typebot.parse_messages(messages)
          if combined_text != "" do
            payload = build_joywo_payload(phone, combined_text, image_url, input)
            if payload, do: Meta.send_joywo_message(payload)
            Session.set_joywo_session(phone, session_id)
          end
        _ -> :ok
      end
    end
  end

  # ─── ID input for cart checkout ───────────────────────────────────────

  defp handle_id_input(phone, msg_lower, cart) do
    id_number = String.replace(msg_lower, ~r/\D/, "")
    if id_number == "" do
      Meta.send_joywo_text(phone, "Please enter a valid numeric ID number:")
    else
      Meta.send_joywo_text(phone, "Verifying your ID, please wait...")
      # In a full implementation: call IPRS here
      customer_name = "Valued Customer"
      Session.set_joywo_cart(phone, Map.merge(cart, %{"state" => "CONFIRM_PAYMENT", "customerName" => customer_name, "idNumber" => id_number}))
      Meta.send_joywo_message(%{
        messaging_product: "whatsapp", to: phone, type: "interactive",
        interactive: %{
          type: "button",
          body: %{text: "Hello #{customer_name},\n\nWould you like to make an order for KES #{cart["total"]}?"},
          action: %{buttons: [
            %{type: "reply", reply: %{id: "joy_pay_now",   title: "✅ Pay Now"}},
            %{type: "reply", reply: %{id: "joy_pay_other", title: "🔄 Change Number"}},
            %{type: "reply", reply: %{id: "joy_cancel",    title: "❌ Cancel"}}
          ]}
        }
      })
    end
  end

  # ─── Payment confirmation ─────────────────────────────────────────────

  defp handle_payment_confirmation(phone, button_id, cart) do
    case button_id do
      "joy_pay_now" ->
        receipt = Mpesa.generate_receipt("JOY")
        Session.set_joywo_cart(phone, Map.merge(cart, %{"state" => "AWAITING_MPESA", "receipt" => receipt}))
        Meta.send_joywo_text(phone, "Sending an M-Pesa prompt for KES #{cart["total"]}. Please enter your PIN to complete the payment.")
        Task.start(fn ->
          Mpesa.fire_stk_push(phone, cart["total"], receipt, "JoyWO Order")
        end)
      "joy_pay_other" ->
        Session.set_joywo_cart(phone, Map.put(cart, "state", "AWAITING_PAYMENT_NUMBER"))
        Meta.send_joywo_text(phone, "Please enter the M-Pesa phone number you wish to use (e.g. 07XXXXXXXX or 2547XXXXXXXX):")
      _ ->
        Session.delete_joywo_cart(phone)
        Meta.send_joywo_text(phone, "Order cancelled.")
    end
  end

  defp handle_payment_number(phone, msg_lower, cart) do
    payment_number = String.replace(msg_lower, ~r/\D/, "")
    if String.length(payment_number) < 9 do
      Meta.send_joywo_text(phone, "Please enter a valid phone number:")
    else
      receipt = Mpesa.generate_receipt("JOY")
      Session.set_joywo_cart(phone, Map.merge(cart, %{"state" => "AWAITING_MPESA", "receipt" => receipt}))
      Meta.send_joywo_text(phone, "Sending an M-Pesa prompt for KES #{cart["total"]} to #{payment_number}. Please enter the PIN to complete the payment.")
      Task.start(fn ->
        Mpesa.fire_stk_push(payment_number, cart["total"], receipt, "JoyWO Order")
      end)
    end
  end

  # ─── JoyWO Typebot ────────────────────────────────────────────────────

  defp handle_typebot(phone, incoming_msg) do
    session_id = Session.get_joywo_session(phone)
    slug = Config.joywo_typebot_slug()

    {messages, input, _sid} =
      if session_id == nil do
        case Typebot.start_chat(slug, %{"Phone" => phone}) do
          {:ok, sid, msgs, inp} ->
            Session.set_joywo_session(phone, sid)
            {msgs, inp, sid}
          _ -> {[], nil, nil}
        end
      else
        case Typebot.continue_chat(session_id, incoming_msg) do
          {:ok, msgs, inp} -> {msgs, inp, session_id}
          {:error, :session_expired} ->
            Session.delete_joywo_session(phone)
            case Typebot.start_chat(slug, %{"Phone" => phone}) do
              {:ok, sid, msgs, inp} ->
                Session.set_joywo_session(phone, sid)
                {msgs, inp, sid}
              _ -> {[], nil, nil}
            end
          _ -> {[], nil, nil}
        end
      end

    {combined_text, image_url} = Typebot.parse_messages(messages)
    if combined_text == "" and image_url == nil, do: return()

    payload = build_joywo_payload(phone, combined_text, image_url, input)
    if payload, do: Meta.send_joywo_message(payload)
  end

  defp build_joywo_payload(phone, combined_text, image_url, input) do
    cond do
      # SHOW_CREATE_GROUP_FLOW
      String.contains?(combined_text, "SHOW_CREATE_GROUP_FLOW:") ->
        case Regex.run(~r/SHOW_CREATE_GROUP_FLOW:\s*(\w+)/, combined_text) do
          [_, flow_id] ->
            %{messaging_product: "whatsapp", to: phone, type: "interactive",
              interactive: %{
                type: "flow",
                header: %{type: "text", text: "Create a JoyWO Group"},
                body:   %{text: "Fill in the details to create a new group:"},
                footer: %{text: "Secure form"},
                action: %{name: "flow", parameters: %{
                  flow_message_version: "3",
                  flow_token: "create_group_#{phone}_#{System.system_time(:millisecond)}",
                  flow_id: flow_id,
                  flow_cta: "Open Form",
                  flow_action: "navigate",
                  flow_action_payload: %{screen: "CREATE_GROUP_SCREEN"}
                }}
              }}
          nil -> nil
        end

      String.contains?(combined_text, "SHOW_FLOW:") ->
        case LipagasBridge.Interceptor.build_flow_payload(combined_text, phone) do
          {:ok, payload} -> payload
          _ -> nil
        end

      String.contains?(combined_text, "SHOW_CATALOG:") ->
        case Regex.run(~r/SHOW_CATALOG:\s*(\w+)/, combined_text) do
          [_, route] ->
            sets = Config.joywo_catalog_sets()
            case Map.get(sets, String.downcase(route)) do
              nil -> %{messaging_product: "whatsapp", to: phone, type: "text", text: %{body: "🛒 Opening store..."}}
              set_id ->
                # Async catalog fetch
                Task.start(fn ->
                  Meta.send_joywo_catalog(phone, set_id, combined_text)
                end)
                nil
            end
          nil -> nil
        end

      is_map(input) && input["type"] == "choice input" && length(input["items"] || []) > 0 ->
        items = input["items"]
        clean = Regex.replace(~r/SHOW_CATALOG:\s*\w+/, combined_text, "") |> String.trim()
        if length(items) <= 3 do
          buttons = items |> Enum.take(3) |> Enum.with_index() |> Enum.map(fn {item, i} ->
            title = String.slice(item["content"] || item["label"] || "Option #{i+1}", 0, 20)
            %{type: "reply", reply: %{id: "joy_#{i}", title: title}}
          end)
          interactive = %{type: "button", body: %{text: clean || "Please choose:"}, action: %{buttons: buttons}}
          interactive = if image_url, do: Map.put(interactive, :header, %{type: "image", image: %{link: image_url}}), else: interactive
          %{messaging_product: "whatsapp", to: phone, type: "interactive", interactive: interactive}
        else
          rows = items |> Enum.take(10) |> Enum.with_index() |> Enum.map(fn {item, i} ->
            title = String.slice(item["content"] || item["label"] || "Option #{i+1}", 0, 24)
            %{id: "joy_#{i}", title: title}
          end)
          %{messaging_product: "whatsapp", to: phone, type: "interactive",
            interactive: %{type: "list", body: %{text: clean || "Please choose:"},
              action: %{button: "View Options", sections: [%{title: "Options", rows: rows}]}}}
        end

      image_url != nil ->
        %{messaging_product: "whatsapp", to: phone, type: "image",
          image: %{link: image_url, caption: combined_text || ""}}

      combined_text != "" ->
        %{messaging_product: "whatsapp", to: phone, type: "text", text: %{body: combined_text}}

      true -> nil
    end
  end
end
