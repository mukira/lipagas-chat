# LipaGas Bot Project Rules

When working in this directory (`/root/lipagas_bot`), all agents and developers MUST adhere strictly to the following rules:

---

## ⚠️ RULE #0 — HIGHEST PRIORITY: UNDERSTAND BEFORE ACTING

> **This rule overrides everything else. It MUST be applied before any code is written, any file is modified, any command is run, or any recommendation is made.**

**Before doing ANYTHING, you MUST:**

1. **Read and understand the current state of all relevant files.** Do not assume anything from memory or prior context. Always read the live file.
3. **Reproduce the problem, not just the symptom.** Before proposing a fix, identify the *root cause* with evidence (logs, code paths, actual data). A guess is not a diagnosis.
4. **Check the live database/state, not just local files.** Local `.json` files and the live database may differ. Always verify the actual running state.
5. **Do NOT modify anything until you have a complete, verified understanding.** Incomplete understanding leads to regressions. Partial fixes that introduce new bugs are worse than doing nothing.
6. **Write an Implementation Plan first** for any non-trivial change, wait for explicit user approval, then execute surgically.

**Violation of this rule is the primary cause of regressions, wasted time, and user frustration. It will not be tolerated.**

---


1. **No Regressions**: Do not break or cause problems to anything that was working before. 
2. **Surgical Fixes**: Always apply fixes surgically. Do not rewrite entire files or systems unless absolutely necessary and explicitly approved. Understand the existing architecture before modifying it.
3. **Always Test and Verify**: You must verify that your solutions are 100% error-free. Test your changes locally to guarantee they work as intended before considering a task complete.
4. **Clean Up**: Always delete temporary or scratch files immediately after the task or test is done. Do not leave behind clutter.
5. **Never Hardcode Secrets**: Always use the `.env` file for API keys, Webhook Tokens, and Database URLs. Never hardcode sensitive information directly into the scripts.

7. **Meaningful Logging**: Avoid silent failures. Ensure all errors are logged clearly with their component tag (e.g., `[Meta Error]`, `[Daraja Error]`) so debugging production logs is fast.
8. **No Unapproved Dependencies**: Do not install new `npm` or `pip` packages to solve a problem without explicit user approval. Attempt to use the existing tech stack to prevent bloat.
9. **Always Backup Before Editing**: Before modifying any existing core file, create a quick backup copy (e.g., `cp bridge.js bridge.js.bak`) so you can instantly revert if something breaks.
10. **Strict Folder Discipline**: Maintain a clean, logical folder structure. Utility functions should go in a `/utils` directory, routing logic in `/routes`, etc. Do not dump everything into the root `/lipagas_bot` folder.
11. **Preserve User UI Customizations**: NEVER overwrite, reset, or modify any user-defined text, descriptions, or button names in the Typebot builder or config files. All additions and modifications must be surgical, and existing text customizations must be preserved at all costs.
12. **Frontend UI Visibility**: All conversational steps, logic, and integrations (including webhooks) MUST always be fully visible and linked properly in the Typebot frontend UI. Avoid using hidden "native" interceptions that bypass the visual flow builder. Everything must be traceable in the Typebot canvas.

### Typebot V6.1 & Next.js Specific Rules

13. **Strict NextAuth Configuration**: The Next.js builder MUST always have a valid, securely generated 32-character `NEXTAUTH_SECRET` environment variable defined in the `.env` file. Without this, NextAuth will fail to decrypt session cookies and trigger silent `500 Internal Server Errors` for all authenticated API routes.
14. **Strict Zod Data Validation (No Nulls) & Pre-Flight Checks**: Typebot v6.1 enforces strict TypeScript Zod validation on database JSON payloads. When dealing with the Postgres `Typebot` table, absolutely no explicit `null` values are allowed in JSON arrays/objects where fields are optional (e.g. `blocks`, `edges`). Optional fields must be cleanly omitted or explicitly set to `undefined`. Injecting `null` will cause catastrophic Zod parsing crashes resulting in `500` errors. 
- **CRITICAL**: ALL programmatic database injections MUST be validated against the exact Typebot TypeScript source schemas (via GitHub/source inspection) BEFORE being executed. Do not guess the schema. A single missing ID or incorrect type will crash the entire flow builder for the user.
15. **Obsolete Block Migrations (httpRequest)**: Legacy Typebot v5 schemas (such as the `"httpRequest"` block type) are fully deprecated in v6.1. Any imported JSON schemas or direct database writes must structurally migrate legacy `"httpRequest"` blocks into native v6.1 `"webhook"` blocks to avoid fatal unhandled validation errors.

- **FRONT-END PRIORITY RULE:** The Typebot Builder UI is the absolute source of truth for all text. The backend (bridge.js) must NEVER hardcode text that overrides the Typebot Builder. When native WhatsApp features (like images or interactive location pins) are required, bridge.js must dynamically extract the text generated by Typebot and wrap it inside the native payload, preserving the user's edits completely. Hidden placeholders (e.g., {{LOCATION_PROMPT}}) should be used to trigger native upgrades instead of hardcoded string matching.
- **STRICT UI PRESERVATION:** Any change in logic MUST NOT change the text or images currently defined in the frontend (Typebot Builder). The frontend text and images are the highest priority and should be preserved exactly as defined by the user. However, variables can be changed as needed for backend optimizations.
- **NEVER USE (n8n):** Never mention, recommend, or use the string `(n8n)` in any context, naming convention, or UI instruction. The system is completely native now.
- **PRESERVE VISUAL SPACING (graphCoordinates):** Whenever programmatic edits are made to Typebot JSON files or the database, you MUST strictly preserve the existing `graphCoordinates` (x, y coordinates). The frontend builder relies on these coordinates for visual spacing. Some blocks may intentionally overlay or cover each other as physically arranged by the user for clarity. Do not reset, auto-layout, or modify `graphCoordinates` unless explicitly requested.
- **ELIXIR FIRST FOR BACKEND LOGIC:** For any functionality that cannot and absolutely cannot be handled by the frontend Typebot builder natively, ONLY use Elixir going forward. No new Node.js services should be introduced for backend interceptions.
- **CLEAN REPOSITORY:** Only leave what is needed for the  application components. Recursively delete all non-useful, temporary, or unused functioning scripts scattered in the system to prevent clutter and confusion.
- **NO GUESSWORK OR PATCHWORK:** Think deeply and perform extensive code tests. Fix issues at the critical place where they fail. Never do guesswork or assumptions. Ensure 100% verified code understanding and do comprehensive code fixes across the entire system, not just bits or trial and error patchwork.
- **DOUBLE RESPONSES & CORE FILES:** Prevent double responses. Never ever change core Chatwoot files ever.
- **DELETE ALL TEMP FILES:** Always delete all the temp files, generated scripts, and scratch files that were created during the task immediately after they are used. Do not leave them lingering in the repository.
- **ARIE TURAK LEVEL EFFICIENCY:** All bots and solutions must be built for maximum efficiency and speed so that responses are as fast as possible.
- **OPTIMIZED FOR SCALED OPERATIONS:** Only implement solutions that are optimized for scaled operations. No manual, stupid, or unverified patchwork fixes. Implement verified fixes once and for all.
- **DO NOT OPEN BROWSER:** Never open the Typebot Builder browser tab to perform UI edits; all automated edge connections and backend fixes must be implemented permanently without requiring manual browser intervention.
- **ZERO USER ACTION ITEMS:** The implementation must fix absolutely everything automatically. Never provide "action items" instructing the user to manually connect blocks or draw lines in the UI. All connection lines must be programmatically connected in the backend during implementation. The user's ONLY job is to refresh the page and click Publish.
- **STRICT ISOLATION:** Any new bot implementation or backend logic must be completely isolated from the LipaGas bot or any other existing bots. No shared routing logic or keyword interception in monolithic scripts. Use physically separate microservices or independent Chatwoot Agent Bot webhooks to ensure a crash in one bot cannot affect another.


## 16. Bot Reset Keywords Whitelisting
- The Elixir bridge ignores conversational inputs that are not explicitly matched to a Typebot flow edge. 
- To ensure the bot reliably triggers a reset when users send conversational greetings or bot names (like 'ruto', 'hi', 'hello'), you MUST explicitly whitelist these in the `@reset_keywords` array inside `TypebotBotHandler.ex`.
- Failure to whitelist conversational triggers will result in the bot silently dropping the message, leaving the user with no reply.


## 17. Persistent Session Greetings
- The bot must maintain the exact same random greeting for a user throughout their entire active session.
- When the bot generates a random greeting during `start_new_session`, it MUST cache this greeting in Redis using the `conv_id`.
- Internal session resets (like deep linking or language switching) should reuse this cached greeting instead of generating a new one.
- The only way to clear the cached greeting and generate a new one is if the user sends the explicit `exit` keyword.

## 18. Strict Frontend Physical Visibility & Visual Linking
- EVERYTHING must be physically visible in the Typebot frontend and editable by the user. 
- You must never hide strings, greetings, or text variations inside backend logic (e.g. Elixir) if it means the user cannot see and click on them as text bubbles in the Typebot UI.
- All blocks must be properly linked visually in the frontend (via drawn edges/connections). Hidden routing or "invisible jumps" that bypass the visual canvas are strictly forbidden.
- This must be strictly enforced. All logic that requires rotating texts must use explicit frontend branching (e.g., Condition Blocks routing to separate Text Groups) and explicitly drawn visual connections so that the UI remains the absolute source of truth and is completely visually editable.

- **NO GUESSING OR TRIAL AND ERROR:** Never guess a solution, bullshit, or use trial and error. Always perform a full, end-to-end code audit before acting, and implement a solution that fixes things 100% correctly with absolutely no half-assed workarounds.

### Rule 56: No Guessing or Trial-and-Error
Never guess a solution, bullshit, or use trial and error. Always perform a full code audit end-to-end. You must provide a solution that fixes things 100% absolutely. No half-assed work.

## 19. Typebot Safe Coordinate Rule
When programmatically injecting new Typebot groups or blocks, DO NOT hardcode static `graphCoordinates` or place them randomly. Always read the coordinates of the adjacent group and dynamically apply a minimum offset (e.g., `x + 400`, `y + (index * 200)`) to ensure new blocks never overlap existing ones.


