defmodule Test do
  def run do
    url = "https://google.serper.dev/news"
    headers = [
      {"X-API-KEY", "437b1209e93d91f3bd678059ef82512cce7dd619"},
      {"Content-Type", "application/json"}
    ]
    payload = %{"q" => "William Ruto latest news today", "gl" => "ke"}
    
    IO.inspect(PresidentialBridge.HTTP.post_json(url, payload, headers))
  end
end

Test.run()
