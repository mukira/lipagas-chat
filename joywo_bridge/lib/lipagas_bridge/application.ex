defmodule LipagasBridge.Application do
  use Application

  @impl true
  def start(_type, _args) do
    redis_url = LipagasBridge.Config.redis_url()
    port      = LipagasBridge.Config.port()

    children = [
      # Redis connection — persistent, auto-reconnects on failure
      {Redix, {redis_url, [name: :redix]}},

      # Groq key rotation Agent — round-robin index across 3 free-tier keys
      %{
        id: :groq_key_index,
        start: {Agent, :start_link, [fn -> 0 end, [name: :groq_key_index]]}
      },

      # Inactivity timer GenServer — supervised, survives crashes
      LipagasBridge.InactivityTimer,

      # Multi-source Scraper and PR alerting GenServer
      LipagasBridge.DataMiner,

      # HTTP server — Bandit with Plug router
      {Bandit, plug: LipagasBridge.Router, scheme: :http, port: port}
    ]

    opts = [strategy: :one_for_one, name: LipagasBridge.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

