import os
import requests

key = os.environ.get("GEMINI_API_KEY")
if not key:
    with open(".env", "r") as f:
        for line in f:
            if line.startswith("GEMINI_API_KEY="):
                key = line.strip().split("=")[1]

url = f"https://generativelanguage.googleapis.com/v1beta/models?key={key}"
r = requests.get(url)
models = [m["name"] for m in r.json().get("models", [])]

working = []
for model in models:
    gen_url = f"https://generativelanguage.googleapis.com/v1beta/{model}:generateContent?key={key}"
    resp = requests.post(gen_url, json={"contents":[{"parts":[{"text":"Hi"}]}]})
    print(f"{model}: {resp.status_code}")
    if resp.status_code == 200:
        working.append(model)
        
print("WORKING MODELS:", working)
