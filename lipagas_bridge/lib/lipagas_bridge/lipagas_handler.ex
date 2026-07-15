defmodule LipagasBridge.LipagasHandler do
  @moduledoc """
  Handles all incoming messages for the LipaGas main bot (Chatwoot webhook).
  This is the translation of the /webhook endpoint in bridge.js.
  """
  alias LipagasBridge.{Chatwoot, Typebot, Meta, Interceptor, Session, InactivityTimer, Mpesa}
  alias LipagasBridge.Config

  @reset_keywords ~w(reset hi hello start menu)

  def handle(event) when is_map(event) do
    # Only process incoming user messages
    if event["event"] != "message_created" or event["message_type"] != "incoming" do
      :skip
    else
      conv_id        = get_in(event, ["conversation", "id"])
      
      attachments    = event["attachments"] || []
      location_text  = Enum.find_value(attachments, "", fn att ->
                         if att["file_type"] == "location" do
                           lat = att["coordinates_lat"] || get_in(att, ["data_url", "coordinates_lat"])
                           lng = att["coordinates_long"] || get_in(att, ["data_url", "coordinates_long"])
                           url = att["data_url"] || ""
                           cond do
                             lat && lng -> "https://maps.google.com/?q=#{lat},#{lng}"
                             String.contains?(url, "maps.google") -> url
                             true -> att["fallback_title"] || ""
                           end
                         else
                           nil
                         end
                       end)
      
      base_content   = event["content"] || ""
      incoming_msg   = if location_text != "", do: location_text, else: base_content

      if incoming_msg == "" do
        :skip
      else
        custom_attrs   = get_in(event, ["conversation", "custom_attributes"]) || %{}
        session_id     = custom_attrs["typebotSessionId"]
        msg_lower      = String.downcase(String.trim(incoming_msg))
        is_reset       = msg_lower in @reset_keywords or String.contains?(msg_lower, "main menu")

        InactivityTimer.cancel(conv_id)

        cond do
        # Bot disabled, not a reset
        custom_attrs["bot_disabled"] == "true" and not is_reset ->
          :skip

        # Agent handoff requested
        String.contains?(msg_lower, "agent") or String.contains?(msg_lower, "speak") or
        msg_lower == "speak_to_agent" ->
          {:ok, phone} = Chatwoot.get_phone(conv_id)
          Chatwoot.handoff_to_agent(conv_id, phone)

        true ->
          # Re-enable bot and clear cart if reset is sent
          if is_reset do
            attrs = if custom_attrs["bot_disabled"] == "true", do: %{bot_disabled: "false"}, else: %{}
            attrs = Map.merge(attrs, %{active_cart_amount: 0, active_cart_label: "", active_cart_rids: ""})
            Chatwoot.update_custom_attributes(conv_id, attrs)
            Chatwoot.post_note(conv_id, "CART_TOTAL:0|")
          end

          if msg_lower in ["clear cart", "🗑️ clear cart"] do
            attrs = %{active_cart_amount: 0, active_cart_label: "", active_cart_rids: ""}
            Chatwoot.update_custom_attributes(conv_id, attrs)
            Chatwoot.post_note(conv_id, "CART_TOTAL:0|")
            case Chatwoot.get_sender(conv_id) do
              {:ok, sender} -> Chatwoot.update_contact(sender.id, attrs)
              _ -> :ok
            end
          end
          cond do
            msg_lower == "retry" ->
              {:ok, phone} = Chatwoot.get_phone(conv_id)
              payload = %{"conversationId" => conv_id, "phone" => phone, "meter" => ""}
              Task.start(fn -> LipagasBridge.HTTP.post_json("http://localhost:4000/trigger-mpesa", payload) end)
              LipagasBridge.Meta.send_text(phone, "🔄 Resending M-Pesa prompt... please check your phone.")

            true ->
              process_typebot(conv_id, incoming_msg, msg_lower, is_reset, session_id, event)
          end
      end
      end
    end
  end
  def handle(_), do: :skip

  # ─── Process message through Typebot ─────────────────────────────────

  defp process_typebot(conv_id, incoming_msg, msg_lower, is_reset, session_id, event) do
    with {:ok, sender} <- Chatwoot.get_sender(conv_id),
         {:ok, attrs}  <- Chatwoot.get_contact_attrs(conv_id) do
      phone       = sender.phone
      sender_name = sender.name
      active_choices = Session.get_active_choices(conv_id)
      category       = Session.get_category(conv_id)

      saved_location = attrs["saved_location"] || ""
      sanitized_location = saved_location |> String.replace("\n", " ") |> String.trim()
      initial_short_loc = resolve_human_location(sanitized_location)
      short_loc = initial_short_loc
      typebot_location = attrs["typebot_location"] || initial_short_loc

      # Update Chatwoot if contact has the old, long version saved
      if saved_location != "" and short_loc != "" and saved_location != short_loc do
        Task.start(fn ->
          Chatwoot.update_contact(sender.id, %{saved_location: short_loc})
        end)
      end

      File.write("/tmp/lipagas.log", "\n[DEBUG] attrs: #{inspect(attrs)}\n", [:append])
      variables_map = %{
        "SavedLocation" => short_loc,
        "contact_name" => sender_name,
        "name" => sender_name,
        "Name" => sender_name,
        "reg_name" => attrs["reg_name"] || "",
        "reg_phone" => attrs["reg_phone"] || "",
        "reg_id" => attrs["reg_id"] || "",
        "entity_name" => attrs["entity_name"] || "",
        "entity_type" => attrs["entity_type"] || "",
        "nearest_town" => attrs["nearest_town"] || ""
      }

      # Chatwoot webhook strips button IDs and only sends the visual 'title'.
      # Since we slice title to 20 chars and expand CART_TOTAL in build_and_send,
      # we must replicate that transformation on active_choices to find what they clicked.
      # Normalize strings by keeping only letters and numbers (ignoring emojis/punctuation) for robust matching
      normalize = fn s -> String.replace(String.downcase(s), ~r/[^\p{L}\p{N}]/u, "") end

      resolved_choice = Enum.find(active_choices, fn choice ->
        {:ok, expanded} = LipagasBridge.Interceptor.expand_cart_amount(choice, conv_id)
        norm_expected = normalize.(String.slice(expanded, 0, 20))
        norm_msg = normalize.(incoming_msg)
        norm_expected == norm_msg or normalize.(choice) == norm_msg
      end)

      # Fuzzy fallback for location buttons if the user edited the frontend text but clicked an old button
      resolved_choice = if is_nil(resolved_choice) and String.contains?(msg_lower, "location") do
        Enum.find(active_choices, fn choice -> String.contains?(String.downcase(choice), "location") end)
      else
        resolved_choice
      end

      is_valid_choice = not is_nil(resolved_choice)
      File.write("/tmp/lipagas.log", "\n---[INCOMING MSG]---\n#{incoming_msg}\nActive Choices: #{inspect(active_choices)}\nResolved: #{inspect(resolved_choice)}\nValid: #{is_valid_choice}\n", [:append])

      # Determine if this is an old/stale button click
      typebot_paths = load_typebot_paths()
      is_old_button = Map.has_key?(typebot_paths, msg_lower) and not is_valid_choice
      best_path     = find_best_path(typebot_paths, msg_lower, category)

      effective_session_id = Session.get_session(conv_id) || session_id

      # Check for invalid option
      if effective_session_id && active_choices != [] && not is_valid_choice &&
         not is_reset && not is_old_button do
        # Trigger the injected Typebot fallback block natively
        slug = LipagasBridge.Typebot.get_bot_slug("default")
        case LipagasBridge.Typebot.start_chat(slug, %{"SystemEvent" => "INVALID_OPTION", "Phone" => format_phone(phone)}) do
          {:ok, new_session_id, messages, input} ->
            {combined_text, image_url} = LipagasBridge.Typebot.parse_messages(messages, variables_map)
            if combined_text != "" do
              combined_text = shorten_text_locations(combined_text, saved_location, short_loc)
              build_and_send(phone, combined_text, image_url, input, conv_id)
              LipagasBridge.Session.set_session(conv_id, new_session_id)
              next_choices = LipagasBridge.Typebot.get_active_choices(input)
              LipagasBridge.Session.set_active_choices(conv_id, next_choices)
              LipagasBridge.Chatwoot.update_custom_attributes(conv_id, %{
                typebotSessionId: new_session_id,
                activeChoices: Jason.encode!(next_choices)
              })
            end
          _ -> :ok
        end
      else
        # Determine session to use
        effective_session = if is_reset or is_old_button do
          Session.delete_session(conv_id)
          nil
        else
          effective_session_id
        end
        File.write("/tmp/lipagas.log", "is_old_button: #{is_old_button}, effective_session: #{inspect(effective_session)}\n", [:append])

        # The message sent to Typebot must be the exact original case string
        effective_msg = resolved_choice || incoming_msg

        # Start or continue Typebot
        {tb_messages, input, new_session_id} =
          if effective_session == nil do
            slug = Typebot.get_bot_slug(msg_lower)
            
            prefill = %{"Phone" => format_phone(phone), "Conversation ID" => to_string(conv_id),
                        "contact_name" => sender_name, "name" => sender_name,
                        "Name" => sender_name, "contact.name" => sender_name}

            prefill = if short_loc != "", do: Map.put(prefill, "SavedLocation", short_loc), else: prefill

            case Typebot.start_chat(slug, prefill) do
              {:ok, new_sid, msgs, inp} ->
                Session.set_session(conv_id, new_sid)
                {msgs, inp} = replay_path(new_sid, best_path, msgs, inp)
                {msgs, inp, new_sid}
              {:error, reason} ->
                IO.puts("[LipaGas] Typebot start error: #{inspect(reason)}")
                {[], nil, nil}
            end
          else
                case Typebot.continue_chat(effective_session, effective_msg) do
              {:ok, msgs, inp} ->
                {msgs, inp, effective_session}
              {:error, :session_expired} ->
                Session.delete_session(conv_id)
                slug = Typebot.get_bot_slug(msg_lower)
                
                prefill = %{"Phone" => format_phone(phone), "Conversation ID" => to_string(conv_id),
                            "contact_name" => sender_name, "name" => sender_name}

                prefill = if short_loc != "", do: Map.put(prefill, "SavedLocation", short_loc), else: prefill
                case Typebot.start_chat(slug, prefill) do
                  {:ok, new_sid, msgs, inp} ->
                    Session.set_session(conv_id, new_sid)
                    {msgs, inp, new_sid}
                  _ -> {[], nil, nil}
                end
              {:error, reason} ->
                IO.puts("[LipaGas] Typebot continue error: #{inspect(reason)}")
                {[], nil, effective_session}
            end
          end

        old_saved_location = saved_location
        old_short_loc = short_loc

        # --- PRE-SCAN FOR NEW SAVED LOCATION ---
        # If Typebot is saving a new location in this turn, extract it to prevent stale location display.
        {saved_location, short_loc, variables_map} =
          case Enum.find_value(tb_messages, nil, fn msg ->
            if msg["type"] == "text" do
              rich = get_in(msg, ["content", "richText"]) || []
              raw_msg_text = Enum.map_join(rich, "\n", fn rt ->
                (is_map(rt) && rt["children"] || [])
                |> Enum.map_join("", fn c ->
                  cond do
                    is_map(c) and c["type"] == "inline-variable" ->
                      get_in(c, ["children", Access.at(0), "text"]) || ""
                    is_map(c) ->
                      c["text"] || ""
                    true ->
                      ""
                  end
                end)
              end)

              File.write("/tmp/lipagas.log", "\n[DEBUG] raw_msg_text: #{inspect(raw_msg_text)}\n", [:append])

              case Regex.run(~r/\[SAVE_LOCATION:([^\]]+)\]/, raw_msg_text) do
                [_, loc] -> String.trim(loc)
                _ -> nil
              end
            else
              nil
            end
          end) do
            nil ->
              {saved_location, short_loc, variables_map}
            new_loc when is_binary(new_loc) and new_loc != "" ->
              new_short = resolve_human_location(new_loc)

              Task.start(fn ->
                LipagasBridge.Chatwoot.update_contact(sender.id, %{saved_location: new_loc})
                if is_nil(attrs["typebot_location"]) do
                  LipagasBridge.Chatwoot.update_custom_attributes(conv_id, %{typebot_location: typebot_location})
                end
              end)

              # NOTE: We intentionally do NOT update typebot_location here locally for this turn.
              # typebot_location must remain the session-start location so that
              # on subsequent turns we can find and replace the old Typebot-seeded text.

              # Update variables_map so parse_messages uses the new location
              new_vars = Map.put(variables_map, "SavedLocation", new_short)
              {new_loc, new_short, new_vars}
          end

        typebot_short_loc = resolve_human_location(typebot_location)

        {combined_text, image_url} = Typebot.parse_messages(tb_messages, variables_map)

        # Forcefully replace old Typebot-seeded location text with the current saved location.
        # Typebot's session was seeded with typebot_location (raw) whose short form is typebot_short_loc.
        # Typebot outputs its short form in messages (e.g. "TRM Drive, TRM Drive").
        # We replace the doubled pattern first, then full and short forms.
        combined_text =
          if typebot_location != "" and typebot_short_loc != short_loc do
            doubled = "#{typebot_short_loc}, #{typebot_short_loc}"
            combined_text
            |> String.replace(doubled, short_loc)
            |> String.replace(typebot_location, short_loc)
            |> String.replace(typebot_short_loc, short_loc)
            |> String.replace(old_saved_location, short_loc)
            |> String.replace(old_short_loc, short_loc)
          else
            combined_text
          end

        # Failsafe: Forcefully overwrite the cart summary location to match the absolute current short_loc.
        # This bypasses any Typebot session memory staleness.
        combined_text =
          if short_loc != "" do
            Regex.replace(~r/📍 Delivery Location:[^\n]+/u, combined_text, "📍 Delivery Location: #{short_loc}")
          else
            combined_text
          end

        # Ensure any persistent long location values inside the text are dynamically shortened
        combined_text = shorten_text_locations(combined_text, saved_location, short_loc)

        # Run interceptors
        {final_text, intercepted} = run_interceptors(combined_text, phone, image_url, conv_id, msg_lower)

        if not intercepted do
          build_and_send(phone, final_text, image_url, input, conv_id)
        end

        # Save state
        next_choices = Typebot.get_active_choices(input)
        new_category = update_category(category, best_path)
        Session.set_active_choices(conv_id, next_choices)
        Session.set_category(conv_id, new_category)
        if new_session_id do
          Chatwoot.update_custom_attributes(conv_id, %{
            typebotSessionId: new_session_id,
            activeChoices:    Jason.encode!(next_choices),
            category:         new_category,
            typebot_location: saved_location
          })
        end
      end

        # Schedule inactivity timer
        InactivityTimer.schedule(conv_id, phone)
    else
      err ->
        IO.puts("[LipaGas] Failed to get sender: #{inspect(err)}")
    end
  end

  # ─── Run all interceptors in sequence ────────────────────────────────

  defp run_interceptors(text, phone, image_url, conv_id, msg_lower) do
    text = Interceptor.strip_stk_push_status(text)

    case Interceptor.process(text, phone, image_url, conv_id) do
      {:intercepted, _} ->
        {text, true}

      {:passthrough, cleaned} ->
        # Expand CART_TOTAL
        {:ok, expanded} = Interceptor.expand_cart_total(cleaned, conv_id)

        # Check SHOW_FLOW
        case Interceptor.build_flow_payload(expanded, phone) do
          {:ok, flow_payload} ->
            Meta.send_message(flow_payload)
            {expanded, true}

          :not_matched ->
            # Check SHOW_CATALOG
            case Interceptor.build_catalog_payload(expanded, phone, msg_lower) do
              {:ok, {:catalog, p, cat_id, set_id, body_text}} ->
                Meta.send_catalog(p, cat_id, set_id, body_text)
                {expanded, true}
              _ ->
                {expanded, false}
            end
        end
    end
  end

  # ─── Build and send the appropriate WhatsApp message ─────────────────

  def build_and_send(phone, text, image_url, input, conv_id) do
    clean = Regex.replace(~r/SHOW_CATALOG:\s*\w+/, text, "") |> String.trim()

    {final_clean, footer_text} = case Regex.run(~r/\[FOOTER:\s*([^\]]+)\]/i, clean) do
      [full_match, footer] ->
        {String.replace(clean, full_match, "") |> String.trim(), String.trim(footer)}
      nil ->
        {clean, nil}
    end

    {final_clean, inline_buttons} = case Regex.run(~r/\[BUTTONS:\s*([^\]]+)\]/i, final_clean) do
      [full_match, btns] ->
        button_list = String.split(btns, "|") |> Enum.map(&String.trim/1)
        {String.replace(final_clean, full_match, "") |> String.trim(), button_list}
      nil ->
        {final_clean, []}
    end

    input_choices = if is_map(input) && input["type"] == "choice input" do
      input["items"] || []
    else
      []
    end

    all_choices = input_choices ++ Enum.map(inline_buttons, fn btn -> %{"content" => btn} end)

    payload =
      cond do
        length(all_choices) > 0 ->
          buttons = all_choices
            |> Enum.take(3)
            |> Enum.map(fn item ->
              raw_title = (is_map(item) && item["content"]) || ""
              {:ok, expanded_title} = Interceptor.expand_cart_amount(raw_title, conv_id)
              # id = original full content so Typebot continue_chat routes correctly
              # title = expanded human-readable text the user sees on WhatsApp
              id    = raw_title
              title = String.slice(expanded_title, 0, 20)
              %{type: "reply", reply: %{id: id, title: title}}
            end)
          interactive = %{type: "button", body: %{text: final_clean || "Please choose:"}, action: %{buttons: buttons}}
          interactive = if footer_text, do: Map.put(interactive, :footer, %{text: footer_text}), else: interactive
          interactive = if image_url, do: Map.put(interactive, :header, %{type: "image", image: %{link: image_url}}), else: interactive
          %{messaging_product: "whatsapp", to: phone, type: "interactive", interactive: interactive}

        final_clean != "" ->
          # Append footer manually since plain text/image doesn't support a native footer block
          text_with_footer = if footer_text do
            "#{final_clean}\n\n_#{footer_text}_"
          else
            final_clean
          end

          if image_url do
            %{
              messaging_product: "whatsapp",
              to: phone,
              type: "image",
              image: %{
                link: image_url,
                caption: text_with_footer
              }
            }
          else
            %{messaging_product: "whatsapp", to: phone, type: "text", text: %{body: text_with_footer}}
          end

        true -> nil
      end

    if payload, do: Meta.send_message(payload)
  end



  # ─── Helper: replay path for direct button navigation ────────────────

  defp replay_path(_session_id, nil, msgs, input), do: {msgs, input}
  defp replay_path(_session_id, [], msgs, input), do: {msgs, input}
  defp replay_path(session_id, path, _msgs, _input) do
    Enum.reduce(path, {[], nil}, fn step, _acc ->
      case Typebot.continue_chat(session_id, step) do
        {:ok, msgs, inp} -> {msgs, inp}
        _                -> {[], nil}
      end
    end)
  end

  def resolve_human_location(location) when is_binary(location) do
    cond do
      location == "" ->
        ""

      String.contains?(location, " - Map: ") ->
        base_name = location |> String.split(" - Map: ") |> List.first() |> String.trim()
        shorten_comma_string(base_name)

      String.starts_with?(location, "http") and String.contains?(location, "maps.google.com") ->
        case Regex.run(~r/q=(-?\d+\.\d+),(-?\d+\.\d+)/, location) do
          [_, lat, lng] ->
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
                |> Enum.take(3)
                
                if length(parts) > 0 do
                  Enum.join(parts, ", ")
                else
                  shorten_comma_string(resp_map["display_name"] || location)
                end
              _ ->
                "Lat: #{lat}, Lng: #{lng}"
            end
          _ ->
            location
        end

      true ->
        shorten_comma_string(location)
    end
  end
  def resolve_human_location(_), do: ""

  defp shorten_comma_string(str) do
    parts = str |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
    if length(parts) > 2 do
      parts |> Enum.take(2) |> Enum.join(", ")
    else
      str
    end
  end

  def shorten_text_locations(text, saved_location, short_loc) when is_binary(text) do
    text = if saved_location != "" and short_loc != "" and saved_location != short_loc do
      sanitized_location = saved_location |> String.replace("\n", " ") |> String.trim()
      text
      |> String.replace(saved_location, short_loc)
      |> String.replace(sanitized_location, short_loc)
    else
      text
    end

    regex = ~r/[^,!?\n\(\)]+(?:,\s*[^,!?\n\(\)]+){2,}/u
    Regex.replace(regex, text, fn match ->
      lower_match = String.downcase(match)
      is_location = String.contains?(lower_match, ["sublocation", "location", "division", "kenya", "road", "drive", "street", "clinic", "estate"])
      
      if is_location do
        parts = match |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
        if length(parts) > 2 do
          parts |> Enum.take(2) |> Enum.join(", ")
        else
          match
        end
      else
        match
      end
    end)
  end

  # ─── Load Typebot path map from Docker Postgres ───────────────────────

  defp load_typebot_paths do
    case File.read("/root/lipagas_bridge/paths.json") do
      {:ok, body} ->
        case Jason.decode(body) do
          {:ok, paths} -> paths
          _ -> %{}
        end
      _ -> %{}
    end
  end

  defp find_best_path(paths, msg, category) do
    # paths.json stores {category => [step1, step2, ...]} maps per button
    # Always return a flat path list, selecting by category then "default"
    case Map.get(paths, msg) do
      nil                              -> nil
      path_map when is_map(path_map)   -> Map.get(path_map, category) || Map.get(path_map, "default") || []
      path_list when is_list(path_list)-> path_list
    end
  end

  defp update_category(current, nil), do: current
  defp update_category(_current, []), do: ""
  defp update_category(_current, [first | _]) do
    lower = String.downcase(first)
    cond do
      String.contains?(lower, "business") -> "business"
      String.contains?(lower, "gas")      -> "retail"
      String.contains?(lower, "token")    -> "tokens"
      true                                -> ""
    end
  end
  defp format_phone("254" <> rest) when byte_size(rest) == 9, do: "0" <> rest
  defp format_phone(phone), do: phone

  def handle_nfm_reply(phone, message) do
    response_json = get_in(message, ["interactive", "nfm_reply", "response_json"]) || "{}"
    flow_response = Jason.decode!(response_json)
    
    # Meta passes the flow_token back inside the response_json string!
    flow_token = flow_response["flow_token"] || get_in(message, ["interactive", "nfm_reply", "flow_token"]) || ""

    is_payg_reg = String.starts_with?(flow_token, "payg_reg_") or Map.has_key?(flow_response, "entity_name")

    if is_payg_reg do
      # Exact keys from flow.json payload: entity_name, entity_type, nearest_town
      entity_name  = flow_response["entity_name"]  || ""
      entity_type  = flow_response["entity_type"]  || ""
      nearest_town = flow_response["nearest_town"] || ""

      IO.puts("[LipaGas] PAYG form received: entity_name=#{entity_name} entity_type=#{entity_type} nearest_town=#{nearest_town}")

      case Chatwoot.search_contact(phone) do
        {:ok, contact} when not is_nil(contact) ->
          contact_id = contact["id"]
          case Chatwoot.get_contact_conversations(contact_id) do
            {:ok, convs} ->
              # Find the open conversation
              active_conv = Enum.find(convs, fn c -> c["status"] == "open" end) || List.first(convs)
              if active_conv do
                conv_id = active_conv["id"]
                custom_attrs = active_conv["custom_attributes"] || %{}

                existing_session = Session.get_session(conv_id) || custom_attrs["typebotSessionId"]

                if existing_session do
                  LipagasBridge.InactivityTimer.cancel(conv_id)
                  case Typebot.continue_chat(existing_session, "form_submitted") do
                    {:ok, msgs, input} ->
                      variables_map = %{
                        "entity_name"  => entity_name,
                        "entity_type"  => entity_type,
                        "nearest_town" => nearest_town,
                        "contact_name" => contact["name"] || "",
                        "Phone"        => format_phone(phone),
                        "reg_name"     => flow_response["reg_name"] || flow_response["name"] || flow_response["Name"] || entity_name || contact["name"] || "",
                        "reg_phone"    => flow_response["reg_phone"] || flow_response["phone"] || flow_response["Phone"] || format_phone(phone),
                        "reg_id"       => flow_response["reg_id"] || flow_response["id_number"] || flow_response["id"] || flow_response["ID"] || "N/A"
                      }
                      {combined_text, image_url} = Typebot.parse_messages(msgs, variables_map)
                      if combined_text != "" do
                        {final_text, intercepted} = run_interceptors(combined_text, phone, image_url, conv_id, "")
                        if not intercepted do
                          build_and_send(phone, final_text, image_url, input, conv_id)
                        end
                        next_choices = Typebot.get_active_choices(input)
                        Session.set_active_choices(conv_id, next_choices)
                        Chatwoot.update_custom_attributes(conv_id, %{
                          activeChoices: Jason.encode!(next_choices),
                          entity_name: variables_map["entity_name"],
                          entity_type: variables_map["entity_type"],
                          nearest_town: variables_map["nearest_town"],
                          reg_name: variables_map["reg_name"],
                          reg_phone: variables_map["reg_phone"],
                          reg_id: variables_map["reg_id"]
                        })
                      end
                    {:error, :session_expired} ->
                      IO.puts("[LipaGas] PAYG session expired for #{phone} — cannot continue")
                    {:error, e} ->
                      IO.puts("[LipaGas] continue_chat failed for #{phone}: #{inspect(e)}")
                  end
                else
                  IO.puts("[LipaGas] No active session found to continue for #{phone}")
                end
              end
            _ -> :ok
          end
        _ -> :ok
      end
    end
  end
end
