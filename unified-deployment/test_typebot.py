import requests

url = "https://bot.lipagas.com/api/v1/typebots/presidential-bridge/startChat"
r = requests.post(url, json={"isOnlyRegistering": False})
print(r.json())
