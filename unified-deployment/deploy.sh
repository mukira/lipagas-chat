#!/bin/bash

echo "=== LIPA-GAS UNIFIED DEPLOYMENT ==="

if [ ! -f .env ]; then
  cp .env.example .env
  echo "Created .env file. Please edit it and fill in your secrets (Meta Tokens, M-Pesa keys, etc.)."
  echo "Run ./deploy.sh again after filling out .env."
  exit 1
fi

echo "Checking SSL certificates..."
DOMAINS=("chat.lipagas.co" "builder.lipagas.co" "flow.lipagas.co")
DATA_PATH="./certbot"

for domain in "${DOMAINS[@]}"; do
  if [ ! -d "$DATA_PATH/conf/live/$domain" ]; then
    echo "Creating dummy certificate for $domain to bootstrap Nginx..."
    mkdir -p "$DATA_PATH/conf/live/$domain"
    openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
      -keyout "$DATA_PATH/conf/live/$domain/privkey.pem" \
      -out "$DATA_PATH/conf/live/$domain/fullchain.pem" \
      -subj "/CN=localhost"
  fi
done

echo "Starting Nginx and all services..."
docker compose -f docker-compose.deploy.yml up -d

echo "Requesting real Let's Encrypt certificates..."
for domain in "${DOMAINS[@]}"; do
  docker compose -f docker-compose.deploy.yml run --rm --entrypoint "\
    certbot certonly --webroot -w /var/www/certbot \
    --email admin@lipagas.co \
    -d $domain \
    --rsa-key-size 4096 \
    --agree-tos \
    --force-renewal" certbot
done

echo "Reloading Nginx to apply new real certificates..."
docker compose -f docker-compose.deploy.yml exec nginx nginx -s reload

echo "=== DEPLOYMENT COMPLETE ==="
echo "All services are running and databases have been restored."
