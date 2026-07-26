import requests
import time

base = {
    "event": "message_created",
    "message_type": "incoming",
    "sender": {"phone_number": "+254723539760", "name": "Mukira"},
    "conversation": {"id": 32, "inbox_id": 10},
    "inbox": {"id": 10},
    "account": {"id": 1}
}

def send_msg(msg):
    p = base.copy()
    p["content"] = msg
    requests.post("http://localhost:4002/webhook", json=p)
    time.sleep(2)

print("Sending English")
send_msg("🇬🇧 English")

print("Sending Ask AI")
send_msg("❓ Ask AI")

print("Sending question")
send_msg("what is the size of kenya ?")
