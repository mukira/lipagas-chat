defmodule PresidentialBridge.Stronpower do
  alias PresidentialBridge.Config

  @doc """
  Purchases a token for the given meter ID and amount.
  Returns {:ok, token} or {:error, reason}
  """
  def purchase_token(meter_id, amount) when is_binary(amount) do
    case Float.parse(amount) do
      {float_amt, _} -> purchase_token(meter_id, float_amt)
      :error -> purchase_token(meter_id, 0.0)
    end
  end

  def purchase_token(meter_id, amount) when is_float(amount) or is_integer(amount) do
    # We use VendingMeterDirectly as per the Stronpower API documentation
    url = "#{Config.stronpower_base()}/VendingMeterDirectly"
    payload = %{
      "CompanyName" => Config.stronpower_company(),
      "UserName"    => Config.stronpower_user(),
      "PassWord"    => Config.stronpower_pass(),
      "MeterId"     => meter_id,
      "Amount"      => amount
    }

    case PresidentialBridge.HTTP.post_json(url, payload) do
      {:ok, %{status: 200, body: body}} ->
        # The Stronpower API usually returns JSON. Let's extract the token.
        # Format might be {"Token": "1234...", ...} or an array.
        token = extract_token(body)
        if token do
          {:ok, token}
        else
          # Fallback if API fails or returns unexpected format
          {:error, "Token not found in response"}
        end
      {:ok, resp} ->
        {:error, "API returned status #{resp.status}"}
      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  defp extract_token(body) when is_map(body) do
    body["Token"] || body["token"] || body["STSToken"]
  end

  defp extract_token([first | _]) when is_map(first) do
    extract_token(first)
  end

  defp extract_token(_), do: nil
end
