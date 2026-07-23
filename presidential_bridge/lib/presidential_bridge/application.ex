defmodule PresidentialBridge.Application do
  use Application

  @impl true
  def start(_type, _args) do
    redis_url = PresidentialBridge.Config.redis_url()
    port      = PresidentialBridge.Config.port()

    children = [
      # Redis connection — persistent, auto-reconnects on failure
      {Redix, {redis_url, [name: :redix]}},

      # Groq key rotation Agent — round-robin index across 3 free-tier keys
      %{
        id: :groq_key_index,
        start: {Agent, :start_link, [fn -> 0 end, [name: :groq_key_index]]}
      },

      # Gemini key rotation Agent
      %{
        id: :gemini_key_index,
        start: {Agent, :start_link, [fn -> 0 end, [name: :gemini_key_index]]}
      },

      # Inactivity timer GenServer — supervised, survives crashes
      PresidentialBridge.InactivityTimer,

      # Multi-source Scraper and PR alerting GenServer
      PresidentialBridge.DataMiner,

      # HTTP server — Bandit with Plug router
      {Bandit, plug: PresidentialBridge.Router, scheme: :http, port: port}
    ]

    opts = [strategy: :one_for_one, name: PresidentialBridge.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

