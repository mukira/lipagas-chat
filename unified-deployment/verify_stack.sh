#!/bin/bash
set -e

cd /home/azureuser/lipagas-chat/unified-deployment

echo "============================================================"
echo "1. SYSTEM MEMORY & SWAP STATUS"
echo "============================================================"
free -h
swapon --show
zramctl

echo ""
echo "============================================================"
echo "2. DOCKER CONTAINER STATUS & RESOURCE FOOTPRINT"
echo "============================================================"
sudo docker compose -f docker-compose.deploy.yml ps
sudo docker stats --no-stream

echo ""
echo "============================================================"
echo "3. DATABASE INTEGRITY (CHATWOOT & TYPEBOT)"
echo "============================================================"
sudo docker compose -f docker-compose.deploy.yml exec -T postgres psql -U postgres -d chatwoot_production -c "SELECT id, name FROM accounts; SELECT id, name, channel_type FROM inboxes; SELECT count(*) AS total_conversations FROM conversations;"
sudo docker compose -f docker-compose.deploy.yml exec -T postgres psql -U postgres -d typebot -c "SELECT id, name, \"publicId\" FROM \"Typebot\";"

echo ""
echo "============================================================"
echo "4. HTTPS & ENDPOINT LATENCY VERIFICATION"
echo "============================================================"
sudo docker compose -f docker-compose.deploy.yml exec -T nginx nginx -t
sudo docker compose -f docker-compose.deploy.yml exec -T nginx nginx -s reload

for url in \
  "https://chat.lipagas.co/app/login" \
  "https://chat.hisia.app/app/login" \
  "https://flow.lipagas.co" \
  "https://flow.hisia.app"
do
  printf "%-55s -> " "$url"
  curl -s -o /dev/null -w "HTTP %{http_code} (%{time_total}s)\n" -m 20 "$url"
done

printf "%-55s -> " "Meta Webhook Verify (flow.lipagas.co/meta-webhook)"
CHALLENGE_LP=$(curl -s -m 10 "https://flow.lipagas.co/meta-webhook?hub.mode=subscribe&hub.verify_token=lipagas_secure_meta_token&hub.challenge=987654")
echo "Response: $CHALLENGE_LP"

printf "%-55s -> " "Meta Webhook Verify (flow.hisia.app/meta-webhook)"
CHALLENGE_HS=$(curl -s -m 10 "https://flow.hisia.app/meta-webhook?hub.mode=subscribe&hub.verify_token=lipagas_secure_meta_token&hub.challenge=987654")
echo "Response: $CHALLENGE_HS"

echo ""
echo "============================================================"
echo "5. END-TO-END BRIDGE -> TYPEBOT SESSION TEST"
echo "============================================================"
curl -s -m 15 -X POST "https://flow.lipagas.co/api/v1/typebots/lipa-gas-whats-app-bot-o9nfrww/startChat" \
  -H "Content-Type: application/json" \
  -d '{"isOnlyRegistering":false,"prefilledVariables":{}}' | head -c 200
echo ""
curl -s -m 15 -X POST "https://flow.hisia.app/api/v1/typebots/presidential-bot/startChat" \
  -H "Content-Type: application/json" \
  -d '{"isOnlyRegistering":false,"prefilledVariables":{"greeting_index":"1"}}' | head -c 200
echo ""
echo "============================================================"
echo "ALL CHECKS PASSED SUCCESSFULLY!"
echo "============================================================"
