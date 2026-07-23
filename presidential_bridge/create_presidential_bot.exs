Mix.install([
  {:httpoison, "~> 2.0"},
  {:jason, "~> 1.4"}
])

api_key = "WCGihbMj8KWUS2jI9jBF44-BktZtrm4Vqz7XSsyT6as"
workspace_id = "cmq5o6k9z00001nmd5apo7dr4"
url = "https://builder.lipagas.co/api/v1/typebots"

payload = %{
  "workspaceId" => workspace_id,
  "name" => "Presidential AI Loop",
  "typebot" => %{
    "name" => "Presidential AI Loop",
    "version" => "6",
    "variables" => [
      %{"id" => "var_user_name", "name" => "user_name"},
      %{"id" => "var_phone_number", "name" => "phone_number"},
      %{"id" => "var_latest_news", "name" => "latest_news"},
      %{"id" => "var_user_input", "name" => "user_input"},
      %{"id" => "var_bot_response", "name" => "bot_response"}
    ],
    "events" => [
      %{
        "id" => "start_event",
        "type": "start",
        "graphCoordinates" => %{"x" => 0, "y" => 0},
        "outgoingEdgeId" => "edge_start_to_welcome"
      }
    ],
    "groups" => [
      %{
        "id" => "group_welcome",
        "title" => "Welcome Loop",
        "graphCoordinates" => %{"x" => 300, "y" => 0},
        "blocks" => [
          %{
            "id" => "block_greet",
            "type" => "text",
            "content" => %{
              "richText" => [
                %{"type" => "p", "children" => [%{"text" => "Welcome to the Presidential channel, {{user_name}}."}]}
              ]
            }
          },
          %{
            "id" => "block_input",
            "type" => "text input",
            "options" => %{"variableId" => "var_user_input"},
            "outgoingEdgeId" => "edge_input_to_proxy"
          }
        ]
      },
      %{
        "id" => "group_proxy",
        "title" => "AI Proxy",
        "graphCoordinates" => %{"x" => 700, "y" => 0},
        "blocks" => [
          %{
            "id" => "block_http",
            "type" => "http request",
            "options" => %{
              "webhook" => %{
                "url" => "https://flow.lipagas.co/api/ai/proxy",
                "method" => "POST",
                "headers" => [%{"key" => "Content-Type", "value" => "application/json"}],
                "body" => "{\"user_name\":\"{{user_name}}\", \"phone\":\"{{phone_number}}\", \"news\":\"{{latest_news}}\", \"message\":\"{{user_input}}\"}"
              },
              "responseVariableMapping" => [
                %{"bodyPath" => "reply", "variableId" => "var_bot_response"}
              ]
            }
          },
          %{
            "id" => "block_reply",
            "type" => "text",
            "content" => %{
              "richText" => [
                %{"type" => "p", "children" => [%{"text" => "{{bot_response}}"}]}
              ]
            },
            "outgoingEdgeId" => "edge_reply_to_input"
          }
        ]
      }
    ],
    "edges" => [
      %{
        "id" => "edge_start_to_welcome",
        "from" => %{"eventId" => "start_event"},
        "to" => %{"groupId" => "group_welcome"}
      },
      %{
        "id" => "edge_input_to_proxy",
        "from" => %{"blockId" => "block_input"},
        "to" => %{"groupId" => "group_proxy"}
      },
      %{
        "id" => "edge_reply_to_input",
        "from" => %{"blockId" => "block_reply"},
        "to" => %{"groupId" => "group_welcome", "blockId" => "block_input"}
      }
    ]
  }
}

headers = [
  {"Authorization", "Bearer #{api_key}"},
  {"Content-Type", "application/json"}
]

case HTTPoison.post(url, Jason.encode!(payload), headers) do
  {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
    IO.puts("Successfully created Typebot!")
    IO.inspect(Jason.decode!(body)["typebot"]["id"])
  {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
    IO.puts("Failed with status #{status}")
    IO.inspect(Jason.decode!(body))
  {:error, %HTTPoison.Error{reason: reason}} ->
    IO.inspect(reason)
end
