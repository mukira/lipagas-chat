import os
import requests
api_key = os.environ.get('GEMINI_KEY_1')

for m in ["gemini-3.5-flash", "gemini-3.5-flash-lite", "gemini-flash-latest"]:
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{m}:generateContent?key={api_key}"
    resp = requests.post(url, json={
        "contents": [{"parts": [{"text": "Hello"}]}]
    })
    print(f"{m}: {resp.status_code}")
    if resp.status_code != 200:
        print(resp.text)
