# SafeGuard iOS - Simple Parental Controls

A clean, simple parental control system using iOS Screen Time API and Firebase for real-time communication between parent and child devices.

## Project Structure

```
SafeGuard-iOS/
├── SafeGuardParent/               # Parent iPhone/iPad App
│   ├── ContentView.swift          # Simple toggle & button UI
│   ├── FamilyControlsManager.swift # Parent control logic
│   └── FirebaseManager.swift      # Firebase command transmission
├── SafeGuardChild/                # Child iPad monitoring app
│   ├── SafeGuardChildApp.swift    # Command processing & restrictions
│   ├── BlockingOverlay.swift      # Countdown timer & blocking overlays
│   └── FirebaseManager.swift      # Firebase listener
└── database.rules.json            # Firebase security rules
```

## Features

### Parent App
- **Restrictions Toggle:** Simple on/off switch for blocking apps
- **5-Minute Warning:** Button to send countdown timer to child device
- **Real-time Status:** See child device connection and restriction status

### Child App
- **Automatic Blocking:** Applies Family Controls restrictions when enabled
- **Countdown Timer:** Shows persistent timer overlay in top-right corner
- **Background Listener:** Receives commands even when app is in background

## Technical Requirements

- iOS 17.0+ (Screen Time API)
- Family Controls entitlement from Apple
- Firebase Realtime Database for device communication
- Xcode 15+

## Setup Instructions

### 1. Firebase Setup
1. Create a Firebase project at https://console.firebase.google.com
2. Add iOS apps for both parent and child
3. Download `GoogleService-Info.plist` files
4. Deploy security rules: `firebase deploy --only database`

### 2. Xcode Configuration
1. Open both Xcode projects
2. Add your Apple Developer Team ID
3. Request Family Controls entitlement from Apple
4. Add `GoogleService-Info.plist` to each project

### 3. Installation
1. Build and install SafeGuardParent on parent's iPhone/iPad
2. Build and install SafeGuardChild on child's iPad
3. Grant Family Controls permissions on child device
4. Devices will auto-connect via Firebase

## How It Works

**Restrictions Toggle ON:**
- Parent app sends "shutdown" command to Firebase
- Child app receives command and applies:
  - Blocks all app categories via Screen Time API
  - Shows full-screen blocking overlay
  - Disables Game Center and in-app purchases

**5-Minute Warning:**
- Parent app sends "warning minutes:5" command
- Child app shows countdown timer in top-right corner
- Timer persists across apps
- Changes color: Orange → Yellow (2min) → Red (1min)

**Restrictions Toggle OFF:**
- Parent app sends "allow" command
- Child app removes all restrictions
- Hides countdown and blocking overlays

## Command Protocol

Commands are sent via Firebase Realtime Database:
- `shutdown` - Enable restrictions
- `allow` - Disable restrictions
- `warning minutes:5` - Show 5-minute countdown

## Security

- Firebase security rules require authentication
- Anonymous auth enabled for device registration
- Commands confirmed with callback mechanism
- 15-30 second timeout for offline devices