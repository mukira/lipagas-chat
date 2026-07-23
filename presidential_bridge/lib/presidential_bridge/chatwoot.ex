defmodule PresidentialBridge.Chatwoot do
  @moduledoc """
  Chatwoot API client using PresidentialBridge.HTTP (Mint-based, OTP 24 compatible).
  """
  alias PresidentialBridge.{Config, HTTP}

  defp base, do: "#{Config.chatwoot_url()}/api/v1/accounts/#{Config.chatwoot_account_id()}"
  defp auth_header, do: {"api_access_token", Config.chatwoot_token()}

  # ─── Get conversation ─────────────────────────────────────────────────

  def get_conversation(conv_id) do
    case HTTP.get("#{base()}/conversations/#{conv_id}", [auth_header()]) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, resp}  -> {:error, "Chatwoot error #{resp.status}"}
      {:error, e}  -> {:error, e}
    end
  end

  def get_contact_conversations(contact_id) do
    case HTTP.get("#{base()}/contacts/#{contact_id}/conversations", [auth_header()]) do
      {:ok, %{status: 200, body: %{"payload" => list}}} when is_list(list) -> {:ok, list}
      {:ok, %{status: 200, body: list}} when is_list(list) -> {:ok, list}
      {:ok, resp}  -> {:error, "Chatwoot error #{resp.status}"}
      {:error, e}  -> {:error, e}
    end
  end

  def get_conversation_messages(conv_id) do
    case HTTP.get("#{base()}/conversations/#{conv_id}/messages", [auth_header()]) do
      {:ok, %{status: 200, body: %{"payload" => list}}} when is_list(list) -> {:ok, list}
      {:ok, %{status: 200, body: list}} when is_list(list) -> {:ok, list}
      {:ok, resp}  -> {:error, "Chatwoot error #{resp.status}"}
      {:error, e}  -> {:error, e}
    end
  end

  def get_phone(conv_id) do
    case get_conversation(conv_id) do
      {:ok, body} ->
        phone = get_in(body, ["meta", "sender", "phone_number"])
        if phone, do: {:ok, String.replace(phone, ~r/[^\d]/, "")}, else: {:error, "no phone"}
      err -> err
    end
  end

  def get_custom_attributes(conv_id) do
    case get_conversation(conv_id) do
      {:ok, body} -> {:ok, body["custom_attributes"] || %{}}
      err         -> err
    end
  end

  def get_sender(conv_id) do
    case get_conversation(conv_id) do
      {:ok, body} ->
        {:ok, %{
          phone: String.replace(get_in(body, ["meta", "sender", "phone_number"]) || "", ~r/[^\d]/, ""),
          name:  get_in(body, ["meta", "sender", "name"]) || "",
          id:    get_in(body, ["meta", "sender", "id"])
        }}
      err -> err
    end
  end

  def get_contact_attrs(conv_id) do
    case get_conversation(conv_id) do
      {:ok, body} ->
        contact_attrs = get_in(body, ["meta", "sender", "custom_attributes"]) || %{}
        conv_attrs    = body["custom_attributes"] || %{}
        {:ok, Map.merge(contact_attrs, conv_attrs)}
      err -> err
    end
  end

  # ─── Update conversation custom attributes ────────────────────────────

  def update_custom_attributes(conv_id, attrs) do
    existing = case get_conversation(conv_id) do
      {:ok, conv} -> conv["custom_attributes"] || %{}
      _ -> %{}
    end
    merged = Map.merge(existing, attrs)
    
    case HTTP.post_json("#{base()}/conversations/#{conv_id}/custom_attributes",
      %{custom_attributes: merged}, [auth_header()]) do
      {:ok, %{status: s}} when s in 200..299 -> :ok
      {:ok, resp} -> {:error, "attr update #{resp.status}"}
      {:error, e} -> {:error, e}
    end
  end

  # ─── Update conversation status ───────────────────────────────────────

  def update_status(conv_id, status) do
    case HTTP.put_json("#{base()}/conversations/#{conv_id}", %{status: status}, [auth_header()]) do
      {:ok, %{status: s}} when s in 200..299 -> :ok
      {:ok, resp} -> {:error, "status update #{resp.status}"}
      {:error, e} -> {:error, e}
    end
  end

  # ─── Post a private note ──────────────────────────────────────────────

  def post_note(conv_id, content) do
    case HTTP.post_json("#{base()}/conversations/#{conv_id}/messages",
      %{content: content, private: true, message_type: "outgoing"}, [auth_header()]) do
      {:ok, %{status: s}} when s in 200..299 -> :ok
      {:ok, resp} -> {:error, "note #{resp.status}"}
      {:error, e} -> {:error, e}
    end
  end

  # ─── Get messages ─────────────────────────────────────────────────────

  def get_messages(conv_id) do
    case HTTP.get("#{base()}/conversations/#{conv_id}/messages", [auth_header()]) do
      {:ok, %{status: 200, body: body}} -> {:ok, body["payload"] || []}
      {:ok, resp}  -> {:error, resp.status}
      {:error, e}  -> {:error, e}
    end
  end

  def get_last_cart_total(conv_id) do
    # Fast path: read active_cart_amount directly from conversation custom attributes
    case get_conversation(conv_id) do
      {:ok, conv} -> 
        sender_attrs = get_in(conv, ["meta", "sender", "custom_attributes"]) || %{}
        conv_attrs = conv["custom_attributes"] || %{}
        attrs = Map.merge(sender_attrs, conv_attrs)
        
        amount = attrs["active_cart_amount"]
        label = attrs["active_cart_label"] || "Catalog Order"
        
        if amount && to_string(amount) != "" && to_string(amount) != "0" do
          {:ok, parse_float(to_string(amount)), label}
        else
          {:error, :not_found}
        end
      err -> err
    end
  end

  # ─── Contact operations ───────────────────────────────────────────────

  def search_contact(phone_digits) do
    q = String.slice(phone_digits, -9, 9)
    case HTTP.get("#{base()}/contacts/search?q=#{q}", [auth_header()]) do
      {:ok, %{status: 200, body: body}} -> {:ok, (body["payload"] || []) |> List.first()}
      {:ok, resp}  -> {:error, resp.status}
      {:error, e}  -> {:error, e}
    end
  end

  def update_contact(contact_id, attrs) do
    case HTTP.put_json("#{base()}/contacts/#{contact_id}", %{custom_attributes: attrs}, [auth_header()]) do
      {:ok, %{status: s}} when s in 200..299 -> :ok
      {:ok, resp} -> {:error, resp.status}
      {:error, e} -> {:error, e}
    end
  end

  # ─── Forward to Chatwoot ──────────────────────────────────────────────

  def forward_to_chatwoot(body) do
    url = "#{Config.chatwoot_url()}/webhooks/whatsapp/+254112250250"
    case HTTP.post_json(url, body) do
      {:ok, _} -> :ok
      {:error, e} -> {:error, e}
    end
  end

  # ─── Handoff to human agent ───────────────────────────────────────────

  def handoff_to_agent(conv_id, phone) do
    update_custom_attributes(conv_id, %{typebotSessionId: "handover", bot_disabled: "true"})
    update_status(conv_id, "open")
    PresidentialBridge.Meta.send_text(phone, "🤝 *Transferring to Agent...*\n\nHold on a moment, a member of our team will be with you shortly!")
    :ok
  end

  defp parse_float(nil), do: 0.0
  defp parse_float(s) do
    case Float.parse(s) do
      {f, _} -> f
      :error  -> 0.0
    end
  end
end
