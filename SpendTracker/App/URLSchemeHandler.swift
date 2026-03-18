// URLSchemeHandler.swift
// URL scheme handling is implemented in SpendTrackerApp.swift
// Scheme: spendtracker://import?sms=<encoded>&sender=<encoded>
//
// iPhone Shortcuts setup for automatic SMS capture:
// 1. Open Shortcuts → Automation → New Automation → Message
// 2. Filter: Sender contains "HDFC" (repeat for SBI, ICICI, etc.)
// 3. Action: "Get Details of Messages" → select "Body"
// 4. Action: "URL" → type: spendtracker://import?sms=
// 5. Append "URL Encode" of the message body to the URL
// 6. Action: "Open URLs"
// 7. Disable "Ask Before Running"
