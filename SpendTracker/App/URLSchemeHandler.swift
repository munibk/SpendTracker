import SwiftUI

// MARK: - URL Scheme Handler
// Handles: spendtracker://import?sms=<encoded>&sender=<encoded>
// Used by iPhone Shortcuts to auto-pass bank SMS into the app

extension SpendTrackerApp {

    func handleIncomingURL(_ url: URL) {
        guard url.scheme?.lowercased() == "spendtracker" else { return }

        switch url.host?.lowercased() {
        case "import":
            handleSMSImport(url: url)
        default:
            break
        }
    }

    private func handleSMSImport(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else { return }

        let params = Dictionary(uniqueKeysWithValues: queryItems.compactMap { item -> (String, String)? in
            guard let value = item.value else { return nil }
            return (item.name, value)
        })

        guard let smsBody = params["sms"]?.removingPercentEncoding else { return }
        let sender = params["sender"]?.removingPercentEncoding ?? "BANK"

        DispatchQueue.main.async {
            _ = self.smsService.importManualSMS(smsBody, sender: sender)
        }
    }
}

/*
 ──────────────────────────────────────────────────────────────────
 iPhone Shortcuts Setup (for near-automatic SMS capture):
 ──────────────────────────────────────────────────────────────────

 1. Open Shortcuts app → Automation → New Automation
 2. Trigger: "Message" → Filter: "Message contains" → type "debited" OR "credited"
    (Or filter by sender: HDFC, SBI, ICICI, etc.)
 3. Action 1: "Get Details of Messages" → Get "Body" of "Shortcut Input"
 4. Action 2: "URL Encode" the message body
 5. Action 3: Open URLs:
      spendtracker://import?sms=[Encoded Body]&sender=[Sender Name]
 6. Toggle "Ask Before Running" → OFF
 7. Toggle "Notify When Run" → OFF

 Now whenever a bank SMS arrives, Shortcuts will silently
 open SpendTracker and import the transaction automatically!

 ──────────────────────────────────────────────────────────────────
 Register URL Scheme in Info.plist (add this inside the <dict>):
 ──────────────────────────────────────────────────────────────────

 <key>CFBundleURLTypes</key>
 <array>
     <dict>
         <key>CFBundleURLName</key>
         <string>com.yourname.spendtracker</string>
         <key>CFBundleURLSchemes</key>
         <array>
             <string>spendtracker</string>
         </array>
     </dict>
 </array>
*/
