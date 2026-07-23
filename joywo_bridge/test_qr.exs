defmodule TestQR do
  def run do
    html = LipagasBridge.Receipt.generate_html("0700", 1500, nil, "RCP-12345")
    # Extract the SVG from the QR section
    qr_data = "https://lipagas.co/verify/RCP-12345"
    encoded = EQRCode.encode(qr_data, :h)
    IO.puts("Version: #{EQRCode.Matrix.size(encoded)}")
  end
end
TestQR.run()
