defmodule TestScan do
  def run do
    data = "https://lipagas.co/verify/RCP-12345"
    svg = LipagasBridge.Receipt.generate_html("0700", 1500, "T", "RCP-12345")
    File.write!("test_receipt.html", svg)
  end
end
TestScan.run()
