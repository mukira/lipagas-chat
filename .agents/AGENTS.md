# Docker Compose Guidelines
- **Reloading `.env` files:** When modifying a `.env` file that is injected into a container via the `env_file:` directive, NEVER use `docker compose restart <service>`. It will not pick up the changes. You MUST use `docker compose up -d <service>` to recreate the container with the new environment variables.

# Chatwoot Guidelines
- **Webhook SSRF Protection:** Chatwoot has strict SSRF protection enabled by default. It will silently block outgoing webhooks (e.g., AgentBot webhooks) if the destination URL resolves to an internal/private IP or a Docker container hostname (e.g., `http://lipagas-bridge:4000`). To configure webhooks successfully, you must route them through a public domain (e.g., via your Nginx proxy `https://flow.lipagas.co/webhook`) so Chatwoot sees a public external IP.


## Typebot Programmatic Injection & Engine Strictness
- **Condition Block Type Casting:** Typebot v6 native `Condition` blocks use strict equality (`===`). If a Condition block evaluates a numeric value configured as a string (e.g., `"Equal to" "4"`), the backend Elixir bridge MUST explicitly cast the variable to a string (`to_string(var)`) before passing it into `prefilledVariables`. Passing an integer will cause the condition to fail and silently halt the bot.
- **Orphaned Edges & Silent Halts:** When programmatically injecting JSON architecture into the Postgres `Typebot` table, absolutely ensure that every `groupId` and `blockId` referenced in the `edges` array actually exists in the `groups` array. If an edge points to a missing node, the Typebot Engine will silently abort the flow (`Error: Session not found`) leaving the user with no response. Always meticulously double-check your `.append()` logic.

## Flow Migration & Text Preservation
- **No Hallucinated Text Migrations:** When migrating, expanding, or translating an existing Typebot flow, NEVER improvise generic text or rewrite the user's original greetings/descriptions unless explicitly told to rewrite them. You must meticulously extract the existing text blocks from the database dump and preserve their exact phrasing, tone, and emojis in the new architecture.
