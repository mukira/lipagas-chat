defmodule LipagasBridge.Receipt do
  @receipts_dir "/tmp/lipagas_receipts"

  def generate_html(phone, amount, token, receipt_no, meter \\ nil) do
    date = Calendar.strftime(Date.utc_today(), "%d %b %Y")
    {name, location} = case LipagasBridge.Chatwoot.search_contact(phone) do
      {:ok, contact} when not is_nil(contact) -> 
        n = contact["name"] || "Customer"
        loc = get_in(contact, ["custom_attributes", "saved_location"]) || ""
        {n, loc}
      _ -> {"Customer", ""}
    end
    
    is_token_receipt = not is_nil(token) and token != "" and token != "PENDING"
    
    fmt_amount = case Float.parse(to_string(amount)) do
      {f, _} -> :erlang.float_to_binary(f, decimals: 2)
      :error -> "0.00"
    end

    items = case LipagasBridge.Chatwoot.search_contact(phone) do
      {:ok, contact} when not is_nil(contact) ->
        case LipagasBridge.Chatwoot.get_contact_conversations(contact["id"]) do
          {:ok, [conv | _]} ->
            case LipagasBridge.Chatwoot.get_last_cart_total(conv["id"]) do
              {:ok, _, label} ->
                label
                |> String.split(", ")
                |> Enum.map(fn item_str ->
                  qty = case Regex.run(~r/\(x(\d+)\)/, item_str) do
                    [_, q] -> q
                    _ -> "1"
                  end
                  
                  price = case Regex.run(~r/@\s*KES\s*([\d.]+)/i, item_str) do
                    [_, p] -> 
                      case Float.parse(p) do
                        {f, _} -> :erlang.float_to_binary(f, decimals: 2)
                        :error -> ""
                      end
                    _ -> ""
                  end
                  
                  name = item_str
                         |> String.replace(~r/\(x\d+\).*/, "")
                         |> String.replace(~r/@\s*KES.*/i, "")
                         |> String.trim()
                         
                  %{name: name, qty: qty, price: price}
                end)
              _ -> [%{name: "LipaGas Order", qty: "1", price: fmt_amount}]
            end
          _ -> [%{name: "LipaGas Order", qty: "1", price: fmt_amount}]
        end
      _ -> [%{name: "LipaGas Order", qty: "1", price: fmt_amount}]
    end

    qr_data = "https://lipagas.co/verify/#{receipt_no}"
    qr_svg = generate_qr_svg(qr_data)

    guilloche_svg = generate_guilloche()

    EEx.eval_string("""
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>LipaGas Receipt</title>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&family=Space+Mono:wght@700&family=Courier+Prime:wght@400;700&display=swap" rel="stylesheet">
  <style>
    * { box-sizing: border-box; }
    html, body {
      margin: 0;
      padding: 0;
      width: <%= if is_token_receipt, do: "375.12pt", else: "360pt" %>;
      height: <%= if is_token_receipt, do: "751.92pt", else: "640pt" %>;
      overflow: hidden;
      background-color: #ffffff;
      font-family: 'Inter', sans-serif;
      color: #1f2937;
    }
    @page {
      margin: 0;
      size: <%= if is_token_receipt, do: "375.12pt 751.92pt", else: "360pt 640pt" %>;
    }
    .receipt-container {
      width: 100%;
      height: 100%;
      padding: <%= if is_token_receipt, do: "0", else: "24px" %>;
      position: relative;
      z-index: 0;
    }

    @font-face {
      font-family: 'Courier Prime';
      src: local('Courier Prime'), local('CourierPrime');
    }
    
    .token-wrapper {
      font-family: 'Courier Prime', Courier, monospace;
      padding: 13pt 24pt 6pt 24pt;
      color: #000;
      background: #fff;
      width: 375pt;
      height: 752pt;
      box-sizing: border-box;
      position: relative;
      margin: 0;
    }
    .token-top-logo {
      display: block;
      margin: 20pt auto 16pt auto;
      width: 201pt;
      height: auto;
    }
    .token-date-time {
      text-align: center;
      font-size: 13pt;
      font-weight: bold;
      margin-bottom: 23pt;
      letter-spacing: 0.5pt;
    }
    .token-box {
      border: 2pt dashed #000;
      border-radius: 8pt;
      padding: 20pt 6pt;
      text-align: center;
      position: relative;
      margin-bottom: 26pt;
      width: 100%;
      box-sizing: border-box;
    }
    .token-label {
      position: absolute;
      top: -9pt;
      left: 50%;
      -webkit-transform: translateX(-50%);
      transform: translateX(-50%);
      background-color: #ffffff;
      padding: 0 10pt;
      font-size: 13pt;
      font-weight: bold;
    }
    .token-code {
      font-size: 17pt;
      font-weight: bold;
      letter-spacing: 1pt;
    }
    .token-divider {
      border-top: 1.5pt dashed #94a3b8;
      margin: 16pt 0;
      width: 100%;
    }
    .token-row {
      overflow: hidden;
      margin-bottom: 13pt;
      font-size: 11pt;
      width: 100%;
    }
    .token-lbl {
      color: #000;
      width: 45%;
      text-align: left;
      float: left;
    }
    .token-val {
      text-align: right;
      width: 55%;
      font-weight: bold;
      float: left;
    }
    .token-row-total {
      overflow: hidden;
      margin-top: 26pt;
      margin-bottom: 13pt;
      font-size: 14.6pt;
      width: 100%;
    }
    .token-row-total .token-lbl {
      font-weight: normal;
      text-align: left;
    }
    .token-row-total .token-val {
      font-weight: bold;
      text-align: right;
    }
    .token-footer-message {
      font-size: 10pt;
      font-weight: normal;
      color: #000;
      text-align: center;
      line-height: 1.6;
      margin-top: 20pt;
      margin-bottom: 10pt;
      padding: 0 6pt;
    }
    .token-footer-info {
      text-align: center;
      font-size: 8pt;
      font-weight: normal;
      line-height: 1.5;
      margin-top: 20pt;
      margin-bottom: 16pt;
    }
    .token-safe-fast {
      text-align: center;
      font-weight: bold;
      font-size: 8pt;
      letter-spacing: 1pt;
      margin-bottom: 10pt;
    }
    .token-for-you {
      text-align: center;
      font-weight: bold;
      font-size: 14.6pt;
      letter-spacing: 2.6pt;
    }
    /* ──────────────────────────────────────────────────────── */

    /* STANDARD RECEIPT STYLING                                 */
    /* ──────────────────────────────────────────────────────── */
    .std-logo-container {
      position: absolute;
      top: 0;
      left: 24px;
      background-color: #ffffff;
      padding: 14px 18px;
      box-shadow: 0px 6px 16px rgba(0, 0, 0, 0.15);
      border: 1px solid #e5e7eb;
      border-top: none;
      border-bottom-left-radius: 8px;
      border-bottom-right-radius: 8px;
      z-index: 10;
    }
    .std-logo-img {
      height: 32px;
      display: block;
    }
    .std-checkmark-container {
      text-align: center;
      margin-top: 90px;
      margin-bottom: 4px;
      transform: translateX(-8px);
    }
    .std-checkmark-svg {
      width: 100px;
      height: 100px;
      color: #43b02a;
      display: block;
      margin: 0 auto;
    }
    .std-greeting {
      text-align: center;
      margin-top: 0px;
      margin-bottom: 30px;
      transform: translateX(-8px);
    }
    .std-greeting-title {
      font-size: 42px;
      font-weight: 800;
      color: #43b02a;
      margin: 0 0 8px 0;
      letter-spacing: -1px;
    }
    .std-greeting-subtitle {
      font-size: 16px;
      color: #43b02a;
      font-weight: 600;
      margin: 0;
    }
    .std-two-col {
      width: 100%;
      border-collapse: collapse;
      margin-top: 50px;
      margin-bottom: 30px;
      table-layout: fixed;
    }
    .std-left-box {
      width: 50%;
      background-color: #43b02a;
      color: #ffffff;
      padding: 12px;
      border-radius: 6px 0 0 6px;
      vertical-align: middle;
    }
    .std-amount-title {
      font-size: 11px;
      font-weight: bold;
      opacity: 0.9;
      margin: 0 0 4px 0;
    }
    .std-amount-value {
      font-size: 20px;
      font-weight: 800;
      margin: 0 0 4px 0;
    }
    .std-phone-label {
      font-size: 10px;
      opacity: 0.9;
    }
    .std-right-box {
      width: 50%;
      border: 1px solid #e5e7eb;
      border-left: none;
      border-radius: 0 6px 6px 0;
      padding: 10px 12px;
      vertical-align: middle;
      font-size: 10px;
    }
    .std-meta-row {
      margin-bottom: 4px;
    }
    .std-meta-row:last-child {
      margin-bottom: 0;
    }
    .std-meta-label {
      color: #6b7280;
    }
    .std-meta-value {
      font-weight: 700;
      color: #1f2937;
    }
    .std-table {
      width: 100%;
      border-collapse: collapse;
      margin-bottom: 20px;
    }
    .std-table-header-col {
      border-bottom: 1px solid #e5e7eb;
      padding-bottom: 6px;
      font-size: 10px;
      font-weight: bold;
      color: #9ca3af;
      letter-spacing: 0.5px;
    }
    .std-table-row-col {
      padding: 8px 0;
      font-size: 12px;
      border-bottom: 1px dashed #e5e7eb;
    }
    .std-table-col-item {
      width: 60%;
      font-weight: 600;
      text-align: left;
    }
    .std-table-col-qty {
      width: 15%;
      text-align: center;
      font-weight: 500;
    }
    .std-table-col-price {
      width: 25%;
      text-align: right;
      font-weight: bold;
    }
    .std-etr-section {
      text-align: center;
    }
    .std-footer-table {
      width: 100%;
      border-collapse: collapse;
      margin-top: auto;
      position: relative;
    }
    .std-qr-line {
      position: absolute;
      left: 20px;
      right: 65px; /* 65px QR + 0px right padding */
      bottom: 52.5px; /* 20px padding + 32.5px half-height */
      height: 2px;
      background-color: #43b02a;
      z-index: -1;
    }
    .std-footer-left {
      width: 30%;
      vertical-align: bottom;
      text-align: left;
      padding-bottom: 100px;
      padding-left: 20px;
    }
    .std-footer-center {
      width: 40%;
      vertical-align: bottom;
      text-align: center;
      padding-bottom: 100px;
    }
    .std-footer-right {
      width: 30%;
      vertical-align: bottom;
      text-align: right;
      padding-bottom: 20px;
      padding-right: 0px;
    }
    .std-kra-marks {
      width: 65px;
      display: inline-block;
    }
    .kra-qr-code {
      display: flex;
      align-items: center;
      justify-content: center;
    }

    .std-etr-title {
      font-size: 14px;
      font-weight: 600;
      color: #43b02a;
      margin: 0 0 8px 0;
      letter-spacing: 1px;
    }
    .std-contact-info {
      font-size: 11px;
      color: #43b02a;
      line-height: 1.6;
      text-align: center;
      font-weight: 400;
    }

    .std-watermark {
      position: absolute;
      top: 0; left: 0; right: 0; bottom: 0;
      pointer-events: none;
      z-index: -1;
    }
    .kra-qr-wrapper {
      position: relative;
      width: 85px;
      height: 85px;
    }
    .kra-qr-code svg {
      width: 100%;
      height: 100%;
      display: block;
    }
    .kra-qr-center-logo {
      position: absolute;
      top: 50%;
      left: 50%;
      transform: translate(-50%, -50%);
      width: 18px;
      height: 18px;
      border-radius: 50%;
      background: white;
      padding: 1.5px;
    }
    .kra-qr-center-logo svg {
      width: 100%;
      height: 100%;
      display: block;
    }
    .std-bottom-badge-container {
      text-align: center;
      margin-top: 10px;
    }
    .std-bottom-badge-top {
      font-size: 10px;
      font-weight: 800;
      color: #43b02a;
      letter-spacing: 1.5px;
      padding-left: 1.5px;
    }
    .std-bottom-badge-bottom {
      font-size: 32px;
      font-weight: 300;
      color: #43b02a;
      margin-top: 2px;
      letter-spacing: -1px;
      padding-right: 1px;
    }
  </style>
</head>
<body>
  <div class="receipt-container">
    <%= if is_token_receipt do %>
      <!-- ──────────────────────────────────────────────────────── -->
      <!-- ──────────────────────────────────────────────────────── -->
  <!-- ──────────────────────────────────────────────────────── -->
  <!-- ──────────────────────────────────────────────────────── -->
  <!-- TOKEN RECEIPT LAYOUT                                     -->
  <!-- ──────────────────────────────────────────────────────── -->
  <div class="token-wrapper">
    <!-- Top Logo area -->
    <img src="data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMzAxIiBoZWlnaHQ9Ijg1IiB2aWV3Qm94PSIwIDAgNjYwOSAxODY0IiBmaWxsPSJub25lIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciPgo8cGF0aCBkPSJNMCA4NjMuMjkxVjBMMjQ3LjE1MiAxMjMuNTc2Vjg2My4yOTFDMjQ3LjE1MiAxMDMzLjg2IDM4NC42NTIgMTE3MS4zNiA1NTUuMjIxIDExNzEuMzZWMTQxOC41MUMyNDguODkyIDE0MTguNTEgMCAxMTY5LjYyIDAgODYzLjI5MVoiIGZpbGw9IiMwMDAwMDAiLz4KPHBhdGggZD0iTTg1OS4xODQgMEM5MjcuMDY0IDAgOTgyLjc2IDU1LjY5NjIgOTgyLjc2IDEyMy41NzZDOTgyLjc2IDE5MS40NTYgOTI3LjA2NCAyNDcuMTUyIDg1OS4xODQgMjQ3LjE1MkM3OTEuMzA1IDI0Ny4xNTIgNzM1LjYwOCAxOTEuNDU2IDczNS42MDggMTIzLjU3NkM3MzUuNjA4IDU1LjY5NjIgNzkxLjMwNSAwIDg1OS4xODQgMFpNNzM1LjYwOCA0MzEuNjQ2TDk4Mi43NiAzMDguMDdWMTQxOC41MUg3MzUuNjA4VjQzMS42NDZaIiBmaWxsPSIjMDAwMDAwIi8+CjxwYXRoIGQ9Ik0xMDkwLjQgODYzLjI5MUMxMDkwLjQgNTU2Ljk2MiAxMzM5LjI5IDMwOC4wNyAxNjQ1LjYyIDMwOC4wN0MxOTUxLjk1IDMwOC4wNyAyMjAwLjg0IDU1Ni45NjIgMjIwMC44NCA4NjMuMjkxQzIyMDAuODQgMTE2OS42MiAxOTUxLjk1IDE0MTguNTEgMTY0NS42MiAxNDE4LjUxQzE1MzAuNzUgMTQxOC41MSAxNDI0LjU4IDEzODMuNyAxMzM3LjU1IDEzMjYuMjdWMTczMy41NEwxMDkwLjQgMTg1Ny4xMlY4NjMuMjkxWk0xNjQ1LjYyIDU1NS4yMjFDMTQ3NS4wNSA1NTUuMjIxIDEzMzcuNTUgNjk0LjQ2MiAxMzM3LjU1IDg2My4yOTFDMTMzNy41NSAxMDMzLjg2IDE0NzUuMDUgMTE3My4xIDE2NDUuNjIgMTE3My4xQzE4MTYuMTkgMTE3My4xIDE5NTMuNjkgMTAzMy44NiAxOTUzLjY5IDg2My4yOTFDMTk1My42OSA2OTQuNDYyIDE4MTYuMTkgNTU1LjIyMSAxNjQ1LjYyIDU1NS4yMjFaIiBmaWxsPSIjMDAwMDAwIi8+CjxwYXRoIGQ9Ik0zMzg2LjcxIDg2My4yOTFWMTQ3OS40M0wzMTEzLjQ1IDEzNDEuOTNDMzAyOC4xNyAxMzkyLjQgMjkzMC43IDE0MTguNTEgMjgzMS40OSAxNDE4LjUxQzI1MjUuMTYgMTQxOC41MSAyMjc2LjI3IDExNjkuNjIgMjI3Ni4yNyA4NjMuMjkxQzIyNzYuMjcgNTU2Ljk2MiAyNTI1LjE2IDMwOC4wNyAyODMxLjQ5IDMwOC4wN0MzMTM3LjgyIDMwOC4wNyAzMzg2LjcxIDU1Ni45NjIgMzM4Ni43MSA4NjMuMjkxWk0yODMxLjQ5IDU1NS4yMjFDMjY2MC45MiA1NTUuMjIxIDI1MjMuNDIgNjkyLjcyMSAyNTIzLjQyIDg2My4yOTFDMjUyMy40MiAxMDMzLjg2IDI2NjAuOTIgMTE3MS4zNiAyODMxLjQ5IDExNzEuMzZDMzAwMi4wNiAxMTcxLjM2IDMxMzkuNTYgMTAzMy44NiAzMTM5LjU2IDg2My4yOTFDMzEzOS41NiA2OTIuNzIxIDMwMDIuMDYgNTU1LjIyMSAyODMxLjQ5IDU1NS4yMjFaIiBmaWxsPSIjMDAwMDAwIi8+CjxwYXRoIGQ9Ik01OTAyLjM1IDEwNjUuMTlINjE0OS41MUM2MTQ5LjUxIDExMjQuMzcgNjE5Ni41IDExNzEuMzYgNjI1NS42OCAxMTcxLjM2QzYzMTQuODUgMTE3MS4zNiA2MzYxLjg1IDExMjQuMzcgNjM2MS44NSAxMDY1LjE5QzYzNjEuODUgMTAyNi45IDYzNDAuOTYgOTk3LjMxIDYzMTMuMTEgOTc0LjY4M0M2MjI5LjU3IDkxMi4wMjUgNTk0NS44NyA4NTIuODQ4IDU5NDUuODcgNjE3Ljg4QzU5NDUuODcgNDQ3LjMxIDYwODUuMTEgMzA4LjA3IDYyNTUuNjggMzA4LjA3QzY0MjYuMjUgMzA4LjA3IDY1NjUuNDkgNDQ3LjMxIDY1NjUuNDkgNjE3Ljg4SDYzMjAuMDhDNjMyMC4wOCA1ODMuMDcgNjI5MC40OSA1NTMuNDgxIDYyNTUuNjggNTUzLjQ4MUM2MjIwLjg3IDU1My40ODEgNjE5My4wMiA1ODMuMDcgNjE5My4wMiA2MTcuODhDNjE5My4wMiA2NDIuMjQ3IDYyMDUuMiA2NjMuMTMzIDYyMjYuMDkgNjczLjU3NkM2Mzk4LjQgNzY1LjgyMyA2NjA5IDgwOS4zMzUgNjYwOSAxMDY1LjE5QzY2MDkgMTI2MC4xMyA2NDUwLjYxIDE0MTguNTEgNjI1NS42OCAxNDE4LjUxQzYwNjAuNzQgMTQxOC41MSA1OTAyLjM1IDEyNjAuMTMgNTkwMi4zNSAxMDY1LjE5WiIgZmlsbD0iIzAwMDAwMCIvPgo8cGF0aCBkPSJNNDMyMy4xOSAzMi4yNzM3SDQ2MDAuNDhDNDYwMC40OCAyMDAuODY0IDQ1MjcuMjcgMzQ1LjA1MyA0NDExLjkyIDQ0OS4zMTNDNDUyNy4yNyA1NTMuNTczIDQ2MDAuNDggNjk3Ljc2MiA0NjAwLjQ4IDg2NC4xMzRDNDYwMC40OCAxMTcyLjQ4IDQzNTQuMjQgMTQxOC43MSA0MDQ1LjkgMTQxOC43MUMzNzM3LjU2IDE0MTguNzEgMzQ5MS4zMyAxMTcyLjQ4IDM0OTEuMzMgODY0LjEzNEMzNDkxLjMzIDU1NS43OTEgMzczNy41NiAzMDkuNTYgNDA0NS45IDMwOS41NkM0MTk2Ljc1IDMwOS41NiA0MzIzLjE5IDE4My4xMTggNDMyMy4xOSAzMi4yNzM3Wk0zNzY4LjYxIDg2NC4xMzRDMzc2OC42MSAxMDE0Ljk4IDM4OTUuMDYgMTE0MS40MiA0MDQ1LjkgMTE0MS40MkM0MTk2Ljc1IDExNDEuNDIgNDMyMy4xOSAxMDE0Ljk4IDQzMjMuMTkgODY0LjEzNEM0MzIzLjE5IDcxMy4yOSA0MTk2Ljc1IDU4Ni44NDcgNDA0NS45IDU4Ni44NDdDMzg5NS4wNiA1ODYuODQ3IDM3NjguNjEgNzEzLjI5IDM3NjguNjEgODY0LjEzNFpNNDMyMy4xOSAxODYyLjM3SDQwNDUuOUM0MDQ1LjkgMTU1NC4wMiA0MjkyLjEzIDEzMDcuNzkgNDYwMC40OCAxMzA3Ljc5VjE1ODUuMDhDNDQ0OS42MyAxNTg1LjA4IDQzMjMuMTkgMTcxMS41MiA0MzIzLjE5IDE4NjIuMzdaIiBmaWxsPSIjMDAwMDAwIi8+CjxwYXRoIGQ9Ik0zOTAyLjE5IDE2NTQuNzZDMzkwMi4xOSAxNzY5LjgxIDM4MDguOTIgMTg2My4wNyAzNjkzLjg4IDE4NjMuMDdDMzU3OC44MyAxODYzLjA3IDM0ODUuNTYgMTc2OS44MSAzNDg1LjU2IDE2NTQuNzZDMzQ4NS41NiAxNTM5LjcxIDM1NzguODMgMTQ0Ni40NSAzNjkzLjg4IDE0NDYuNDVDMzgwOC45MiAxNDQ2LjQ1IDM5MDIuMTkgMTUzOS43MSAzOTAyLjE5IDE2NTQuNzZaIiBmaWxsPSIjMDAwMDAwIi8+CjxwYXRoIGQ9Ik01ODA4LjQ3IDg2NC43ODJWMTQ4MC45Mkw1NTM1LjIxIDEzNDMuNDJDNTQ0OS45MiAxMzkzLjkgNTM1Mi40NSAxNDIwIDUyNTMuMjUgMTQyMEM0OTQ2LjkyIDE0MjAgNDY5OC4wMiAxMTcxLjExIDQ2OTguMDIgODY0Ljc4MkM0Njk4LjAyIDU1OC40NTMgNDk0Ni45MiAzMDkuNTYgNTI1My4yNSAzMDkuNTZDNTU1OS41OCAzMDkuNTYgNTgwOC40NyA1NTguNDUzIDU4MDguNDcgODY0Ljc4MlpNNTI1My4yNSA1NTYuNzEyQzUwODIuNjggNTU2LjcxMiA0OTQ1LjE4IDY5NC4yMTIgNDk0NS4xOCA4NjQuNzgyQzQ5NDUuMTggMTAzNS4zNSA1MDgyLjY4IDExNzIuODUgNTI1My4yNSAxMTcyLjg1QzU0MjMuODIgMTE3Mi44NSA1NTYxLjMyIDEwMzUuMzUgNTU2MS4zMiA4NjQuNzgyQzU1NjEuMzIgNjk0LjIxMiA1NDIzLjgyIDU1Ni43MTIgNTI1My4yNSA1NTYuNzEyWiIgZmlsbD0iIzAwMDAwMCIvPgo8L3N2Zz4=" alt="LipaGas Logo" class="token-top-logo" />


    <!-- Date & Time -->
    <div class="token-date-time">
      <%= Calendar.strftime(DateTime.utc_now(), "%a, %b %d &bull; %Y") %>
    </div>

    <!-- Token Box -->
      <div class="token-box">
        <span class="token-label">Token</span>
        <div class="token-code"><%= token %></div>
      </div>

    <!-- Details -->
    <div class="token-row">
      <span class="token-lbl">Token Type</span>
      <span class="token-val">Credit</span>
    </div>
    
    <div class="token-divider"></div>

    <div class="token-row">
      <span class="token-lbl">Customer Name</span>
      <span class="token-val"><%= name %></span>
    </div>
    <div class="token-row">
      <span class="token-lbl">Phone</span>
      <span class="token-val">+<%= phone %></span>
    </div>
    
    <div class="token-divider"></div>
    
    <div class="token-row">
      <span class="token-lbl">Meter Number</span>
      <span class="token-val"><%= meter || "N/A" %></span>
    </div>
    
    <div class="token-divider"></div>

    <div class="token-row">
      <span class="token-lbl">Amount</span>
      <span class="token-val"><%= fmt_amount %> KES</span>
    </div>
    <div class="token-row">
      <span class="token-lbl">Tax</span>
      <span class="token-val">0.00 KES</span>
    </div>
    <div class="token-row-total">
      <span class="token-lbl">Total</span>
      <span class="token-val"><%= fmt_amount %> KES</span>
    </div>
    
    <div class="token-divider"></div>

    <div class="token-row">
      <span class="token-lbl">Operator</span>
      <span class="token-val">LipaGas System</span>
    </div>

    <!-- Footer Message -->
    <div class="token-footer-message">
      Thank you for choosing LipaGas! We hope to
      serve you again soon. Have a wonderful day.
    </div>

    <div class="token-footer-info">
      Question? Comment? Feel free to get in touch!<br>
      Pine Tree Plaza Ngong Road<br>
      P.O Box 233 - 00100, Nairobi<br>
      +254 112 250 250<br>
      www.lipagas.co
    </div>
    
    <div class="token-safe-fast">
      SAFE &bull; FAST &bull; RELIABLE
    </div>
    <div class="token-for-you">
      FOR YOU
    </div>
  </div>

    <% else %>
      <!-- ──────────────────────────────────────────────────────── -->
      <!-- STANDARD RECEIPT LAYOUT                                  -->
      <!-- ──────────────────────────────────────────────────────── -->
      <table style="width: 100%; height: 100%; border-collapse: collapse;">
        <tr>
          <td style="vertical-align: top; padding: 0;">
            <!-- Subtle Background Watermark -->
            <div class="std-watermark">
              <svg xmlns="http://www.w3.org/2000/svg" width="100%" height="100%">
                <defs>
                  <pattern id="wavy" x="0" y="0" width="30" height="6" patternUnits="userSpaceOnUse">
                    <path d="M0 3 Q7.5 -1, 15 3 T30 3" fill="none" stroke="#000000" stroke-width="0.2" opacity="0.08"/>
                  </pattern>
                </defs>
                <rect x="0" y="0" width="100%" height="100%" fill="url(#wavy)"/>
              </svg>
            </div>

            <!-- Logo -->
            <div class="std-logo-container">
              <img src="https://cdn.lipagas.co/bot/assets/lipagas.svg" class="std-logo-img" alt="LipaGas" />
            </div>

            <!-- Checkmark Graphic -->
            <div class="std-checkmark-container" style="display: flex; justify-content: center; align-items: center; margin-bottom: 5pt;">
              <div class="logo-text">
                <svg width="54pt" height="54pt" viewBox="0 0 24 24" id="verified" xmlns="http://www.w3.org/2000/svg">
                  <path d="M21.37,12c0,1-.86,1.79-1.14,2.67s-.1,2.08-.65,2.83-1.73.94-2.5,1.49-1.28,1.62-2.18,1.92S13,20.65,12,20.65s-2,.55-2.9.27S7.67,19.55,6.92,19,5,18.28,4.42,17.51s-.35-1.92-.65-2.83S2.63,13,2.63,12s.86-1.8,1.14-2.68.1-2.08.65-2.83S6.15,5.56,6.92,5,8.2,3.39,9.1,3.09s1.93.27,2.9.27,2-.55,2.9-.27S16.33,4.46,17.08,5s1.94.72,2.5,1.49.35,1.92.65,2.83S21.37,11,21.37,12Z" fill="#43b02a"></path>
                  <polyline points="8 12 11 15 16 10" fill="none" stroke="#ffffff" stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5"></polyline>
                </svg>
              </div>
            </div>

            <!-- Greeting -->
            <div class="std-greeting">
              <div class="std-greeting-title">Hi <%= name %>,</div>
              <div class="std-greeting-subtitle">Thank you for trusting LipaGas.</div>
            </div>

            <!-- Two Column Layout -->
            <table class="std-two-col">
              <tr>
                <!-- Left Box -->
                <td class="std-left-box">
                  <div class="std-amount-title">Total Amount Paid:</div>
                  <div class="std-amount-value">KES <%= fmt_amount %></div>
                  <div class="std-phone-label">Phone: <strong><%= phone %></strong></div>
                  <%= if location != "" do %>
                    <div class="std-phone-label" style="margin-top: 5px;">Delivery: <strong><%= location %></strong></div>
                  <% end %>
                </td>
                <!-- Right Box -->
                <td class="std-right-box">
                  <div class="std-meta-row">
                    <span class="std-meta-label">Date:</span>
                    <span class="std-meta-value"><%= date %></span>
                  </div>
                  <div class="std-meta-row">
                    <span class="std-meta-label">Transaction No:</span>
                    <span class="std-meta-value"><%= receipt_no %></span>
                  </div>
                  <div class="std-meta-row">
                    <span class="std-meta-label">Payment Type:</span>
                    <span class="std-meta-value">Merchant Pay</span>
                  </div>
                </td>
              </tr>
            </table>

            <!-- Item Table -->
            <table class="std-table">
              <thead>
                <tr>
                  <th class="std-table-header-col std-table-col-item">ITEM</th>
                  <th class="std-table-header-col std-table-col-qty">QTY</th>
                  <th class="std-table-header-col std-table-col-price">PRICE</th>
                </tr>
              </thead>
              <tbody>
                <%= for item <- items do %>
                <tr>
                  <td class="std-table-row-col std-table-col-item"><%= item.name %></td>
                  <td class="std-table-row-col std-table-col-qty"><%= item.qty %></td>
                  <td class="std-table-row-col std-table-col-price">
                    <%= if item.price != "" do %>KES <%= item.price %><% else %>-<% end %>
                  </td>
                </tr>
                <% end %>
              </tbody>
            </table>
          </td>
        </tr>
        <tr>
          <td style="vertical-align: bottom; padding: 0; height: 1%;">
            <!-- Dynamic Footer Section -->
        <table class="std-footer-table">
          <tr>
            <!-- Left: Empty (Holds QR line) -->
            <td class="std-footer-left">
              <div class="std-qr-line"></div>
            </td>

            <!-- Center: ETR & BADGE -->
            <td class="std-footer-center">
              <div class="std-etr-section">
                <div class="std-etr-title" style="margin-bottom: 8px;">ETR</div>
                <div class="std-contact-info">
                  Pine Tree Plaza Ngong Road<br>
                  P.O Box 233 &ndash; 00100, Nairobi<br>
                  +254 112 250 250<br>
                  www.lipagas.co
                </div>
              </div>

              <div class="std-bottom-badge-container">
                <div class="std-bottom-badge-top">SAFE &bull; FAST &bull; RELIABLE</div>
                <div class="std-bottom-badge-bottom">FOR YOU</div>
              </div>
            </td>

            <!-- Right: QR Code -->
            <td class="std-footer-right">
              <div class="std-kra-marks">
                <div class="kra-qr-wrapper">
                  <div class="kra-qr-code">
                    <%= qr_svg %>
                  </div>
                </div>
              </div>
            </td>
          </tr>
        </table>
          </td>
        </tr>
      </table>
    <% end %>
  </div>
</body>
</html>
    """,[name: name, location: location, phone: phone, date: date, receipt_no: receipt_no, amount: amount, fmt_amount: fmt_amount, token: token, is_token_receipt: is_token_receipt, meter: meter, qr_svg: qr_svg, guilloche_svg: guilloche_svg, items: items])
  end
  defp generate_qr_svg(data) do
    encoded = EQRCode.encode(data, :q)
    %EQRCode.Matrix{matrix: rows} = encoded
    size = EQRCode.Matrix.size(encoded)
    m = 10       # pixels per module
    q = 4        # quiet-zone modules
    dim = (size + 2 * q) * m
    off = q * m

    matrix_list = rows |> Tuple.to_list() |> Enum.map(&Tuple.to_list/1)

    # EQRCode includes a 2-module quiet zone in the matrix
    # So actual QR data starts at row/col index 2
    qz = 2  # EQRCode quiet zone size in the matrix

    in_finder? = fn r, c ->
      # Top-Left finder: rows 2..8, cols 2..8 (in matrix coords)
      tl = r >= qz and r < qz+7 and c >= qz and c < qz+7
      # Top-Right finder: rows 2..8, cols size-5..size-1 (last 7 cols)
      tr = r >= qz and r < qz+7 and c >= size-qz-7 and c < size-qz
      # Bottom-Left finder: rows size-5..size-1, cols 2..8
      bl = r >= size-qz-7 and r < size-qz and c >= qz and c < qz+7
      tl or tr or bl
    end

    get_dark? = fn r, c ->
      if r >= 0 and r < size and c >= 0 and c < size do
        Enum.at(Enum.at(matrix_list, r), c) == 1
      else
        false
      end
    end

    # Slightly rounded data modules to match the requested visual style
    modules =
      for r <- 0..(size - 1), c <- 0..(size - 1), into: "" do
        if get_dark?.(r, c) and not in_finder?.(r, c) do
          cx = off + c * m
          cy = off + r * m
          "<rect x='#{cx}' y='#{cy}' width='#{m+0.5}' height='#{m+0.5}' rx='#{m*0.3}' ry='#{m*0.3}' fill='#1b4d11'/>"
        else
          ""
        end
      end

    # Scannable Finder Pattern with custom visual effects ("Leaf" style)
    # The user requested specific shapes for the corners (finders):
    # - Outer Frame: 3 rounded corners, 1 sharp corner pointing towards the QR center
    # - Pupil: Pure circle
    draw_finder = fn r_off, c_off, type ->
      # r_off, c_off are in matrix coordinates (including EQRCode's quiet zone)
      x = off + c_off * m
      y = off + r_off * m

      # Outer 7x7 black square - rounded
      outer_rounded = "<rect x='#{x}' y='#{y}' width='#{7*m}' height='#{7*m}' rx='#{m*2.5}' ry='#{m*2.5}' fill='#43b02a'/>"
      
      # Inner 5x5 white square - rounded
      white_rounded = "<rect x='#{x+m}' y='#{y+m}' width='#{5*m}' height='#{5*m}' rx='#{m*1.5}' ry='#{m*1.5}' fill='#ffffff'/>"
      
      # Sharp corner modifiers to square off the corner pointing to the center
      {bx, by, wx, wy} = case type do
        :tl -> {x + 5*m, y + 5*m, x + 4*m, y + 4*m} # Bottom-Right sharp
        :tr -> {x,       y + 5*m, x + m,   y + 4*m} # Bottom-Left sharp
        :bl -> {x + 5*m, y,       x + 4*m, y + m}   # Top-Right sharp
      end
      
      outer_sharp = "<rect x='#{bx}' y='#{by}' width='#{2*m}' height='#{2*m}' fill='#43b02a'/>"
      white_sharp = "<rect x='#{wx}' y='#{wy}' width='#{2*m}' height='#{2*m}' fill='#ffffff'/>"
      
      # Center 3x3 pupil - pure circle
      pupil = "<circle cx='#{x + 3.5*m}' cy='#{y + 3.5*m}' r='#{1.5*m}' fill='#000000'/>"

      outer_rounded <> outer_sharp <> white_rounded <> white_sharp <> pupil
    end

    finders = [
      draw_finder.(qz, qz, :tl),           # Top-Left
      draw_finder.(qz, size-qz-7, :tr),    # Top-Right
      draw_finder.(size-qz-7, qz, :bl)     # Bottom-Left
    ] |> Enum.join()

    cx = dim / 2
    cy = dim / 2
    
    # Draw our LipaGas single mark in the center
    # Logo covers ~20% of QR area - safe with :q (25%) error correction
    # lr must be <= 0.225 * (dim/2) to stay within correction capacity
    lr = m * 3.5
    logo_w = 1088
    logo_h = 1786
    ls = (lr * 1.6) / max(logo_w, logo_h)
    lx = cx - logo_w * ls / 2
    ly = cy - logo_h * ls / 2

    # These are the precise paths of the lipagas-single.svg you provided
    logo_paths =
      "<path d='M817.08 0H1087.57C1087.57 164.43 1016.16 305.061 903.636 406.749C1016.16 508.436 1087.57 649.067 1087.57 811.334C1087.57 1112.07 847.375 1352.22 546.595 1352.22C245.815 1352.22 5.62402 1112.07 5.62402 811.334C5.62402 510.599 245.815 270.445 546.595 270.445C693.739 270.445 817.08 147.122 817.08 0ZM276.108 811.334C276.108 958.456 399.451 1081.78 546.595 1081.78C693.739 1081.78 817.08 958.456 817.08 811.334C817.08 664.212 693.739 540.889 546.595 540.889C399.451 540.889 276.108 664.212 276.108 811.334ZM817.08 1784.93H546.595C546.595 1484.2 786.787 1244.05 1087.57 1244.05V1514.49C940.422 1514.49 817.08 1637.81 817.08 1784.93Z' fill='#ffffff'/>" <>
      "<path d='M406.406 1582.45C406.406 1694.66 315.429 1785.63 203.203 1785.63C90.9773 1785.63 0 1694.66 0 1582.45C0 1470.24 90.9773 1379.28 203.203 1379.28C315.429 1379.28 406.406 1470.24 406.406 1582.45Z' fill='#ffffff'/>"

    # Assemble: white halo + green circle + LipaGas paths
    center =
      "<circle cx='#{cx}' cy='#{cy}' r='#{lr + m}' fill='#ffffff'/>" <>
      "<circle cx='#{cx}' cy='#{cy}' r='#{lr}' fill='#43b02a'/>" <>
      "<g transform='translate(#{lx},#{ly}) scale(#{ls})'>#{logo_paths}</g>"

    bg = ""
    "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 #{dim} #{dim}' width='100%' height='100%' shape-rendering='crispEdges'>#{bg}#{finders}#{modules}#{center}</svg>"
  end

  defp guilloche_path(r1, r2, d) do
    # Epitrochoid parametric curve: creates the layered petal rosette effect
    # lcm determines when the curve closes; we need r2 full rotations
    steps = 6000
    pts = for i <- 0..steps do
      t = i / steps * 2 * :math.pi * r2
      x = (r1 + r2) * :math.cos(t) - d * :math.cos((r1 + r2) / r2 * t)
      y = (r1 + r2) * :math.sin(t) - d * :math.sin((r1 + r2) / r2 * t)
      {Float.round(x + 100, 1), Float.round(y + 100, 1)}
    end
    [{sx, sy} | rest] = pts
    coords = Enum.map(rest, fn {x, y} -> "L#{x} #{y}" end) |> Enum.join(" ")
    "M#{sx} #{sy} #{coords}Z"
  end

  defp generate_guilloche do
    p1 = guilloche_path(66, 13, 68)
    p2 = guilloche_path(50, 11, 52)
    p3 = guilloche_path(35, 9, 37)
    p4 = guilloche_path(21, 7, 23)
    p5 = guilloche_path(10, 5, 11)
    # The max radius of the epitrochoid is r1 + r2 + d = 66 + 13 + 68 = 147.
    # Centered at 100, 100, the bounds are -47 to 247.
    # ViewBox set to fully encompass the natural circular shape to remove square cutoffs.
    """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="-50 -50 300 300" width="100%" height="100%">
      <path d="#{p1}" fill="none" stroke="#bdeaa9" stroke-width="0.1" opacity="1.0"/>
      <path d="#{p2}" fill="none" stroke="#9adb7c" stroke-width="0.15" opacity="1.0"/>
      <path d="#{p3}" fill="none" stroke="#78cc50" stroke-width="0.2" opacity="1.0"/>
      <path d="#{p4}" fill="none" stroke="#56bd24" stroke-width="0.25" opacity="1.0"/>
      <path d="#{p5}" fill="none" stroke="#43b02a" stroke-width="0.3" opacity="1.0"/>
    </svg>
    """
  end


  def generate_receipt(phone, amount, token, receipt_no, meter \\ nil) do
    File.mkdir_p!(@receipts_dir)
    id = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
    html_path = Path.join(@receipts_dir, "#{id}.html")
    pdf_path = Path.join(@receipts_dir, "#{id}.pdf")

    html = generate_html(phone, amount, token, receipt_no, meter)

    File.write!(html_path, html)

    is_token = amount > 0 and token != nil
    w = if is_token, do: "375.12pt", else: "360pt"
    h = if is_token, do: "751.92pt", else: "640pt"

    {_, 0} = System.cmd("wkhtmltopdf", [
      "--page-width", w,
      "--page-height", h,
      "--margin-top", "0",
      "--margin-bottom", "0",
      "--margin-left", "0",
      "--margin-right", "0",
      "--disable-smart-shrinking",
      html_path,
      pdf_path
    ])

    

    File.rm!(html_path)

    id
  end

  def get_pdf_path(id) do
    Path.join(@receipts_dir, "#{id}.pdf")
  end

end
