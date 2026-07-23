defmodule PresidentialBridge.TypebotBotHandler do
  @moduledoc """
  Generic Typebot bot handler for Chatwoot Agent Bot events.

  Receives a Chatwoot message_created payload + Typebot slug.
  Manages Redis sessions, calls Typebot, then sends native WhatsApp messages
  (buttons, lists, images, text) directly via Meta Graph API for that inbox.
  """
  alias PresidentialBridge.{Typebot, Session, HTTP}

  @graph_base "https://graph.facebook.com/v21.0"
  @reset_keywords ~w(reset hi hello start menu back ruto exit)

  # ─── Inbox → Meta credentials map ────────────────────────────────────
  # Add one entry per WhatsApp inbox that has a bot assigned.
  # phone_number_id is in: Chatwoot DB → channel_whatsapp.provider_config
  @inbox_meta %{
    10 => %{
      phone_number_id: "1156689577536011",
      token: "EAAUbTMY5PfMBSEszVg4HAZA1aOZCcea5VBmZBEGMYIxOMnx1u0m4cbEJZAsIpQe6ZAHGu9cHCfm5dffeCXldFX1A28bErrqXMZCxDhGVAXUYexKSAWBpT8w2048naM0SF55x1DTiZBeqpLLQwrMoFqj9QJt0bpjhZBhsKnVAHctNjNoj3O0Eh5gdnZBZAhPZAdpoA06yBga4QeSHxz31vZBXqQagYmjBOiBlt9hmkVOrts6UfZAenFKZCDnVUgmuQdGfoeSHElW4CKmmlgQFL0jzBZAnIO110ou2IOKiD0HbSZAUOgsSvE0ErJDJ1dsMEUHNhV6zB883dcrLe2oZD"
    }
    # Add more inboxes here when you add more bots:
    # 5 => %{phone_number_id: "xxx", token: "yyy"}
  }

  # ─── Entry Point ──────────────────────────────────────────────────────

  def handle(payload, slug) do
    Task.start(fn -> do_handle(payload, slug) end)
  end

  # ─── Core Logic ───────────────────────────────────────────────────────

  defp do_handle(payload, slug) do
    conv_id  = get_in(payload, ["conversation", "id"])
    inbox_id = get_in(payload, ["inbox", "id"])
    phone    = extract_phone(payload)
    content  = payload["content"] || ""
    msg_lower = String.downcase(String.trim(content))
    user_name = get_in(payload, ["sender", "name"]) || 
                get_in(payload, ["conversation", "meta", "sender", "name"]) || "Citizen"

    meta = Map.get(@inbox_meta, inbox_id)
    if is_nil(meta) or is_nil(phone) or phone == "" do
      IO.puts("[TypebotBotHandler] Missing meta config for inbox_id=#{inbox_id} or phone. Skipping.")
    else
      # --- INTERCEPTOR: Projects Near Me Location Input ---
      awaiting = Redix.command!(:redix, ["GET", "awaiting_location:#{phone}"]) == "true"
      
      is_projects_btn = msg_lower in [
        "📍 projects near me", 
        "📍 miradi karibu nami", 
        "📍 projects area yangu",
        "projects near me",
        "miradi karibu nami",
        "projects area yangu"
      ]

      cond do
        awaiting and msg_lower not in @reset_keywords ->
          IO.puts("[TypebotBotHandler] Intercepting location: #{content}")
          Redix.command!(:redix, ["DEL", "awaiting_location:#{phone}"])
          
          persistent_lang = Session.get_language(phone) || "english"
          lang = cond do
            persistent_lang =~ "Kiswahili" -> "kiswahili"
            persistent_lang =~ "Sheng" -> "sheng"
            true -> "english"
          end

          wait_msg = cond do
            lang == "kiswahili" -> "🔍 Natafuta miradi karibu nawe..."
            lang == "sheng" -> "🔍 Nacheki ma-project area yako..."
            true -> "🔍 Searching for projects near you..."
          end
          send_meta(%{messaging_product: "whatsapp", to: phone, type: "text", text: %{body: wait_msg}}, meta)
          
          Task.start(fn ->
            result_text = PresidentialBridge.ProjectSearch.search(content, lang, user_name)
            send_meta(%{messaging_product: "whatsapp", to: phone, type: "text", text: %{body: result_text}}, meta)
            
            # Reset Typebot back to Main Menu silently
            do_handle(Map.put(payload, "content", "Ruto"), slug)
          end)

        is_projects_btn ->
          IO.puts("[TypebotBotHandler] Intercepting Projects button click")
          Redix.command!(:redix, ["SET", "awaiting_location:#{phone}", "true", "EX", "300"])
          
          persistent_lang = Session.get_language(phone) || "english"
          prompt_text = cond do
            persistent_lang =~ "Kiswahili" -> "🌍 Uko wapi? Tafadhali andika jina la mji, wilaya, au kaunti yako:"
            persistent_lang =~ "Sheng" -> "🌍 Uko area gani? Type jina ya tao, mtaa, ama county yako:"
            true -> "🌍 Where are you located? Please type your town, district, or county:"
          end
          
          send_meta(%{messaging_product: "whatsapp", to: phone, type: "text", text: %{body: prompt_text}}, meta)

        true ->
          IO.puts("[TypebotBotHandler] conv_id=#{conv_id} inbox=#{inbox_id} phone=#{phone} msg=#{inspect(content)}")

          button_mapping = build_dynamic_button_mapping(slug)
          matched_btn = Map.get(button_mapping, msg_lower)
          is_deep_switch = not is_nil(matched_btn)

          # Reset session on keywords or deep switch
          if msg_lower in @reset_keywords or is_deep_switch do
      if msg_lower == "exit" do
        IO.puts("[TypebotBotHandler] Exit keyword received — clearing greeting cache for conv #{conv_id}")
        Session.delete_greeting(conv_id)
      end
      IO.puts("[TypebotBotHandler] Reset keyword or deep switch — clearing session for conv #{conv_id}")
      Session.delete_session(conv_id)
    end

    session_id = Session.get_session(conv_id)

    {messages, input} =
      if is_nil(session_id) or msg_lower in @reset_keywords or is_deep_switch do
        {first_msgs, first_input, new_session_id} = start_new_session(conv_id, slug, payload)
        
        if is_deep_switch and new_session_id do
          [lang_str, topic_str] = matched_btn
          IO.puts("[TypebotBotHandler] Fast-forwarding deep switch: lang=#{lang_str} topic=#{inspect(topic_str)}")
          
          case Typebot.continue_chat(new_session_id, lang_str) do
            {:ok, lang_msgs, lang_input} ->
              if topic_str do
                case Typebot.continue_chat(new_session_id, topic_str) do
                  {:ok, topic_msgs, topic_input} -> 
                    IO.inspect(topic_msgs, label: "DEBUG DEEP SWITCH TOPIC MSGS")
                    {topic_msgs, topic_input}
                  _ -> {lang_msgs, lang_input}
                end
              else
                {lang_msgs, lang_input}
              end
            _ ->
              {first_msgs, first_input}
          end
        else
          persistent_lang = Session.get_language(phone)
          should_fast_forward = not is_nil(persistent_lang)
          
          if should_fast_forward and new_session_id do
            IO.puts("[TypebotBotHandler] Fast-forwarding persistent language: #{persistent_lang}")
            case Typebot.continue_chat(new_session_id, persistent_lang) do
              {:ok, lang_msgs, lang_input} -> {lang_msgs, lang_input}
              _ -> {first_msgs, first_input}
            end
          else
            {first_msgs, first_input}
          end
        end
      else
        continue_session(conv_id, session_id, slug, content, payload)
      end

      send_whatsapp_response(phone, meta, messages, input, conv_id)
      end
    end
  rescue
    e ->
      IO.puts("[TypebotBotHandler] Error: #{inspect(e)}\n#{Exception.format(:error, e, __STACKTRACE__)}")
  end

  defp return(), do: :ok

  # ─── Phone Extraction ─────────────────────────────────────────────────

  defp extract_phone(payload) do
    raw = get_in(payload, ["sender", "phone_number"]) ||
          get_in(payload, ["conversation", "meta", "sender", "phone_number"]) || ""
    String.replace(raw, ~r/[^\d]/, "")
  end

  # ─── Session Management ───────────────────────────────────────────────

  defp start_new_session(conv_id, slug, payload) do
    IO.puts("[TypebotBotHandler] Starting new session for conv #{conv_id} bot #{slug}")
    
    user_name = get_in(payload, ["sender", "name"]) || 
                get_in(payload, ["conversation", "meta", "sender", "name"]) || ""
    
    phone = extract_phone(payload)

    latest_news =
      case Redix.command(:redix, ["GET", "presidential_context"]) do
        {:ok, val} when is_binary(val) -> val
        _ -> "No latest news."
      end

    display_name = if user_name && String.trim(user_name) != "", do: user_name, else: "Mwananchi"

    greeting_index = Session.get_greeting(conv_id)
    greeting_index = if is_nil(greeting_index) do
      new_idx = Enum.random(1..5)
      Session.set_greeting(conv_id, Integer.to_string(new_idx))
      new_idx
    else
      case Integer.parse(to_string(greeting_index)) do
        {idx, _} -> idx
        :error -> Enum.random(1..5)
      end
    end

    # Dynamic Buttons & Summaries (Fetch from the 48-language JSON map in Redis)
    dynamic_translations = case Redix.command(:redix, ["GET", "dynamic_news_translations"]) do
      {:ok, val} when is_binary(val) and val != "" -> 
        case Jason.decode(val) do
          {:ok, json} -> json
          _ -> %{}
        end
      _ -> %{}
    end

    en_data = Map.get(dynamic_translations, "english", %{})
    sw_data = Map.get(dynamic_translations, "kiswahili", %{})
    sh_data = Map.get(dynamic_translations, "sheng", %{})

    dynamic_btn_en = Map.get(en_data, "button", "News")
    dynamic_btn_sw = Map.get(sw_data, "button", "Habari")
    dynamic_btn_sh = Map.get(sh_data, "button", "Riba")

    dynamic_summary_en = Map.get(en_data, "summary", "")
    dynamic_summary_sw = Map.get(sw_data, "summary", "")
    dynamic_summary_sh = Map.get(sh_data, "summary", "")

    prefilled_vars = %{
      "user_name" => user_name,
      "display_name" => display_name,
      "phone_number" => phone,
      "latest_news" => latest_news,
      "greeting_index" => to_string(greeting_index),
      "dynamic_btn_en" => dynamic_btn_en,
      "dynamic_btn_sw" => dynamic_btn_sw,
      "dynamic_btn_sh" => dynamic_btn_sh,
      "dynamic_summary" => dynamic_summary_en,
      "dynamic_summary_sw" => dynamic_summary_sw,
      "dynamic_summary_sh" => dynamic_summary_sh
    }
    IO.puts("[TypebotBotHandler] prefilled_vars: #{inspect(prefilled_vars)}")

    case Typebot.start_chat(slug, prefilled_vars) do
      {:ok, session_id, messages, input} ->
        Session.set_session(conv_id, session_id)
        {messages, input, session_id}
      {:error, reason} ->
        IO.puts("[TypebotBotHandler] start_chat failed: #{inspect(reason)}")
        {[], nil, nil}
    end
  end

  defp continue_session(conv_id, session_id, slug, content, payload) do
    phone = extract_phone(payload)
    content_lower = String.downcase(String.trim(content))
    
    # Save persistent language if they clicked a language button
    if content_lower in ["🇬🇧 english", "🇰🇪 kiswahili", "😎 sheng"] do
      Session.set_language(phone, content)
      IO.puts("[TypebotBotHandler] Saved persistent language for #{phone}: #{content}")
    end

    IO.puts("[TypebotBotHandler] Calling Typebot.continue_chat for session: #{session_id}")
    case Typebot.continue_chat(session_id, content) do
      {:ok, messages, input} ->
        IO.puts("[TypebotBotHandler] Typebot responded with messages: #{inspect(messages)} input: #{inspect(input)}")
        {messages, input}
      {:error, :session_expired} ->
        IO.puts("[TypebotBotHandler] Session expired for conv #{conv_id}, restarting")
        Session.delete_session(conv_id)
        {msgs, inp, _id} = start_new_session(conv_id, slug, payload)
        {msgs, inp}
      {:error, reason} ->
        IO.puts("[TypebotBotHandler] continue_chat failed: #{inspect(reason)}")
        {[], nil}
    end
  end

  # ─── WhatsApp Response Rendering ─────────────────────────────────────

  defp send_whatsapp_response(_phone, _meta, [], nil, _conv_id), do: :ok
  defp send_whatsapp_response(phone, meta, messages, input, conv_id) do
    {text, image_url} = Typebot.parse_messages(messages)

    cond do
      # ─── NATIVE META FEATURES ─────────────────────────────────────────────
      String.contains?(text, "SHOW_FLOW:") ->
        if image_url do
          send_meta(%{messaging_product: "whatsapp", to: phone, type: "image", image: %{link: image_url}}, meta)
        end
        case PresidentialBridge.Interceptor.build_flow_payload(text, phone) do
          {:ok, flow_payload} -> send_meta(flow_payload, meta)
          _ -> :ok
        end

      String.contains?(text, "[LOCATION_PROMPT]") ->
        if image_url do
          send_meta(%{messaging_product: "whatsapp", to: phone, type: "image", image: %{link: image_url}}, meta)
        end
        body_text = String.replace(text, "[LOCATION_PROMPT]", "") |> String.trim()
        interactive = %{
          type: "location_request_message",
          body: %{text: body_text},
          action: %{name: "send_location"}
        }
        send_meta(%{messaging_product: "whatsapp", to: phone, type: "interactive", interactive: interactive}, meta)
        PresidentialBridge.Session.set_waiting_location(conv_id, true)

      # ─── STANDARD TYPEBOT FEATURES ────────────────────────────────────────
      # Choice input with ≤3 items → WhatsApp interactive buttons
      is_map(input) and input["type"] == "choice input" and
        length(input["items"] || []) in 1..3 ->
          items = input["items"] || []
          buttons = items |> Enum.with_index() |> Enum.map(fn {item, i} ->
            original = String.trim(item["content"] || item["label"] || "Option #{i+1}")
            title = String.slice(original, 0, 20)
            # Use original as ID so the exact string goes back to Typebot
            %{type: "reply", reply: %{id: String.slice(original, 0, 256), title: title}}
          end)
          
          # --- ROBUST INTERCEPTOR: Typebot engine drops the variable if it contains complex markdown ---
          # If this is the News interactive block, fetch the text directly from Redis to ensure we never get a blank text.
          buttons_list = Enum.map(input["items"] || [], & &1["content"])
          text = cond do
            "📄 Read Full Updates" in buttons_list ->
              raw_redis = Redix.command!(:redix, ["GET", "dynamic_news_translations"]) || "{}"
              json = Jason.decode!(raw_redis)
              Map.get(Map.get(json, "english", %{}), "summary", text)
            "📄 Soma Taarifa Kamili" in buttons_list ->
              raw_redis = Redix.command!(:redix, ["GET", "dynamic_news_translations"]) || "{}"
              json = Jason.decode!(raw_redis)
              Map.get(Map.get(json, "kiswahili", %{}), "summary", text)
            "📄 Cheki Rada Yote" in buttons_list ->
              raw_redis = Redix.command!(:redix, ["GET", "dynamic_news_translations"]) || "{}"
              json = Jason.decode!(raw_redis)
              Map.get(Map.get(json, "sheng", %{}), "summary", text)
            "⬅️ Back to Main Menu" in buttons_list ->
              Redix.command!(:redix, ["GET", "dynamic_full_news_en"]) || text
            "⬅️ Rudi Nyuma" in buttons_list ->
              Redix.command!(:redix, ["GET", "dynamic_full_news_sw"]) || text
            "⬅️ Rudi Base" in buttons_list ->
              Redix.command!(:redix, ["GET", "dynamic_full_news_sh"]) || text
            true -> text
          end

          # Format text for WhatsApp: The LLM generates standard markdown (`**Text**`), but WhatsApp uses `*Text*`.
          # We simply replace double asterisks with single asterisks.
          formatted_text = String.replace(text, "**", "*")

          fallback = if Enum.any?(buttons_list, &String.contains?(&1, "⬅️")), do: "What would you like to do next?", else: "Please choose:"

          # WhatsApp interactive body text limit is 1024. If it's too big, fallback.
          body_text = if String.length(formatted_text) > 1000 do
             send_meta(%{messaging_product: "whatsapp", to: phone, type: "text", text: %{body: formatted_text}}, meta)
             fallback
          else
             if(formatted_text != "", do: formatted_text, else: fallback)
          end

          interactive = %{
            type: "button",
            body: %{text: body_text},
            action: %{buttons: buttons}
          }
          IO.inspect(buttons, label: "DEBUG BUTTONS")
          IO.inspect(interactive, label: "DEBUG INTERACTIVE")
          interactive = if image_url do
            Map.put(interactive, :header, %{type: "image", image: %{link: image_url}})
          else
            interactive
          end
          send_meta(%{messaging_product: "whatsapp", to: phone, type: "interactive", interactive: interactive}, meta)

      # Choice input with >3 items → WhatsApp list message
      is_map(input) and input["type"] == "choice input" and
        length(input["items"] || []) > 3 ->
          items = input["items"] || []
          
          rows = items |> Enum.take(10) |> Enum.with_index() |> Enum.map(fn {item, i} ->
            original = String.trim(item["content"] || item["label"] || "Option #{i+1}")
            title = String.slice(original, 0, 24)
            %{id: String.slice(original, 0, 200), title: title}
          end)
          
          body_text = if String.length(text) > 1000 do
            send_meta(%{messaging_product: "whatsapp", to: phone, type: "text", text: %{body: text}}, meta)
            "Please choose:"
          else
            if(text != "", do: text, else: "Please choose:")
          end

          send_meta(%{
            messaging_product: "whatsapp", to: phone, type: "interactive",
            interactive: %{
              type: "list",
              body: %{text: body_text},
              action: %{button: "View Options", sections: [%{title: "Options", rows: rows}]}
            }
          }, meta)

      # Image with caption
      image_url != nil and text != "" ->
        send_meta(%{messaging_product: "whatsapp", to: phone, type: "image",
          image: %{link: image_url, caption: text}}, meta)

      # Image only
      image_url != nil ->
        send_meta(%{messaging_product: "whatsapp", to: phone, type: "image",
          image: %{link: image_url}}, meta)

      # Plain text
      text != "" ->
        send_meta(%{messaging_product: "whatsapp", to: phone, type: "text",
          text: %{body: text}}, meta)

      true ->
        :ok
    end
  end

  # ─── Meta Graph API Sender ────────────────────────────────────────────

  defp send_meta(payload, nil) do
    send_meta(payload, %{phone_number_id: PresidentialBridge.Config.phone_id(), token: PresidentialBridge.Config.meta_token()})
  end

  defp send_meta(payload, %{phone_number_id: pid, token: token}) do
    url = "#{@graph_base}/#{pid}/messages"
    case HTTP.post_json(url, payload, [{"Authorization", "Bearer #{token}"}]) do
      {:ok, %{status: s}} when s in 200..299 ->
        IO.puts("[TypebotBotHandler] WhatsApp message sent (status #{s})")
      {:ok, resp} ->
        IO.puts("[TypebotBotHandler] Meta API error: #{resp.status} — #{inspect(resp.body)}")
      {:error, e} ->
        IO.puts("[TypebotBotHandler] HTTP error: #{inspect(e)}")
    end
  end

  # ─── Dynamic Button Mapping (Ghost Simulator) ──────────────────────────

  defp build_dynamic_button_mapping(slug) do
    cached = Session.get_button_mapping(slug)
    if cached do
      cached
    else
      IO.puts("[TypebotBotHandler] Ghost Simulation: Building dynamic button mapping for #{slug}")
      mapping = %{}
      case Typebot.start_chat(slug, %{"greeting_index" => 1}) do
        {:ok, _session_id, _messages, input} ->
          langs = Typebot.get_active_choices(input)
          mapping = Enum.reduce(langs, mapping, fn lang, acc ->
            Map.put(acc, String.downcase(lang), [lang, nil])
          end)
          
          mapping = Enum.reduce(langs, mapping, fn lang, acc ->
            case Typebot.start_chat(slug, %{"greeting_index" => 1}) do
              {:ok, sid, _, _} ->
                case Typebot.continue_chat(sid, lang) do
                  {:ok, _, topic_input} ->
                    topics = Typebot.get_active_choices(topic_input)
                    Enum.reduce(topics, acc, fn topic, inner_acc ->
                      Map.put(inner_acc, String.downcase(topic), [lang, topic])
                    end)
                  _ -> acc
                end
              _ -> acc
            end
          end)
          Session.set_button_mapping(slug, mapping)
          mapping
        _ ->
          %{}
      end
    end
  end
end
