defmodule PresidentialBridge.DataMiner do
  use GenServer
  require Logger

  @apify_key  "apify_api_s8ED1751q9pWXuBO6vvhiorRHAn2og2GHHPe"
  @serper_key "437b1209e93d91f3bd678059ef82512cce7dd619"
  @gemini_key "AIzaSyDy03Ybx7gzSJbRlqeYHbKK0L73-XLEq_k"
  @pr_whatsapp_number "254723539760"

  # ─── Timers ────────────────────────────────────────────────────────────────
  # Apify (paid credits) — every 60 min
  @apify_interval   60 * 60 * 1000
  # RSS feeds (free)    — every 30 min
  @rss_interval     30 * 60 * 1000
  # Serper (paid credits, PR alerts only) — every 120 min
  @serper_interval  120 * 60 * 1000

  # ─── RSS Sources ───────────────────────────────────────────────────────────
  @rss_feeds [
    {"Nation",  "https://nation.africa/kenya/rss.xml"},
    {"KBC",     "https://www.kbc.co.ke/feed/"}
  ]

  # Only keep items whose title/description contains one of these (case-insensitive)
  @rss_keywords ["ruto", "president", "state house", "government", "kenya",
                 "cabinet", "deputy president", "state house"]

  # ─── Context Chunking ──────────────────────────────────────────────────────
  @max_section_chars 1500   # Per source section
  @max_context_chars 3000   # Total merged context

  # ─── Lifecycle ─────────────────────────────────────────────────────────────

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def init(state) do
    Logger.info("[DataMiner] Started. Scheduling multi-source scraping.")
    # Fire all tracks immediately on boot
    send(self(), :scrape_x)
    send(self(), :scrape_rss)
    send(self(), :analyze_media)
    {:ok, state}
  end

  # ─── Scheduled Handlers ────────────────────────────────────────────────────

  def handle_info(:scrape_x, state) do
    Task.start(fn -> fetch_official_x_data() end)
    Process.send_after(self(), :scrape_x, @apify_interval)
    {:noreply, state}
  end

  def handle_info(:scrape_rss, state) do
    Task.start(fn -> fetch_rss_data() end)
    Process.send_after(self(), :scrape_rss, @rss_interval)
    {:noreply, state}
  end

  def handle_info(:analyze_media, state) do
    Task.start(fn -> analyze_media_sentiment() end)
    Process.send_after(self(), :analyze_media, @serper_interval)
    {:noreply, state}
  end

  # ─── Track 1: Official X Scraper (Apify) ───────────────────────────────────

  defp fetch_official_x_data do
    Logger.info("[DataMiner] Fetching official X data from Apify...")
    url = "https://api.apify.com/v2/acts/kaitoeasyapi~twitter-x-data-tweet-scraper-pay-per-result-cheapest/run-sync-get-dataset-items?token=#{@apify_key}"
    
    # Tracking all official handles provided
    search_query = "from:WilliamsRuto OR from:StateHouseKenya OR from:SpokespersonGoK OR from:MwauraIsaac1"
    payload = %{"searchTerms" => [search_query], "maxItems" => 5}

    case PresidentialBridge.HTTP.post_json(url, payload, []) do
      {:ok, %{status: status, body: items}} when status in [200, 201] and is_list(items) ->
        x_section =
          items
          |> Enum.map(fn item ->
            date = item["createdAt"] || item["created_at"] || ""
            text = item["text"] || item["full_text"] || ""
            "Date: #{date}\nTweet: #{text}"
          end)
          |> Enum.join("\n\n")
          |> String.slice(0, @max_section_chars)

        Logger.info("[DataMiner] X context fetched (#{byte_size(x_section)} chars).")
        store_merged_context(:x, x_section)

      err ->
        Logger.error("[DataMiner] Apify X fetch failed: #{inspect(err)}")
    end
  end

  # ─── Track 2: RSS News Scraper (Free) ──────────────────────────────────────

  defp fetch_rss_data do
    Logger.info("[DataMiner] Fetching RSS feeds...")

    items_by_source =
      @rss_feeds
      |> Enum.map(fn {label, url} ->
        case PresidentialBridge.HTTP.get(url) do
          {:ok, %{status: status, body: body}} when status in [200, 301] ->
            items = parse_rss(body, label)
            filtered = Enum.filter(items, &relevant?/1)
            kept = Enum.take(filtered, 5)
            Logger.info("[DataMiner] RSS #{label}: #{length(kept)} relevant items kept.")
            kept
          err ->
            Logger.warning("[DataMiner] RSS #{label} failed: #{inspect(err)}")
            []
        end
      end)
      |> List.flatten()

    news_section =
      items_by_source
      |> Enum.map(fn {source, title, date} -> "[#{source}] #{title} (#{date})" end)
      |> Enum.join("\n")
      |> String.slice(0, @max_section_chars)

    Logger.info("[DataMiner] RSS context built (#{byte_size(news_section)} chars).")
    store_merged_context(:rss, news_section)
  end

  defp parse_rss(body, label) do
    # Extract <item>...</item> blocks
    items = Regex.scan(~r/<item>(.*?)<\/item>/s, body, capture: :all_but_first)

    Enum.map(items, fn [item_body] ->
      title   = extract_tag(item_body, "title")
      pub_date = extract_tag(item_body, "pubDate") |> format_date()
      {label, title, pub_date}
    end)
  end

  defp extract_tag(body, tag) do
    case Regex.run(~r/<#{tag}><!\[CDATA\[(.*?)\]\]><\/#{tag}>|<#{tag}>(.*?)<\/#{tag}>/s, body, capture: :all_but_first) do
      [cdata, _] when cdata != "" -> String.trim(cdata)
      [_, plain] when plain != "" -> String.trim(plain)
      [val] when val != ""        -> String.trim(val)
      _                           -> ""
    end
  end

  defp format_date(""), do: ""
  defp format_date(date_str) do
    # Keep just the date portion for brevity: "Tue, 21 Jul 2026"
    date_str |> String.split(",") |> List.last("") |> String.trim() |> String.split(" ") |> Enum.take(3) |> Enum.join(" ")
  end

  defp relevant?({_source, title, _date}) do
    lower = String.downcase(title)
    Enum.any?(@rss_keywords, fn kw -> String.contains?(lower, kw) end)
  end

  # ─── Merged Context Storage ─────────────────────────────────────────────────
  # Context is stored in two Redis keys, then merged on read.
  # This lets each track update independently without race conditions.

  defp store_merged_context(track, section) do
    redis_key = case track do
      :x   -> "presidential_context_x"
      :rss -> "presidential_context_rss"
    end
    Redix.command(:redix, ["SET", redis_key, section])
    rebuild_context()
  end

  defp rebuild_context do
    x_section   = redis_get("presidential_context_x",   "")
    rss_section = redis_get("presidential_context_rss",  "")

    merged = """
=== [OFFICIAL X / TWITTER] ===
#{x_section}

=== [KENYAN NEWS] ===
#{rss_section}
""" |> String.trim() |> String.slice(0, @max_context_chars)

    Redix.command(:redix, ["SET", "presidential_context", merged])
    Logger.info("[DataMiner] presidential_context updated (#{byte_size(merged)} chars total).")
  end

  defp redis_get(key, default) do
    case Redix.command(:redix, ["GET", key]) do
      {:ok, val} when is_binary(val) -> val
      _ -> default
    end
  end

  # ─── Track 3: Media Sentiment via Serper + Gemini (PR Alerts) ─────────────

  defp analyze_media_sentiment do
    Logger.info("[DataMiner] Running Serper media sentiment analysis...")
    url = "https://google.serper.dev/news"
    headers = [{"X-API-KEY", @serper_key}]
    payload = %{"q" => "William Ruto latest news today", "gl" => "ke"}

    case PresidentialBridge.HTTP.post_json(url, payload, headers) do
      {:ok, %{status: 200, body: body}} ->
        news_items = body["news"] || []

        summary =
          news_items
          |> Enum.take(5)
          |> Enum.map(& "- #{&1["title"]}: #{&1["snippet"]}")
          |> Enum.join("\n")

        news_hash = :erlang.phash2(summary)
        stored_hash = redis_get("serper_news_hash", "")

        if Integer.to_string(news_hash) == stored_hash do
          Logger.info("[DataMiner] Serper news unchanged (hash match). Skipping Gemini.")
        else
          Logger.info("[DataMiner] Serper news changed. Running Gemini sentiment check.")
          Redix.command(:redix, ["SET", "serper_news_hash", Integer.to_string(news_hash)])
          check_sentiment_with_gemini(summary)
        end

      err ->
        Logger.error("[DataMiner] Serper fetch failed: #{inspect(err)}")
    end
  end

  defp check_sentiment_with_gemini(summary) do
    prompt = """
    You are a PR sentiment analyzer. Analyze the following news headlines about the President of Kenya.
    If the general sentiment is highly negative, controversial, or damaging to his PR narrative, respond with exactly "NEGATIVE".
    Otherwise, respond with "OKAY".

    News:
    #{summary}
    """

    url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=#{@gemini_key}"
    body = %{contents: [%{parts: [%{text: prompt}]}]}

    case PresidentialBridge.HTTP.post_json(url, body, []) do
      {:ok, %{status: 200, body: resp_body}} ->
        reply = get_in(resp_body, ["candidates", Access.at(0), "content", "parts", Access.at(0), "text"]) || ""
        if String.contains?(String.upcase(reply), "NEGATIVE") do
          alert_pr_team(summary)
        else
          Logger.info("[DataMiner] PR Sentiment: OKAY.")
        end
      _ ->
        Logger.error("[DataMiner] Gemini sentiment check failed.")
    end
  end

  defp alert_pr_team(summary) do
    Logger.warning("[DataMiner] NEGATIVE sentiment detected. Alerting PR team.")
    token    = "EAAUbTMY5PfMBSEszVg4HAZA1aOZCcea5VBmZBEGMYIxOMnx1u0m4cbEJZAsIpQe6ZAHGu9cHCfm5dffeCXldFX1A28bErrqXMZCxDhGVAXUYexKSAWBpT8w2048naM0SF55x1DTiZBeqpLLQwrMoFqj9QJt0bpjhZBhsKnVAHctNjNoj3O0Eh5gdnZBZAhPZAdpoA06yBga4QeSHxz31vZBXqQagYmjBOiBlt9hmkVOrts6UfZAenFKZCDnVUgmuQdGfoeSHElW4CKmmlgQFL0jzBZAnIO110ou2IOKiD0HbSZAUOgsSvE0ErJDJ1dsMEUHNhV6zB883dcrLe2oZD"
    phone_id = "1156689577536011"

    msg = """
    🚨 *PR ALERT - The Spin Room* 🚨
    Negative media narrative detected regarding the President.

    *Latest Media Snippets:*
    #{summary}

    _This alert was generated automatically by the Spin Room subsystem._
    """

    payload = %{
      messaging_product: "whatsapp",
      to: @pr_whatsapp_number,
      type: "text",
      text: %{body: msg}
    }

    url = "https://graph.facebook.com/v21.0/#{phone_id}/messages"
    PresidentialBridge.HTTP.post_json(url, payload, [{"Authorization", "Bearer #{token}"}])
  end
end
