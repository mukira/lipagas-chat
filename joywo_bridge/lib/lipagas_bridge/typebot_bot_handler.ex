defmodule LipagasBridge.TypebotBotHandler do
  @moduledoc """
  Generic Typebot bot handler for Chatwoot Agent Bot events.

  Receives a Chatwoot message_created payload + Typebot slug.
  Manages Redis sessions, calls Typebot, then sends native WhatsApp messages
  (buttons, lists, images, text) directly via Meta Graph API for that inbox.
  """
  alias LipagasBridge.{Typebot, Session, HTTP}

  @graph_base "https://graph.facebook.com/v21.0"
  @reset_keywords ~w(reset hi hello start menu back)

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

    meta = Map.get(@inbox_meta, inbox_id)
    unless meta && phone && phone != "" do
      IO.puts("[TypebotBotHandler] Missing meta config for inbox_id=#{inbox_id} or phone. Skipping.")
      return()
    end

    IO.puts("[TypebotBotHandler] conv_id=#{conv_id} inbox=#{inbox_id} phone=#{phone} msg=#{inspect(content)}")

    # Reset session on keywords
    if msg_lower in @reset_keywords do
      IO.puts("[TypebotBotHandler] Reset keyword — clearing session for conv #{conv_id}")
      Session.delete_session(conv_id)
    end

    session_id = Session.get_session(conv_id)

    {messages, input} =
      if is_nil(session_id) or msg_lower in @reset_keywords do
        start_new_session(conv_id, slug, payload)
      else
        continue_session(conv_id, session_id, slug, content, payload)
      end

    send_whatsapp_response(phone, meta, messages, input, conv_id)
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

    prefilled_vars = %{
      "user_name" => user_name,
      "phone_number" => phone,
      "latest_news" => latest_news
    }

    case Typebot.start_chat(slug, prefilled_vars) do
      {:ok, session_id, messages, input} ->
        Session.set_session(conv_id, session_id)
        {messages, input}
      {:error, reason} ->
        IO.puts("[TypebotBotHandler] start_chat failed: #{inspect(reason)}")
        {[], nil}
    end
  end

  defp continue_session(conv_id, session_id, slug, content, payload) do
    IO.puts("[TypebotBotHandler] Calling Typebot.continue_chat for session: #{session_id}")
    case Typebot.continue_chat(session_id, content) do
      {:ok, messages, input} ->
        IO.puts("[TypebotBotHandler] Typebot responded with messages: #{inspect(messages)} input: #{inspect(input)}")
        {messages, input}
      {:error, :session_expired} ->
        IO.puts("[TypebotBotHandler] Session expired for conv #{conv_id}, restarting")
        Session.delete_session(conv_id)
        start_new_session(conv_id, slug, payload)
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
        case LipagasBridge.Interceptor.build_flow_payload(text, phone) do
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
        LipagasBridge.Session.set_waiting_location(conv_id, true)

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
          interactive = %{
            type: "button",
            body: %{text: if(text != "", do: text, else: "Please choose:")},
            action: %{buttons: buttons}
          }
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
          body_text = if text != "", do: text, else: "Please choose:"
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
    send_meta(payload, %{phone_number_id: LipagasBridge.Config.phone_id(), token: LipagasBridge.Config.meta_token()})
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
end
