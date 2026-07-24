import os
import redis

password = os.environ.get('REDIS_PASSWORD')
r = redis.Redis(host='unified-deployment-redis-1', port=6379, password=password, decode_responses=True)

keys = r.keys('presidential_bridge_translation:*')
if keys:
    r.delete(*keys)
    print(f"Deleted {len(keys)} keys")
else:
    print("No keys found")
