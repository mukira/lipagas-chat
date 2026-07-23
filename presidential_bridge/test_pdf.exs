import PresidentialBridge.Receipt
html = PresidentialBridge.Receipt.generate_html("254723539760", 950, "0237-7746-8981-9028-5626", "UFLEM8UHCD", nil)
File.write!("/tmp/test.html", html)
System.cmd("wkhtmltopdf", ["--page-width", "562pt", "--page-height", "1127pt", "--margin-top", "0", "--margin-bottom", "0", "--margin-left", "0", "--margin-right", "0", "--disable-smart-shrinking", "--zoom", "1.0", "/tmp/test.html", "/tmp/test.pdf"])
