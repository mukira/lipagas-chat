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
  @kenyan_languages [
    # Bare names (as sent from the secondary Typebot choice list)
    "kikuyu", "dholuo", "kalenjin", "kamba", "luhya", "somali", "kisii", "mijikenda", 
    "meru", "turkana", "masai", "maasai", "embu", "taita", "swahili", "kiswahili",
    "sheng", "pokot", "samburu", "rendille", "borana", "gabra", "orma", "kuria",
    "mbeere", "tharaka", "sabaot", "pokomo", "tugen", "nandi", "kipsigis", "keiyo",
    "marakwet", "terik", "sengwer", "ogiek", "yaaku", "el molo", "dahalo", "boni",
    "njemps", "taveta", "giriama", "digo", "chonyi", "rabai", "jibana", "kambe",
    "ribe", "kauma", "english",
    # Emoji-prefixed primary choices
    "🇬🇧 english", "🇰🇪 kiswahili", "😎 sheng",
    # Emoji-prefixed secondary (Other) choice
    "🇰🇪 other"
  ]

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
      
      # --- GLOBAL LANGUAGE INTERCEPTOR ---
      if msg_lower in @kenyan_languages and not awaiting do
        Session.set_language(phone, content)
        IO.puts("[TypebotBotHandler] Global intercept: Saved persistent language for #{phone}: #{content}")
      end
      
      is_projects_btn = msg_lower in [
        "📍 projects near me", 
        "📍 miradi karibu nami", 
        "📍 projects area yangu",
        "projects near me",
        "miradi karibu nami",
        "projects area yangu"
      ]

      is_news_btn = msg_lower in [
        "📰 rais news",
        "rais news",
        "📰 president's updates",
        "📰 taarifa za rais",
        "📰 rada ya prezzo",
        "📰 habari mpya",
        "habari mpya"
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
            lang == "kiswahili" -> "Ngoja kidogo, wacha niangalie miradi yote inayofanyika katika eneo lako 🇰🇪"
            lang == "sheng" -> "Tuliza kiasi, wacha nimsheki ma-project zote zinajengwa mtaani kwenu 🇰🇪"
            true -> "Hold on, let me look up the exact projects happening in your neighborhood 🇰🇪"
          end
          send_meta(%{messaging_product: "whatsapp", to: phone, type: "text", text: %{body: wait_msg}}, meta)
          
          Task.start(fn ->
            {intro_text, projects} = PresidentialBridge.ProjectSearch.search(content, lang, user_name)
            # 1. Send the intro text first
            send_meta(%{messaging_product: "whatsapp", to: phone, type: "text", text: %{body: intro_text}}, meta)
            
            # 2. Cache projects and assign priority images
            count = PresidentialBridge.ProjectPaginator.cache_projects(intro_text, projects, phone, content)
            
            # 3. Build Card 0 inline
            if count > 0 do
              raw_queue = Redix.command!(:redix, ["GET", "projects_queue_v130:#{phone}"])
              queue_data = Jason.decode!(raw_queue)
              queue = queue_data["projects"] || []
              Task.start(fn -> send_project_card(phone, meta, 0, queue) end)
            end
          end)

        (msg_lower in ["show first update 🚀", "start briefing 🚀"] or String.match?(msg_lower, ~r/next 🔥$/)) and Redix.command!(:redix, ["GET", "news_queue:#{phone}"]) != nil ->
          IO.puts("[TypebotBotHandler] Intercepting News Pagination")
          is_start = msg_lower in ["show first update 🚀", "start briefing 🚀"]
          
          current_index_str = Redix.command!(:redix, ["GET", "news_index:#{phone}"]) || "-1"
          current_index = String.to_integer(current_index_str)
          
          next_index = if is_start, do: 0, else: current_index + 1
          Redix.command!(:redix, ["SET", "news_index:#{phone}", to_string(next_index), "EX", "86400"])

          raw_queue = Redix.command!(:redix, ["GET", "news_queue:#{phone}"])
          queue = if raw_queue, do: Jason.decode!(raw_queue), else: []
          
          Task.start(fn -> send_news_card(phone, meta, next_index, queue) end)

        String.match?(msg_lower, ~r/next 🏗️$/) and Redix.command!(:redix, ["GET", "projects_queue_v130:#{phone}"]) != nil and Redix.command!(:redix, ["GET", "projects_index:#{phone}"]) != nil ->
          IO.puts("[TypebotBotHandler] Intercepting Projects Next button click")
          current_index_str = Redix.command!(:redix, ["GET", "projects_index:#{phone}"]) || "0"
          current_index = String.to_integer(current_index_str)
          next_index = current_index + 1
          Redix.command!(:redix, ["SET", "projects_index:#{phone}", to_string(next_index), "EX", "3600"])

          raw_queue = Redix.command!(:redix, ["GET", "projects_queue_v130:#{phone}"])
          queue_data = if raw_queue, do: Jason.decode!(raw_queue), else: %{"projects" => []}
          queue = queue_data["projects"] || []
          
          Task.start(fn -> send_project_card(phone, meta, next_index, queue) end)

        msg_lower in ["search another", "yes, search again"] ->
          IO.puts("[TypebotBotHandler] Intercepting Search Another button click")
          Redix.command!(:redix, ["SET", "awaiting_location:#{phone}", "true", "EX", "300"])
          
          persistent_lang = Session.get_language(phone) || "english"
          prompt_text = cond do
            persistent_lang =~ "Kiswahili" -> "Tuzungumzie eneo lako, *#{user_name}*! Ni mji, eneo bunge, au kaunti gani unaita nyumbani? Niambie ili tuangalie miradi ambayo serikali yangu inajenga karibu nawe."
            persistent_lang =~ "Sheng" -> "Tucheze stori ya mtaa yako, *#{user_name}*! Ni tao, constituency, ama county gani kwenu? Nichekie hapo ndio tuangalie ma-projects serikali yangu inajenga mtaani kwenu."
            true -> "Let's talk about your area, *#{user_name}*! Which town, constituency, or county do you call home? Tell me so we can look at what my administration is building near you."
          end
          
          send_meta(%{messaging_product: "whatsapp", to: phone, type: "text", text: %{body: prompt_text}}, meta)

        msg_lower == "main menu" ->
          IO.puts("[TypebotBotHandler] Intercepting Main Menu button click")
          persistent_lang = Session.get_language(phone) || "english"
          lang_str = cond do
            persistent_lang =~ "Kiswahili" -> "Kiswahili"
            persistent_lang =~ "Sheng" -> "Sheng"
            true -> "English"
          end
          # Trigger the deep switch logic natively to jump straight to the Main Menu
          do_handle(Map.put(payload, "content", lang_str), slug)

        msg_lower in ["🔙 back", "back", "menu", "⬅️ back to main menu"] ->
          IO.puts("[TypebotBotHandler] Intercepting Back/Menu — returning to Ushindi Loop menu for #{phone}")
          # Clear pagination caches to start fresh next time
          Redix.command(:redix, ["DEL", "news_index:#{phone}", "projects_index:#{phone}"])
          # Delete the current Typebot session so it doesn't get stuck
          Session.delete_session(conv_id)
          
          send_ushindi_loop_menu(phone, user_name, meta)

        msg_lower == "done ✅" ->
          IO.puts("[TypebotBotHandler] Intercepting Done ✅ — sending closing message for #{phone}")
          persistent_lang = Session.get_language(phone) || "english"
          closing_msg = cond do
            persistent_lang =~ "Kiswahili" -> "✅ Umesoma habari zote za leo! Nasikuishukuru kwa ushirikiano wako. Ikiwa una swali lolote, mimi niko hapa."
            persistent_lang =~ "Sheng" -> "✅ Umalize ma-updates zote za leo fam! Ukihitaji kitu, nipigie tena. Tutaonana! 🇰🇪"
            true -> "✅ You've read all of today's updates! Thank you for staying engaged. If you have any questions or want to explore more, I'm always here for you. 🇰🇪"
          end
          send_meta(%{messaging_product: "whatsapp", to: phone, type: "text", text: %{body: closing_msg}}, meta)
          
          # Delete the stale news-pagination session and pagination state BEFORE sending loop menu
          Redix.command(:redix, ["DEL", "news_index:#{phone}", "projects_index:#{phone}"])
          Session.delete_session(conv_id)
          
          send_ushindi_loop_menu(phone, user_name, meta)

        is_projects_btn ->
          IO.puts("[TypebotBotHandler] Intercepting Projects button click")
          Redix.command!(:redix, ["SET", "awaiting_location:#{phone}", "true", "EX", "300"])
          
          persistent_lang = Session.get_language(phone) || "english"
          prompt_text = cond do
            persistent_lang =~ "Kiswahili" -> "Tuzungumzie eneo lako, *#{user_name}*! Ni mji, eneo bunge, au kaunti gani unaita nyumbani? Niambie ili tuangalie miradi ambayo serikali yangu inajenga karibu nawe."
            persistent_lang =~ "Sheng" -> "Tucheze stori ya mtaa yako, *#{user_name}*! Ni tao, constituency, ama county gani kwenu? Nichekie hapo ndio tuangalie ma-projects serikali yangu inajenga mtaani kwenu."
            true -> "Let's talk about your area, *#{user_name}*! Which town, constituency, or county do you call home? Tell me so we can look at what my administration is building near you."
          end
          
          send_meta(%{messaging_product: "whatsapp", to: phone, type: "text", text: %{body: prompt_text}}, meta)

        is_news_btn ->
          IO.puts("[TypebotBotHandler] Intercepting News button click natively")
          count = PresidentialBridge.NewsPaginator.cache_news(phone)
          
          persistent_lang = Session.get_language(phone) || "english"
          count_msg = cond do
            persistent_lang =~ "Kiswahili" -> "Wacha nikupe muhtasari wa mambo makuu #{count} yanayofanyika kote nchini leo, *#{user_name}*!"
            persistent_lang =~ "Sheng" -> "Wacha nikupe rada ya ma-issue #{count} zinamake waves Kenya mzima leo, *#{user_name}*!"
            true -> "Let me brief you on #{count} major developments happening across the country today, *#{user_name}*!"
          end
          
          btn_payload = %{
            messaging_product: "whatsapp",
            to: phone,
            type: "interactive",
            interactive: %{
              type: "button",
              body: %{text: count_msg},
              action: %{
                buttons: [
                  %{
                    type: "reply",
                    reply: %{id: "start briefing 🚀", title: "Start briefing 🚀"}
                  }
                ]
              }
            }
          }
          send_meta(btn_payload, meta)

        true ->
          IO.puts("[TypebotBotHandler] conv_id=#{conv_id} inbox=#{inbox_id} phone=#{phone} msg=#{inspect(content)}")

          button_mapping = build_dynamic_button_mapping(slug)
          matched_btn = Map.get(button_mapping, msg_lower)
          is_deep_switch = not is_nil(matched_btn)

          is_ask_me_click = Enum.any?(
            ["ask me", "❓ ask me", "ask ai", "ask a question"],
            fn b -> String.contains?(msg_lower, b) end
          )

          is_button_click = Enum.any?(
            ["manifesto", "scorecard"],
            fn b -> String.contains?(msg_lower, b) end
          )

          cond do
            # --- NATIVE INTERCEPTION FOR ASK ME BUTTON -> DELIVER QUESTION PROMPT ---
            is_ask_me_click ->
              IO.puts("[TypebotBotHandler] Native Interception: Ask Me -> Delivering Question Prompt")
              prompt_text = "Let's talk, my friend! What question do you have for me today? Type it right here. 🇰🇪"
              send_meta(%{messaging_product: "whatsapp", to: phone, type: "text", text: %{body: prompt_text}}, meta)

            # --- FREEFORM NON-MENU INPUT NATIVE AI TAKEOVER ---
            not (msg_lower in @reset_keywords or is_deep_switch or is_button_click or msg_lower in @kenyan_languages or String.starts_with?(msg_lower, "http")) and String.length(msg_lower) > 1 ->
              IO.puts("[TypebotBotHandler] Freeform Non-Menu Native AI Takeover: #{inspect(content)}")
              persistent_lang = Session.get_language(phone) || "english"

              ai_payload = %{
                "user_name" => user_name,
                "user_language" => persistent_lang,
                "user_topic" => content,
                "InitialMessage" => content
              }

              case PresidentialBridge.AIProxy.process_request(ai_payload) do
                {:ok, ai_response} ->
                  formatted_ai_response = String.replace(ai_response, "[AI_RESPONSE_DIALOG]", "")
                                          |> String.replace("**", "*")
                                          |> String.trim()
                  send_meta(%{messaging_product: "whatsapp", to: phone, type: "text", text: %{body: formatted_ai_response}}, meta)

                  # Send interactive follow-up menu
                  followup_payload = %{
                    messaging_product: "whatsapp",
                    to: phone,
                    type: "interactive",
                    interactive: %{
                      type: "button",
                      body: %{text: "What would you like to explore next, my friend?"},
                      action: %{
                        buttons: [
                          %{type: "reply", reply: %{id: "❓ Ask Me", title: "❓ Ask Me"}},
                          %{type: "reply", reply: %{id: "⬅️ Back to Main Menu", title: "⬅️ Back to Main Menu"}}
                        ]
                      }
                    }
                  }
                  send_meta(followup_payload, meta)

                _ ->
                  process_default_typebot_flow(conv_id, inbox_id, phone, content, msg_lower, slug, payload, meta, matched_btn, is_deep_switch)
              end

            true ->
              process_default_typebot_flow(conv_id, inbox_id, phone, content, msg_lower, slug, payload, meta, matched_btn, is_deep_switch)
          end
      end
    end
  rescue
    e ->
      IO.puts("[TypebotBotHandler] Error: #{inspect(e)}\n#{Exception.format(:error, e, __STACKTRACE__)}")
  end

  defp process_default_typebot_flow(conv_id, inbox_id, phone, content, msg_lower, slug, payload, meta, matched_btn, is_deep_switch) do
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

    {messages, input, client_side_actions} =
      if is_nil(session_id) or msg_lower in @reset_keywords or is_deep_switch do
        {first_msgs, first_input, new_session_id, first_csa} = start_new_session(conv_id, slug, payload)
        
        if is_deep_switch and new_session_id do
          [lang_str, topic_str] = matched_btn
          IO.puts("[TypebotBotHandler] Fast-forwarding deep switch: lang=#{lang_str} topic=#{inspect(topic_str)}")
          
          case Typebot.continue_chat(new_session_id, lang_str) do
            {:ok, lang_msgs, lang_input, lang_csa} ->
              if topic_str do
                case Typebot.continue_chat(new_session_id, topic_str) do
                  {:ok, topic_msgs, topic_input, topic_csa} -> 
                    IO.inspect(topic_msgs, label: "DEBUG DEEP SWITCH TOPIC MSGS")
                    {topic_msgs, topic_input, topic_csa}
                  _ -> {lang_msgs, lang_input, lang_csa}
                end
              else
                {lang_msgs, lang_input, lang_csa}
              end
            _ ->
              {first_msgs, first_input, first_csa}
          end
        else
          {first_msgs, first_input, first_csa}
        end
      else
        continue_session(conv_id, session_id, slug, content, payload)
      end

      send_whatsapp_response(phone, meta, messages, input, conv_id, client_side_actions)
  rescue
    e ->
      IO.puts("[TypebotBotHandler] Error in default flow: #{inspect(e)}\n#{Exception.format(:error, e, __STACKTRACE__)}")
  end



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
      new_idx = Enum.random([1, 2, 4, 5])
      Session.set_greeting(conv_id, Integer.to_string(new_idx))
      new_idx
    else
      case Integer.parse(to_string(greeting_index)) do
        {idx, _} -> idx
        :error -> Enum.random([1, 2, 4, 5])
      end
    end

    # Fetch core English data and hash
    dynamic_btn_en = "📰 President's Updates"
    dynamic_summary = Redix.command!(:redix, ["GET", "dynamic_summary"]) || "[]"
    content_hash = Redix.command!(:redix, ["GET", "dynamic_content_hash"]) || "none"

    channel_link = "\n\n📢 *Want to get these updates directly?* Join the President's official WhatsApp Channel here: https://whatsapp.com/channel/0029VbCLeJXJpe8ZJPvxlY05"

    # Pre-translated Swahili and Sheng
    sw_raw = Redix.command!(:redix, ["GET", "trans_cache:kiswahili:#{content_hash}"])
    sw_data = if sw_raw, do: Jason.decode!(sw_raw), else: %{}
    dynamic_btn_sw = "📰 Taarifa za Rais"
    dynamic_summary_sw = (if is_binary(Map.get(sw_data, "summary", "")), do: Map.get(sw_data, "summary", ""), else: Jason.encode!(Map.get(sw_data, "summary", ""))) <> channel_link

    sh_raw = Redix.command!(:redix, ["GET", "trans_cache:sheng:#{content_hash}"])
    sh_data = if sh_raw, do: Jason.decode!(sh_raw), else: %{}
    dynamic_btn_sh = "📰 Rada ya Prezzo"
    dynamic_summary_sh = (if is_binary(Map.get(sh_data, "summary", "")), do: Map.get(sh_data, "summary", ""), else: Jason.encode!(Map.get(sh_data, "summary", ""))) <> channel_link

    # On-Demand translation check for persistent language
    persistent_lang = Session.get_language(phone) || "english"
    persistent_lang = String.downcase(String.trim(persistent_lang))
    
    # Clean emoji and leading spaces from language name if present
    persistent_lang = String.replace(persistent_lang, ~r/^[^\p{L}]+/u, "")

    {final_btn_en, final_summary_en} = if persistent_lang in ["english", "kiswahili", "sheng", "other"] do
      {dynamic_btn_en, dynamic_summary <> channel_link}
    else
      cache_key = "trans_cache:#{persistent_lang}:#{content_hash}"
      case Redix.command(:redix, ["GET", cache_key]) do
        {:ok, val} when is_binary(val) and val != "" ->
          IO.puts("[TypebotBotHandler] Cache HIT for language: #{persistent_lang}")
          lang_data = Jason.decode!(val)
          btn = Map.get(lang_data, "button", dynamic_btn_en)
          summ = (if is_binary(Map.get(lang_data, "summary", "")), do: Map.get(lang_data, "summary", ""), else: Jason.encode!(Map.get(lang_data, "summary", "")))
          {btn, summ <> channel_link}
        _ ->
          IO.puts("[TypebotBotHandler] Cache MISS for language: #{persistent_lang} — translating on demand...")
          case PresidentialBridge.AIProxy.translate_for_language(persistent_lang, dynamic_summary) do
            {:ok, reply} ->
              cleaned = reply |> String.replace(~r/```json\n?/, "") |> String.replace(~r/```/, "") |> String.trim()
              Redix.command(:redix, ["SET", cache_key, cleaned])
              lang_data = Jason.decode!(cleaned)
              btn = dynamic_btn_en
              summ = (if is_binary(Map.get(lang_data, "summary", "")), do: Map.get(lang_data, "summary", ""), else: Jason.encode!(Map.get(lang_data, "summary", "")))
              {btn, summ <> channel_link}
            _ ->
              IO.puts("[TypebotBotHandler] Translation failed for #{persistent_lang}. Falling back to English.")
              {dynamic_btn_en, dynamic_summary <> channel_link}
          end
      end
    end

    prefilled_vars = %{
      "user_name" => user_name,
      "display_name" => display_name,
      "phone_number" => phone,
      "latest_news" => latest_news,
      "greeting_index" => to_string(greeting_index),
      "dynamic_btn_en" => final_btn_en,
      "dynamic_btn_sw" => dynamic_btn_sw,
      "dynamic_btn_sh" => dynamic_btn_sh,
      "dynamic_summary" => final_summary_en,
      "dynamic_summary_sw" => dynamic_summary_sw,
      "dynamic_summary_sh" => dynamic_summary_sh,
      "news_count" => "0"
    }
    IO.puts("[TypebotBotHandler] prefilled_vars: #{inspect(prefilled_vars)}")

    case Typebot.start_chat(slug, prefilled_vars) do
      {:ok, session_id, messages, input, client_side_actions} ->
        Session.set_session(conv_id, session_id)
        {messages, input, session_id, client_side_actions}
      {:error, reason} ->
        IO.puts("[TypebotBotHandler] start_chat failed: #{inspect(reason)}")
        {[], nil, nil, []}
    end
  end

  defp continue_session(conv_id, session_id, slug, content, payload) do
    _phone = extract_phone(payload)
    _content_lower = String.downcase(String.trim(content))

    IO.puts("[TypebotBotHandler] Calling Typebot.continue_chat for session: #{session_id}")
    case Typebot.continue_chat(session_id, content) do
      {:ok, messages, input, client_side_actions} ->
        IO.puts("[TypebotBotHandler] Typebot responded with messages: #{inspect(messages)} input: #{inspect(input)}")
        {messages, input, client_side_actions}
      {:error, :session_expired} ->
        IO.puts("[TypebotBotHandler] Session expired for conv #{conv_id}, restarting")
        Session.delete_session(conv_id)
        {msgs, inp, _id, csa} = start_new_session(conv_id, slug, payload)
        {msgs, inp, csa}
      {:error, reason} ->
        IO.puts("[TypebotBotHandler] continue_chat failed: #{inspect(reason)}")
        {[], nil, []}
    end
  end

  # ─── WhatsApp Response Rendering ─────────────────────────────────────

  defp send_whatsapp_response(_phone, _meta, [], nil, _conv_id, _csa), do: :ok
  defp send_whatsapp_response(phone, meta, messages, input, conv_id, _client_side_actions) do
    {raw_text, image_url} = Typebot.parse_messages(messages)

    is_bypass_var_set = String.contains?(raw_text, "{{NO_TRANSLATE}}")
    text = String.replace(raw_text, "{{NO_TRANSLATE}}", "") |> String.trim()

    # --- AI RESPONSE DIALOG INTERCEPTOR ---
    {text, input} = if String.contains?(text, "[AI_RESPONSE_DIALOG]") do
      clean_text = String.replace(text, "[AI_RESPONSE_DIALOG]", "") |> String.trim()
      dialog_input = %{
        "type" => "choice input",
        "items" => [
          %{"content" => "❓ Ask Me"},
          %{"content" => "⬅️ Back to Main Menu"}
        ]
      }
      {clean_text, dialog_input}
    else
      {text, input}
    end

    # --- DOCUMENT INTERCEPTOR ---
    {text, doc_url, doc_name} = case Regex.run(~r/\[SEND_DOCUMENT:(.*?)\|(.*?)\]/, text) do
      [full_match, url, name] ->
        {String.replace(text, full_match, "") |> String.trim(), url, name}
      _ ->
        {text, nil, nil}
    end
    
    # Custom Manifesto & Scorecard formatting
    text = cond do
      doc_name != nil and String.contains?(String.downcase(doc_name), "manifesto") ->
        "📜 *OFFICIAL UDA 2022 MANIFESTO*\n\nMy friend, here is our official 2022 UDA Manifesto.\n\nThis is the blueprint for our Bottom-Up Economic Transformation Agenda (BETA). Explore the plan, ask me any questions directly, or view our Scorecard of delivered promises!"
      doc_name != nil and String.contains?(String.downcase(doc_name), "scorecard") ->
        "📊 *PRESIDENTIAL SCORECARD OF DELIVERED PROMISES*\n\nMy friend, here is our official Scorecard of delivered promises.\n\nThis demonstrates how we are executing our Bottom-Up Economic Transformation Agenda (BETA) across Affordable Housing, Hustler Fund, Agriculture, and Infrastructure. Take a look at what we have achieved!"
      true -> text
    end

    # --- REDUNDANT BUTTON FILTERING ---
    input = if is_map(input) and input["type"] == "choice input" and doc_name != nil do
      filtered_items = cond do
        String.contains?(String.downcase(doc_name), "manifesto") ->
          Enum.reject(input["items"] || [], fn i -> 
            String.contains?(String.downcase(i["content"] || i["label"] || ""), "manifesto")
          end)
        String.contains?(String.downcase(doc_name), "scorecard") ->
          Enum.reject(input["items"] || [], fn i -> 
            String.contains?(String.downcase(i["content"] || i["label"] || ""), "scorecard")
          end)
        true -> input["items"]
      end
      Map.put(input, "items", filtered_items)
    else
      input
    end

    is_lang_screen = is_bypass_var_set or (is_map(input) and input["type"] == "choice input" and
      Enum.any?(input["items"] || [], fn i -> 
        label = i["content"] || i["label"] || ""
        String.contains?(label, "Sheng") or 
        String.contains?(label, "Kikuyu") or
        String.contains?(label, "Dholuo") or
        String.contains?(label, "Kiswahili")
      end))

    cond do
      # ─── NATIVE META FEATURES ─────────────────────────────────────────────
      String.contains?(text, "SHOW_FLOW:") ->
        if image_url do
          send_meta(%{messaging_product: "whatsapp", to: phone, type: "image", image: %{link: image_url}}, meta, is_lang_screen)
        end
        if doc_url do
          send_meta(%{messaging_product: "whatsapp", to: phone, type: "document", document: %{link: doc_url, filename: doc_name}}, meta, is_lang_screen)
        end
        case PresidentialBridge.Interceptor.build_flow_payload(text, phone) do
          {:ok, flow_payload} -> send_meta(flow_payload, meta, is_lang_screen)
          _ -> :ok
        end

      String.contains?(text, "[LOCATION_PROMPT]") ->
        if image_url do
          send_meta(%{messaging_product: "whatsapp", to: phone, type: "image", image: %{link: image_url}}, meta, is_lang_screen)
        end
        if doc_url do
          send_meta(%{messaging_product: "whatsapp", to: phone, type: "document", document: %{link: doc_url, filename: doc_name}}, meta, is_lang_screen)
        end
        body_text = String.replace(text, "[LOCATION_PROMPT]", "") |> String.trim()
        interactive = %{
          type: "location_request_message",
          body: %{text: body_text},
          action: %{name: "send_location"}
        }
        send_meta(%{messaging_product: "whatsapp", to: phone, type: "interactive", interactive: interactive}, meta, is_lang_screen)
        PresidentialBridge.Session.set_waiting_location(conv_id, true)

      # ─── STANDARD TYPEBOT FEATURES ────────────────────────────────────────
      # Choice input with ≤3 items → WhatsApp interactive buttons
      is_map(input) and input["type"] == "choice input" and
        length(input["items"] || []) in 1..3 ->
          items = input["items"] || []
          originals = items |> Enum.with_index() |> Enum.map(fn {item, i} ->
            String.trim(item["content"] || item["label"] || "Option #{i+1}")
          end)

          lang = PresidentialBridge.Session.get_language(phone)
          translated_titles =
            if lang && lang not in ["English", "🇬🇧 English"] && not is_lang_screen do
              PresidentialBridge.Translation.translate_button_labels(originals, lang, 20)
            else
              originals
            end

          buttons = Enum.zip(originals, translated_titles) |> Enum.map(fn {original, translated} ->
            title = String.slice(translated || original, 0, 20)
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

          fallback = cond do
            Enum.any?(buttons_list, &String.contains?(&1, "Manifesto")) or Enum.any?(buttons_list, &String.contains?(&1, "Scorecard")) ->
              "What would you like to explore? You can ask me anything directly, read the official Manifesto, or view our current Scorecard of delivered promises."
            Enum.any?(buttons_list, &String.contains?(&1, "⬅️")) ->
              "What would you like to explore next, my friend?"
            true ->
              "Please choose:"
          end

          # WhatsApp interactive body text limit is 1024. If it's too big, fallback.
          body_text = if String.length(formatted_text) > 1000 do
             send_meta(%{messaging_product: "whatsapp", to: phone, type: "text", text: %{body: formatted_text}}, meta, is_lang_screen)
             fallback
          else
             if(formatted_text != "", do: formatted_text, else: fallback)
          end

          interactive = %{
            type: "button",
            body: %{text: body_text},
            action: %{buttons: buttons}
          }
          
          # Native fallback for language screen poster
          image_url = if is_lang_screen and is_nil(image_url) do
            "https://pub-649993d9eee74362a33a90ae2e2d8939.r2.dev/bot-images/bonga-na%20-rais.jpg"
          else
            image_url
          end

          interactive = cond do
            doc_url != nil ->
              Map.put(interactive, :header, %{type: "document", document: %{link: doc_url, filename: doc_name}})
            image_url != nil ->
              Map.put(interactive, :header, %{type: "image", image: %{link: image_url}})
            true -> interactive
          end
          
          send_meta(%{messaging_product: "whatsapp", to: phone, type: "interactive", interactive: interactive}, meta, is_lang_screen)

      # Choice input with >3 items → WhatsApp list message
      is_map(input) and input["type"] == "choice input" and
        length(input["items"] || []) > 3 ->
          if doc_url do
             send_meta(%{messaging_product: "whatsapp", to: phone, type: "document", document: %{link: doc_url, filename: doc_name}}, meta, is_lang_screen)
          end
          if image_url do
             send_meta(%{messaging_product: "whatsapp", to: phone, type: "image", image: %{link: image_url}}, meta, is_lang_screen)
          end
          
          items = input["items"] || []
          capped_items = Enum.take(items, 10)
          
          originals = capped_items |> Enum.with_index() |> Enum.map(fn {item, i} ->
            String.trim(item["content"] || item["label"] || "Option #{i+1}")
          end)

          lang = PresidentialBridge.Session.get_language(phone)
          translated_titles =
            if lang && lang not in ["English", "🇬🇧 English"] && not is_lang_screen do
              PresidentialBridge.Translation.translate_button_labels(originals, lang, 24)
            else
              originals
            end

          rows = Enum.zip(originals, translated_titles) |> Enum.map(fn {original, translated} ->
            title = String.slice(translated || original, 0, 24)
            %{id: String.slice(original, 0, 200), title: title}
          end)

          view_options_label =
            if lang && lang not in ["English", "🇬🇧 English"] do
              PresidentialBridge.Translation.translate_button_labels(["View Options"], lang, 20)
              |> List.first() || "View Options"
            else
              "View Options"
            end

          fallback = "Please choose an option from the menu."
          body_text = if String.length(text) > 1000 do
            send_meta(%{messaging_product: "whatsapp", to: phone, type: "text", text: %{body: text}}, meta, is_lang_screen)
            fallback
          else
            if(text != "", do: text, else: fallback)
          end

          send_meta(%{
            messaging_product: "whatsapp", to: phone, type: "interactive",
            interactive: %{
              type: "list",
              body: %{text: body_text},
              action: %{button: String.slice(view_options_label, 0, 20), sections: [%{title: "Options", rows: rows}]}
            }
          }, meta, is_lang_screen)

      true ->
        cond do
          doc_url != nil ->
             doc_payload = %{link: doc_url, filename: doc_name}
             doc_payload = if text != "", do: Map.put(doc_payload, :caption, text), else: doc_payload
             send_meta(%{messaging_product: "whatsapp", to: phone, type: "document", document: doc_payload}, meta, is_lang_screen)
          image_url != nil ->
             img_payload = %{link: image_url}
             img_payload = if text != "", do: Map.put(img_payload, :caption, text), else: img_payload
             send_meta(%{messaging_product: "whatsapp", to: phone, type: "image", image: img_payload}, meta, is_lang_screen)
          text != "" ->
             send_meta(%{messaging_product: "whatsapp", to: phone, type: "text", text: %{body: text}}, meta, is_lang_screen)
          true ->
             :ok
        end
    end
  end

  # ─── Meta Graph API Sender ────────────────────────────────────────────

  defp send_meta(payload, meta, bypass_translation \\ false) do
    phone = payload[:to]
    
    payload = if is_binary(phone) and phone != "" and not bypass_translation do
      lang = PresidentialBridge.Session.get_language(phone)
      if lang && lang not in ["English", "🇬🇧 English"] do
         translate_meta_payload(payload, lang)
      else
         payload
      end
    else
      payload
    end

    meta = meta || %{phone_number_id: PresidentialBridge.Config.phone_id(), token: PresidentialBridge.Config.meta_token()}
    pid = meta.phone_number_id
    token = meta.token

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

  defp translate_meta_payload(payload, lang) do
    case payload[:type] do
      "text" ->
        if text_body = get_in(payload, [:text, :body]) do
           translated = PresidentialBridge.Translation.translate(text_body, lang)
           put_in(payload, [:text, :body], translated)
        else
           payload
        end
      "interactive" ->
        interactive = payload[:interactive] || %{}
        body_text = get_in(interactive, [:body, :text])
        if body_text do
           translated = PresidentialBridge.Translation.translate(body_text, lang)
           interactive = put_in(interactive, [:body, :text], translated)
           put_in(payload, [:interactive], interactive)
        else
           payload
        end
      "image" ->
        caption = get_in(payload, [:image, :caption])
        if caption do
           translated = PresidentialBridge.Translation.translate(caption, lang)
           put_in(payload, [:image, :caption], translated)
        else
           payload
        end
      _ ->
        payload
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
        {:ok, _session_id, _messages, input, _csa} ->
          langs = Typebot.get_active_choices(input)
          mapping = Enum.reduce(langs, mapping, fn lang, acc ->
            Map.put(acc, String.downcase(lang), [lang, nil])
          end)
          
          mapping = Enum.reduce(langs, mapping, fn lang, acc ->
            case Typebot.start_chat(slug, %{"greeting_index" => 1}) do
              {:ok, sid, _, _, _} ->
                case Typebot.continue_chat(sid, lang) do
                  {:ok, _, topic_input, _} ->
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

  # ─── News Image Cards: parse bullets and send one image per point ─────────

  defp send_news_card(phone, meta, next_index, queue) do
    total_count = length(queue)
    item = Enum.at(queue, next_index)

    if item do
      display_index = next_index + 1
      is_last = display_index >= total_count
      button_label = if is_last, do: "Done ✅", else: "#{display_index + 1}/#{total_count} Next 🔥"

      # Generate AI headline/subtitle lazily for the image overlay
      {ai_headline, ai_subtitle, presidential_body} = PresidentialBridge.NewsPaginator.generate_headline_for_overlay(item["detail"] || "", item["author_handle"] || "")

      # Generate overlay URLs in parallel
      overlay_urls = item["image_urls"]
        |> Task.async_stream(
             fn img_url -> PresidentialBridge.ImageOverlay.generate(img_url, ai_headline, ai_subtitle) end,
             timeout: 30_000,
             max_concurrency: 4
           )
        |> Enum.map(fn {:ok, url} -> url; _ -> nil end)
        |> Enum.reject(&is_nil/1)

      body_text = if String.length(presidential_body || "") > 10, do: presidential_body, else: (item["detail"] || "")
      date_str = item["subtitle"] || (Date.utc_today() |> Calendar.strftime("%A, %-d %B %Y"))

      raw_text_body = """
      📅 #{date_str}

      *#{ai_headline}*

      #{body_text}
      """

      text_body = if String.length(raw_text_body) > 1000, do: String.slice(raw_text_body, 0, 997) <> "...", else: raw_text_body

      fallback_url = "/app/lib/presidential_bridge/ruto_fallback.jpg"
      first_image_url = List.first(overlay_urls) || fallback_url
      remaining_images = Enum.drop(overlay_urls, 1)

      # 1. Send all extra images first (if any)
      Enum.each(remaining_images, fn url ->
        send_meta(%{
          messaging_product: "whatsapp",
          to: phone,
          type: "image",
          image: %{link: url}
        }, meta, false)
        Process.sleep(200) # Tiny delay to help ordering for extra images
      end)

      # 2. Send the Main Card (Atomic Image + Text + Buttons)
      btn_payload = %{
        messaging_product: "whatsapp",
        to: phone,
        type: "interactive",
        interactive: %{
          type: "button",
          header: %{type: "image", image: %{link: first_image_url}},
          body: %{text: text_body},
          action: %{
            buttons: 
              if display_index > 1 do
                [
                  %{type: "reply", reply: %{id: "🔙 Back", title: "🔙 Back"}},
                  %{type: "reply", reply: %{id: button_label, title: String.slice(button_label, 0, 20)}}
                ]
              else
                [
                  %{type: "reply", reply: %{id: button_label, title: String.slice(button_label, 0, 20)}}
                ]
              end
          }
        }
      }
      send_meta(btn_payload, meta, false)
    else
      IO.puts("[TypebotBotHandler] Failed to find news for Next at index #{next_index}")
    end
  end

  defp send_project_card(phone, meta, next_index, queue) do
    total_count = length(queue)
    item = Enum.at(queue, next_index)

    if item do
      display_index = next_index + 1
      is_last = display_index >= total_count
      button_label = if is_last, do: "Done ✅", else: "#{display_index + 1}/#{total_count} Next 🏗️"
      
      clean_headline = item["headline"] || item["title"] || "Development Projects"
      clean_subtitle = item["short_subtitle"] || item["subtitle"] || ""
      clean_detail = item["detail"] || ""

      text_body = """
      📅 #{item["date"]}

      *#{clean_headline}*

      #{clean_detail}
      """

      # Generate overlay URLs in parallel for all images in the project
      raw_imgs = case item["image_urls"] do
        urls when is_list(urls) and length(urls) > 0 -> Enum.reject(urls, &is_nil/1)
        _ -> if item["image_url"], do: [item["image_url"]], else: ["/app/lib/presidential_bridge/ruto_fallback.jpg"]
      end

      raw_imgs = if length(raw_imgs) == 0, do: ["/app/lib/presidential_bridge/ruto_fallback.jpg"], else: raw_imgs

      overlay_urls = raw_imgs
        |> Task.async_stream(
             fn img_url -> PresidentialBridge.ImageOverlay.generate(img_url, clean_headline, clean_subtitle) end,
             timeout: 30_000,
             max_concurrency: 3
           )
        |> Enum.map(fn {:ok, url} -> url; _ -> nil end)
        |> Enum.reject(&is_nil/1)

      fallback_url = "/app/lib/presidential_bridge/ruto_fallback.jpg"
      first_image_url = List.first(overlay_urls) || fallback_url
      remaining_images = Enum.drop(overlay_urls, 1)

      # 1. Send all extra images first (if any)
      Enum.each(remaining_images, fn url ->
        send_meta(%{
          messaging_product: "whatsapp",
          to: phone,
          type: "image",
          image: %{link: url}
        }, meta, false)
        Process.sleep(200) # Tiny delay to help ordering
      end)

      # 2. Send the Main Card (Atomic Image + Text + Buttons)
      btn_payload = %{
        messaging_product: "whatsapp",
        to: phone,
        type: "interactive",
        interactive: %{
          type: "button",
          header: %{type: "image", image: %{link: first_image_url}},
          body: %{text: text_body},
          action: %{
            buttons: 
              if display_index > 1 do
                [
                  %{type: "reply", reply: %{id: "🔙 Back", title: "🔙 Back"}},
                  %{type: "reply", reply: %{id: button_label, title: String.slice(button_label, 0, 20)}}
                ]
              else
                [
                  %{type: "reply", reply: %{id: button_label, title: String.slice(button_label, 0, 20)}}
                ]
              end
          }
        }
      }
      send_meta(btn_payload, meta)
    else
      IO.puts("[TypebotBotHandler] Failed to find project at index #{next_index}")
    end
  end

  defp send_ushindi_loop_menu(phone, user_name, meta) do
    greeting_text = """
    Tuendelee, my Friend #{user_name}! 👋

    Kenya's story is being written right now, and you are part of it.

    Let me show you what's being done.
    """

    btn_payload = %{
      messaging_product: "whatsapp",
      to: phone,
      type: "interactive",
      interactive: %{
        type: "button",
        header: %{type: "image", image: %{link: "https://pub-649993d9eee74362a33a90ae2e2d8939.r2.dev/bot-images/tuendelee.jpg"}},
        body: %{text: greeting_text},
        action: %{
          buttons: [
            %{type: "reply", reply: %{id: "📰 Rais News", title: "📰 Rais News"}},
            %{type: "reply", reply: %{id: "📍 Projects Near Me", title: "📍 Projects Near Me"}},
            %{type: "reply", reply: %{id: "💬 Ask President Ruto", title: "💬 Ask President Ruto"}}
          ]
        }
      }
    }

    send_meta(btn_payload, meta)
  end

end
