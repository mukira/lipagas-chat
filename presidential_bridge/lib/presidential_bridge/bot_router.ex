defmodule PresidentialBridge.BotRouter do
  @moduledoc """
  Central routing brain for Chatwoot Agent Bot events.

  Maps inbox_id -> Typebot slug.
  To add a new bot: add one line to @inbox_bot_map. Zero other changes needed.
  """

  # ─── Bot Map ──────────────────────────────────────────────────────────
  # inbox_id (integer) => Typebot slug (string)
  # Find your inbox_id in Chatwoot Settings → Inboxes → click the inbox → check URL
  @inbox_bot_map %{
    10 => "my-typebot-jpjwqnz"   # Influence AI WhatsApp → JoyWo Bot (published slug, NOT the internal ID)
    # Add more bots here as you scale:
    # 5  => "lipa-gas-whats-app-bot-o9nfrww",  # LipaGas WhatsApp → LipaGas Bot
    # 12 => "some-other-bot-slug",              # Another inbox → Another bot
  }

  # ─── Event Handler ────────────────────────────────────────────────────

  def handle(%{"event" => "message_created", "message_type" => "incoming"} = payload) do
    inbox_id = get_in(payload, ["inbox", "id"])
    content  = get_in(payload, ["content"]) || ""
    phone    = get_in(payload, ["sender", "phone_number"])
    conv_id  = get_in(payload, ["conversation", "id"])

    # Fallback default from the map if no active_bot is set
    default_slug = Map.get(@inbox_bot_map, inbox_id)

    if phone do
      content_clean = String.trim(String.downcase(content))

      # Keyword Interception
      cond do
        content_clean == "ruto" ->
          IO.puts("[BotRouter] Keyword RUTO detected for #{phone}. Switching to Presidential Bot.")
          PresidentialBridge.Session.set_active_bot(phone, "presidential-bot")
          # Force a Chatwoot status update here if necessary, or just clear Typebot session
          PresidentialBridge.Session.delete_session(conv_id)

        content_clean == "joywo" ->
          IO.puts("[BotRouter] Keyword JOYWO detected for #{phone}. Switching to JoyWo Bot.")
          PresidentialBridge.Session.set_active_bot(phone, "my-typebot-jpjwqnz")
          PresidentialBridge.Session.delete_session(conv_id)

        true ->
          :ok
      end

      # Determine the active bot slug based on user session, falling back to default
      active_slug = PresidentialBridge.Session.get_active_bot(phone) || default_slug

      if active_slug do
        IO.puts("[BotRouter] Routing inbox_id=#{inbox_id} for #{phone} to slug=#{active_slug}")
        PresidentialBridge.TypebotBotHandler.handle(payload, active_slug)
        :handled
      else
        IO.puts("[BotRouter] No bot configured for inbox_id=#{inspect(inbox_id)}, skipping")
        :skip
      end
    else
      IO.puts("[BotRouter] No phone number in payload, skipping routing")
      :skip
    end
  end

  # Ignore all other events (conversation_created, message_updated, etc.)
  def handle(_payload), do: :skip
end
