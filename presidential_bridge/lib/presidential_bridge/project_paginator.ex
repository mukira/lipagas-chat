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

    # Concurrently fetch serper & og images per project
    projects_with_images = Task.async_stream(projects, fn item ->
      headline = item["title"] || item["name"] || "Project"
      clean_headline = String.slice(headline, 0, 40)
      link = item["link"] || ""
      serper = fetch_serper_images(clean_headline, location)
      og = scrape_og_image(link)
      {item, serper, og}
    end, max_concurrency: 5, timeout: 15_000)
    |> Enum.map(fn {:ok, res} -> res; _ -> nil end)
    |> Enum.reject(&is_nil/1)

    parsed_projects = Enum.reduce(projects_with_images, {[], images_pool}, fn {item, serper, og}, {projects_acc, current_pool} ->
      headline = item["title"] || item["name"] || "Project"
      subtitle = item["subtitle"] || ""
      detail = item["detail"] || ""

      # Apply strict truncation to avoid overlay clipping
      clean_headline = String.slice(headline, 0, 40)
      clean_subtitle = String.slice(subtitle, 0, 60)

      # Build image list up to 3
      images = (serper ++ List.wrap(og)) |> Enum.uniq() |> Enum.reject(&is_nil/1) |> Enum.reject(&(&1 == ""))
      
      {final_images, new_pool} = fill_images(images, 3, current_pool)

      queue_item = %{
        "headline" => headline,
        "subtitle" => subtitle,
        "short_headline" => clean_headline,
        "short_subtitle" => clean_subtitle,
        "detail" => detail,
        "image_urls" => final_images,
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

  defp fetch_serper_images(project_title, location) do
    url = "https://google.serper.dev/images"
    api_key = System.get_env("SERPER_API_KEY") || ""
    headers = [{"X-API-KEY", api_key}]
    query = "President Ruto #{project_title} in #{location} Kenya"
    
    case PresidentialBridge.HTTP.post_json(url, %{q: query, gl: "ke"}, headers) do
      {:ok, %{status: 200, body: resp_body}} ->
        if is_map(resp_body) do
          images = resp_body["images"] || []
          # Extract just the image URLs (take up to 3)
          Enum.map(images, fn img -> img["imageUrl"] end) |> Enum.take(3)
        else
          []
        end
      _ -> []
    end
  end

  defp fill_images(images, max_count, pool) do
    current_len = length(images)
    if current_len >= max_count do
      {Enum.take(images, max_count), pool}
    else
      needed = max_count - current_len
      fallback_imgs = Enum.take(pool, needed) |> Enum.map(fn item ->
        if is_map(item), do: item["url"], else: nil
      end) |> Enum.reject(&is_nil/1)
      
      new_pool = Enum.drop(pool, needed)
      
      final_imgs = images ++ fallback_imgs
      final_imgs = if length(final_imgs) == 0 do
        ["https://lipagas.com/static/presidential_fallback.png"]
      else
        final_imgs
      end
      {final_imgs, new_pool}
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
