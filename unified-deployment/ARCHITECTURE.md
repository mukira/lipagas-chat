# LipaGas Unified System Architecture

This document provides a highly detailed, no-bullshit breakdown of how the LipaGas ecosystem is wired together. It covers the data flow, the Docker container topology, how the internal components communicate, and how the stack is optimized to run on an **836 MiB RAM VM** (see [VM_OPTIMIZATION_REPORT.md](./VM_OPTIMIZATION_REPORT.md) for the full optimization & benchmark report).

## 1. High-Level Data Flow

The entire system relies on an Nginx reverse proxy that routes traffic based on domains to 3 main applications:
- **Chatwoot / Influence Dashboard** (`chat.lipagas.co`, `chat.hisia.app`)
- **Typebot** (`flow.lipagas.co`, `flow.hisia.app`, `builder.lipagas.co`, `builder.hisia.app`)
- **LipaGas Bridge** (`flow.lipagas.co/meta-webhook`, `flow.hisia.app/meta-webhook`)

### The WhatsApp Webhook Journey (End-to-End)
When a user sends a message on WhatsApp:
1. **Meta (WhatsApp)** fires an HTTP POST request to your configured webhook URL: `https://flow.lipagas.co/meta-webhook`.
2. **Nginx** receives this request on port `443` (SSL).
3. **Nginx** checks its routing table and sees that `flow.lipagas.co/meta-webhook` is designated for the LipaGas Bridge.
4. **Nginx** proxies the request to `http://lipagas-bridge:4000/meta-webhook`.
5. **LipaGas Bridge** (Elixir application) processes the incoming JSON payload.
6. The Bridge simultaneously sends the payload over the internal Docker network to:
   - **Typebot Viewer** (`http://typebot-viewer:3000`) to generate automated conversational responses.
   - **Chatwoot** (`http://chatwoot:3000`) to log the conversation so human agents can see the chat in the dashboard.
7. **Typebot** responds with the next flow step, and the Bridge uses the Meta Graph API to send the text/interactive message back to the WhatsApp user.

## 2. Docker Compose Topology (`docker-compose.deploy.yml`)

### Core Services (Active 24/7)
- **postgres (`pgvector/pgvector:pg16`):** Central storage containing two isolated databases (`chatwoot_production` and `typebot`), tuned for low memory (`shared_buffers=64MB`, `max_connections=40`).
- **redis (`redis:alpine`):** Authenticated in-memory queue (`--maxmemory 64mb --maxmemory-policy allkeys-lru`) used by Chatwoot, Sidekiq, and the LipaGas Bridge.
- **chatwoot + Embedded Sidekiq (`chatwoot/chatwoot:v4.17.0`):** The main Rails server exposing the human-agent dashboard and REST APIs on port 3000, with **Sidekiq 7.3 embedded inside the Puma process** via `99_embedded_sidekiq.rb` (`EMBED_SIDEKIQ=true`, `SIDEKIQ_CONCURRENCY=2`) to save ~430 MiB of RAM.
- **typebot-viewer:** The execution engine for live chat flows (`flow.lipagas.co` / `flow.hisia.app`).
- **lipagas-bridge:** Custom Elixir application acting as middleware between Meta WhatsApp, M-Pesa Daraja, Stronpower, Chatwoot, and Typebot.
- **nginx:** Reverse proxy with dynamic Docker DNS resolution (`127.0.0.11`) and Let's Encrypt SSL certificates for both `*.lipagas.co` and `*.hisia.app`.
- **certbot:** Sidecar container that wakes up every 12 hours to renew Let's Encrypt SSL certificates.

### Optional / On-Demand Services (`profiles: ["extras"]`)
- **typebot-builder**, **joywo-bridge**, **presidential-bridge**, and standalone **sidekiq** are assigned to `profiles: ["extras"]` and can be started anytime with:
  ```bash
  sudo docker compose -f docker-compose.deploy.yml --profile extras up -d <service>
  ```

## 3. Database Initialization & Migration Strategy

When the unified stack is launched for the first time, the `postgres` container executes `/docker-entrypoint-initdb.d/00-init.sh`:
1. Initializes the `chatwoot_production` and `typebot` databases and roles.
2. Restores `01-chatwoot.dump.gz` (which includes all 41 Chatwoot v4.17.0 schema migrations) and runs `03-migrations.sql` idempotently.
3. Restores `02-typebot.dump.gz` into `typebot`.

## 4. Verification & Health Checks

Run `./verify_stack.sh` at any time to verify system memory/zram status, Docker container health, database integrity, SSL certificates, and live endpoint latencies.
