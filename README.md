# 💰 SpendTracker — Personal Bank SMS Analyzer for iOS

A **personal-use iOS app** that reads bank SMS messages, auto-categorizes spending, shows beautiful charts, and generates monthly reports. Built for Indian banks.

---

## ⚠️ Developing iOS on Windows — What You Need to Know

Apple requires **macOS + Xcode** to compile and sign iOS apps. On Windows, you have these options:

### ✅ Option A: macOS Virtual Machine (Recommended for Free)
1. Install **VMware Workstation** or **VirtualBox** (free)
2. Download a macOS Ventura/Sonoma VM image
3. Install **Xcode** inside the VM
4. Open this project in Xcode and build

### ✅ Option B: Rent a Mac in the Cloud (~$1/hour)
- Use **MacStadium**, **MacinCloud**, or **GitHub Actions** (free CI)
- Upload this project, build, download the `.ipa`

### ✅ Option C: GitHub Actions (100% Free)
- Push this code to a private GitHub repo
- Use the included `.github/workflows/build.yml`
- GitHub builds it on a real Mac and emails you the `.ipa`

### ✅ Option D: Buy a used Mac Mini (~₹15,000 secondhand)
- Most reliable long-term option

---

## 📱 Installing on Your iPhone WITHOUT App Store

### Method 1: AltStore (Free, easiest)
1. Install **AltServer** on Windows from https://altstore.io
2. Install **AltStore** on your iPhone via AltServer
3. Drag the `.ipa` file into AltStore → Install
4. Re-sign every 7 days (free) or use AltStore PAL (~€1.50/year)

### Method 2: Sideloadly (Free)
1. Download **Sideloadly** from https://sideloadly.io
2. Connect iPhone via USB
3. Drag `.ipa` → Install
4. Go to iPhone Settings → VPN & Device Management → Trust your Apple ID

### Method 3: Free Apple Developer Account + Xcode
- Connect iPhone to Mac/VM
- In Xcode: Product → Run (installs directly, no App Store needed)
- Valid for 7 days, re-run to refresh

---

## 🏦 Supported Banks
- HDFC Bank
- SBI (State Bank of India)
- ICICI Bank
- Axis Bank
- Kotak Mahindra Bank
- Yes Bank
- Punjab National Bank
- Bank of Baroda
- IndusInd Bank
- Federal Bank
- (Generic UPI pattern as fallback)

---

## 📂 Project Structure
```
SpendTracker/
├── App/
│   └── SpendTrackerApp.swift          # App entry point
├── Models/
│   ├── Transaction.swift              # Core data model
│   ├── Category.swift                 # Spending categories
│   └── MonthlyReport.swift            # Report model
├── Services/
│   ├── SMSReaderService.swift         # Reads Messages database
│   ├── SMSParserService.swift         # Parses bank SMS patterns
│   ├── CategoryService.swift          # Auto-categorization ML
│   ├── PersistenceService.swift       # CoreData storage
│   └── NotificationService.swift      # Background alerts
├── Views/
│   ├── Dashboard/                     # Home screen
│   ├── Transactions/                  # Transaction list
│   ├── Charts/                        # Pie/Bar/Line charts
│   ├── Reports/                       # Monthly PDF reports
│   └── Settings/                      # Config & bank setup
└── Extensions/                        # Helpers
```

---

## 🔧 Setup Steps
1. Open `SpendTracker.xcodeproj` in Xcode
2. Select your Apple ID in Signing & Capabilities
3. Change Bundle ID to something unique: `com.yourname.spendtracker`
4. Connect iPhone → Build & Run
5. Grant SMS permissions when prompted

---

## ✨ Features
- 📩 Auto-reads bank debit/credit SMS in background
- 🏷️ Smart category detection (Food, Shopping, UPI, Fuel, Bills, ATM)
- 📊 Interactive charts (Pie, Bar, Line trend)
- 📅 Monthly spending report with PDF export
- 🔔 Overspending alerts
- 💾 All data stored locally (privacy-first)
- 🌙 Dark mode support
