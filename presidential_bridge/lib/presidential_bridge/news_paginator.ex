defmodule PresidentialBridge.NewsPaginator do
  require Logger

  def cache_news(text, phone) do
    # Same bullet parsing logic as send_news_image_cards
    bullets = text
      |> String.split(~r/\n/)
      |> Enum.map(&String.trim/1)
      |> Enum.filter(fn line -> 
           String.starts_with?(line, "•") or 
           String.starts_with?(line, "*") or
           String.starts_with?(line, "Tweet:")
         end)
      |> Enum.filter(fn line ->
           not String.contains?(line, "whatsapp.com") and
           not String.contains?(line, "📢")
         end)
      |> Enum.map(fn line ->
           line
           |> String.replace(~r/^[•*]\s*/, "")
           |> String.replace(~r/^Tweet:\s*/, "")
           |> String.replace(~r/^\[[^\]]*\]\s*/, "")  # Strip [KBC], [Nation], [SOURCE] prefixes
           |> String.trim()
         end)
      |> Enum.reject(&(&1 == ""))

    images_pool =
      case Redix.command(:redix, ["GET", "presidential_images"]) do
        {:ok, val} when is_binary(val) ->
          case Jason.decode(val) do
            {:ok, list} when is_list(list) -> list
            _ -> []
          end
        _ -> []
      end

    parsed_news = Enum.reduce(bullets, {[], images_pool}, fn bullet_text, {news_acc, current_pool} ->
      if length(current_pool) > 0 do
        bullet_lower = String.downcase(bullet_text)
        words = bullet_lower
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
        
        parts = String.split(bullet_text, ["—", "-", ":"], parts: 2)
        {headline, subtitle} = case parts do
          [h, s] -> {String.replace(h, ~r/\*/, "") |> String.trim(), String.trim(s)}
          [h] -> {String.replace(h, ~r/\*/, "") |> String.trim(), ""}
          _ -> {bullet_text, ""}
        end

        # If no subtitle, leave it blank — never duplicate the headline as subtitle
        desc = subtitle

        item = %{
          "headline" => headline,
          "subtitle" => desc,
          "image_url" => img["url"],
          "button_payload" => "news_read_more_#{length(news_acc)}"
        }
        {[item | news_acc], List.delete(current_pool, img)}
      else
        {news_acc, current_pool}
      end
    end)
    |> elem(0)

    Redix.command(:redix, ["SET", "news_queue:#{phone}", Jason.encode!(parsed_news), "EX", "86400"])
    length(parsed_news)
  end
end
