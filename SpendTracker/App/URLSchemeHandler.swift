// URLSchemeHandler.swift
// Intentionally empty — URL handling is in SpendTrackerApp.swift
// Shortcuts automation: spendtracker://import?sms=<encoded>&sender=<encoded>
//
// iPhone Shortcuts setup:
// 1. Shortcuts app → Automation → New Automation → Message
// 2. Filter: Sender contains "HDFC" (or SBI, ICICI, etc.)
// 3. Action: Get Details of Messages → Body
// 4. Action: URL → spendtracker://import?sms=[URL Encoded Body]
// 5. Action: Open URLs
// 6. Turn OFF "Ask Before Running"
