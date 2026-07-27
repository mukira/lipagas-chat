{:ok, pid} = Redix.start_link(host: "localhost", port: 6379)
tweets = case Redix.command(pid, ["GET", "presidential_x_tweets"]) do
  {:ok, nil} -> "nil"
  {:ok, val} -> "Length: #{length(Jason.decode!(val))}"
  err -> inspect(err)
end
IO.puts("presidential_x_tweets: #{tweets}")

last_id = case Redix.command(pid, ["GET", "last_seen_tweet_id"]) do
  {:ok, val} -> val
  _ -> "nil"
end
IO.puts("last_seen_tweet_id: #{last_id}")

queue = case Redix.command(pid, ["GET", "news_queue:254723539760"]) do
  {:ok, val} when is_binary(val) -> "Length: #{length(Jason.decode!(val))}"
  _ -> "nil"
end
IO.puts("news_queue:254723539760: #{queue}")
