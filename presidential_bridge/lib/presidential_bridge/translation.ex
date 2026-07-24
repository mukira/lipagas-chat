defmodule PresidentialBridge.Translation do
  @moduledoc """
  Multi-model translation engine with Redis caching.

  Waterfall chain (best Kenyan vernacular accuracy first):
    1. gemini-1.5-pro
    2. gemini-2.0-flash
    3. gemini-1.5-flash
    4. gemini-1.0-pro
  """

  @gemini_base "https://generativelanguage.googleapis.com/v1beta/models"

  @gemini_models [
    "gemini-1.5-pro",
    "gemini-2.0-flash",
    "gemini-1.5-flash",
    "gemini-1.0-pro"
  ]

  # ─── Public API ────────────────────────────────────────────────────────────

  def translate(text, target_lang) when is_binary(text) and text != "" do
    hash = :crypto.hash(:sha256, text) |> Base.encode16(case: :lower)
    key  = "pres_trans:#{String.downcase(target_lang)}:#{hash}"

    case Redix.command(:redix, ["GET", key]) do
      {:ok, val} when is_binary(val) and val != "" ->
        IO.puts("[Translation] Cache HIT for #{target_lang}: #{String.slice(text, 0, 20)}...")
        val

      _ ->
        IO.puts("[Translation] Cache MISS for #{target_lang}. Starting model waterfall...")
        translated = run_waterfall(text, target_lang)
        if translated && translated != "" && translated != text do
          Redix.command(:redix, ["SET", key, translated])
          IO.puts("[Translation] Cached translation for #{target_lang}.")
        end
        translated
    end
  end
  def translate(text, _), do: text

  # ─── Model Waterfall ───────────────────────────────────────────────────────

  defp run_waterfall(text, target_lang) do
    gemini_keys = [
      System.get_env("GEMINI_KEY_1") || "",
      System.get_env("GEMINI_API_KEY") || "",
      System.get_env("GEMINI_KEY_2") || ""
    ] |> Enum.uniq() |> Enum.reject(&(&1 == ""))

    case try_gemini_waterfall(text, target_lang, gemini_keys) do
      {:ok, translation} ->
        translation
      :exhausted ->
        IO.puts("[Translation] All models exhausted for #{target_lang}. Trying Kiswahili fallback...")
        # If target language was already Kiswahili, avoid infinite loop and fallback to English
        if String.downcase(target_lang) =~ "kiswahili" or String.downcase(target_lang) =~ "swahili" do
          IO.puts("[Translation] Target was Kiswahili, returning original English text.")
          text
        else
          case try_gemini_waterfall(text, "Kiswahili", gemini_keys) do
            {:ok, swahili_translation} -> swahili_translation
            :exhausted ->
              IO.puts("[Translation] CRITICAL: Kiswahili fallback failed. Returning original English text.")
              text
          end
        end
    end
  end

  # ─── Gemini: Try every model × every key ──────────────────────────────────

  defp try_gemini_waterfall(text, target_lang, keys) do
    prompt = build_prompt(text, target_lang)
    Enum.reduce_while(@gemini_models, :exhausted, fn model, _acc ->
      IO.puts("[Translation] Trying Gemini model: #{model}...")
      case try_gemini_model(model, prompt, keys) do
        {:ok, result} -> {:halt, {:ok, result}}
        :failed       -> {:cont, :exhausted}
      end
    end)
  end

  defp try_gemini_model(model, prompt, keys) do
    Enum.reduce_while(keys, :failed, fn key, _acc ->
      url = "#{@gemini_base}/#{model}:generateContent?key=#{key}"
      payload = %{
        "contents"        => [%{"parts" => [%{"text" => prompt}]}],
        "generationConfig" => %{"temperature" => 0.0}
      }

      # 45-second timeout for the HTTP request to allow Gemini to complete long translations accurately
      timeout_ms = 45000

      case PresidentialBridge.HTTP.post_json(url, payload, [], timeout_ms) do
        {:ok, %{status: 200, body: body}} ->
          case parse_gemini_response(body) do
            {:ok, text} ->
              IO.puts("[Translation] ✅ Gemini #{model} succeeded.")
              {:halt, {:ok, text}}
            :parse_error ->
              IO.puts("[Translation] ⚠️  Gemini #{model} returned unparseable response or TRANSLATION_FAILED.")
              {:cont, :failed}
          end

        {:ok, %{status: 429}} ->
          IO.puts("[Translation] ⚠️  Gemini #{model} rate-limited (429). Trying next key...")
          {:cont, :failed}

        {:ok, %{status: status}} ->
          IO.puts("[Translation] ⚠️  Gemini #{model} returned #{status}. Trying next key...")
          {:cont, :failed}

        {:error, reason} ->
          IO.puts("[Translation] ⚠️  Gemini #{model} HTTP error: #{inspect(reason)}. Trying next key...")
          {:cont, :failed}
      end
    end)
  end

  defp parse_gemini_response(body) do
    try do
      json = if is_binary(body), do: Jason.decode!(body), else: body
      candidate = List.first(json["candidates"] || [])
      part = List.first(get_in(candidate || %{}, ["content", "parts"]) || [])
      raw_text = String.trim(part["text"] || "")

      # If model explicitly failed
      if String.contains?(raw_text, "TRANSLATION_FAILED") do
        :parse_error
      else
        # Strip markdown ticks for JSON
        clean_text = raw_text
                     |> String.replace(~r/^```(?:json)?\n?/i, "")
                     |> String.replace(~r/\n?```$/i, "")
                     |> String.trim()
        
        parsed_json = Jason.decode!(clean_text)
        translation = String.trim(parsed_json["translation"] || "")

        if translation != "" and not String.contains?(translation, "TRANSLATION_FAILED") do
          {:ok, translation}
        else
          :parse_error
        end
      end
    rescue
      e -> 
        IO.puts("[Translation] Parse error: #{inspect(e)}")
        :parse_error
    end
  end

  # ─── Prompt Builder ────────────────────────────────────────────────────────

  defp build_prompt(text, target_lang) do
    """
    You are an expert, native-speaking Kenyan linguist.
    Translate the following English text to #{target_lang}.

    CRITICAL INSTRUCTIONS:
    1. If you are not completely fluent in #{target_lang}, or if you do not know the language natively, you MUST return exactly "TRANSLATION_FAILED". Do NOT attempt to guess, hallucinate, or fallback to Swahili/English.
    2. PRESERVE ALL PROPER NOUNS. Do NOT translate names of people (e.g., Mukira, Ruto), places (e.g., Gikomba, Kisumu), or brand names. Leave them exactly as they are in the original text.
    3. If you do know the language, you must first silently analyze the target language's grammatical syntax (Subject-Verb-Object, noun classes, etc.) to ensure a super accurate, native-sounding translation.
    4. Return your final response as a raw JSON object matching exactly this schema: {"translation": "your accurate translation here"}
    5. EXACTLY PRESERVE all original formatting, including paragraphs, newlines (\n), and spacing. Do NOT collapse paragraphs into a single block. Your translated text must have the exact same number of paragraphs as the original text.
    
    Text: #{text}
    """
  end
end
