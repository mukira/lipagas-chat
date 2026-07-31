defmodule PresidentialBridge.NewsPaginator do
  require Logger

  @seed_tweets [
    %{
      "id" => "seed_1",
      "text" => "I met with the delegation of Cyprus led by Envoy Marios Lysiotis at State House, Nairobi. We discussed deepening our bilateral relations in trade, education, and maritime security.",
      "createdAt" => "2026-07-28T10:00:00Z",
      "all_photo_urls" => [],
      "author" => %{"userName" => "StateHouseKenya"}
    },
    %{
      "id" => "seed_2",
      "text" => "Inspected the ongoing construction of the Affordable Housing Program units in Mukuru, Nairobi County. Over 5,000 youth are currently employed on-site delivering modern homes for hustlers.",
      "createdAt" => "2026-07-27T14:30:00Z",
      "all_photo_urls" => [],
      "author" => %{"userName" => "WilliamsRuto"}
    },
    %{
      "id" => "seed_3",
      "text" => "Official launch of the Digital Hubs initiative in Kiambu County. We are connecting over 100,000 youth to global digital jobs through high-speed internet hubs across all constituencies.",
      "createdAt" => "2026-07-26T09:15:00Z",
      "all_photo_urls" => [],
      "author" => %{"userName" => "WilliamsRuto"}
    },
    %{
      "id" => "seed_4",
      "text" => "Disbursed additional funding to the Hustler Fund Micro-Loans division. Millions of micro-entrepreneurs across Kenya continue to access affordable credit to expand their small businesses.",
      "createdAt" => "2026-07-25T16:00:00Z",
      "all_photo_urls" => [],
      "author" => %{"userName" => "WilliamsRuto"}
    },
    %{
      "id" => "seed_5",
      "text" => "Commissioned the expanded Fertilizer Subsidy distribution network in Eldoret, Uasin Gishu County. Farmers across the country are securing subsidized fertilizer at Ksh 2,500 per 50kg bag to boost food production.",
      "createdAt" => "2026-07-24T11:45:00Z",
      "all_photo_urls" => [],
      "author" => %{"userName" => "WilliamsRuto"}
    }
  ]

  def cache_news(phone) do
    news_items = fetch_serper_news()

    images_pool =
      case Redix.command(:redix, ["GET", "presidential_images"]) do
        {:ok, val} when is_binary(val) ->
          case Jason.decode(val) do
            {:ok, list} when is_list(list) -> list
            _ -> []
          end
        _ -> []
      end

    parsed_news = news_items
      |> Enum.with_index()
      |> Enum.map(fn {item, idx} ->
        headline = item["title"] || item["text"] || item["full_text"] || ""
        subtitle = item["date"] || item["createdAt"] || item["created_at"] || ""
        detail = item["snippet"] || headline
        source = item["source"] || item["author_handle"] || get_in(item, ["author", "userName"]) || ""
        
        all_photo_urls = item["all_photo_urls"] || []

        image_urls = cond do
          is_list(all_photo_urls) and length(all_photo_urls) > 0 ->
            all_photo_urls
          is_binary(item["imageUrl"]) and item["imageUrl"] != "" ->
            [item["imageUrl"]]
          true ->
            case fetch_serper_image(headline) do
              img when is_binary(img) and img != "" -> [img]
              _ ->
                img = pick_best_image(headline, images_pool)
                if img, do: [img["url"]], else: ["/app/lib/presidential_bridge/ruto_fallback.jpg"]
            end
        end

        %{
          "headline"   => truncate(headline, 50),
          "subtitle"   => format_tweet_date(subtitle),
          "detail"     => detail,
          "image_urls" => image_urls,
          "author_handle" => source,
          "button_payload" => "news_read_more_#{idx}"
        }
      end)

    Redix.command(:redix, ["SET", "news_queue:#{phone}", Jason.encode!(parsed_news), "EX", "259200"])
    length(parsed_news)
  end

  defp fetch_serper_news() do
    cache_key = "serper_latest_news_v2"
    case Redix.command(:redix, ["GET", cache_key]) do
      {:ok, val} when is_binary(val) ->
        case Jason.decode(val) do
          {:ok, list} when is_list(list) and length(list) > 0 -> list
          _ -> fetch_serper_news_from_api(cache_key)
        end
      _ -> fetch_serper_news_from_api(cache_key)
    end
  end

  defp get_serper_key do
    keys = [
      System.get_env("SERPER_API_KEY"),
      System.get_env("SERPER_API_KEY_1"),
      System.get_env("SERPER_API_KEY_2")
    ] |> Enum.reject(fn k -> is_nil(k) or k == "" end)

    if length(keys) > 0, do: Enum.random(keys), else: ""
  end

  defp fetch_serper_news_from_api(cache_key) do
    url = "https://google.serper.dev/news"
    api_key = get_serper_key()
    headers = [{"X-API-KEY", api_key}]
    payload = %{"q" => "William Ruto Kenya", "gl" => "ke"}

    case PresidentialBridge.HTTP.post_json(url, payload, headers) do
      {:ok, %{status: 200, body: body}} ->
        news_items = body["news"] || []
        if length(news_items) > 0 do
          Redix.command(:redix, ["SET", cache_key, Jason.encode!(news_items), "EX", "259200"])
          news_items
        else
          @seed_tweets
        end
      _ -> 
        @seed_tweets
    end
  end

  defp fetch_serper_image(title) do
    clean_title = String.replace(title, ~r/\s+/, " ") |> String.trim()
    hash = :crypto.hash(:md5, clean_title) |> Base.encode16(case: :lower)
    cache_key = "serper_news_img_v3:#{hash}"

    case Redix.command(:redix, ["GET", cache_key]) do
      {:ok, val} when is_binary(val) and val != "" -> val
      _ ->
        url = "https://google.serper.dev/images"
        api_key = get_serper_key()
        headers = [{"X-API-KEY", api_key}]
        query = "William Ruto #{clean_title}"

        case PresidentialBridge.HTTP.post_json(url, %{q: query, gl: "ke"}, headers) do
          {:ok, %{status: 200, body: resp_body}} ->
            images = resp_body["images"] || []
            valid_images = Enum.filter(images, fn img ->
              w = img["imageWidth"] || 0
              h = img["imageHeight"] || 0
              w >= 300 and h >= 200
            end)
            
            selected_img = case List.first(valid_images) do
              %{"imageUrl" => img_url} when is_binary(img_url) -> img_url
              _ -> 
                case List.first(images) do
                  %{"imageUrl" => img_url} when is_binary(img_url) -> img_url
                  _ -> nil
                end
            end

            if selected_img do
              Redix.command(:redix, ["SET", cache_key, selected_img, "EX", "2592000"]) # 30 days
            end
            selected_img

          _ -> nil
        end
    end
  end

  def generate_headline_for_overlay(text, author_handle) do
    # Fallback default
    clean_text = String.replace(text, ~r/\s+/, " ") |> String.trim()
    fallback_headline = if String.length(clean_text) > 100, do: String.slice(clean_text, 0, 100), else: clean_text
    
    hash = :crypto.hash(:md5, clean_text) |> Base.encode16(case: :lower)
    cache_key = "overlay_headline_v130:#{hash}"

    case Redix.command(:redix, ["GET", cache_key]) do
      {:ok, val} when is_binary(val) ->
        case Jason.decode(val) do
          {:ok, %{"headline" => h, "subtitle" => s, "body" => b}} -> {h, s, b}
          _ -> {fallback_headline, "", ""}
        end
      _ ->
        voice_instruction = if String.downcase(author_handle) == "williamsruto" do
          "Rewrite the tweet body in first-person."
        else
          "Summarize the tweet cleanly in third person."
        end

        language = "English"

        prompt = """
    You are William Ruto, the President of Kenya.
    You are summarizing this news article directly for a citizen on WhatsApp.
    
    Output strictly in JSON format matching this schema:
    {
      "headline": "A full 1st-person active sentence starting with a capital letter (e.g. 'I Met The Envoy Of Cyprus In Nairobi'). Plain text only, NO markdown. Max 65 characters.",
      "subtitle": "High-context 1st-person sentence in natural sentence case ending with a full-stop (e.g. 'We enjoy decades of bilateral and trade relations.'). MUST include specific facts, numbers, or outcomes. NEVER use Title Cased words or weird shorthand like '1000s of'. Max 65 characters.",
      "body": "Opening 1st-person line (e.g. 'Let me tell you, my friend, let me brief you on this critical project:'), followed by 3 to 4 IN-DEPTH bullet points starting with '• '. Each bullet point MUST be 2-3 sentences long, providing thorough context, specific numbers, economic impact, and future steps in President Ruto's authentic voice ('My friend', 'Bottom-up', 'We must be honest'). Separate each bullet point with double line breaks (\\n\\n). NEVER output a wall of text. Max 950 characters."
    }

    FEW-SHOT EXAMPLES OF HIGH QUALITY OUTPUT:
    Example 1 (Diplomacy):
    {
      "headline": "I Met The Envoy Of Cyprus In Nairobi",
      "subtitle": "We enjoy decades of bilateral and diplomatic ties."
    }
    Example 2 (Empowerment):
    {
      "headline": "I Launched The Talanta Hela Initiative In Nairobi",
      "subtitle": "We are empowering over 100,000 young Kenyan creatives."
    }

    Rules:
    - Persona: Authentic, direct, accountable, and deliberate. You MUST use your unique speech patterns (e.g. "My friend", "Let me tell you", "The plan", "Bottom-up").
    - Headline Grammar: MUST include proper articles where appropriate (e.g. 'I Met The Envoy' NOT 'I Met Envoy').
    - Subtitle Rules: MUST be in natural sentence case ending with a full-stop (.). ABSOLUTELY NO Title Casing on every word ('We Enjoy 1000s Of...') or weird shorthand ('1000s of'). Use standard English ('thousands of').
    - Strictly 1st-person ONLY ("I", "We"). Never 3rd person. Generic "AI politician" or sterile corporate language is STRICTLY FORBIDDEN.
    - Write the response entirely in: #{String.upcase(language)}.
    - Note on voice: #{voice_instruction}
    
    Article Text:
    #{String.slice(text, 0, 3000)}
    """
        
        case PresidentialBridge.AIProxy.call_groq_json_round_robin(prompt) do
          {:ok, reply} ->
            cleaned = reply |> String.replace(~r/```json\n?/, "") |> String.replace(~r/```/, "") |> String.trim()
            case Jason.decode(cleaned) do
              {:ok, parsed = %{"headline" => h, "subtitle" => s, "body" => b}} ->
                # Cache for 3 days
                Redix.command(:redix, ["SET", cache_key, Jason.encode!(parsed), "EX", "259200"])
                {h, s, b}
              _ -> {fallback_headline, "", ""}
            end
          _ -> {fallback_headline, "", ""}
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
    date_lower = String.downcase(date_str)
    
    cond do
      Regex.match?(~r/(\d+)\s*(?:h|hr|hour)s?\s*ago/, date_lower) ->
        [_, num] = Regex.run(~r/(\d+)\s*(?:h|hr|hour)s?\s*ago/, date_lower)
        DateTime.utc_now() |> DateTime.add(-(String.to_integer(num) * 3600), :second) |> Calendar.strftime("%a, %d %b %Y")
        
      Regex.match?(~r/(\d+)\s*(?:m|min|minute)s?\s*ago/, date_lower) ->
        [_, num] = Regex.run(~r/(\d+)\s*(?:m|min|minute)s?\s*ago/, date_lower)
        DateTime.utc_now() |> DateTime.add(-(String.to_integer(num) * 60), :second) |> Calendar.strftime("%a, %d %b %Y")
        
      Regex.match?(~r/(\d+)\s*day?s?\s*ago/, date_lower) ->
        [_, num] = Regex.run(~r/(\d+)\s*day?s?\s*ago/, date_lower)
        Date.utc_today() |> Date.add(-String.to_integer(num)) |> Calendar.strftime("%a, %d %b %Y")
        
      Regex.match?(~r/(\d+)\s*week?s?\s*ago/, date_lower) ->
        [_, num] = Regex.run(~r/(\d+)\s*week?s?\s*ago/, date_lower)
        Date.utc_today() |> Date.add(-(String.to_integer(num) * 7)) |> Calendar.strftime("%a, %d %b %Y")
        
      true ->
        case DateTime.from_iso8601(date_str) do
          {:ok, dt, _} -> Calendar.strftime(dt, "%a, %d %b %Y")
          _ -> 
            case Date.from_iso8601(date_str) do
              {:ok, d} -> Calendar.strftime(d, "%a, %d %b %Y")
              _ -> Date.utc_today() |> Calendar.strftime("%a, %d %b %Y")
            end
        end
    end
  end
  defp format_tweet_date(_), do: Date.utc_today() |> Calendar.strftime("%a, %d %b %Y")
end
