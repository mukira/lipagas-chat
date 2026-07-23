defmodule PresidentialBridge.InactivityTimer do
  @moduledoc """
  Supervised inactivity timer using Elixir Process.send_after.
  Unlike Node.js setTimeout, these timers are supervised and will not 
  cause memory leaks. Timer state is tracked in a GenServer.
  
  On server restart, timers are naturally cleared (expected behavior — 
  any new message from a user will simply reset the timer).
  """
  use GenServer
  alias PresidentialBridge.{Config, Chatwoot, Meta}

  @timeout_ms 60_000  # 1 minute

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def schedule(conv_id, phone) do
    GenServer.cast(__MODULE__, {:schedule, conv_id, phone})
  end

  def cancel(conv_id) do
    GenServer.cast(__MODULE__, {:cancel, conv_id})
  end

  # ─── GenServer callbacks ──────────────────────────────────────────────

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_cast({:schedule, conv_id, phone}, state) do
    # Cancel any existing timer
    state = cancel_timer(state, conv_id)
    ref   = Process.send_after(self(), {:fire, conv_id, phone}, @timeout_ms)
    {:noreply, Map.put(state, conv_id, ref)}
  end

  @impl true
  def handle_cast({:cancel, conv_id}, state) do
    {:noreply, cancel_timer(state, conv_id)}
  end

  @impl true
  def handle_info({:fire, conv_id, phone}, state) do
    Task.start(fn -> send_inactivity_reminder(conv_id, phone) end)
    {:noreply, Map.delete(state, conv_id)}
  end

  # ─── Private ──────────────────────────────────────────────────────────

  defp cancel_timer(state, conv_id) do
    case Map.get(state, conv_id) do
      nil -> state
      ref ->
        Process.cancel_timer(ref)
        Map.delete(state, conv_id)
    end
  end

  defp send_inactivity_reminder(conv_id, phone) do
    # Double-check: skip if bot is disabled or order is completed
    skip? = case Chatwoot.get_custom_attributes(conv_id) do
      {:ok, attrs} ->
        attrs["bot_disabled"] == "true" or attrs["order_state"] == "completed"
      _ -> false
    end

    unless skip? do
      # Trigger the Typebot visual flow for inactivity timeout
      slug = PresidentialBridge.Typebot.get_bot_slug("default")
      
      case PresidentialBridge.Typebot.start_chat(slug, %{"SystemEvent" => "INACTIVITY_TIMEOUT", "Phone" => phone}) do
        {:ok, session_id, messages, input} ->
          # Parse the resulting visual blocks (text + buttons)
          {combined_text, image_url} = PresidentialBridge.Typebot.parse_messages(messages)
          
          if combined_text != "" do
             PresidentialBridge.PresidentialHandler.build_and_send(phone, combined_text, image_url, input, conv_id)
             PresidentialBridge.Session.set_session(phone, session_id)
          end
        _ -> :ok
      end
    end
  rescue
    e -> IO.puts("[InactivityTimer] Error: #{inspect(e)}")
  end
end
