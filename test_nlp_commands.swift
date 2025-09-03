#!/usr/bin/env swift

// Test script for SafeGuard Natural Language Processing
// Run with: swift test_nlp_commands.swift

import Foundation

// Mock implementations for testing
struct MockFirebaseManager {
    var isConnected = true
    var childDevices = [MockChildDevice(id: "test-device")]
    
    func sendCommandToChild(command: String, childDeviceID: String) async -> Bool {
        print("Firebase Command Sent: '\(command)' to device \(childDeviceID)")
        return true
    }
}

struct MockChildDevice {
    let id: String
}

// Test Commands from Requirements
let testCommands = [
    "Block all games for 2 hours",
    "Give him 10 more minutes", 
    "No more YouTube until homework is done",
    "Send a warning that dinner is in 10 minutes",
    "Remove all restrictions for the weekend",
    "Educational apps only for 30 minutes",
    "Bedtime mode starting now",
    "Block social media for 1 hour"
]

print("🧪 Testing SafeGuard Natural Language Processing")
print(String(repeating: "=", count: 50))

// Test each command
for (index, command) in testCommands.enumerated() {
    print("\n\(index + 1). Testing: '\(command)'")
    
    // Simulate the GemmaModel processing
    let gemmaResult = simulateGemmaProcessing(command)
    print("   LLM Output: \(gemmaResult)")
    
    // Simulate the MCP command conversion
    let firebaseCommand = simulateFirebaseConversion(gemmaResult)
    print("   Firebase Command: '\(firebaseCommand)'")
}

func simulateGemmaProcessing(_ input: String) -> String {
    let lowercased = input.lowercased()
    
    if lowercased.contains("block") && lowercased.contains("game") {
        return "shutdown apps:games duration:120"
    } else if lowercased.contains("more minutes") || lowercased.contains("more time") {
        return "extend minutes:10"
    } else if lowercased.contains("youtube") {
        return "block apps:youtube"
    } else if lowercased.contains("warning") && lowercased.contains("dinner") {
        return "warning minutes:10 msg:Dinner is ready in 10 minutes"
    } else if lowercased.contains("remove") && lowercased.contains("restrictions") {
        return "allow"
    } else if lowercased.contains("educational") {
        return "educational duration:30"
    } else if lowercased.contains("bedtime") {
        return "bedtime"
    } else if lowercased.contains("social media") {
        return "shutdown apps:social duration:60"
    }
    
    return "warning minutes:5"
}

func simulateFirebaseConversion(_ mcpOutput: String) -> String {
    return mcpOutput // For now, direct pass-through
}

print("\n✅ Natural Language Processing test completed!")