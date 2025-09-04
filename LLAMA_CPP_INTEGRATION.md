# llama.cpp Integration Guide for SafeGuard iOS

## Overview
This guide covers integrating llama.cpp with SafeGuard's parent app for local LLM inference using the downloaded Gemma 2 2B model.

## Integration Steps

### 1. Add llama.cpp to Xcode Project

#### Option A: Swift Package Manager (Recommended)
1. Open `SafeGuardParent.xcodeproj` in Xcode
2. Go to **File → Add Package Dependencies**
3. Add: `https://github.com/ggerganov/llama.cpp`
4. Select version: Latest release
5. Add to target: SafeGuardParent

#### Option B: Manual Integration
```bash
# Clone llama.cpp
git clone https://github.com/ggerganov/llama.cpp.git
cd llama.cpp

# Build for iOS
cmake -B build-ios -DLLAMA_BUILD_EXAMPLES=OFF -DCMAKE_OSX_ARCHITECTURES="arm64" -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0
cmake --build build-ios --config Release

# Copy headers and library to Xcode project
cp build-ios/libllama.a /Users/ezakas/SafeGuard-iOS/SafeGuardParent/SafeGuardParent/
cp include/llama.h /Users/ezakas/SafeGuard-iOS/SafeGuardParent/SafeGuardParent/
```

### 2. Update GemmaModel.swift for Real Inference

Replace the current placeholder implementation with actual llama.cpp calls:

```swift
import Foundation
// Add llama.cpp bridging header

class GemmaModel {
    private var ctx: OpaquePointer?
    private var model: OpaquePointer?
    private let modelPath: String
    
    init(modelPath: String) {
        self.modelPath = modelPath
    }
    
    func loadModel() async throws {
        // Initialize llama.cpp context
        // Load GGUF model file
        // Set up sampling parameters
    }
    
    func processNaturalLanguage(_ input: String) async throws -> MCPCommand {
        // Use llama.cpp to generate structured JSON response
        // Parse JSON into MCPCommand
        // Return structured command
    }
}
```

### 3. Model File Integration

The Gemma model is already downloaded to:
`/Users/ezakas/SafeGuard-iOS/SafeGuardParent/SafeGuardParent/Models/gemma-3n-e2b.gguf`

**Current Setup**: Model path uses fallback logic:
1. **Bundle Resource**: `Bundle.main.path(forResource: "gemma-3n-e2b", ofType: "gguf")` (production)
2. **Development Path**: Local file system path (current development)

**For Production Deployment**:
1. Drag model file into Xcode project
2. Ensure "Add to target" is checked for SafeGuardParent
3. Set bundle resource type in Build Phases

### 4. Bridging Header Setup

Create `SafeGuardParent-Bridging-Header.h`:
```c
#import "llama.h"
```

Add to Build Settings:
- **Objective-C Bridging Header**: `SafeGuardParent/SafeGuardParent-Bridging-Header.h`

### 5. Build Configuration

Add to **Build Settings**:
- **Header Search Paths**: Add llama.cpp include directory
- **Library Search Paths**: Add llama.cpp build directory  
- **Other Linker Flags**: `-lllama`

### 6. Testing Integration

Run the existing test:
```bash
swift test_nlp_commands.swift
```

Test with actual parent app by building in Xcode and testing these commands:
- "Block all games for 2 hours"
- "Give him 10 more minutes"
- "Send warning that dinner is ready"

## Current Implementation Status

✅ **Completed Infrastructure:**
- MCP tool definitions (`MCPTypes.swift`)
- SafeGuard MCP server (`SafeGuardMCP.swift`) 
- Enhanced command parsing in child device
- Structured command execution pipeline
- Gemma model wrapper foundation (`GemmaModel.swift`)
- Model file downloaded (1.5GB GGUF format)

🔄 **Next Steps:**
1. Add llama.cpp framework to Xcode project
2. Implement actual LLM inference in `GemmaModel.swift`
3. Test complete pipeline with real model
4. Build and deploy to test devices

## File Structure

```
SafeGuardParent/
├── LLM/
│   ├── GemmaModel.swift         ✅ Created (placeholder)
│   ├── SafeGuardMCP.swift       ✅ Created  
│   └── MCPTypes.swift           ✅ Created
├── Models/
│   └── gemma-3n-e2b.gguf       ✅ Downloaded (1.5GB)
└── FamilyControlsManager.swift  ✅ Updated for MCP pipeline
```

## Integration Benefits

1. **Natural Language Understanding**: Replace simple keyword matching with sophisticated LLM parsing
2. **Structured Commands**: Enhanced command format with duration, app targeting, custom messages
3. **MCP Architecture**: Standardized tool calling for consistent command execution
4. **Local Processing**: On-device inference for privacy and offline capability
5. **Backward Compatibility**: Fallback to keyword matching if LLM fails

The infrastructure is complete and ready for llama.cpp integration!