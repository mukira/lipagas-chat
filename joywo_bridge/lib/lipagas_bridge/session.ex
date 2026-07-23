defmodule LipagasBridge.Session do
  @moduledoc """
  Redis-backed session store for Typebot sessions, JoyWO sessions, and 
  bot-disabled state. Survives server restarts.
  
  All session data is persisted in Redis with TTL expiry.
  """

  @session_ttl 3600        # 1 hour for Typebot sessions
  @joywo_ttl   3600        # 1 hour for JoyWO sessions
  @inactivity  60_000      # 1 minute inactivity timeout (ms)

  # ─── Typebot Session (LipaGas main bot) ──────────────────────────────

  def get_session(conv_id) do
    case Redix.command(:redix, ["GET", "tb_session:#{conv_id}"]) do
      {:ok, nil}     -> nil
      {:ok, val}     -> val
      {:error, _}    -> nil
    end
  end

  def set_session(conv_id, session_id) do
    Redix.command(:redix, ["SET", "tb_session:#{conv_id}", session_id, "EX", @session_ttl])
  end

  def delete_session(conv_id) do
    Redix.command(:redix, ["DEL", "tb_session:#{conv_id}"])
  end

  # ─── Active Choices (for invalid option detection) ───────────────────

  def get_active_choices(conv_id) do
    case Redix.command(:redix, ["GET", "choices:#{conv_id}"]) do
      {:ok, nil} -> []
      {:ok, val} ->
        case Jason.decode(val) do
          {:ok, list} -> list
          _           -> []
        end
      {:error, _} -> []
    end
  end

  def set_active_choices(conv_id, choices) when is_list(choices) do
    Redix.command(:redix, ["SET", "choices:#{conv_id}", Jason.encode!(choices), "EX", @session_ttl])
  end

  # ─── Category tracking ───────────────────────────────────────────────

  def get_category(conv_id) do
    case Redix.command(:redix, ["GET", "category:#{conv_id}"]) do
      {:ok, nil}  -> ""
      {:ok, val}  -> val
      {:error, _} -> ""
    end
  end

  def set_category(conv_id, category) do
    Redix.command(:redix, ["SET", "category:#{conv_id}", category, "EX", @session_ttl])
  end

  # ─── JoyWO Typebot Session ────────────────────────────────────────────

  def get_joywo_session(phone) do
    case Redix.command(:redix, ["GET", "joywo_session:#{phone}"]) do
      {:ok, nil}  -> nil
      {:ok, val}  -> val
      {:error, _} -> nil
    end
  end

  def set_joywo_session(phone, session_id) do
    Redix.command(:redix, ["SET", "joywo_session:#{phone}", session_id, "EX", @joywo_ttl])
  end

  def delete_joywo_session(phone) do
    Redix.command(:redix, ["DEL", "joywo_session:#{phone}"])
  end

  # ─── JoyWO Cart State ─────────────────────────────────────────────────

  def get_joywo_cart(phone) do
    case Redix.command(:redix, ["GET", "joywo_cart:#{phone}"]) do
      {:ok, nil} -> %{"state" => "IDLE"}
      {:ok, val} ->
        case Jason.decode(val) do
          {:ok, map} -> map
          _          -> %{"state" => "IDLE"}
        end
      {:error, _} -> %{"state" => "IDLE"}
    end
  end

  def set_joywo_cart(phone, cart_map) do
    Redix.command(:redix, ["SET", "joywo_cart:#{phone}", Jason.encode!(cart_map), "EX", @joywo_ttl])
  end

  def delete_joywo_cart(phone) do
    Redix.command(:redix, ["DEL", "joywo_cart:#{phone}"])
  end

  # ─── JoyWO Table Banking State ───────────────────────────────────────

  def get_joywo_tb_state(phone) do
    case Redix.command(:redix, ["GET", "joywo_tb:#{phone}"]) do
      {:ok, nil} -> nil
      {:ok, val} ->
        case Jason.decode(val) do
          {:ok, map} -> map
          _          -> nil
        end
      {:error, _} -> nil
    end
  end

  def set_joywo_tb_state(phone, state_map) do
    Redix.command(:redix, ["SET", "joywo_tb:#{phone}", Jason.encode!(state_map), "EX", @joywo_ttl])
  end

  def delete_joywo_tb_state(phone) do
    Redix.command(:redix, ["DEL", "joywo_tb:#{phone}"])
  end

  # ─── Presidential Sessions ────────────────────────────────────────────

  def get_presidential_session(phone) do
    case Redix.command(:redix, ["GET", "pres_session:#{phone}"]) do
      {:ok, nil}  -> nil
      {:ok, val}  -> val
      {:error, _} -> nil
    end
  end

  def set_presidential_session(phone, session_id) do
    Redix.command(:redix, ["SET", "pres_session:#{phone}", session_id, "EX", @joywo_ttl])
  end

  def delete_presidential_session(phone) do
    Redix.command(:redix, ["DEL", "pres_session:#{phone}"])
  end

  # ─── Active Bot State Routing ─────────────────────────────────────────

  def get_active_bot(phone) do
    case Redix.command(:redix, ["GET", "active_bot:#{phone}"]) do
      {:ok, nil}  -> "my-typebot-jpjwqnz" # Default to JoyWo
      {:ok, val}  -> val
      {:error, _} -> "my-typebot-jpjwqnz"
    end
  end

  def set_active_bot(phone, bot_slug) do
    Redix.command(:redix, ["SET", "active_bot:#{phone}", bot_slug, "EX", 86400 * 30]) # 30 days
  end

  def delete_active_bot(phone) do
    Redix.command(:redix, ["DEL", "active_bot:#{phone}"])
  end

  # ─── Location Tracking ───────────────────────────────────────────────

  def get_waiting_location(conv_id) do
    case Redix.command(:redix, ["GET", "loc_wait:#{conv_id}"]) do
      {:ok, val} -> val == "true"
      _ -> false
    end
  end

  def set_waiting_location(conv_id, val) when is_boolean(val) do
    if val do
      Redix.command(:redix, ["SET", "loc_wait:#{conv_id}", "true", "EX", 300]) # 5 mins
    else
      Redix.command(:redix, ["DEL", "loc_wait:#{conv_id}"])
    end
  end
end
