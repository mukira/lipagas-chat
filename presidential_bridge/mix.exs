defmodule PresidentialBridge.MixProject do
  use Mix.Project

  def project do
    [
      app: :presidential_bridge,
      version: "0.1.0",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {PresidentialBridge.Application, []}
    ]
  end

  defp deps do
    [
      {:bandit,  "~> 1.0"},
      {:mint,    "~> 1.0"},
      {:castore, "~> 1.0"},
      {:jason,   "~> 1.4"},
      {:redix,   "~> 1.1"},
      {:plug,    "~> 1.14"},
      {:eqrcode, "~> 0.1.10"}
    ]
  end
end
