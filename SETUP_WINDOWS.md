# 🛠️ Complete Setup Guide — SpendTracker on Windows

## ⚡ Fastest Path: GitHub Actions (100% Free, No Mac Needed)

### Step 1 — Create a GitHub Account
Go to https://github.com and sign up (free).

### Step 2 — Create a Private Repository
1. Click **New Repository**
2. Name it `SpendTracker`
3. Set it to **Private**
4. Click **Create Repository**

### Step 3 — Upload This Project
Option A — GitHub Desktop (easiest on Windows):
1. Download GitHub Desktop: https://desktop.github.com
2. Clone your new repo
3. Copy all files from this `SpendTracker/` folder into it
4. Commit & Push

Option B — Command line:
```bash
git init
git add .
git commit -m "Initial commit"
git remote add origin https://github.com/YOUR_USERNAME/SpendTracker.git
git push -u origin main
```

### Step 4 — Trigger the Build
1. Go to your repo on GitHub.com
2. Click **Actions** tab
3. Click **Build SpendTracker IPA**
4. Click **Run workflow** → **Run workflow**
5. Wait ~10 minutes

### Step 5 — Download the IPA
1. Click the completed workflow run
2. Scroll down to **Artifacts**
3. Download **SpendTracker-IPA.zip**
4. Extract it → you'll get `SpendTracker.ipa`

---

## 📲 Install on iPhone (Windows + AltStore — Free)

### Step 1 — Install AltServer on Windows
1. Download from https://altstore.io/altserver/
2. Install and run AltServer
3. Click the icon in system tray

### Step 2 — Install AltStore on iPhone
1. Connect iPhone to PC via USB
2. Trust the computer on your iPhone
3. Click AltServer tray icon → **Install AltStore** → select your iPhone
4. Enter your Apple ID (free account works)

### Step 3 — Trust the App
1. On iPhone: **Settings → General → VPN & Device Management**
2. Find your Apple ID → **Trust**

### Step 4 — Install SpendTracker
1. Open AltStore on iPhone
2. Tap **My Apps** → **+** (top left)
3. Select the `SpendTracker.ipa` file
4. App installs!

### Step 5 — Keep It Active
- AltStore re-signs apps every 7 days automatically when:
  - Your iPhone is connected to the same WiFi as your PC
  - AltServer is running in the tray
- **Or** get AltStore PAL (~€1.50/year) for unlimited duration

---

## 🔄 Alternative: Sideloadly (Also Free)

1. Download: https://sideloadly.io/#download
2. Open Sideloadly
3. Connect iPhone via USB
4. Drag `SpendTracker.ipa` into Sideloadly
5. Enter Apple ID → Click **Start**
6. Trust app in iPhone Settings

---

## 📩 About SMS Reading

### Important Reality Check
iOS **does not allow** any app to read SMS messages in the background via public APIs. This is an Apple privacy restriction. Here is how SpendTracker handles it:

| Method | How It Works | Setup |
|--------|-------------|-------|
| **Manual Paste** (default) | You copy-paste bank SMS text into the app | Works on all iPhones, no setup |
| **Automation (Shortcuts)** | iPhone Shortcuts runs when SMS arrives → sends to app | Free, built into iOS |
| **iCloud Sync** | Pair with a Mac and sync via shared iCloud container | Requires Mac |

### 🏆 Recommended: iPhone Shortcuts Automation
This is the best free solution that works without jailbreak:

1. Open **Shortcuts** app on iPhone
2. Go to **Automation** tab → **+** → **New Automation**
3. Select **Message** → set Filter: **Sender contains** `HDFC`, `SBI`, etc.
4. Add Action: **Open App** → **SpendTracker**
5. Add Action: **Text** → paste the shortcut URL scheme
6. Enable "Run Immediately"

This triggers SpendTracker to open whenever a bank SMS arrives, 
and you paste the SMS — takes 2 seconds.

### Advanced: X-Callback URL Scheme
SpendTracker supports `spendtracker://import?sms=<encoded_text>` 
so Shortcuts can pass the SMS body directly into the app automatically.

---

## 🏦 Supported Banks (25+)

| Bank | SMS Sender IDs |
|------|---------------|
| HDFC Bank | HDFC, HDFCBK, HDFCBANK |
| ICICI Bank | ICICI, ICICIB |
| SBI | SBI, SBIINB, SBIPSG |
| Axis Bank | AXIS, AXISBK |
| Kotak Mahindra | KOTAK, KOTAKBK |
| Yes Bank | YESBANK, YBL |
| IndusInd | INDUSIND |
| IDFC First | IDFCFIRST, IDFC |
| Federal Bank | FEDERALBANK |
| RBL Bank | RBLBANK |
| Bandhan Bank | BANDHAN |
| PNB | PNB, PUNJABNAT |
| Bank of Baroda | BOB, BARODABK |
| Canara Bank | CANARA |
| Union Bank | UNIONBANK |
| Bank of India | BOI |
| Central Bank | CBI |
| UCO Bank | UCO |
| Indian Bank | INDIANBANK |
| IOB | IOB |
| IDBI Bank | IDBI |
| AU Small Finance | AUBANK |
| Airtel Payments | AIRTEL |
| Paytm Payments | PAYTMBANK |
| + Any Generic | Detected by keywords |

---

## ❓ FAQ

**Q: Why can't the app read SMS automatically?**
A: Apple's iOS privacy model blocks all apps from reading SMS. Only telecom/dialer apps approved by Apple can do this. Use the Shortcuts automation method above for near-automatic capture.

**Q: Will the app expire after 7 days?**
A: Only if AltServer isn't running. Keep it in your PC's startup programs and it will auto-refresh silently.

**Q: Is my financial data safe?**
A: Yes — everything is stored only on your iPhone using UserDefaults. Nothing is uploaded anywhere.

**Q: Can I use this on iPad too?**
A: Yes, the UI is responsive and works on iPad.

**Q: How do I update the app?**
A: Make changes → push to GitHub → Actions builds a new IPA → drag into AltStore.
