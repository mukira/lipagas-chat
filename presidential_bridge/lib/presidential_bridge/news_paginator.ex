defmodule PresidentialBridge.NewsPaginator do
  require Logger

  def cache_news(text, phone) do
    items = case Jason.decode(text) do
      {:ok, parsed} when is_list(parsed) -> parsed
      _ -> []
    end

    # Filter out invalid or garbage items
    items = items
      |> Enum.filter(fn item ->
        title = item["title"] || ""
        String.length(title) >= 5 and not String.starts_with?(title, "http")
      end)

    images_pool =
      case Redix.command(:redix, ["GET", "presidential_images"]) do
        {:ok, val} when is_binary(val) ->
          case Jason.decode(val) do
            {:ok, list} when is_list(list) -> list
            _ -> []
          end
        _ -> []
      end

    parsed_news = Enum.reduce(items, {[], images_pool}, fn item, {news_acc, current_pool} ->
      if length(current_pool) > 0 do
        headline = item["title"] || ""
        subtitle = item["subtitle"] || ""
        detail = item["detail"] || ""

        search_text = String.downcase(headline <> " " <> subtitle)
        words = search_text
          |> String.split(~r/[\s\*•:,\.\!\?]+/)
          |> Enum.filter(fn w -> String.length(w) > 3 end)
        
        best_img =
          current_pool
          |> Enum.map(fn img ->
            tweet = img["tweet_text"] || ""
            score = Enum.count(words, fn w -> String.contains?(tweet, w) end)
            {score, img}
          end)
          |> Enum.filter(fn {score, _} -> score > 0 end)
          |> Enum.sort_by(fn {score, _} -> -score end)
          |> List.first()
        
        img = case best_img do
          {_, matched} -> matched
          nil -> Enum.random(current_pool)
        end
        
        queue_item = %{
          "headline" => headline,
          "subtitle" => subtitle,
          "detail" => detail,
          "image_url" => img["url"],
          "button_payload" => "news_read_more_#{length(news_acc)}"
        }
        
        # Append to accumulator to keep original order (Fix for RC5)
        {news_acc ++ [queue_item], List.delete(current_pool, img)}
      else
        {news_acc, current_pool}
      end
    end)
    |> elem(0)

    Redix.command(:redix, ["SET", "news_queue:#{phone}", Jason.encode!(parsed_news), "EX", "86400"])
    length(parsed_news)
  end
end
