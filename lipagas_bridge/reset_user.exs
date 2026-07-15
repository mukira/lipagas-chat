defmodule TesterReset do
  def run(phone) do
    case LipagasBridge.Chatwoot.search_contact(phone) do
      {:ok, contact} when not is_nil(contact) ->
        contact_id = contact["id"]
        IO.puts("Found contact ID: #{contact_id}")

        url = "#{LipagasBridge.Config.chatwoot_url()}/api/v1/accounts/#{LipagasBridge.Config.chatwoot_account_id()}/contacts/#{contact_id}"
        token = LipagasBridge.Config.chatwoot_token()
        
        cmd = "curl -s -X DELETE '#{url}' -H 'api_access_token: #{token}'"
        {output, status} = System.cmd("sh", ["-c", cmd])
        IO.puts("Contact deleted. Status: #{status}")
        IO.puts("Response: #{output}")

      _ ->
        IO.puts("Contact not found.")
    end
  end
end

TesterReset.run("0723539760")
