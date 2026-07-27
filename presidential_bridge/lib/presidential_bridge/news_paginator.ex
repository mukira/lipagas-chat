defmodule PresidentialBridge.NewsPaginator do
  require Logger

  def cache_news_from_tweets(phone) do
    raw_tweets = case Redix.command(:redix, ["GET", "presidential_x_tweets"]) do
      {:ok, val} when is_binary(val) -> Jason.decode!(val)
      _ -> []
    end

    images_pool =
      case Redix.command(:redix, ["GET", "presidential_images"]) do
        {:ok, val} when is_binary(val) ->
          case Jason.decode(val) do
            {:ok, list} when is_list(list) -> list
            _ -> []
          end
        _ -> []
      end

    parsed_news = raw_tweets
      |> Enum.with_index()
      |> Enum.map(fn {tweet, idx} ->
        text = tweet["text"] || tweet["full_text"] || ""
        created_at = tweet["createdAt"] || tweet["created_at"] || ""
        all_photo_urls = tweet["all_photo_urls"] || []

        image_urls = if length(all_photo_urls) > 0 do
          all_photo_urls
        else
          img = pick_best_image(text, images_pool)
          if img, do: [img["url"]], else: []
        end

        %{
          "headline"   => truncate(text, 50),
          "subtitle"   => format_tweet_date(created_at),
          "detail"     => text,
          "image_urls" => image_urls,
          "button_payload" => "news_read_more_#{idx}"
        }
      end)

    Redix.command(:redix, ["SET", "news_queue:#{phone}", Jason.encode!(parsed_news), "EX", "259200"])
    length(parsed_news)
  end

  def generate_headline_for_overlay(text) do
    # Fallback default
    clean_text = String.replace(text, ~r/\s+/, " ") |> String.trim()
    fallback_headline = if String.length(clean_text) > 100, do: String.slice(clean_text, 0, 100), else: clean_text
    
    hash = :crypto.hash(:md5, clean_text) |> Base.encode16(case: :lower)
    cache_key = "overlay_headline:#{hash}"

    case Redix.command(:redix, ["GET", cache_key]) do
      {:ok, val} when is_binary(val) ->
        case Jason.decode(val) do
          {:ok, %{"headline" => h, "subtitle" => s}} -> {h, s}
          _ -> {fallback_headline, ""}
        end
      _ ->
        prompt = """
        You are a WhatsApp news card writer for Kenya's Presidential bot.
        Given this tweet text, write:
        1. A headline (max 10 words, punchy, no truncation)
        2. A subtitle (max 6 words, the date/context if visible, e.g. "Wed Jul 22, State House")

        Tweet: #{text}

        Respond ONLY in valid JSON: {"headline": "...", "subtitle": "..."}
        """
        
        case PresidentialBridge.AIProxy.call_groq_json_round_robin(prompt) do
          {:ok, reply} ->
            cleaned = reply |> String.replace(~r/```json\n?/, "") |> String.replace(~r/```/, "") |> String.trim()
            case Jason.decode(cleaned) do
              {:ok, parsed = %{"headline" => h, "subtitle" => s}} ->
                # Cache for 3 days
                Redix.command(:redix, ["SET", cache_key, Jason.encode!(parsed), "EX", "259200"])
                {h, s}
              _ -> {fallback_headline, ""}
            end
          _ -> {fallback_headline, ""}
        end
    end
  end

  defp pick_best_image(_text, []), do: nil
  defp pick_best_image(text, pool) do
    search_text = String.downcase(text)
    words = search_text
      |> String.split(~r/[\s\*•:,\.\!\?]+/)
      |> Enum.filter(fn w -> String.length(w) > 3 end)
    
    best_img =
      pool
      |> Enum.map(fn img ->
        tweet = img["tweet_text"] || ""
        score = Enum.count(words, fn w -> String.contains?(tweet, w) end)
        {score, img}
      end)
      |> Enum.filter(fn {score, _} -> score > 0 end)
      |> Enum.sort_by(fn {score, _} -> -score end)
      |> List.first()
    
    case best_img do
      {_, matched} -> matched
      nil -> Enum.random(pool)
    end
  end

  defp truncate(text, max_len) do
    clean_text = String.replace(text, ~r/\s+/, " ") |> String.trim()
    if String.length(clean_text) > max_len do
      String.slice(clean_text, 0, max_len - 3) <> "..."
    else
      clean_text
    end
  end

  defp format_tweet_date(date_str) when is_binary(date_str) and date_str != "" do
    # Try parsing "Sat Jul 25 10:20:00 +0000 2026" or standard ISO
    case DateTime.from_iso8601(date_str) do
      {:ok, dt, _} -> 
        Calendar.strftime(dt, "%a, %d %b %Y")
      _ ->
        # If apify format is "Mon, 27 Jul 2026 ...", just grab the first part or return as is
        String.slice(date_str, 0, 16)
    end
  end
  defp format_tweet_date(_), do: ""
end
