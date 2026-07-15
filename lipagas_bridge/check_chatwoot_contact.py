import requests
import json
import os

api_key = "JtE4mN71wM2H2F3P33Q6zUo4"
headers = {"api_access_token": api_key}
phone = "254723539760" # from the logs

# search contact
url = f"http://127.0.0.1:3000/api/v1/accounts/1/contacts/search?q={phone}"
resp = requests.get(url, headers=headers)
data = resp.json()

if data.get("payload"):
    contact = data["payload"][0]
    print(f"Contact Name: {contact.get('name')}")
    print(f"Custom Attributes: {json.dumps(contact.get('custom_attributes', {}), indent=2)}")
else:
    print("Contact not found")
