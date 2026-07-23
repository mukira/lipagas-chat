defmodule PresidentialBridge.Config do
  @moduledoc """
  Central configuration for all external service credentials and URLs.
  All values are read from environment variables with secure defaults.
  """

  # ─── LipaGas / Meta ───────────────────────────────────────────────────
  def meta_token,    do: System.get_env("META_TOKEN")    || "EAAUbTMY5PfMBRKNBhFeUJreZBhWvjNMYk3ZAoqGsRyz26vLb5KGJ6BUcKZAhN5ATO9oaz3sZANE6VyxN6pEulcmzQQtU3ZCbpEzN3ghCZAIKp4TymJLJxvqS6bXzZBoMJmEYGhytQnZCIVlRYmvePWm7OEAt1rrJW6Wlc688K4PucbZC9Esztns3ViAHQJjfMZCwZDZD"
  def phone_id,      do: System.get_env("PHONE_ID")      || "630116346849511"
  def catalog_id,    do: System.get_env("CATALOG_ID")    || "3924938727637666"
  def verify_token,  do: System.get_env("META_VERIFY_TOKEN") || "presidential_secure_meta_token"

  # ─── JoyWO ────────────────────────────────────────────────────────────
  def joywo_meta_token, do: System.get_env("JOYWO_META_TOKEN") || "EAAUbTMY5PfMBRv8M1g2egZCtmbeASz4qkeTSwjZB5Y6ay6qBkQDaOs2T7j9ZBCODEzJmZC2mdufrxXpdqZAga1DpEaQYwjLZBWOdvWvNvtxA9rLyAqWDdsdF5Uy1g7oX66uKAmY8zrZADObjYiicDLkOKJgwWiQ3uTPb3eRpYRh7oOQZAKpFNYItIwuC3lQNFQZDZD"
  def joywo_phone_id,   do: System.get_env("JOYWO_PHONE_ID")   || "1138087209378803"

  # ─── Chatwoot ─────────────────────────────────────────────────────────
  def chatwoot_url,        do: System.get_env("CHATWOOT_URL")        || "https://chat.lipagas.co"
  def chatwoot_token,      do: System.get_env("CHATWOOT_TOKEN")      || "QURq3keSBWjo3XVoPrjy7MUg"
  def chatwoot_account_id, do: System.get_env("CHATWOOT_ACCOUNT_ID") || "1"
  # Agent Bot token — generated in Chatwoot Settings → Integrations → Agent Bots → (your bot) → Access Token
  def chatwoot_bot_token,  do: System.get_env("CHATWOOT_BOT_TOKEN")  || "zXDW1wqKjXqH2uZmR7rZSDi5"

  # ─── Typebot ──────────────────────────────────────────────────────────
  def typebot_base_url,     do: "https://flow.lipagas.co/api/v1/typebots"
  def typebot_continue_url, do: "https://flow.lipagas.co/api/v1/sessions"
  def typebot_default_slug, do: "lipa-gas-whats-app-bot-o9nfrww"

  # ─── M-Pesa / Daraja ─────────────────────────────────────────────────
  def mpesa_shortcode,    do: System.get_env("MPESA_SHORTCODE")    || "4103503"
  def mpesa_passkey,      do: System.get_env("MPESA_PASSKEY")      || "bdc325698488a139c88f91d109e15c71c907a653e77488b6365dced07bf49e69"
  def mpesa_auth_key,     do: System.get_env("MPESA_AUTH_KEY")     || "VkczTXhadTM3TE9JekZhb2x4emR2cUlhakZadFVISk06RnVPall4U0dCeEgwdnlVMg=="
  def mpesa_callback_url, do: System.get_env("MPESA_CALLBACK_URL") || "https://flow.lipagas.co/meta-webhook/mpesa-callback"

  # ─── Stronpower PAYG API ─────────────────────────────────────────────
  def stronpower_base,    do: System.get_env("STRONPOWER_BASE")    || "http://www.server-newv.stronpower.com/api"
  def stronpower_company, do: System.get_env("STRONPOWER_COMPANY") || "LipaGas"
  def stronpower_user,    do: System.get_env("STRONPOWER_USER")    || "MukiraGitonga"
  def stronpower_pass,    do: System.get_env("STRONPOWER_PASS")    || "123456"

  # ─── Redis ────────────────────────────────────────────────────────────
  def redis_url, do: System.get_env("REDIS_URL") || "redis://localhost:6379"

  # ─── Server ───────────────────────────────────────────────────────────
  def port, do: String.to_integer(System.get_env("PORT") || "4002")

  # ─── JoyWO Bots ───────────────────────────────────────────────────────
  def joywo_typebot_slug,  do: "my-typebot-jpjwqnz"
  def presidential_bot_id, do: "presidential-bot"

  # ─── Catalog Sets ─────────────────────────────────────────────────────
  def presidential_catalog_sets do
    %{
      "brands_6kg_refill"  => "1268680201403656",
      "brands_6kg_new"     => "1260049439586798",
      "brands_13kg_refill" => "716756781464829",
      "brands_13kg_new"    => "1696690757988972",
      "brands_50kg_refill" => "859392040485724",
      "brands_50kg_new"    => "1902818767033594",
      "retail_menu"        => "958353106673281",
      "wholesale_new"      => "1182878963979586",
      "wholesale_refill"   => "1927689918203262"
    }
  end

  def joywo_catalog_sets do
    %{
      "bicycle"   => "3458007944359873",
      "gas"       => "1405047311419451",
      "watertanks"=> "1549795990109012"
    }
  end

  def joywo_catalog_id, do: "1520533706178244"
end
