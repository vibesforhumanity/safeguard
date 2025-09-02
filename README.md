# SafeGuard iOS - Intelligent Parental Controls

## Project Structure

```
SafeGuard-iOS/
├── PRD_Parental_Controls_App.md    # Product Requirements Document
├── ParentApp/                      # Parent iPhone/iPad App
│   ├── SafeGuardParent.swift      # Main parent app UI
│   ├── FamilyControlsManager.swift # Screen Time API integration
│   └── Info.plist                 # App configuration with Family Controls entitlement
├── ChildMonitor/                   # Child iPad monitoring app
│   ├── ChildDeviceMonitor.swift   # Background monitoring and command processing
│   └── DeviceActivityMonitor.swift # Device activity tracking
├── Shared/                         # Shared components
│   ├── ContentModerator.swift     # Content analysis and filtering logic
│   └── CloudKitManager.swift      # Real-time parent-child communication
└── SafeGuardParent.xcodeproj/     # Xcode project file
```

## MVP Features

1. **Real-time Controls:** Parent can instantly control child's iPad
2. **Conversational Interface:** Natural language commands like "educational only"
3. **Basic Content Filtering:** Age-appropriate app category restrictions
4. **Warning System:** Timed warnings before restrictions activate

## Technical Requirements

- iOS 17.0+ (Screen Time API)
- Family Controls entitlement from Apple
- CloudKit for device communication
- Family Sharing group setup

## Setup Instructions

1. Open `SafeGuardParent.xcodeproj` in Xcode
2. Add your Apple Developer Team ID
3. Request Family Controls entitlement from Apple
4. Build and install parent app on iPhone
5. Build and install child monitor on iPad
6. Pair devices through Family Sharing

## Next Steps

- Test basic app restrictions
- Implement real-time command transmission
- Add content analysis capabilities
- Integrate with streaming service APIs