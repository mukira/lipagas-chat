# Presidential Bot Project Rules

When working in this directory (`/root/presidential_bot`), all agents and developers MUST adhere strictly to the following rules:

1. **No Regressions**: Do not break or cause problems to anything that was working before. 
2. **Surgical Fixes**: Always apply fixes surgically. Do not rewrite entire files or systems unless absolutely necessary and explicitly approved. Understand the existing architecture before modifying it.
3. **Always Test and Verify**: You must verify that your solutions are 100% error-free. Test your changes locally to guarantee they work as intended before considering a task complete.
4. **Clean Up**: Always delete temporary or scratch files immediately after the task or test is done. Do not leave behind clutter.
5. **Never Hardcode Secrets**: Always use the `.env` file for API keys, Webhook Tokens, and Database URLs. Never hardcode sensitive information directly into the scripts.
6. **Handle Edge Cases Gracefully (No Crashing)**: When relying on external APIs (like Meta, Truecaller, or Gemini), you must always wrap calls in `try/catch` blocks. If an API fails, provide a safe fallback so the server never crashes.
7. **Meaningful Logging**: Avoid silent failures. Ensure all errors are logged clearly with their component tag (e.g., `[OSINT Error]`, `[Gemini Rate Limit]`) so debugging production logs is fast.
8. **No Unapproved Dependencies**: Do not install new `npm` or `pip` packages to solve a problem without explicit user approval. Attempt to use the existing tech stack to prevent bloat.
9. **Always Backup Before Editing**: Before modifying any existing core file, create a quick backup copy (e.g., `cp server.js server.js.bak`) so you can instantly revert if something breaks.
10. **Strict Folder Discipline**: Maintain a clean, logical folder structure. Python scripts should go in a `/scripts` or `/core` directory, utility functions in `/utils`, etc. Do not dump everything into the root `/presidential_bot` folder.
