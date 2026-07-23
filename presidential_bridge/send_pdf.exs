defmodule SendPDF do
  def run do
    phone = "254723539760"
    amount = "950"
    token = "0237-7746-8981-9028-5626"
    receipt_no = "UFLEM8UHCD"
    meter = "04172997324"

    id = PresidentialBridge.Receipt.generate_receipt(phone, amount, token, receipt_no, meter)
    pdf_path = PresidentialBridge.Receipt.get_pdf_path(id)
    
    IO.puts("Generated PDF at #{pdf_path}")
    
    case PresidentialBridge.Meta.upload_media(pdf_path, "application/pdf") do
      {:ok, media_id} ->
        IO.puts("Uploaded successfully, media_id: #{media_id}")
        PresidentialBridge.Meta.send_document_by_id(phone, media_id, "LipaGas_Token_UFLEM8UHCD.pdf")
        IO.puts("Sent document!")
      error ->
        IO.puts("Failed to upload: #{inspect(error)}")
    end
  end
end

SendPDF.run()
