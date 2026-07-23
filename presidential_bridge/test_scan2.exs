defmodule TestScan do
  def run do
    svg = PresidentialBridge.Receipt.generate_html("0700", 1500, nil, "RCP-12345")
    File.write!("test_receipt2.html", svg)
  end
end
TestScan.run()
