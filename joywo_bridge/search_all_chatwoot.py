import requests
import json

api_key = "JtE4mN71wM2H2F3P33Q6zUo4"
headers = {"api_access_token": api_key}
phone_to_find = "254112250250"

url = "http://127.0.0.1:3000/api/v1/accounts/1/contacts"
found = False

for page in range(1, 10):
    resp = requests.get(f"{url}?page={page}", headers=headers)
    data = resp.json()
    contacts = data.get("payload", [])
    if not contacts:
        break
        
    for contact in contacts:
        if phone_to_find in str(contact.get("phone_number", "")):
            print(f"Found Contact ID: {contact.get('id')}")
            print(f"Name: {contact.get('name')}")
            print(f"Phone: {contact.get('phone_number')}")
            print(f"Custom Attributes: {json.dumps(contact.get('custom_attributes', {}), indent=2)}")
            found = True
            break
    if found:
        break

if not found:
    print("Contact still not found in all pages.")
