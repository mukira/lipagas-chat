defmodule PresidentialBridge.ImageOverlay do
  require Logger

  @doc """
  Generates an image overlay and returns the public R2 URL.
  Checks Redis cache first.
  """
  def generate(image_url, headline, subtitle \\ "") do
    # Generate a cache key
    hash = :crypto.hash(:md5, "#{image_url}_#{headline}") |> Base.encode16(case: :lower)
    cache_key = "overlay_v10:#{hash}"
    
    # Check Redis Cache
    case Redix.command(:redix, ["GET", cache_key]) do
      {:ok, url} when is_binary(url) ->
        Logger.info("[ImageOverlay] Cache hit for #{cache_key}")
        url
      _ ->
        Logger.info("[ImageOverlay] Generating new overlay for #{headline}")
        
        # Temp file for output
        output_path = "/tmp/overlay_v10_#{hash}.jpg"
        logo_path = "/app/lib/presidential_bridge/influence_logo-white.png" # Using pre-converted PNG
        
        python_script = "/app/lib/presidential_bridge/image_overlay.py"
        args = [python_script, image_url, headline, subtitle, output_path, logo_path]
        
        case System.cmd("python3", args) do
          {output, 0} ->
            public_url = String.trim(output)
            # We got the URL, save it to Redis for 30 days
            Redix.command(:redix, ["SETEX", cache_key, "2592000", public_url])
            public_url
          {error_msg, code} ->
            Logger.error("[ImageOverlay] Python script failed with code #{code}: #{error_msg}")
            # Fallback to the original image URL if compositing fails
            image_url
        end
    end
  end
end
