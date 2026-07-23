defmodule TestSTK do
  def run do
    {:ok, _} = Application.ensure_all_started(:httpoison)
    
    amount = 4.0
    phone = "254723539760"
    receipt = LipagasBridge.Mpesa.generate_receipt("TOK")
    
    IO.puts("Firing STK Push for #{amount} to #{phone} with receipt #{receipt}...")
    res = LipagasBridge.Mpesa.fire_stk_push(phone, amount, receipt, "Tokens Payment")
    IO.inspect(res)
  end
end

TestSTK.run()
