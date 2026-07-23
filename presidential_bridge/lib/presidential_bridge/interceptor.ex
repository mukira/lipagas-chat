defmodule PresidentialBridge.Interceptor do
  @moduledoc """
  Intercepts special tags in Typebot output text and converts them into
  native WhatsApp payloads. Follows the FRONT-END PRIORITY RULE strictly:
  - Text, images, buttons are defined in Typebot Builder
  - This module ONLY handles native WhatsApp API features Typebot cannot do
  """
  alias PresidentialBridge.{Meta, Config}

  # ─── Tags that require native WhatsApp features ───────────────────────
  # These are set in Typebot text blocks and intercepted here

  @doc """
  Process all interceptors on the combined text.
  Returns {:intercepted, actions} | {:passthrough, cleaned_text}
  where actions is a list of side-effects to perform.
  """
  def process(combined_text, phone, image_urls, conv_id) do
    cond do
      # [LOCATION_PROMPT] — Native WhatsApp location request button
      String.contains?(combined_text, "[LOCATION_PROMPT]") ->
        body_text = String.replace(combined_text, "[LOCATION_PROMPT]", "") |> String.trim()
        
        if is_list(image_urls) do
          Enum.each(image_urls, fn img ->
            if img && img != "" do
              Meta.send_message(%{
                messaging_product: "whatsapp",
                to: phone,
                type: "image",
                image: %{link: img}
              })
              Process.sleep(500) # Ensure WhatsApp sequences them in the correct display order
            end
          end)
        end

        interactive = %{
          type: "location_request_message",
          body: %{text: body_text},
          action: %{name: "send_location"}
        }
        Meta.send_message(%{messaging_product: "whatsapp", to: phone, type: "interactive", interactive: interactive})
        PresidentialBridge.Session.set_waiting_location(conv_id, true)
        {:intercepted, :location_prompt}

      # [SAVE_LOCATION:...] — Silently saves the user's location to Chatwoot memory forever
      String.contains?(combined_text, "[SAVE_LOCATION:") ->
        location = case Regex.run(~r/\[SAVE_LOCATION:([^\]]+)\]/, combined_text) do
          [_, loc] -> String.trim(loc)
          _ -> ""
        end
        body_text = Regex.replace(~r/\[SAVE_LOCATION:[^\]]*\]/, combined_text, "") |> String.trim()

        if location != "" do
          case PresidentialBridge.Chatwoot.get_sender(conv_id) do
            {:ok, sender} ->
              PresidentialBridge.Chatwoot.update_contact(sender.id, %{saved_location: location})
            _ -> :ok
          end
        end

        # Return passthrough so the rest of the text is sent normally
        {:passthrough, body_text}

      # [ADD_TO_CART:AMOUNT|LABEL] — Adds the amount to the current cart total
      String.contains?(combined_text, "[ADD_TO_CART:") ->
        body_text = Regex.replace(~r/\[ADD_TO_CART:[^\]]*\]/, combined_text, "") |> String.trim()

        case Regex.run(~r/\[ADD_TO_CART:([\d.]+)\|([^\]]+)\]/, combined_text) do
          [_, amt_str, lbl_str] ->
            add_amt = parse_float(amt_str)
            base_lbl = String.trim(lbl_str)

            enriched_lbl = if base_lbl == "Gas Tokens" do
              meter = case PresidentialBridge.Chatwoot.get_conversation_messages(conv_id) do
                {:ok, msgs} ->
                  msg = msgs
                    |> Enum.reverse()
                    |> Enum.find(fn m ->
                         m["message_type"] == 0 and
                         m["content"] != nil and
                         Regex.match?(~r/^\d{10,13}$/, String.trim(m["content"]))
                       end)
                  if msg, do: String.trim(msg["content"]), else: nil
                _ -> nil
              end
              if meter, do: "Gas Tokens (Meter: #{meter})", else: base_lbl
            else
              base_lbl
            end

            add_lbl = if String.contains?(enriched_lbl, "@ KES"), do: enriched_lbl, else: "#{enriched_lbl} @ KES #{round(add_amt)}"

            # Fetch existing
            {cur_amt, cur_lbl} = case PresidentialBridge.Chatwoot.get_last_cart_total(conv_id) do
              {:ok, val, lbl} -> {val, String.replace(lbl, "Catalog Order:", "") |> String.trim()}
              _ -> {0, ""}
            end

            new_amt = cur_amt + add_amt
            new_lbl = if cur_lbl == "" or cur_lbl == "LipaGas Order", do: add_lbl, else: "#{cur_lbl}, #{add_lbl}"

            # Synchronously post the note so subsequent [CART_TOTAL] logic finds it
            PresidentialBridge.Chatwoot.post_note(conv_id, "CART_TOTAL:#{new_amt}|#{new_lbl}")

            # Synchronously update attributes so race conditions don't happen
            new_attrs = %{
              active_cart_amount: new_amt,
              active_cart_label: new_lbl,
              order_state: "pending"
            }
            PresidentialBridge.Chatwoot.update_custom_attributes(conv_id, new_attrs)
            case PresidentialBridge.Chatwoot.get_sender(conv_id) do
              {:ok, sender} -> 
                PresidentialBridge.Chatwoot.update_contact(sender.id, new_attrs)
              _ -> :ok
            end
          _ -> :ok
        end

        {:passthrough, body_text}

      # [PROCESS_ORDER:AMOUNT|METER] — Triggers M-Pesa STK Push
      String.contains?(combined_text, "[PROCESS_ORDER") ->
        body_text = Regex.replace(~r/\[PROCESS_ORDER[^\]]*\]/, combined_text, "") |> String.trim()

        amount_str = case Regex.run(~r/\[PROCESS_ORDER[:]?([\d.]+)?/, combined_text) do
          [_, amt] -> amt
          _ -> ""
        end

        {amount, label} = if amount_str == "" or parse_float(amount_str) <= 0 do
          case PresidentialBridge.Chatwoot.get_last_cart_total(conv_id) do
            {:ok, val, lbl} -> {val, lbl}
            _ -> {0, "LipaGas Payment"}
          end
        else
          label = case PresidentialBridge.Chatwoot.get_last_cart_total(conv_id) do
            {:ok, _, lbl} when lbl != "" -> lbl
            _ -> "LipaGas Payment"
          end
          {parse_float(amount_str), label}
        end

        meter = case Regex.run(~r/\[PROCESS_ORDER[^|\]]*\|([^\]]+)\]/, combined_text) do
          [_, m] -> m
          _ -> ""
        end

        meter = if meter == "" do
          case PresidentialBridge.Chatwoot.get_conversation_messages(conv_id) do
            {:ok, msgs} ->
              msg = msgs
                |> Enum.reverse()
                |> Enum.find(fn m -> 
                     m["message_type"] == 0 and 
                     m["content"] != nil and 
                     Regex.match?(~r/^\d{10,13}$/, String.trim(m["content"]))
                   end)
              if msg, do: String.trim(msg["content"]), else: ""
            _ -> ""
          end
        else
          meter
        end

        # Cache the amount and label to Chatwoot so retries seamlessly fetch them
        if amount > 0 do
          Task.start(fn ->
            PresidentialBridge.Chatwoot.update_custom_attributes(conv_id, %{
              active_cart_amount: amount,
              active_cart_label: label
            })
          end)
        end

        # Fire STK push in a separate async process (won't block)
        Task.start(fn ->
          trigger_stk_push(phone, amount, label, meter, conv_id)
        end)
        
        # Return passthrough so Typebot's native buttons (e.g. Retry, Help) are attached and sent!
        {:passthrough, body_text}

      true ->
        {:passthrough, combined_text}
    end
  end

  # ─── STK_PUSH_STATUS — strip tag, let Typebot Builder handle the UI ───

  def strip_stk_push_status(text) do
    String.replace(text, "[STK_PUSH_STATUS]", "") |> String.trim()
  end

  # ─── SHOW_FLOW — build native WhatsApp Flow from Typebot text ─────────

  def build_flow_payload(combined_text, phone) do
    case Regex.run(~r/SHOW_FLOW:\s*(\w+)/, combined_text) do
      [_, flow_id] ->
        header_text  = extract_field(combined_text, "Header", "Form Registration")
        body_text    = extract_field(combined_text, "Body",   "Click below to fill out the secure form:")
        footer_text  = extract_field(combined_text, "Footer", "Secure form")
        cta_text     = extract_field(combined_text, "CTA",    "Open Form")
        screen_name  = extract_field(combined_text, "Screen", "REGISTRATION_SCREEN")
        token_prefix = extract_field(combined_text, "TokenPrefix", "flow")

        payload = %{
          messaging_product: "whatsapp",
          to: phone,
          type: "interactive",
          interactive: %{
            type: "flow",
            header: %{type: "text", text: header_text},
            body:   %{text: body_text},
            footer: %{text: footer_text},
            action: %{
              name: "flow",
              parameters: %{
                flow_message_version: "3",
                flow_token: "#{token_prefix}_#{phone}_#{System.system_time(:millisecond)}",
                flow_id: flow_id,
                flow_cta: cta_text,
                flow_action: "navigate",
                flow_action_payload: %{screen: screen_name}
              }
            }
          }
        }
        {:ok, payload}

      nil -> :not_matched
    end
  end

  # ─── SHOW_CATALOG — fetch live products and build product list ────────

  def build_catalog_payload(combined_text, phone, msg_lower) do
    case Regex.run(~r/SHOW_CATALOG:\s*(\w+)/, combined_text) do
      [_, route_raw] ->
        route = resolve_catalog_route(route_raw, msg_lower)
        sets  = Config.presidential_catalog_sets()
        body_text = Regex.replace(~r/SHOW_CATALOG:\s*\w+/, combined_text, "") |> String.trim()
        body_text = if body_text == "", do: "Please select your brand from our live catalog below:", else: body_text

        case Map.get(sets, route) do
          nil ->
            {:error, "Unknown catalog route: #{route}"}
          set_id ->
            {:ok, {:catalog, phone, Config.catalog_id(), set_id, body_text}}
        end

      nil -> :not_matched
    end
  end

  # ─── CART_TOTAL — expand to pure amount for buttons ────────────────────

  def expand_cart_amount(combined_text, conv_id) do
    case PresidentialBridge.Chatwoot.get_last_cart_total(conv_id) do
      {:ok, amount, _label} ->
        final_text = Regex.replace(~r/\[CART_TOTAL[^\]]*\]/, combined_text, format_kes(amount))
        {:ok, final_text}
      _ ->
        final_text = Regex.replace(~r/\[CART_TOTAL[^\]]*\]/, combined_text, "0")
        {:ok, final_text}
    end
  end

  # ─── CART_TOTAL — expand to order summary text ───────────────────────

  def expand_cart_total(combined_text, conv_id) do
    # Fetch details from Chatwoot
    {db_amount, db_label} =
      case PresidentialBridge.Chatwoot.get_last_cart_total(conv_id) do
        {:ok, amount, label} -> {amount, String.replace(label, "Catalog Order:", "") |> String.trim()}
        _ -> {0, "Tokens / Fuel"}
      end

    cond do
      # New style: User configured placeholders and emojis directly in Typebot Builder
      String.contains?(combined_text, "[CART_ITEM]") ->
        # Format the cart items vertically by replacing comma-space with a newline
        db_label_vertical = String.replace(db_label, ", ", "\n")
        text_with_item = String.replace(combined_text, "[CART_ITEM]", db_label_vertical)

        final_text = Regex.replace(~r/\[CART_TOTAL[^\]]*\]/, text_with_item, format_kes(db_amount))

        {:ok, final_text}

      # Old style: Fallback layout
      true ->
        final_text = Regex.replace(~r/\[CART_TOTAL[^\]]*\]/, combined_text, "Item: *#{db_label}*\nTotal: *KES #{format_kes(db_amount)}*")

        {:ok, final_text}
    end
  end

  # ─── Private helpers ──────────────────────────────────────────────────

  defp extract_field(text, field, default) do
    case Regex.run(~r/#{field}:\s*(.+)/i, text) do
      [_, val] -> String.trim(val)
      nil      -> default
    end
  end

  defp resolve_catalog_route("retail_menu", msg_lower) do
    cond do
      String.contains?(msg_lower, "refill") -> "wholesale_refill"
      String.contains?(msg_lower, "new")    -> "wholesale_new"
      true                                  -> "retail_menu"
    end
  end
  defp resolve_catalog_route(route, _), do: route

  defp trigger_stk_push(phone, amount, label, meter, conv_id, retries \\ 3) do
    alias PresidentialBridge.{Mpesa, Chatwoot}
    formatted = Mpesa.format_phone(phone)
    
    {prefix, popup_text} =
      cond do
        String.contains?(String.downcase(label), "token") -> {"TOK", "Tokens Payment"}
        String.contains?(String.downcase(label), "wholesale") -> {"WH", "Wholesale Order"}
        String.contains?(String.downcase(label), "retail") -> {"RET", "Retail Order"}
        String.contains?(String.downcase(label), "catalog") -> {"CAT", "Catalog Order"}
        true -> {"LPG", label}
      end

    receipt = Mpesa.generate_receipt(prefix)

    IO.puts("[STK] Firing: phone=#{formatted} amount=#{amount} receipt=#{receipt} label=#{label}")

    case Mpesa.fire_stk_push(formatted, amount, receipt, popup_text) do
      {:ok, resp} ->
        IO.puts("[STK] ✅ Success: receipt=#{receipt} response=#{inspect(resp)}")
        Chatwoot.post_note(conv_id, "ORDER_STATE:completed|Receipt:#{receipt}|Amount:#{amount}|")
        Chatwoot.update_custom_attributes(conv_id, %{order_state: "completed"})
        if meter != "" do
          Chatwoot.post_note(conv_id, "PAYG_METER:#{meter}")
        end
      {:error, reason} ->
        IO.puts("[STK] ❌ FAILED: reason=#{inspect(reason)} phone=#{formatted} amount=#{amount}")
        if retries > 1 do
          IO.puts("[STK] ♻️ Retrying... (#{retries - 1} attempts left)")
          Process.sleep(2000)
          trigger_stk_push(phone, amount, label, meter, conv_id, retries - 1)
        else
          PresidentialBridge.Meta.send_text(phone, "⚠️ Safaricom's M-Pesa network is currently experiencing delays and did not respond. Please click the 'Retry' button in the previous message to try again.")
        end
    end
  end

  defp parse_float(s) do
    str = s |> to_string() |> String.replace(~r/[^\d.]/, "")
    case Float.parse(str) do
      {f, _} -> f
      :error ->
        case Integer.parse(str) do
          {i, _} -> i / 1
          :error -> 0.0
        end
    end
  end

  defp format_kes(amount) do
    amt = if is_binary(amount), do: parse_float(amount), else: amount
    amt = if is_integer(amt), do: amt / 1, else: amt

    if is_float(amt) do
      parts = amt |> :erlang.float_to_binary(decimals: 2) |> String.split(".")
      
      int_part = Enum.at(parts, 0)
                 |> String.graphemes()
                 |> Enum.reverse()
                 |> Enum.chunk_every(3)
                 |> Enum.map(&Enum.reverse/1)
                 |> Enum.map(&Enum.join/1)
                 |> Enum.reverse()
                 |> Enum.join(",")
                 
      dec_part = Enum.at(parts, 1)

      if amt >= 1000.0 and dec_part == "00" do
        int_part
      else
        "#{int_part}.#{dec_part}"
      end
    else
      to_string(amt)
    end
  end
end
