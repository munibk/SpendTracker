# Gmail Integration Setup Guide

## Overview
SpendTracker uses Gmail's official API to read your bank transaction emails.
It only requests READ-ONLY access — it never sends, modifies, or deletes emails.

---

## Step 1 — Create Google Cloud Project (Free)

1. Go to https://console.cloud.google.com
2. Click **Select a project** → **New Project**
3. Name: `SpendTracker` → Click **Create**

---

## Step 2 — Enable Gmail API

1. Go to **APIs & Services → Library**
2. Search **Gmail API**
3. Click it → Click **Enable**

---

## Step 3 — Create OAuth Credentials

1. Go to **APIs & Services → Credentials**
2. Click **+ Create Credentials → OAuth Client ID**
3. If prompted, configure **OAuth Consent Screen** first:
   - User Type: **External**
   - App name: `SpendTracker`
   - Your email as support email
   - Click **Save and Continue** through all steps
   - Add your Gmail as a **Test User**
4. Back to Create OAuth Client ID:
   - Application type: **iOS**
   - Bundle ID: `com.yourname.spendtracker`
   - Click **Create**
5. Copy the **Client ID** (looks like: `396449652721-030jr599hc1r67sj22hngg0imt4pha0s.apps.googleusercontent.com`)

---

## Step 4 — Add Client ID to App

1. Open `SpendTracker/Services/GmailService.swift`
2. Find this line:
   ```swift
   private let clientID = "YOUR_GOOGLE_CLIENT_ID.apps.googleusercontent.com"
   ```
3. Replace `YOUR_GOOGLE_CLIENT_ID` with your actual Client ID
4. Save the file

---

## Step 5 — Rebuild & Reinstall

```bash
git add .
git commit -m "feat: add Gmail client ID"
git push
```

Then rebuild via GitHub Actions → reinstall IPA

---

## Step 6 — Connect in App

1. Open SpendTracker → Tap **Gmail** tab
2. Tap **Connect with Gmail**
3. Safari opens → Sign in with Google
4. Allow SpendTracker to read emails
5. App opens automatically — you're connected!

---

## Step 7 — Import Emails

1. Tap **Fetch Bank Emails Now**
2. App scans your Gmail for bank transaction emails
3. All transactions are imported automatically!

---

## Supported Bank Email Senders

| Bank | Email |
|------|-------|
| HDFC | alerts@hdfcbank.net |
| ICICI | credit_cards@icicibank.com |
| SBI | sbiatm@sbi.co.in |
| Axis | alerts@axisbank.com |
| Kotak | noreply@kotak.com |
| All Banks | Subject: "debited", "credited", "transaction" |

---

## Privacy & Security

- SpendTracker ONLY reads emails matching bank patterns
- Access token stored securely on your device
- No data sent to any server
- You can disconnect anytime from Settings → Gmail tab
