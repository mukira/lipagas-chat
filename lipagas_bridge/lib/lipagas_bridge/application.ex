defmodule LipagasBridge.Application do
  use Application

  @impl true
  def start(_type, _args) do
    redis_url = LipagasBridge.Config.redis_url()
    port      = LipagasBridge.Config.port()

    children = [
      # Redis connection — persistent, auto-reconnects on failure
      {Redix, {redis_url, [name: :redix]}},

      # Inactivity timer GenServer — supervised, survives crashes
      LipagasBridge.InactivityTimer,

      # HTTP server — Bandit with Plug router
      {Bandit, plug: LipagasBridge.Router, scheme: :http, port: port}
    ]

    opts = [strategy: :one_for_one, name: LipagasBridge.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

