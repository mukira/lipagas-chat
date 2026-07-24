import os
import requests

api_key = os.environ.get('GEMINI_KEY_1')
resp = requests.get(f"https://generativelanguage.googleapis.com/v1beta/models?key={api_key}")
print([m['name'] for m in resp.json().get('models', []) if 'gemini' in m['name']])
