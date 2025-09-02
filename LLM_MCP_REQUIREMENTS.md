# SafeGuard iOS - LLM/MCP Integration Requirements

## Project Overview
SafeGuard is a cross-device parental controls system with two iOS apps:
- **Parent App** (iPhone): Sends natural language commands via Firebase
- **Child App** (iPad): Receives commands and applies Family Controls restrictions

## Current State (main branch)
✅ Firebase Realtime Database communication across family Apple IDs  
✅ Basic keyword matching: "shutdown", "warning", "allow"  
✅ Family Controls app blocking with DeviceActivity scheduling  
✅ Modern ChatGPT-style UI with suggested prompts  
✅ Real-time status updates and notifications  

## LLM/MCP Integration Goals (llm-mcp-integration branch)

### 1. Replace Keyword Matching with LLM
**Current**: Simple `contains()` logic for "shutdown", "warning", "allow"  
**Target**: Gemma 3n E2B model (~1GB) for natural language understanding

**Example transformations:**
- "Block all games for 2 hours" → `{"action": "shutdown", "duration": 7200, "category": "games"}`
- "Give him 10 more minutes" → `{"action": "extend", "duration": 600}`
- "No more YouTube until homework is done" → `{"action": "block_app", "app": "youtube", "condition": "homework"}`

### 2. MCP Server Architecture
Create MCP bridge with these tools:

```typescript
{
  "send_restriction_command": {
    "description": "Apply app/time restrictions to child device",
    "parameters": {
      "action": "shutdown|warning|allow|extend",
      "duration_minutes": "number",
      "apps": "array of app names",
      "message": "string for notifications"
    }
  },
  "get_device_status": {
    "description": "Check current restrictions and device state",
    "returns": "active restrictions, blocked apps, schedule"
  },
  "check_child_activity": {
    "description": "Get recent app usage data",
    "returns": "app usage statistics, time spent"
  },
  "schedule_timed_restriction": {
    "description": "Set time-based controls",
    "parameters": {
      "start_time": "ISO datetime",
      "end_time": "ISO datetime", 
      "restriction_type": "bedtime|educational|social_only"
    }
  }
}
```

### 3. Technical Implementation

#### Model Integration
- **Framework**: llama.cpp with GGUF format (proven iOS compatibility)
- **Model**: Gemma 3n E2B (~2B parameters, ~1GB quantized)
- **Inference**: Local on-device processing for privacy
- **Integration**: Swift Package Manager + C++ bridging

#### MCP Bridge Structure
```swift
// SafeGuardMCP.swift
class SafeGuardMCPServer {
    private let llm: GemmaModel
    private let firebase: FirebaseManager
    
    func processNaturalLanguageCommand(_ input: String) async -> MCPResponse
    func getAvailableTools() -> [MCPTool]
    func executeCommand(_ command: MCPCommand) async -> Bool
}
```

#### File Structure
```
SafeGuardParent/
├── LLM/
│   ├── GemmaModel.swift         // Core ML model wrapper
│   ├── SafeGuardMCP.swift       // MCP server implementation  
│   └── MCPTypes.swift           // Command/response structures
├── Models/
│   └── gemma-3n-e2b.gguf       // Downloaded model file
└── FirebaseManager.swift        // Existing Firebase communication
```

### 4. Current Firebase Structure
```json
{
  "devices": {
    "AF9FCCD4-ACA7-40B0-AD1A-CBF3E5714732": {
      "deviceID": "AF9FCCD4-ACA7-40B0-AD1A-CBF3E5714732",
      "name": "iPad", 
      "type": "child",
      "lastSeen": 1693934567000
    }
  },
  "commands": {
    "AF9FCCD4-ACA7-40B0-AD1A-CBF3E5714732": {
      "command_id": {
        "command": "shutdown",
        "timestamp": 1693934567000
      }
    }
  },
  "status": {
    "AF9FCCD4-ACA7-40B0-AD1A-CBF3E5714732": {
      "message": "Emergency shutdown active until 11:44 AM - all apps blocked",
      "timestamp": 1693934567000
    }
  }
}
```

### 5. Implementation Steps

1. **Add llama.cpp + Core ML frameworks** to SafeGuardParent
2. **Download Gemma 3n E2B GGUF model** to project bundle
3. **Create GemmaModel wrapper** for Swift inference
4. **Design MCP tool schema** for SafeGuard commands
5. **Replace processNaturalLanguageCommand()** with LLM+MCP pipeline
6. **Add structured command validation** before Firebase transmission
7. **Test natural language → structured commands** flow

### 6. Key Files to Modify

- `SafeGuardParent/SafeGuardParent/FamilyControlsManager.swift:67` - Replace with LLM processing
- `SafeGuardChild/SafeGuardChild/SafeGuardChildApp.swift:87` - Add structured command handling
- Add new LLM infrastructure files as outlined above

### 7. Success Criteria

✅ Parent app accepts complex natural language commands  
✅ LLM converts to structured JSON commands  
✅ MCP validates and executes appropriate tools  
✅ Child device receives structured commands  
✅ Family Controls restrictions applied correctly  
✅ Real-time status feedback to parent  

### 8. Testing Commands
- "Block all social media apps for 2 hours"
- "Give him 15 more minutes then bedtime mode"  
- "No gaming until after 3pm today"
- "Send a warning that dinner is in 10 minutes"
- "Remove all restrictions for the weekend"

## Repository Info
- **Repo**: https://github.com/vibesforhumanity/safeguard
- **Main branch**: Working Firebase implementation
- **LLM branch**: `llm-mcp-integration` (current)
- **Firebase URL**: https://safeguard-family-99133-default-rtdb.firebaseio.com/

## Firebase Setup Required
1. Firebase project: "SafeGuard Family" 
2. Anonymous Authentication enabled
3. Realtime Database in test mode
4. GoogleService-Info.plist files in both Xcode projects

---

**Next implementer**: Start with adding llama.cpp framework and downloading Gemma 3n E2B model to the parent app. The infrastructure is solid - just need to swap keyword matching for LLM+MCP processing.