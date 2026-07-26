defmodule PresidentialBridge.ProjectPaginator do
  require Logger

  require Logger

  def cache_projects(intro_text, projects, phone, location) do
    # Fetch Presidential X Pool
    images_pool =
      case Redix.command(:redix, ["GET", "presidential_images"]) do
        {:ok, val} when is_binary(val) ->
          case Jason.decode(val) do
            {:ok, list} when is_list(list) -> Enum.shuffle(list)
            _ -> []
          end
        _ -> []
      end

    # Fetch Serper Images
    serper_images = fetch_serper_images(location)

    parsed_projects = Enum.reduce(projects, {[], images_pool}, fn item, {projects_acc, current_pool} ->
      headline = item["title"] || item["name"] || "Project"
      subtitle = item["subtitle"] || ""
      detail = item["detail"] || ""
      link = item["link"] || ""

      # Apply strict truncation to avoid overlay clipping
      clean_headline = String.slice(headline, 0, 40)
      clean_subtitle = String.slice(subtitle, 0, 60)

      # Determine best image using Priority Waterfall
      # Priority 1: Serper /images (if we can find a matching one)
      # Priority 2: og:image scrape (if link is available)
      # Priority 3: X Pool fallback
      img_url = find_best_image(clean_headline, link, serper_images)
      
      {final_img_url, new_pool} = if is_nil(img_url) and length(current_pool) > 0 do
        fallback_img = Enum.at(current_pool, 0)
        {fallback_img["url"], List.delete_at(current_pool, 0)}
      else
        {img_url || "https://lipagas.com/static/presidential_fallback.png", current_pool}
      end

      queue_item = %{
        "headline" => headline,
        "subtitle" => subtitle,
        "short_headline" => clean_headline,
        "short_subtitle" => clean_subtitle,
        "detail" => detail,
        "image_url" => final_img_url,
        "date" => item["date"] || (Date.utc_today() |> Calendar.strftime("%A, %-d %B %Y")),
        "button_payload" => "project_read_more_#{length(projects_acc)}"
      }

      {projects_acc ++ [queue_item], new_pool}
    end)
    |> elem(0)

    # Save to Redis
    queue_data = %{
      "intro" => intro_text,
      "projects" => parsed_projects
    }
    
    Redix.command(:redix, ["SET", "projects_queue:#{phone}", Jason.encode!(queue_data), "EX", "3600"])
    Redix.command(:redix, ["SET", "projects_index:#{phone}", "0", "EX", "3600"])
    
    length(parsed_projects)
  end

  defp fetch_serper_images(location) do
    url = "https://google.serper.dev/images"
    api_key = System.get_env("SERPER_API_KEY") || ""
    headers = [{"X-API-KEY", api_key}]
    query = "President Ruto projects #{location} Kenya"
    
    case PresidentialBridge.HTTP.post_json(url, %{q: query, gl: "ke"}, headers) do
      {:ok, %{status: 200, body: resp_body}} ->
        if is_map(resp_body) do
          images = resp_body["images"] || []
          # Extract just the image URLs
          Enum.map(images, fn img -> img["imageUrl"] end)
        else
          []
        end
      _ -> []
    end
  end

  defp find_best_image(_headline, link, serper_images) do
    serper_img = if length(serper_images) > 0, do: Enum.random(serper_images), else: nil
    
    if serper_img do
      serper_img
    else
      scrape_og_image(link)
    end
  end

  defp scrape_og_image(link) when is_binary(link) and link != "" do
    try do
      case PresidentialBridge.HTTP.get(link, [{"User-Agent", "Mozilla/5.0"}]) do
        {:ok, %{status: 200, body: html}} when is_binary(html) ->
          case Regex.run(~r/content=["']([^"']+)["'][^>]*property=["']og:image["']/i, html) do
            [_, url] -> url
            _ ->
              case Regex.run(~r/property=["']og:image["'][^>]*content=["']([^"']+)["']/i, html) do
                [_, url] -> url
                _ -> nil
              end
          end
        _ -> nil
      end
    rescue
      _ -> nil
    end
  end
  defp scrape_og_image(_), do: nil
end
