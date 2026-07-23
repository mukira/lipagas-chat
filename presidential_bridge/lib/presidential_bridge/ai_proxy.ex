defmodule PresidentialBridge.AIProxy do
  @moduledoc """
  AI Proxy endpoint handler for Typebot webhook calls.

  Optimizations for free-tier API usage:
  - Round-robin Groq key rotation (spreads load across all 3 keys)
  - Redis LLM response caching (10-min TTL, zero tokens on cache hit)
  - Prompt context truncation (3000 chars max)
  - Exponential backoff on Groq 429 rate limits
  - Gemini fallback if all Groq keys exhausted
  """

  @groq_keys [
    System.get_env("GROQ_KEY_1") || "gsk_dummy",
    System.get_env("GROQ_KEY_2") || "gsk_dummy",
    System.get_env("GROQ_KEY_3") || "gsk_dummy"
  ]
  @groq_key_count length(@groq_keys)

  @gemini_keys [
    System.get_env("GEMINI_KEY_1") || "AQ_dummy",
    System.get_env("GEMINI_KEY_2") || "AQ_dummy"
  ]
  @gemini_key_count length(@gemini_keys)

  # Max chars of news context to inject per LLM call (~750 tokens)
  @max_context_chars 3000

  # Redis LLM cache TTL in seconds (10 minutes)
  @cache_ttl 600

  @system_prompt """
  You are President William Samoei Ruto of Kenya, speaking directly and personally to a Kenyan citizen named {{user_name}}.

  You are warm, firm, and inspiring — like you are at a public rally.
  You speak in first person for emotional moments and third person for official facts. Use your signature phrases naturally: hustler, bottom-up, mwananchi, kazi ni kazi, Kenya Kwanza.

  When asked about criticism, scandals, or problems:
  1. Empathise genuinely first: "I hear you. I understand."
  2. Then redirect calmly with verified official facts only.

  Respond fully in {{user_language}}. 
  If English: conversational, warm, no jargon.
  If Kiswahili: standard Sanifu Swahili, respectful, not stiff.
  If Sheng: authentic Nairobi youth Sheng — casual, energetic, real.

  Topic focus: The user selected "{{user_topic}}" — prioritize this context.
  Keep your answers under 120 words.
  End every response with a forward-looking statement (e.g. "And we are just getting started. The best is still coming for you.")

  Official Context (verified news only — do NOT hallucinate):
  {{latest_news}}

  Rules:
  - Never make up facts — only use the context above
  - Never be robotic or sound like a press release
  - Greet {{user_name}} by name on the FIRST message only
  - End every response with a forward-looking statement

  User Message:
  """

  # ─── Public API ────────────────────────────────────────────────────────────

  def process_request(payload) do
    user_name    = Map.get(payload, "user_name", "Citizen")
    user_language = Map.get(payload, "user_language", "English")
    user_topic    = Map.get(payload, "user_topic", "General Question")
    latest_news  = (Map.get(payload, "latest_news") || Map.get(payload, "news") || "No recent updates available.")
                   |> String.slice(0, @max_context_chars)
    user_message = (Map.get(payload, "InitialMessage") || Map.get(payload, "message") || "")
                   |> String.trim()

    # Check Redis cache first — zero token cost on hit
    cache_key = build_cache_key(user_message)
    case Redix.command(:redix, ["GET", cache_key]) do
      {:ok, cached} when is_binary(cached) and cached != "" ->
        IO.puts("[AIProxy] Cache HIT for: #{String.slice(user_message, 0, 40)}...")
        {:ok, cached}

      _ ->
        # Format the prompt
        prompt =
          @system_prompt
          |> String.replace("{{latest_news}}", latest_news)
          |> String.replace("{{user_name}}", user_name)
          |> String.replace("{{user_language}}", user_language)
          |> String.replace("{{user_topic}}", user_topic)

        # Try Groq with round-robin rotation + exponential backoff
        case try_groq_round_robin(prompt, user_message) do
          {:ok, reply} ->
            # Cache the reply
            Redix.command(:redix, ["SET", cache_key, reply, "EX", Integer.to_string(@cache_ttl)])
            IO.puts("[AIProxy] Groq reply cached for #{@cache_ttl}s.")
            {:ok, reply}

          {:error, _reason} ->
            IO.puts("[AIProxy] All Groq keys exhausted. Falling back to Gemini.")
            try_gemini(prompt, user_message)
        end
    end
  end

  # ─── Round-Robin Groq Rotation ─────────────────────────────────────────────

  defp try_groq_round_robin(prompt, user_message) do
    # Get the next key index atomically from the Agent
    start_index = Agent.get_and_update(:groq_key_index, fn idx ->
      next = rem(idx + 1, @groq_key_count)
      {idx, next}
    end)

    # Build a rotated list starting from start_index
    keys_in_order = @groq_keys
      |> Enum.with_index()
      |> Enum.sort_by(fn {_, i} -> rem(i - start_index + @groq_key_count, @groq_key_count) end)
      |> Enum.map(fn {k, _} -> k end)

    try_groq_with_backoff(prompt, user_message, keys_in_order, 0, false)
  end

  # Public entry point for DataMiner to fetch JSON
  def call_groq_json_round_robin(prompt, user_message \\ "") do
    start_index = Agent.get_and_update(:groq_key_index, fn idx ->
      next = rem(idx + 1, @groq_key_count)
      {idx, next}
    end)

    keys_in_order = @groq_keys
      |> Enum.with_index()
      |> Enum.sort_by(fn {_, i} -> rem(i - start_index + @groq_key_count, @groq_key_count) end)
      |> Enum.map(fn {k, _} -> k end)

    try_groq_with_backoff(prompt, user_message, keys_in_order, 0, true)
  end

  defp try_groq_with_backoff(_prompt, _msg, [], _attempt, _json_mode), do: {:error, :all_keys_exhausted}

  defp try_groq_with_backoff(prompt, user_message, [key | rest], attempt, json_mode) do
    url = "https://api.groq.com/openai/v1/chat/completions"
    headers = [
      {"Authorization", "Bearer #{key}"},
      {"Content-Type", "application/json"}
    ]
    
    messages = if user_message == "" do
      [%{role: "user", content: prompt}]
    else
      [
        %{role: "system", content: prompt},
        %{role: "user", content: user_message}
      ]
    end

    body = %{
      model: "llama-3.3-70b-versatile",
      messages: messages,
      temperature: 0.7,
      max_tokens: 300
    }
    
    body = if json_mode, do: Map.put(body, :response_format, %{type: "json_object"}), else: body

    case PresidentialBridge.HTTP.post_json(url, body, headers) do
      {:ok, %{status: 200, body: resp_body}} ->
        reply = get_in(resp_body, ["choices", Access.at(0), "message", "content"])
        {:ok, reply}

      {:ok, %{status: 429}} ->
        # Rate limited — exponential backoff before trying next key
        backoff_ms = round(:math.pow(2, attempt) * 1000)
        IO.puts("[AIProxy] Groq key #{attempt + 1} rate-limited (429). Backoff #{backoff_ms}ms...")
        Process.sleep(backoff_ms)
        try_groq_with_backoff(prompt, user_message, rest, attempt + 1, json_mode)

      {:ok, %{status: status}} ->
        IO.puts("[AIProxy] Groq key #{attempt + 1} returned #{status}. Trying next key.")
        try_groq_with_backoff(prompt, user_message, rest, attempt + 1, json_mode)

      {:error, reason} ->
        IO.puts("[AIProxy] Groq key #{attempt + 1} error: #{inspect(reason)}. Trying next key.")
        try_groq_with_backoff(prompt, user_message, rest, attempt + 1, json_mode)
    end
  end

  # ─── Gemini Fallback & Translator ──────────────────────────────────────────

  def call_gemini_round_robin(prompt) do
    start_index = Agent.get_and_update(:gemini_key_index, fn idx ->
      next = rem(idx + 1, @gemini_key_count)
      {idx, next}
    end)

    keys_in_order = @gemini_keys
      |> Enum.with_index()
      |> Enum.sort_by(fn {_, i} -> rem(i - start_index + @gemini_key_count, @gemini_key_count) end)
      |> Enum.map(fn {k, _} -> k end)

    try_gemini_with_backoff(prompt, keys_in_order, 0)
  end

  defp try_gemini_with_backoff(_prompt, [], _attempt), do: {:error, :all_keys_exhausted}

  defp try_gemini_with_backoff(prompt, [key | rest], attempt) do
    url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent?key=#{key}"
    body = %{contents: [%{parts: [%{text: prompt}]}]}

    case PresidentialBridge.HTTP.post_json(url, body, []) do
      {:ok, %{status: 200, body: resp_body}} ->
        reply = get_in(resp_body, ["candidates", Access.at(0), "content", "parts", Access.at(0), "text"])
        {:ok, reply || ""}
      
      {:ok, %{status: 429}} ->
        backoff_ms = round(:math.pow(2, attempt) * 1000)
        IO.puts("[AIProxy] Gemini key #{attempt + 1} rate-limited (429). Backoff #{backoff_ms}ms...")
        Process.sleep(backoff_ms)
        try_gemini_with_backoff(prompt, rest, attempt + 1)

      {:ok, %{status: status}} ->
        IO.puts("[AIProxy] Gemini key #{attempt + 1} returned #{status}. Trying next key.")
        try_gemini_with_backoff(prompt, rest, attempt + 1)
        
      {:error, reason} ->
        IO.puts("[AIProxy] Gemini key #{attempt + 1} error: #{inspect(reason)}. Trying next key.")
        try_gemini_with_backoff(prompt, rest, attempt + 1)
    end
  end

  defp try_gemini(prompt, user_message) do
    full_prompt = prompt <> "\n\n" <> user_message
    case call_gemini_round_robin(full_prompt) do
      {:ok, reply} when reply != "" -> {:ok, reply}
      _ -> {:error, "Gemini fallback failed."}
    end
  end

  # ─── Cache Key ─────────────────────────────────────────────────────────────

  defp build_cache_key(message) do
    hash = :crypto.hash(:md5, String.downcase(String.trim(message))) |> Base.encode16(case: :lower)
    "llm_cache:#{hash}"
  end
end
