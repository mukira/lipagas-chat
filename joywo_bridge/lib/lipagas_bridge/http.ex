defmodule LipagasBridge.HTTP do
  @moduledoc """
  Lightweight HTTP client built on Mint.
  Works on OTP 24 (unlike Finch 0.16+ which requires OTP 25).
  """

  @timeout 30_000

  # ─── GET request ──────────────────────────────────────────────────────

  def get(url, headers \\ []) do
    do_request(:get, url, headers, "")
  end

  # ─── POST request with JSON body ──────────────────────────────────────

  def post_json(url, body_map, headers \\ []) do
    json_body    = Jason.encode!(body_map)
    all_headers  = [{"content-type", "application/json"}, {"content-length", byte_size(json_body)} | headers]
    do_request(:post, url, all_headers, json_body)
  end

  # ─── PUT request with JSON body ───────────────────────────────────────

  def put_json(url, body_map, headers \\ []) do
    json_body    = Jason.encode!(body_map)
    all_headers  = [{"content-type", "application/json"}, {"content-length", byte_size(json_body)} | headers]
    do_request(:put, url, all_headers, json_body)
  end

  # ─── Core request ─────────────────────────────────────────────────────

  defp do_request(method, url, headers, body, redirect_count \\ 0) when redirect_count < 5 do
    uri     = URI.parse(url)
    scheme  = String.to_atom(uri.scheme)
    host    = uri.host
    port    = uri.port || (if uri.scheme == "https", do: 443, else: 80)
    path    = (uri.path || "/") <> if(uri.query, do: "?#{uri.query}", else: "")

    mint_headers = Enum.map(headers, fn {k, v} -> {to_string(k), to_string(v)} end)

    with {:ok, conn}        <- Mint.HTTP.connect(scheme, host, port, [timeout: @timeout]),
         {:ok, conn, _ref}  <- Mint.HTTP.request(conn, method_str(method), path, mint_headers, body),
         {:ok, status, resp_headers, resp_body} <- receive_response(conn, @timeout) do
      Mint.HTTP.close(conn)

      # Follow 301/302 redirects automatically
      if status in [301, 302, 307, 308] do
        location = resp_headers
          |> Enum.find(fn {k, _} -> String.downcase(k) == "location" end)
          |> case do
            {_, loc} -> loc
            nil -> nil
          end
        if location do
          do_request(method, location, headers, body, redirect_count + 1)
        else
          {:error, "Redirect with no Location header"}
        end
      else
        parsed_body = decode_body(resp_body, resp_headers)
        {:ok, %{status: status, headers: resp_headers, body: parsed_body}}
      end
    else
      {:error, conn, reason} when is_map(conn) ->
        Mint.HTTP.close(conn)
        {:error, inspect(reason)}
      {:error, reason} ->
        {:error, inspect(reason)}
    end
  rescue
    e -> {:error, inspect(e)}
  end

  defp do_request(_method, _url, _headers, _body, _count), do: {:error, "Too many redirects"}


  # ─── Receive all response chunks ──────────────────────────────────────

  defp receive_response(conn, timeout, status \\ nil, headers \\ [], body \\ "") do
    receive do
      message ->
        case Mint.HTTP.stream(conn, message) do
          {:ok, conn, responses} ->
            {status, headers, body} = process_responses(responses, status, headers, body)
            if done?(responses) do
              {:ok, status, headers, body}
            else
              receive_response(conn, timeout, status, headers, body)
            end
          {:error, _conn, reason, _responses} ->
            {:error, conn, reason}
          :unknown ->
            receive_response(conn, timeout, status, headers, body)
        end
    after
      timeout -> {:error, conn, :timeout}
    end
  end

  defp process_responses(responses, status, headers, body) do
    Enum.reduce(responses, {status, headers, body}, fn
      {:status, _ref, s}, {_, h, b}  -> {s, h, b}
      {:headers, _ref, hs}, {s, _, b}-> {s, hs, b}
      {:data, _ref, d}, {s, h, b}    -> {s, h, b <> d}
      _, acc -> acc
    end)
  end

  defp done?(responses) do
    Enum.any?(responses, fn
      {:done, _} -> true
      _          -> false
    end)
  end

  defp decode_body(body, _headers) do
    case Jason.decode(body) do
      {:ok, parsed} when is_map(parsed) or is_list(parsed) -> parsed
      _ -> body
    end
  end

  defp method_str(:get),    do: "GET"
  defp method_str(:post),   do: "POST"
  defp method_str(:put),    do: "PUT"
  defp method_str(:delete), do: "DELETE"
end
