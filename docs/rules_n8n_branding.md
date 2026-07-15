# Surgical Branding Rules for n8n (LipaGas AI)

To ensure the n8n platform remains 100% "Pull-Friendly" (upgradable via git without conflicts) while being fully white-labeled, follow these strict Nginx-level branding rules.

## 1. The "Sacred Core" Protocol (DO NOT EDIT SOURCE)
*   **ZERO SOURCE MODIFICATION**: Never modify files in `/usr/local/lib/node_modules/n8n/`, `/home/node/.n8n`, or any internal n8n directories.
*   **WHY**: Direct edits break `npm update` and `git pull`. All branding must happen at the **Network Layer (Nginx)** or **DOM Layer (JS Injection)**.

## 2. Nginx Asset Hijacking (Venn Identity)
*   **RULE**: Use Nginx `alias` to swap the logo and favicon. The source file is strictly **/root/venn.svg**.
*   **COLOR**: The logo stroke must be strictly **#FF4D2D** (Venn Orange).
*   **TARGETS**: 
    *   `/assets/logo.svg` -> `/root/venn.svg`
    *   `/favicon.ico` -> `/root/venn.svg`
    *   `/assets/favicon.ico` -> `/root/venn.svg`
*   **CONFIG**:
    ```nginx
    location ~* ^/(assets/)?(logo\.svg|favicon\.ico)$ {
        alias /var/www/n8n-branding/venn.svg;
        add_header Cache-Control "no-cache, must-revalidate" always;
        types { } default_type image/svg+xml;
    }
    ```

## 3. Strict Nginx-Only Branding (The Head Hijack)
*   **RULE**: All visual changes must be done via Nginx `sub_filter` by injecting a `<style>` block into the `<head>`.
*   **WHY**: This is the most resilient method for SPAs (Single Page Apps) where assets are inlined or bundled. Targeting CSS classes is safer than literal SVG string replacement.
*   **ENFORCEMENT**:
    ```nginx
    sub_filter '<head>' '<head><style>._logo_bk7tg_125 { display:none !important; } ._logoText_bk7tg_131 { display:none !important; } ._logoContainer_bk7tg_125::before { content: ""; display: inline-block; width: 32px; height: 26px; background: url(/assets/logo.svg) no-repeat center; background-size: contain; margin-right: 10px; } ._logoContainer_bk7tg_125::after { content: "Venn"; color: white; font-family: Arial, sans-serif; font-weight: bold; font-size: 22px; vertical-align: middle; }</style>';
    ```
*   **FORBIDDEN**: Do not modify core source files. All branding happens at the Nginx layer.

## 4. SSE & Stream Preservation (CRITICAL)
*   **RULE**: Never apply `sub_filter` to the `/rest/push` or `/rest/events` paths.
*   **WHY**: n8n uses Server-Sent Events (SSE) for real-time updates. Buffering or filtering these streams will hang the dashboard and stop nodes from showing "Running" status.
*   **FIX**: Always set `proxy_set_header Accept-Encoding "";` in the main location and disable buffering for n8n endpoints.

## 5. Surgical String Replacement (Official Rebrand: Venn)
*   **RULE**: Replace user-facing strings like "n8n" with "**Venn**" in the HTML stream.
*   **ENFORCEMENT**:
    ```nginx
    sub_filter 'n8n' 'Venn';
    ```
*   **CAUTION**: Do not replace "n8n" in script source URLs or internal JSON keys, as this will break the application logic. Only apply this to HTML content.

## 6. Branding Asset Storage
*   **RULE**: All custom assets must live in `/var/www/n8n-branding/`.
*   **PERMISSIONS**: Ensure the `www-data` user has read access to this directory.

## 7. Stability & Reload Protocol
*   **DRY RUN**: Always run `nginx -t` before reloading.
*   **RELOAD**: Use `systemctl reload nginx` for branding changes. Do **NOT** restart the n8n service for CSS/Logo changes; it is unnecessary and disrupts active workflows.
