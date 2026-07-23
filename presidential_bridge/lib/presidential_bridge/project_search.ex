defmodule PresidentialBridge.ProjectSearch do
  require Logger

  @serper_api_key System.get_env("SERPER_API_KEY") || ""

  @doc """
  Takes a user location string, queries Groq to construct a search query, hits Serper,
  and recurses up to 1 time if no projects are found. Returns the final formatted PR message.
  """
  def search(location, language \\ "english", user_name \\ "Citizen") do
    # 1. First Pass
    query = build_query(location, false)
    results = run_serper(query)

    {final_results, final_query} = 
      if projects_found?(results) do
        {results, query}
      else
        Logger.info("[ProjectSearch] No projects found for #{location}. Recursing to broader region...")
        # 2. Recursive Pass (e.g., Town -> County)
        broader_query = build_query(location, true)
        broader_results = run_serper(broader_query)
        {broader_results, broader_query}
      end

    format_response(final_results, final_query, language, user_name)
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
    # Simple heuristic: if we have organic results, we pretend we found something.
    case Jason.decode(serper_json_str) do
      {:ok, json} -> 
        organic = json["organic"] || []
        length(organic) > 0
      _ -> false
    end
  end

  defp format_response(serper_json_str, query_used, language, user_name) do
    # Fetch internal context to blend in if we want, but Serper is enough.
    prompt = """
    You are William Ruto, the President of Kenya, texting a citizen named #{user_name} on WhatsApp.
    Based on the following Google search results for the query: "#{query_used}", 
    write a highly-personal, direct message to #{user_name} explaining the development projects in their area.
    
    Rules:
    - Persona: Direct, warm, and conversational. Sound exactly like a personal WhatsApp text from the President to #{user_name}. (e.g. "#{user_name}, here's what I'm doing in your area...")
    - Formatting: Do NOT write paragraphs. Give ONLY the raw facts using bullet points: Project Name, Status, Budget (if available).
    - Use WhatsApp bold formatting (e.g., *Project Name*).
    - Use emojis tastefully.
    - If the results are completely empty or irrelevant, politely explain to #{user_name} that you are continuously expanding projects and you've noted their region.
    - Write the response entirely in: #{String.upcase(language)}.
    
    Search Results:
    #{String.slice(serper_json_str, 0, 3000)}
    """

    case PresidentialBridge.AIProxy.call_groq_round_robin(prompt) do
      {:ok, formatted} -> String.trim(formatted)
      _ -> "I'm sorry #{user_name}, I couldn't fetch the projects for your location right now. Please try again later."
    end
  end
end
