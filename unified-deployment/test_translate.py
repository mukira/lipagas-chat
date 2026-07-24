import os
import requests
import json

api_key = os.environ.get('GEMINI_KEY_1')
url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:generateContent?key={api_key}"

prompt = """
You are a highly accurate translator specializing in Kenyan languages.
Translate the following English text to Kalenjin.
Return ONLY the translated text, nothing else. Do NOT include quotes, explanations, or any other text.
Text: Jambo, Mukira. Kila asubuhi huamka nikiwaza jambo moja...
"""

resp = requests.post(url, json={
    "contents": [{"parts": [{"text": prompt}]}],
    "generationConfig": {"temperature": 0.0}
})

print(f"Status: {resp.status_code}")
if resp.status_code == 200:
    try:
        data = resp.json()
        print(data['candidates'][0]['content']['parts'][0]['text'])
    except Exception as e:
        print("Parsing error:", e)
        print(resp.text)
else:
    print(resp.text)
