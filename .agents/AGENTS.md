# Docker Compose Guidelines
- **Reloading `.env` files:** When modifying a `.env` file that is injected into a container via the `env_file:` directive, NEVER use `docker compose restart <service>`. It will not pick up the changes. You MUST use `docker compose up -d <service>` to recreate the container with the new environment variables.

# Chatwoot Guidelines
- **Webhook SSRF Protection:** Chatwoot has strict SSRF protection enabled by default. It will silently block outgoing webhooks (e.g., AgentBot webhooks) if the destination URL resolves to an internal/private IP or a Docker container hostname (e.g., `http://lipagas-bridge:4000`). To configure webhooks successfully, you must route them through a public domain (e.g., via your Nginx proxy `https://flow.lipagas.co/webhook`) so Chatwoot sees a public external IP.
