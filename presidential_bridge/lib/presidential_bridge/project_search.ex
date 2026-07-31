defmodule PresidentialBridge.ProjectSearch do
  require Logger

  @serper_api_key System.get_env("SERPER_API_KEY") || ""

  @doc """
  Takes a user location string, queries Groq to construct a search query, hits Serper,
  and recurses up to 1 time if no projects are found. Returns the final formatted PR message.
  """
  def search(location, language \\ "english", user_name \\ "Citizen") do
    normalized_loc = String.downcase(String.trim(location))
    cache_key = "projects_cache_v21:#{normalized_loc}"

    case Redix.command(:redix, ["GET", cache_key]) do
      {:ok, val} when is_binary(val) ->
        Logger.info("[ProjectSearch] Cache HIT for location: #{normalized_loc}")
        case Jason.decode(val) do
          {:ok, %{"intro" => intro, "projects" => projects}} -> {intro, projects}
          _ -> run_full_search(location, language, user_name, cache_key)
        end
      _ ->
        Logger.info("[ProjectSearch] Cache MISS for location: #{normalized_loc}")
        run_full_search(location, language, user_name, cache_key)
    end
  end

  defp run_full_search(location, language, user_name, cache_key) do
    # 1. First Pass
    query = build_query(location, false)
    results = run_serper(query)

    {final_results, _final_query} = 
      if projects_found?(results) do
        {results, query}
      else
        Logger.info("[ProjectSearch] No projects found for #{location}. Recursing to broader region...")
        # 2. Recursive Pass (e.g., Town -> County)
        broader_query = build_query(location, true)
        broader_results = run_serper(broader_query)
        {broader_results, broader_query}
      end

    {intro, projects} = format_response(final_results, location, language, user_name)
    
    if length(projects) > 0 do
      Redix.command(:redix, ["SET", cache_key, Jason.encode!(%{"intro" => intro, "projects" => projects}), "EX", "86400"])
    end
    
    {intro, projects}
  end

  defp build_query(location, is_recursive) do
    instruction = if is_recursive do
      "The user searched for '#{location}' but no projects were found. Identify the parent COUNTY or REGION of '#{location}' in Kenya, and output a Google search query to find President Ruto's development projects in that broader region."
    else
      "Output a highly specific Google search query to find President Ruto's development projects in or near '#{location}', Kenya."
    end

    prompt = """
    You are an expert Kenyan geographer and PR strategist.
    #{instruction}
    The query must include 'President Ruto development projects'.
    Respond ONLY with the exact search query string. Do not include quotes or any other text.
    """

    case PresidentialBridge.AIProxy.call_groq_round_robin(prompt) do
      {:ok, query} -> String.trim(query) |> String.replace("\"", "")
      _ -> "President Ruto development projects in #{location} Kenya"
    end
  end

  defp run_serper(query) do
    url = "https://google.serper.dev/search"
    headers = [
      {"X-API-KEY", @serper_api_key}
    ]
    body_map = %{q: query, gl: "ke"}

    case PresidentialBridge.HTTP.post_json(url, body_map, headers) do
      {:ok, %{status: 200, body: resp_body}} ->
        if is_map(resp_body) or is_list(resp_body) do
          Jason.encode!(resp_body)
        else
          resp_body
        end
      _ ->
        "{}"
    end
  end

  defp projects_found?(serper_json_str) do
    case Jason.decode(serper_json_str) do
      {:ok, json} -> 
        organic = json["organic"] || []
        length(organic) > 0
      _ -> false
    end
  end

  defp format_response(serper_json_str, location, language, user_name) do
    # Minimize Serper tokens to save Groq RPM/TPM
    minimized_results = case Jason.decode(serper_json_str) do
      {:ok, %{"organic" => organic}} ->
        organic
        |> Enum.take(4)
        |> Enum.map(fn item -> %{title: item["title"], snippet: item["snippet"]} end)
        |> Jason.encode!()
      _ -> serper_json_str
    end

    prompt = """
    You are William Ruto, the President of Kenya, speaking directly to a citizen named #{user_name} on WhatsApp.
    Based on the following project search results for location "#{location}", generate a project update.
    
    Output strictly valid JSON matching this schema:
    {
      "intro": "Warm, direct introductory text explicitly using this format based on language (NO hardcoded 'County'): If English: 'My friend *#{user_name}*, every part of Kenya matters to us. Take a look at the ground work we are delivering in #{location}'. If Kiswahili: 'Rafiki yangu *#{user_name}*, kila sehemu ya Kenya ni muhimu kwetu. Angalia kazi halisi tunayotekeleza hapa #{location}'. If Sheng: 'Buda *#{user_name}*, kila mtaa ni maana kwetu. Naoza ma-projects za ground tunadrop hapa #{location}'.",
      "projects": [
        {
          "title": "Full, grammatically complete 1st-person active sentence starting with a capital letter (e.g. 'I Inspected The Blue Economy Projects In Mombasa'). MUST be a 100% complete grammatical English sentence, plain text only. Max 65 characters.",
          "subtitle": "High-context 1st-person sentence in natural sentence case ending with a full-stop (e.g. 'We allocated Sh3.2 Billion connecting 33,000 households.'). MUST include specific concrete facts, figures, shillings, or job numbers. NEVER output generic filler or Title Cased words. Max 65 characters.",
          "detail": "Opening 1st-person line (e.g. 'Let me tell you, my friend, let me brief you on our ground work here:'), followed by 3 to 4 IN-DEPTH bullet points starting with '• '. Each bullet point MUST be 2-3 sentences long, providing thorough context, specific shilling figures or job numbers, economic impact, and future steps under BETA in President Ruto's authentic voice ('My friend', 'Bottom-up', 'We must be honest'). Separate each bullet point with double line breaks (\\n\\n). NEVER output a wall of text. Max 950 characters.",
          "date": "Project date (e.g. 'Jul 17, 2024' or 'Jul 17'). You MUST extract and preserve the project date if available in the search snippet. Do NOT omit it, so the calendar badge displays properly."
        }
      ]
    }

    FEW-SHOT EXAMPLES OF HIGH QUALITY OUTPUT:
    Example 1:
    {
      "title": "I Inspected The Power Grid Project In Wajir",
      "subtitle": "We allocated Sh3.2 Billion connecting 33,000 households."
    }
    Example 2:
    {
      "title": "I Launched The Blue Economy Projects In Mombasa",
      "subtitle": "We are creating 5,000 jobs for our youth along the coast."
    }
    
    Rules:
    - Persona: Authentic, direct, accountable, and deliberate. You MUST use your unique speech patterns (e.g. "My friend", "Let me tell you", "The plan", "Bottom-up").
    - Subtitle Context: Subtitles MUST provide rich, specific, quantifiable context (shillings, job counts, family beneficiaries, exact milestones). Vague statements like 'We completed plans' or Title-Cased words ('We Enjoy 1000s Of...') are STRICTLY FORBIDDEN.
    - Grammar & Punctuation: Title MUST be a complete active 1st-person sentence starting capitalized. Subtitle MUST be in natural sentence case starting capitalized and ending with a full-stop (.).
    - Strictly 1st-person ONLY ("I", "We"). Never 3rd person. Generic "AI politician" or sterile corporate language is STRICTLY FORBIDDEN.
    - Write the response entirely in: #{String.upcase(language)}.
    
    Search Results:
    #{minimized_results}
    """

    result = case PresidentialBridge.AIProxy.call_groq_round_robin(prompt) do
      {:ok, r} -> {:ok, r}
      _ ->
        Logger.info("[ProjectSearch] Groq failed. Falling back to Gemini...")
        PresidentialBridge.AIProxy.call_gemini_round_robin(prompt)
    end

    case result do
      {:ok, response_str} -> 
        cleaned = String.replace(response_str, ~r/```(?:json)?|```/, "") |> String.trim()
        case Jason.decode(cleaned) do
          {:ok, %{"intro" => intro, "projects" => projects}} ->
            cleaned_projects = Enum.map(projects, fn p ->
              p
              |> Map.update("title", "", fn t -> String.replace(t || "", ~r/\s*(\.|\.\.\.|\.\.\.\.)\s*$/, "") end)
              |> Map.update("subtitle", "", fn s -> String.replace(s || "", ~r/\s*(\.|\.\.\.|\.\.\.\.)\s*$/, "") end)
            end)
            {intro, cleaned_projects}
          _ ->
            extract_hardcoded_projects(serper_json_str, user_name)
        end
      _ -> 
        extract_hardcoded_projects(serper_json_str, user_name)
    end
  end

  defp extract_hardcoded_projects(serper_json_str, user_name) do
    Logger.info("[ProjectSearch] AI generation failed or rate limited. Using raw Serper data fallback.")
    case Jason.decode(serper_json_str) do
      {:ok, json} ->
        organic = json["organic"] || []
        
        if length(organic) > 0 do
          projects = 
            organic
            |> Enum.map(fn item ->
              raw_title = (item["title"] || "Development Project")
                          |> String.replace(~r/^(Category Archives|Archive for|Home|Projects|Search Results for):\s*/i, "")
                          |> String.replace(~r/\s*-\s*.*$/, "")
                          |> String.replace(~r/\s*(\.|\.\.\.|\.\.\.\.)\s*$/, "")
                          |> String.trim()

              title = raw_title
                      |> String.replace(~r/President William Ruto's/i, "My")
                      |> String.replace(~r/President Ruto's/i, "My")
                      |> String.replace(~r/William Ruto's/i, "My")
                      |> String.replace(~r/Ruto's/i, "My")
                      |> String.replace(~r/\bi's\b/i, "my")
                      |> String.replace(~r/Governor Patrick Ole Ntutu/i, "My Local Partners")
                      |> String.replace(~r/Governor [A-Z][a-z]+/i, "County Leadership")
                      |> String.replace(~r/Projects commissioned by/i, "I Commissioned Projects Including")
                      |> String.replace(~r/President William Ruto/i, "I")
                      |> String.replace(~r/President Ruto/i, "I")

              clean_title = if String.length(title) > 65 do
                sliced = String.slice(title, 0, 65)
                case Regex.run(~r/^(.*)\s\S*$/, sliced) do
                  [_, up_to_last_space] -> up_to_last_space
                  _ -> sliced
                end
              else
                title
              end
              |> String.replace(~r/\s*(about|to|for|with|on|at|by|from|in|of|into|and|or|but|as|that|a|an|the)\s*$/i, "")
              
              raw_snippet = (item["snippet"] || "")
                            |> String.replace(~r/^(Category Archives|Archive for|Home|Projects):\s*/i, "")
                            |> String.trim()

              subtitle_clean = raw_snippet
                               |> String.replace(~r/President William Ruto's/i, "My")
                               |> String.replace(~r/President Ruto's/i, "My")
                               |> String.replace(~r/William Ruto's/i, "My")
                               |> String.replace(~r/Ruto's/i, "My")
                               |> String.replace(~r/\bi's\b/i, "my")
                               |> String.replace(~r/Governor Patrick Ole Ntutu/i, "my administration in partnership with local leaders")
                               |> String.replace(~r/Governor [A-Z][a-z]+/i, "county leadership")

              clean_subtitle = if String.length(subtitle_clean) > 65 do
                sliced = String.slice(subtitle_clean, 0, 65)
                case Regex.run(~r/^(.*)\s\S*$/, sliced) do
                  [_, up_to_last_space] -> up_to_last_space
                  _ -> sliced
                end
              else
                subtitle_clean
              end
              |> String.replace(~r/\s*(about|to|for|with|on|at|by|from|in|of|into|and|or|but|as|that|a|an|the)\s*$/i, "")
              |> String.replace(~r/\s*(\.|\.\.\.|\.\.\.\.)\s*$/, "")
              
              detail_clean = raw_snippet
                             |> String.replace(~r/\s*(\.|\.\.\.|\.\.\.\.)\s*$/, "")
                             |> String.replace(~r/Governor Patrick Ole Ntutu/i, "my administration in partnership with local leadership")
              
              detail_full = """
              Let me tell you, my friend, let me brief you on our ground work here:
              
              • We are committed to delivering impact across Kenya. #{detail_clean}. 
              
              • Through our Bottom-Up Economic Transformation Agenda, we are accelerating infrastructure, schools, and markets to transform lives directly. This project is a testament to our ongoing focus on grassroot development.
              
              • We will continue working with local leadership to ensure that every shilling allocated benefits the people. My friend, we are executing our plan.
              """ |> String.trim()

              %{
                "headline" => clean_title,
                "subtitle" => clean_subtitle,
                "short_headline" => clean_title,
                "short_subtitle" => clean_subtitle,
                "detail" => detail_full,
                "date" => Date.utc_today() |> Calendar.strftime("%A, %-d %B %Y")
              }
            end)

          {"#{user_name}, here are the projects I found for your location:", projects}
        else
          {"I'm sorry #{user_name}, I couldn't find any specific projects for your location right now. We are continuously expanding.", []}
        end

      _ ->
        {"I'm sorry #{user_name}, I couldn't fetch the projects for your location right now. Please try again later.", []}
    end
  end
end
