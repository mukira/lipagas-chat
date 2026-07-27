defmodule PresidentialBridge.DataMiner do
  use GenServer
  require Logger

  @apify_key  "apify_api_s8ED1751q9pWXuBO6vvhiorRHAn2og2GHHPe"
  @serper_key System.get_env("SERPER_API_KEY") || ""
  @pr_whatsapp_number "254723539760"

  # ─── Timers ────────────────────────────────────────────────────────────────
  # Apify (paid credits) — every 60 min
  @apify_interval   60 * 60 * 1000
  # RSS feeds (free)    — every 30 min
  @rss_interval     30 * 60 * 1000
  # Serper (paid credits, PR alerts only) — every 120 min
  @serper_interval  120 * 60 * 1000

  # ─── RSS Sources ───────────────────────────────────────────────────────────
  @rss_feeds []

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
        
        # Extract images from the items
        extract_images_from_items(items)

      err ->
        Logger.error("[DataMiner] Apify X fetch failed: #{inspect(err)}")
    end
  end
  
  defp extract_images_from_items(items) do
    counties = [
      "mombasa", "kwale", "kilifi", "tana river", "lamu", "taita taveta", "garissa",
      "wajir", "mandera", "marsabit", "isiolo", "meru", "tharaka nithi", "embu",
      "kitui", "machakos", "makueni", "nyandarua", "nyeri", "kirinyaga", "murang'a",
      "kiambu", "turkana", "west pokot", "samburu", "trans nzoia", "uasin gishu",
      "elgeyo marakwet", "nandi", "baringo", "laikipia", "nakuru", "narok", "kajiado",
      "kericho", "bomet", "kakamega", "vihiga", "bungoma", "busia", "siaya", "kisumu",
      "homa bay", "migori", "kisii", "nyamira", "nairobi", "housing", "road", "water",
      "agriculture", "education", "health"
    ]

    images =
      items
      |> Enum.flat_map(fn item ->
        text = item["text"] || item["full_text"] || ""
        # Apify Twitter actor returns `media` array or `extendedEntities.media`
        media_list = item["media"] || get_in(item, ["extendedEntities", "media"]) || get_in(item, ["entities", "media"]) || []
        
        # Get first photo URL
        photo = Enum.find(media_list, fn m -> m["type"] == "photo" end)
        if photo do
          url = photo["media_url_https"] || photo["url"] || photo["media_url"]
          if url do
            text_lower = String.downcase(text)
            matched_keywords = Enum.filter(counties, fn c -> String.contains?(text_lower, c) end)
            
            [%{url: url, tweet_text: String.downcase(text), keywords: matched_keywords}]
          else
            []
          end
        else
          []
        end
      end)
      
    if length(images) > 0 do
      Logger.info("[DataMiner] Extracted #{length(images)} images from X.")
      Redix.command(:redix, ["SET", "presidential_images", Jason.encode!(images)])
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
    
    # Generate dynamic buttons based on the new context
    Task.start(fn -> generate_dynamic_buttons(merged) end)
  end

  defp redis_get(key, default) do
    case Redix.command(:redix, ["GET", key]) do
      {:ok, val} when is_binary(val) -> val
      _ -> default
    end
  end

  defp generate_dynamic_buttons(merged_context) do
    Logger.info("[DataMiner] Step 1: Generating English summary using Groq...")
    
    groq_prompt = """
    You are President William Samoei Ruto of Kenya, speaking directly and personally to a Kenyan citizen via WhatsApp. You are warm, authoritative, and speak in first person at ALL times.

    HARD RULES — NEVER BREAK THESE:
    - NEVER use "Ruto", "The President", "He", "The government" as subjects. You ARE the speaker.
    - NEVER reference source names like KBC, Nation, Twitter, X, or any media outlet.
    - ALWAYS write in first person: "I", "We", "My government", "I am proud to announce", "Today, we delivered".

    Based on the following news context, write:
    1. "en_button": A short punchy English label starting with ONE emoji (under 20 chars).
    2. "summary_en": A JSON array of news items. EACH item MUST have:
       - "title": A short WhatsApp-friendly header (under 40 chars). Plain text only, absolutely NO markdown, NO asterisks.
       - "subtitle": A short one-liner subtitle (under 60 chars). Plain text only, NO markdown, NO asterisks.  
       - "detail": 2-3 sentences in first person expanding on this specific update. Warm, presidential tone. DO NOT repeat the title or subtitle verbatim.
    3. "full_news_en": A detailed, well-formatted PR update written as if I am addressing the nation personally. First-person throughout. Bold headers. Clear separators. Do NOT mention any source names.

    Respond ONLY with a valid JSON object matching the exact keys: "en_button", "summary_en", "full_news_en".

    News Context:
    #{merged_context}
    """

    case PresidentialBridge.AIProxy.call_groq_json_round_robin(groq_prompt) do
      {:ok, groq_json_str} ->
        # Clean JSON block if wrapped in markdown just in case
        cleaned_groq = groq_json_str |> String.replace(~r/```json\n?/, "") |> String.replace(~r/```/, "") |> String.trim()
        
        case Jason.decode(cleaned_groq) do
          {:ok, groq_json} ->
            Logger.info("[DataMiner] Step 2: Translating summary into 48 languages using Gemini...")
            gemini_prompt = """
            You are an expert translator specializing in ALL Kenyan ethnic languages.
            I have an English button and a summary array composed of titles, subtitles, and details. I need you to translate them into 48 Kenyan languages, including but not limited to:
            Kiswahili, Sheng, Kikuyu, Luo, Kalenjin, Kamba, Gusii, Meru, Mijikenda, Somali, Turkana, Maasai, Embu, Taita, Pokot, Kuria, Borana, Rendille, Samburu, etc.
            
            Button constraints: MUST start with ONE emoji, MUST be under 20 chars total.
            Summary constraints: Translate the "title", "subtitle", and "detail" fields of each item in the array. You MUST maintain the warm, first-person voice of President William Ruto speaking directly to the citizen in all translations.
            
            Input JSON:
            #{Jason.encode!(groq_json)}
            
            Respond ONLY with a valid JSON object where the keys are the language names (lowercase) and the values are objects containing "button" and "summary" (which should be an array of the translated items).
            Example:
            {
              "english": {"button": "...", "summary": [{"title": "...", "subtitle": "...", "detail": "..."}]},
              "kiswahili": {"button": "...", "summary": [{"title": "...", "subtitle": "...", "detail": "..."}]},
              "sheng": {"button": "...", "summary": [{"title": "...", "subtitle": "...", "detail": "..."}]}
            }
            Do this for as many Kenyan languages as possible (aim for 48).
            """
            
            case PresidentialBridge.AIProxy.call_dataminer_gemini(gemini_prompt) do
              {:ok, reply} ->
                cleaned_json = reply |> String.replace(~r/```json\n?/, "") |> String.replace(~r/```/, "") |> String.trim()
                
                case Jason.decode(cleaned_json) do
                  {:ok, gemini_json} ->
                    # Inject the English original so it's always there
                    final_map = Map.put(gemini_json, "english", %{
                      "button" => groq_json["en_button"] || "",
                      "summary" => groq_json["summary_en"] || ""
                    })
                    
                    Redix.command(:redix, ["SET", "dynamic_news_translations", Jason.encode!(final_map)])
                    
                    # Keep backward compatibility for the existing 3 groups to not break the Typebot immediately
                    sw_data = Map.get(gemini_json, "kiswahili", %{})
                    sh_data = Map.get(gemini_json, "sheng", %{})
                    Redix.command(:redix, ["SET", "dynamic_btn_en", groq_json["en_button"] || ""])
                    Redix.command(:redix, ["SET", "dynamic_btn_sw", Map.get(sw_data, "button", "Swahili Update")])
                    Redix.command(:redix, ["SET", "dynamic_btn_sh", Map.get(sh_data, "button", "Sheng Update")])
                    Redix.command(:redix, ["SET", "dynamic_summary", groq_json["summary_en"] || ""])
                    Redix.command(:redix, ["SET", "dynamic_summary_sw", Map.get(sw_data, "summary", "")])
                    Redix.command(:redix, ["SET", "dynamic_summary_sh", Map.get(sh_data, "summary", "")])
                    
                    Logger.info("[DataMiner] 48-Language Dynamic translations saved successfully.")

                    # --- Step 3: Translate Full News separately to avoid Gemini timeouts ---
                    Logger.info("[DataMiner] Step 3: Translating Full News into Swahili and Sheng...")
                    full_news_prompt = """
                    You are an expert translator specializing in Kenyan languages.
                    Translate the following highly-positive PR update into Kiswahili and Sheng.
                    Maintain the exact structural formatting (WhatsApp bold *Title*, bullet points, and clear separators).
                    
                    Text to translate:
                    #{groq_json["full_news_en"] || "No updates available."}
                    
                    Respond ONLY with a valid JSON object matching the keys: "full_news_sw", "full_news_sh".
                    """
                    
                    case PresidentialBridge.AIProxy.call_dataminer_gemini(full_news_prompt) do
                      {:ok, full_news_reply} ->
                        cleaned_fn = full_news_reply |> String.replace(~r/```json\n?/, "") |> String.replace(~r/```/, "") |> String.trim()
                        case Jason.decode(cleaned_fn) do
                          {:ok, fn_json} ->
                            Redix.command(:redix, ["SET", "dynamic_full_news_en", groq_json["full_news_en"] || ""])
                            Redix.command(:redix, ["SET", "dynamic_full_news_sw", fn_json["full_news_sw"] || ""])
                            Redix.command(:redix, ["SET", "dynamic_full_news_sh", fn_json["full_news_sh"] || ""])
                            Logger.info("[DataMiner] Full News translations saved successfully.")
                          _ -> Logger.error("[DataMiner] Failed to decode Full News JSON: #{cleaned_fn}")
                        end
                      _ -> Logger.error("[DataMiner] Full News Gemini translation failed.")
                    end

                  _ ->
                    Logger.error("[DataMiner] Failed to decode Gemini 48-lang JSON: #{cleaned_json}")
                end
              _ ->
                Logger.error("[DataMiner] Gemini translation failed.")
            end
            
          _ -> Logger.error("[DataMiner] Failed to decode Groq JSON: #{groq_json_str}")
        end
      {:error, reason} ->
        Logger.error("[DataMiner] Groq generation failed: #{inspect(reason)}. Falling back to Gemini...")
        case PresidentialBridge.AIProxy.call_dataminer_gemini(groq_prompt) do
          {:ok, gemini_fallback_str} ->
            cleaned_fallback = gemini_fallback_str |> String.replace(~r/```json\n?/, "") |> String.replace(~r/```/, "") |> String.trim()
            case Jason.decode(cleaned_fallback) do
              {:ok, fallback_json} ->
                Logger.info("[DataMiner] Gemini fallback succeeded. Running translation pipeline...")
                gemini_prompt = """
                You are an expert translator specializing in ALL Kenyan ethnic languages.
                I have an English button and a summary composed of a main title and bullet points. I need you to translate them into 48 Kenyan languages, including but not limited to:
                Kiswahili, Sheng, Kikuyu, Luo, Kalenjin, Kamba, Gusii, Meru, Mijikenda, Somali, Turkana, Maasai, Embu, Taita, Pokot, Kuria, Borana, Rendille, Samburu, etc.

                Button constraints: MUST start with ONE emoji, MUST be under 20 chars total.
                Summary constraints: Maintain the exact structural formatting (WhatsApp bold *Title*, bullet points, and strictly the *Header*: description format for every bullet). MUST maintain the warm, first-person voice of President William Ruto.

                Input JSON:
                #{Jason.encode!(fallback_json)}

                Respond ONLY with a valid JSON object where the keys are the language names (lowercase) and the values are objects containing "button" and "summary".
                """

                case PresidentialBridge.AIProxy.call_dataminer_gemini(gemini_prompt) do
                  {:ok, trans_reply} ->
                    cleaned_trans = trans_reply |> String.replace(~r/```json\n?/, "") |> String.replace(~r/```/, "") |> String.trim()
                    case Jason.decode(cleaned_trans) do
                      {:ok, trans_json} ->
                        final_map = Map.put(trans_json, "english", %{
                          "button" => fallback_json["en_button"] || "",
                          "summary" => fallback_json["summary_en"] || ""
                        })
                        Redix.command(:redix, ["SET", "dynamic_news_translations", Jason.encode!(final_map)])
                        sw_data = Map.get(trans_json, "kiswahili", %{})
                        sh_data = Map.get(trans_json, "sheng", %{})
                        Redix.command(:redix, ["SET", "dynamic_btn_en", fallback_json["en_button"] || ""])
                        Redix.command(:redix, ["SET", "dynamic_btn_sw", Map.get(sw_data, "button", "Habari Mpya")])
                        Redix.command(:redix, ["SET", "dynamic_btn_sh", Map.get(sh_data, "button", "Updates Zii")])
                        Redix.command(:redix, ["SET", "dynamic_summary", fallback_json["summary_en"] || ""])
                        Redix.command(:redix, ["SET", "dynamic_summary_sw", Map.get(sw_data, "summary", "")])
                        Redix.command(:redix, ["SET", "dynamic_summary_sh", Map.get(sh_data, "summary", "")])
                        Redix.command(:redix, ["SET", "dynamic_full_news_en", fallback_json["full_news_en"] || ""])
                        Logger.info("[DataMiner] Gemini fallback: 48-lang translations saved successfully.")
                      _ -> Logger.error("[DataMiner] Gemini fallback: Failed to decode translation JSON.")
                    end
                  _ -> Logger.error("[DataMiner] Gemini fallback: Translation step also failed.")
                end
              _ -> Logger.error("[DataMiner] Gemini fallback: Failed to decode fallback JSON: #{cleaned_fallback}")
            end
          {:error, fallback_reason} ->
            Logger.error("[DataMiner] Gemini fallback also failed: #{inspect(fallback_reason)}. No news generated.")
        end
    end  # end outer case call_groq_json_round_robin
  end  # end generate_dynamic_buttons

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

    case PresidentialBridge.AIProxy.call_dataminer_gemini(prompt) do
      {:ok, reply} ->
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
