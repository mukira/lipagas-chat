phone = "254723539760"
amount = "500"
receipt = "TEST-RCT-123"
meter = nil
token = nil

IO.puts("Generating receipt...")
id = PresidentialBridge.Receipt.generate_receipt(phone, amount, token, receipt, meter)
pdf_path = PresidentialBridge.Receipt.get_pdf_path(id)

IO.puts("Uploading to Meta from #{pdf_path}...")
case PresidentialBridge.Meta.upload_media(pdf_path) do
  {:ok, media_id} ->
    IO.puts("Uploaded! Media ID: #{media_id}")
    IO.puts("Sending to WhatsApp...")
    res = PresidentialBridge.Meta.send_document_by_id(phone, media_id, "LipaGas_Receipt_#{receipt}.pdf")
    IO.puts("Result: #{inspect(res)}")
  err ->
    IO.puts("Failed to upload: #{inspect(err)}")
end

File.rm(pdf_path)
