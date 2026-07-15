# System Rules for Future Prompts

## 1. Surgical Edits Only
- Always perform surgical edits to specific sections and parts of the code that require rectification.
- **DO NOT** modify, rearrange, or touch any other parts of the code.
- Maintain existing comments, formatting, and logic outside the specific area of change.

## 2. Direct Code Interaction
- **ALWAYS** edit the code directly using the provided editing tools (`replace_file_content`, `multi_replace_file_content`).
- **NEVER** use Python or JavaScript scripts to automate or perform the editing process.
- **NEVER** write a script to edit the code through the terminal.

## 3. Platform-Specific Syntax & APIs
- Apply the correct syntax for the specific versions of **n8n** and **Chatwoot** used in this workspace.
- **n8n Version**: Use syntax compatible with **n8n v2.13.4**.
- **API Versions**: Always use **Meta Graph API v21.0** and **Chatwoot API v1** for all requests. Any update to a newer API version must be explicitly requested.

## 4. Code Quality, Reliability & Formatting
- **ALWAYS** provide complete, production-ready code and JSON.
- **NEVER** provide half-cooked, incomplete, or placeholder code.
- **Standardized Naming**: Every node must have a descriptive, human-readable name including its function and platform. Use emojis as prefixes: `⚙️` for Code, `📥` for Webhook, `💬` for Meta/Chat, `🔑` for Auth, `🔀` for Switch, `📄` for Google, `📤` for Upload.
- **Variable Naming**: Use `snake_case` for all variables within Code nodes and JSON payloads (e.g., `conversation_id`, `saved_price`).
- **Optimization**: In n8n Code nodes, always use `$json` for the current data. Avoid using `$node` for historical data unless absolutely necessary.
- **Documentation**: Any complex Code node must include header comments explaining its purpose. Use n8n Sticky Notes to label major workflow sections.
- **Mock Data**: Every `Code` node must include a commented-out section at the top containing a **Mock Input Object** for isolated testing.
- Ensure all logic is sound and will not cause runtime or syntax errors upon deployment.
- All JSON/workflow configurations must be production-level and clearly documented with comments or annotations where applicable.

## 5. Advanced Architecture & Security
- **M-Pesa Handling**: Every M-Pesa STK Push node must be followed by a **Wait node** (30-60s) or a **Polling Loop** to verify status if the callback is delayed.
- **Data Privacy**: Mask Personally Identifiable Information (PII) like phone numbers (e.g., `254712***678`) in logs or external error reports.
- **Modularization**: Extract repeated logic (e.g., reading Chatwoot notes, parsing payments) into **Sub-workflows** or dedicated helper nodes.
- **Backup Integrity**: Before major structural changes (e.g., editing the Master Router), create a timestamped backup of the workflow JSON (e.g., `workflow_backup_YYYYMMDD.json`).
