defmodule LipagasBridge.Router do
  use Plug.Router

  plug Plug.Logger
  plug Plug.Parsers,
    parsers: [:json],
    pass: ["*/*"],
    json_decoder: Jason
  plug Plug.Static, at: "/receipts", from: "/tmp/lipagas_receipts"
  plug :match
  plug :dispatch

  alias LipagasBridge.{Config, MetaHandler, LipagasHandler, Mpesa, Chatwoot, Meta}

  # ─── Health Check ─────────────────────────────────────────────────────

  get "/" do
    send_resp(conn, 200, "🔥 LipaGas Elixir Bridge v1.0 running on port #{Config.port()}")
  end

  # ─── Meta Webhook Verification ────────────────────────────────────────

  get "/meta-webhook" do
    conn    = fetch_query_params(conn)
    params  = conn.query_params
    mode    = params["hub.mode"]
    token   = params["hub.verify_token"]
    challenge = params["hub.challenge"]

    if mode == "subscribe" and token == Config.verify_token() do
      IO.puts("[Meta] Webhook verified!")
      send_resp(conn, 200, challenge)
    else
      send_resp(conn, 403, "Forbidden")
    end
  end

  # ─── Meta Webhook POST (incoming WhatsApp messages) ───────────────────

  post "/meta-webhook" do
    # Always respond 200 immediately — process async
    conn = send_resp(conn, 200, "EVENT_RECEIVED")
    Task.start(fn -> MetaHandler.handle(conn.body_params) end)
    conn
  end

  # ─── M-Pesa Callback (from Safaricom Daraja) ──────────────────────────

  post "/meta-webhook/mpesa-callback" do
    conn = send_resp(conn, 200, Jason.encode!(%{success: true}))
    Task.start(fn ->
      try do
        callback = conn.body_params
        stk_body = get_in(callback, ["Body", "stkCallback"]) || get_in(callback, ["body", "stkCallback"])

        {is_success, amount, receipt, phone} = 
          cond do
            not is_nil(stk_body) ->
              result_code = stk_body["ResultCode"]
              IO.puts("[M-Pesa Callback] STK ResultCode: #{result_code}")
              if result_code == 0 do
                metadata = stk_body["CallbackMetadata"]["Item"] || []
                a = Enum.find_value(metadata, fn item -> if item["Name"] == "Amount", do: item["Value"] end)
                r = Enum.find_value(metadata, fn item -> if item["Name"] == "MpesaReceiptNumber", do: item["Value"] end)
                p = Enum.find_value(metadata, fn item -> if item["Name"] == "PhoneNumber", do: item["Value"] end) |> to_string()
                {true, a, r, p}
              else
                {false, nil, nil, nil}
              end

            Map.has_key?(callback, "TransID") ->
              IO.puts("[M-Pesa Callback] C2B Confirmation: #{callback["TransID"]}")
              a = callback["TransAmount"]
              r = callback["TransID"]
              p = callback["MSISDN"] |> to_string()
              {true, a, r, p}

            true ->
              {false, nil, nil, nil}
          end

        if is_success do
          case Redix.command(:redix, ["SET", "mpesa_receipt:#{receipt}", "1", "NX", "EX", "86400"]) do
            {:ok, "OK"} ->
              # The phone comes as 254... Let's query Chatwoot
              case Chatwoot.search_contact(phone) do
                {:ok, contact} when not is_nil(contact) ->
                  contact_id = contact["id"]
                  case Chatwoot.get_contact_conversations(contact_id) do
                    {:ok, [conv | _]} ->
                      conv_id = conv["id"]
                      cart_label = case Chatwoot.get_last_cart_total(conv_id) do
                        {:ok, _, l} -> String.downcase(l)
                        _ -> ""
                      end
                      is_token = String.match?(cart_label, ~r/token|payg/)

                      # Check if there are non-token items in the cart
                      has_non_token = cart_label
                        |> String.split(",")
                        |> Enum.any?(fn s -> not String.match?(String.downcase(s), ~r/token|payg/) end)

                      # Get all messages to find the PAYG_METER private note
                      case Chatwoot.get_conversation_messages(conv_id) do
                        {:ok, msgs} ->
                          meter_msg = if is_token do
                            Enum.find(msgs, fn m -> m["private"] == true and String.contains?(m["content"] || "", "PAYG_METER:") end)
                          else
                            nil
                          end
                          
                          if meter_msg do
                            "PAYG_METER:" <> meter = meter_msg["content"]
                            meter = String.trim(meter)

                            # 1. Generate Main Receipt if there are non-token items
                            if has_non_token do
                              IO.puts("[M-Pesa Callback] Mixed order: generating MAIN receipt for conv #{conv_id}")
                              id_main = LipagasBridge.Receipt.generate_receipt(phone, amount, nil, receipt, nil)
                              pdf_path_main = LipagasBridge.Receipt.get_pdf_path(id_main)
                              case Meta.upload_media(pdf_path_main) do
                                {:ok, media_id} ->
                                  Meta.send_document_by_id(phone, media_id, "LipaGas_Receipt_#{receipt}.pdf")
                                err ->
                                  IO.puts("[M-Pesa Callback] Failed to upload MAIN PDF: #{inspect(err)}")
                              end
                              File.rm(pdf_path_main)
                            end

                            # 2. Extract Token Amount securely
                            token_str = cart_label 
                                        |> String.split(",") 
                                        |> Enum.find(fn s -> String.match?(String.downcase(s), ~r/token|payg/) end)
                            
                            token_amount = if token_str do
                              case Regex.run(~r/@\s*KES\s*([\d.]+)/i, token_str) do
                                [_, amt] -> 
                                  {val, _} = Float.parse(amt)
                                  val
                                _ -> amount
                              end
                            else
                              amount
                            end

                            # 3. Purchase Token
                            IO.puts("[M-Pesa Callback] Purchasing token for meter #{meter} with amount #{token_amount}")
                            token_code = case LipagasBridge.Stronpower.purchase_token(meter, token_amount) do
                              {:ok, t} -> t
                              _ -> "PENDING (System Delayed)"
                            end

                            # 4. Generate & Send TOKEN Receipt
                            id_token = LipagasBridge.Receipt.generate_receipt(phone, token_amount, token_code, "#{receipt}-TOK", meter)
                            pdf_path_token = LipagasBridge.Receipt.get_pdf_path(id_token)

                            case Meta.upload_media(pdf_path_token) do
                              {:ok, media_id} ->
                                Meta.send_document_by_id(phone, media_id, "LipaGas_Token_#{receipt}.pdf")
                              err ->
                                IO.puts("[M-Pesa Callback] Failed to upload TOKEN PDF: #{inspect(err)}")
                            end
                            File.rm(pdf_path_token)
                            
                            if has_non_token do
                              Chatwoot.post_note(conv_id, "✅ M-Pesa successful. Main Receipt: #{receipt}. Token Generated: #{token_code} for Meter #{meter}")
                            else
                              Chatwoot.post_note(conv_id, "✅ M-Pesa successful (Token Only). Token: #{token_code} for Meter #{meter}")
                            end

                          else
                            # Standard purchase (no PAYG_METER found or not a token)
                            IO.puts("[M-Pesa Callback] Standard purchase (MAIN) for conv #{conv_id}")
                            
                            id = LipagasBridge.Receipt.generate_receipt(phone, amount, nil, receipt, nil)
                            pdf_path = LipagasBridge.Receipt.get_pdf_path(id)

                            case Meta.upload_media(pdf_path) do
                              {:ok, media_id} ->
                                Meta.send_document_by_id(phone, media_id, "LipaGas_Receipt_#{receipt}.pdf")
                              err ->
                                IO.puts("[M-Pesa Callback] Failed to upload MAIN PDF: #{inspect(err)}")
                            end
                            File.rm(pdf_path)
                            
                            Chatwoot.post_note(conv_id, "✅ M-Pesa successful. Receipt: #{receipt}.")
                          end
                          
                          # -- Clear the shopping cart --
                          reset_attrs = %{
                            active_cart_amount: 0,
                            active_cart_label: "",
                            active_cart_rids: "",
                            order_state: "paid"
                          }
                          Chatwoot.update_custom_attributes(conv_id, reset_attrs)
                          case Chatwoot.get_sender(conv_id) do
                            {:ok, sender} -> Chatwoot.update_contact(sender.id, reset_attrs)
                            _ -> :ok
                          end
                          Chatwoot.post_note(conv_id, "CART_TOTAL:0|")
                          
                        _ -> nil
                      end
                    _ -> nil
                  end
                _ -> nil
              end
            _ -> 
              IO.puts("[M-Pesa Callback] Duplicate receipt ignored: #{receipt}")
          end
        end
      rescue
        e -> 
          IO.puts("[M-Pesa Callback Error] #{inspect(e)}")
          IO.inspect(__STACKTRACE__)
      end
    end)
    conn
  end

  # ─── M-Pesa STK Push trigger (from Typebot webhook) ──────────────────

  post "/meta-webhook/mpesa-push" do
    conn = send_resp(conn, 200, Jason.encode!(%{success: true}))
    Task.start(fn ->
      try do
        phone  = conn.body_params["phone"]
        if phone do
          digits = String.replace(phone, ~r/[^\d]/, "")
          q = String.slice(digits, -9, 9)
          case Chatwoot.search_contact(q) do
            {:ok, contact} when not is_nil(contact) ->
              attrs  = contact["custom_attributes"] || %{}
              amount = Float.parse(to_string(attrs["active_cart_amount"] || "0")) |> elem(0)
              if amount > 0 do
                formatted = Mpesa.format_phone(phone)
                receipt   = Mpesa.generate_receipt("LPG")
                Mpesa.fire_stk_push(formatted, amount, receipt, "Gas Payment")
              end
            _ -> :skip
          end
        end
      rescue
        e -> IO.puts("[mpesa-push Error] #{inspect(e)}")
      end
    end)
    conn
  end

  # ─── Chatwoot Webhook POST (Agent Bot + Typebot session management) ───

  post "/webhook" do
    IO.puts("[Presidential Bridge Webhook] Event: #{inspect(conn.body_params["event"])}, Msg Type: #{inspect(conn.body_params["message_type"])}, Content: #{inspect(conn.body_params["content"])}")
    conn = send_resp(conn, 200, "OK")
    Task.start(fn ->
      try do
        # We know this webhook is exclusively for the Presidential/JoyWo bot (Agent Bot 2)
        # So we hardcode the active slug to the Typebot slug for that bot
        active_slug = LipagasBridge.Config.joywo_typebot_slug()
        LipagasBridge.TypebotBotHandler.handle(conn.body_params, active_slug)
      rescue
        e -> IO.puts("[Presidential Bridge Webhook Error] #{inspect(e)}\n#{Exception.format(:error, e, __STACKTRACE__)}")
      end
    end)
    conn
  end

  # ─── AI Proxy Webhook POST ─────────────────────────────────────────────

  post "/api/ai/proxy" do
    IO.puts("[AIProxy] Received payload: #{inspect(conn.body_params)}")
    case LipagasBridge.AIProxy.process_request(conn.body_params) do
      {:ok, reply} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{reply: reply}))
      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(500, Jason.encode!(%{error: inspect(reason)}))
    end
  end

  # ─── Random Greeting Webhook ──────────────────────────────────────────

  post "/api/ai/greeting" do
    name = conn.body_params["user_name"]
    name = if name && String.trim(name) != "", do: name, else: "Mwananchi"

    greetings = [
      "Habari yako, #{name}! 👋\n\nIt's me, William Ruto. I know you're busy, and I respect that. So let me be quick.\n\nThis is your direct line to what my government is doing for you, real projects, real money, real facts. No spin, no noise.\n\nWhat would you like to know today?",
      "Sasa, #{name}! 🇰🇪\n\nYou know me, I came from nothing, a chicken seller from Sugoi. I understand what it means to hustle every day for your family.\n\nThat's exactly why I built this, so you can ask me anything, and I'll give you straight answers about what we're building for Kenya.\n\nWhat's on your mind?",
      "Habari za leo! 👋\n\nI'm here. Not my spokesperson. Not a press release. Me.\n\nI started this because I believe in you, #{name}, and every Kenyan deserves direct, honest communication about what your government is doing.\n\nAsk me anything, projects, policies, or what's happening in your area. Facts only.",
      "Karibu sana, #{name}. 🙏\n\nEvery morning I wake up thinking about one thing, how do I make sure the mwananchi's life is better than yesterday?\n\nThis is where that conversation happens. Whether you're a farmer, a trader, a student, or just a curious Kenyan, you belong here.\n\nWhat can I help you with today?",
      "Karibu, #{name}! 👋\n\nKenya's story is being written right now, and you are part of it.\n\nWhether you're a hustler in Gikomba, a farmer in Rift Valley, a student in Kisumu, or a mama running a small business, this government is working for you.\n\nLet me show you what's being done. Ask me anything. 🇰🇪"
    ]
    
    reply = Enum.random(greetings)
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{greeting: reply}))
  end

  # ─── PAYG Meter Validation ────────────────────────────────────────────

  post "/api/typebot/validate-payg" do
    meter = conn.body_params["meter"]
    if !meter do
      send_resp(conn, 400, Jason.encode!(%{error: "Missing meter"}))
    else
      alias LipagasBridge.Config
      url = "#{Config.stronpower_base()}/QueryMeterInfo"
      payload = %{
        "CompanyName" => Config.stronpower_company(),
        "UserName"    => Config.stronpower_user(),
        "PassWord"    => Config.stronpower_pass(),
        "MeterId"     => meter
      }
      case LipagasBridge.HTTP.post_json(url, payload) do
        {:ok, %{status: 200, body: body}} ->
          result = if is_list(body) and length(body) > 0 do
            first = List.first(body)
            if first["Customer_name"] && !String.contains?(first["Company_name"] || "", "Error") do
              %{isValid: true, accountName: first["Customer_name"]}
            else
              %{isValid: false}
            end
          else
            if body["Customer_name"] do
              %{isValid: true, accountName: body["Customer_name"]}
            else
              %{isValid: false}
            end
          end
          send_resp(conn, 200, Jason.encode!(result))
        _ ->
          send_resp(conn, 200, Jason.encode!(%{isValid: false, error: "Stronpower API error"}))
      end
    end
  end

  # ─── Trigger STK Push directly ────────────────────────────────────────

  post "/api/typebot/trigger-stk" do
    phone     = conn.body_params["phone"]
    amount    = conn.body_params["amount"]
    reference = conn.body_params["reference"]

    receipt = reference || Mpesa.generate_receipt("LPG")
    case Mpesa.fire_stk_push(phone, amount, receipt, "LipaGas Payment") do
      {:ok, _} ->
        send_resp(conn, 200, Jason.encode!(%{success: true, receipt: receipt}))
      {:error, reason} ->
        send_resp(conn, 500, Jason.encode!(%{success: false, error: reason}))
    end
  end

  # ─── Trigger M-Pesa from Typebot webhook block ────────────────────────

  post "/trigger-mpesa" do
    conn = send_resp(conn, 200, Jason.encode!(%{success: true, message: "M-Pesa STK push initiated"}))
    Task.start(fn ->
      conv_id = conn.body_params["conversationId"]
      phone   = conn.body_params["phone"]
      meter   = conn.body_params["meter"]
      if conv_id && phone do
        case Chatwoot.get_last_cart_total(conv_id) do
          {:ok, amount, label} when amount > 0 ->
            formatted = Mpesa.format_phone(phone)
            receipt   = Mpesa.generate_receipt("LPG")
            case Mpesa.fire_stk_push(formatted, amount, receipt, "LipaGas Payment") do
              {:ok, _} ->
                Chatwoot.post_note(conv_id, "ORDER_STATE:completed|Receipt:#{receipt}|Amount:#{amount}|")
                Chatwoot.update_custom_attributes(conv_id, %{order_state: "completed"})
                if meter && meter != "" do
                  Chatwoot.post_note(conv_id, "PAYG_METER:#{meter}")
                end
              {:error, reason} ->
                IO.puts("[trigger-mpesa] STK error: #{inspect(reason)}")
            end
          _ ->
            Meta.send_text(phone, "⚠️ We could not find your order amount. Please start a new order or contact support at 0723539760.")
        end
      end
    end)
    conn
  end

  # ─── JoyWO Webhook GET (verification) ────────────────────────────────

  get "/joywo-webhook" do
    conn    = fetch_query_params(conn)
    params  = conn.query_params
    mode    = params["hub.mode"]
    token   = params["hub.verify_token"]
    challenge = params["hub.challenge"]

    if mode == "subscribe" and token == Config.verify_token() do
      IO.puts("[JoyWO] Webhook verified!")
      send_resp(conn, 200, challenge)
    else
      send_resp(conn, 403, "Forbidden")
    end
  end

  # ─── JoyWO Webhook POST ───────────────────────────────────────────────

  post "/joywo-webhook" do
    conn = send_resp(conn, 200, "OK")
    Task.start(fn ->
      body    = conn.body_params
      if body["object"] == "whatsapp_business_account" do
        message = get_in(body, ["entry", Access.at(0), "changes", Access.at(0), "value", "messages", Access.at(0)])
        phone   = message && message["from"]
        if phone && message do
          LipagasBridge.JoywoHandler.handle(phone, message)
        end
      end
    end)
    conn
  end

  # ─── JoyWO M-Pesa Callback ────────────────────────────────────────────

  post "/joywo-mpesa-callback" do
    conn = send_resp(conn, 200, "OK")
    Task.start(fn ->
      try do
        body        = conn.body_params
        stk_body    = get_in(body, ["Body", "stkCallback"])
        result_code = stk_body && stk_body["ResultCode"]

        # Find user awaiting M-Pesa — scan Redis
        # (In JS this was an in-memory Map scan, we use Redis here)
        IO.puts("[JoyWO M-Pesa] Callback received, ResultCode: #{result_code}")
        # Full implementation would scan Redis SCAN joywo_cart:* for AWAITING_MPESA state
        # and send success/failure message accordingly
      rescue
        e -> IO.puts("[JoyWO M-Pesa Callback Error] #{inspect(e)}")
      end
    end)
    conn
  end

  # ─── Receipt Previews ──────────────────────────────────────────────────

  get "/preview/token" do
    html = LipagasBridge.Receipt.generate_html("254723539760", "500", "1234-5678-9012-3456-7890", "TEST-RCT-123", "04172997324")
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
  end

  get "/preview/standard" do
    html = LipagasBridge.Receipt.generate_html("254723539760", "500", nil, "TEST-RCT-123", nil)
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
  end

  # ─── 404 catch-all ────────────────────────────────────────────────────

  match _ do
    send_resp(conn, 404, "Not Found")
  end
end
