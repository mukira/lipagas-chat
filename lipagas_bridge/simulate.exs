defmodule Simulator do
  def run do
    IO.puts("Starting chat...")
    case LipagasBridge.Typebot.start_chat("lipa-gas-whats-app-bot-o9nfrww", %{"Phone" => "0723539760", "Name" => "Test"}) do
      {:ok, sid, msgs, input} ->
        IO.puts("Session ID: #{sid}")
        # Assuming the first input is "I need Gas 🔥"
        
        IO.puts("\nSending 'I need Gas 🔥'...")
        {:ok, msgs, input} = LipagasBridge.Typebot.continue_chat(sid, "I need Gas 🔥")
        
        IO.puts("\nSending '13KG Refill'...")
        {:ok, msgs, input} = LipagasBridge.Typebot.continue_chat(sid, "13KG Refill")
        
        IO.puts("\nSending '1'...")
        {:ok, msgs, input} = LipagasBridge.Typebot.continue_chat(sid, "1")

        IO.puts("\nSending 'View sent cart'...")
        {:ok, msgs, input} = LipagasBridge.Typebot.continue_chat(sid, "View sent cart")

        IO.puts("\nSending 'Test Location'...")
        {:ok, msgs, input} = LipagasBridge.Typebot.continue_chat(sid, "Test Location")
        
        IO.puts("\nChecking where we are:")
        LipagasBridge.Typebot.parse_messages(msgs) |> inspect() |> IO.puts()
        IO.puts("Input: #{inspect(input)}")

        IO.puts("\nSending '✏️ Change Number'...")
        case LipagasBridge.Typebot.continue_chat(sid, "✏️ Change Number") do
          {:ok, final_msgs, final_input} ->
            IO.puts("Success:")
            LipagasBridge.Typebot.parse_messages(final_msgs) |> inspect() |> IO.puts()
            IO.puts("Final Input: #{inspect(final_input)}")
          err ->
            IO.puts("Error: #{inspect(err)}")
        end
        
      err ->
        IO.puts("Start Error: #{inspect(err)}")
    end
  end
end

Simulator.run()
