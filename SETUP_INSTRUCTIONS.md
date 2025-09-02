# SafeGuard iOS Setup Instructions

## Create Xcode Project Manually

1. **Open Xcode**
2. **Create New Project:**
   - Choose "iOS" → "App"
   - Product Name: `SafeGuardParent`
   - Bundle Identifier: `com.safeguard.parent`
   - Language: Swift
   - Interface: SwiftUI
   - Save to: `/Users/ezakas/SafeGuard-iOS/`

3. **Add Frameworks to Parent App:**
   - Select project → SafeGuardParent Target → "Frameworks, Libraries, and Embedded Content"
   - Add: `FamilyControls.framework`
   - Add: `ManagedSettings.framework`  
   - Add: `DeviceActivity.framework`
   - Add: `CloudKit.framework`

4. **Configure Entitlements:**
   - Select project → Target → "Signing & Capabilities"
   - Click "+" → Add "Family Controls"
   - The entitlement `com.apple.developer.family-controls` will be added

5. **Add Source Files:**
   - Delete the default `ContentView.swift`
   - Add these files to your project:
     - `ParentApp/SafeGuardParent.swift`
     - `ParentApp/FamilyControlsManager.swift`
     - `Shared/CloudKitManager.swift`
     - `Shared/ContentModerator.swift`

6. **Configure Info.plist:**
   - Add usage descriptions for Family Controls
   - Set minimum iOS version to 17.0

## Important Notes

- **Family Controls Entitlement:** You need to request this from Apple through your developer account
- **Testing:** Family Controls only works on physical devices, not simulator
- **Family Sharing:** Devices must be in the same Family Sharing group

## Create Child Monitor App

1. **Create Second Xcode Project:**
   - Product Name: `SafeGuardChild`
   - Bundle Identifier: `com.safeguard.child`
   - Copy files from `/SafeGuardChild/SafeGuardChild/` to new project
   - Add same frameworks as parent app

2. **Add CloudKit Schema:**
   - Both apps need CloudKit container: `iCloud.com.safeguard.family`
   - Record types: `ParentCommand`, `ChildActivity`

## Next Steps After Setup

1. Build and run parent app on iPhone
2. Build and run child monitor on iPad  
3. Configure CloudKit container in Apple Developer Console
4. Test cross-device communication and restrictions