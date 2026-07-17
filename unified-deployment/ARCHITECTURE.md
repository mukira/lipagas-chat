# LipaGas Unified System Architecture

This document provides a highly detailed, no-bullshit breakdown of how the LipaGas ecosystem is wired together. It covers the data flow, the Docker container topology, and how the internal components communicate.

## 1. High-Level Data Flow

The entire system relies on an Nginx reverse proxy that routes traffic based on domains to 3 main applications:
- **Chatwoot** (`chat.lipagas.co`, `influence.deepintelgroup.com`)
- **Typebot** (`builder.lipagas.co`, `flow.lipagas.co`)
- **LipaGas Bridge** (`flow.lipagas.co/meta-webhook`)

### The WhatsApp Webhook Journey (End-to-End)
When a user sends a message on WhatsApp:
1. **Meta (WhatsApp)** fires an HTTP POST request to your configured webhook URL: `https://flow.lipagas.co/meta-webhook`.
2. **Nginx** receives this request on port `443` (SSL).
3. **Nginx** checks its routing table and sees that `flow.lipagas.co/meta-webhook` is designated for the LipaGas Bridge.
4. **Nginx** proxies the request to `http://lipagas-bridge:4000/meta-webhook`.
5. **LipaGas Bridge** (Elixir application) processes the incoming JSON payload.
6. The Bridge simultaneously sends the payload to:
   - **Typebot** (via its internal API at `typebot-viewer:3000`) to generate automated conversational responses.
   - **Chatwoot** (via its API at `chatwoot:3000`) to log the conversation so human agents can see the chat in the dashboard.
7. **Typebot** responds with the next flow step, and the Bridge uses the Meta Graph API to send the text/interactive message back to the WhatsApp user.

## 2. Docker Compose Topology

The `docker-compose.deploy.yml` completely encapsulates this architecture so it is 100% portable.

### Core Services
- **postgres (16-alpine):** The central nervous system for storage. Contains two distinct databases (`chatwoot_production` and `typebot`) isolated from each other.
- **redis (alpine):** An in-memory queue used by Chatwoot's Sidekiq workers and Typebot for caching real-time sessions.
- **chatwoot (web):** The main Rails server exposing the human-agent dashboard and REST APIs on port 3000.
- **sidekiq (worker):** Chatwoot's background job processor (handles emails, push notifications, and async tasks).
- **typebot-builder:** The visual drag-and-drop dashboard for creating chat flows (exposed at `builder.lipagas.co`).
- **typebot-viewer:** The execution engine for the flows (exposed at `flow.lipagas.co`).
- **lipagas-bridge:** The custom Elixir application that acts as the middleware between Meta, Chatwoot, and Typebot.
- **nginx:** The traffic cop. Routes external domains to internal Docker network addresses.
- **certbot:** A sidecar container that wakes up every 12 hours to renew Let's Encrypt SSL certificates.

## 3. Database Initialization Strategy

When the unified stack is launched on the new VM for the first time, the `postgres` container reads from the `/docker-entrypoint-initdb.d` folder.
It executes `00-create-dbs.sql` to initialize the dual schemas.
Then, it automatically consumes `01-chatwoot.sql` and `02-typebot.sql` to perfectly restore the system state without manual intervention.

## 4. Environment Secrets

All sensitive variables (Meta Tokens, M-Pesa Passkeys, database passwords) are centrally managed in a single `.env` file at the root of the deployment directory. The containers read these environment variables at boot time. None of these secrets are baked into the Docker images.
