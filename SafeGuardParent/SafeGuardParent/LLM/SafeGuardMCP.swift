import Foundation
import UIKit
import FirebaseDatabase

@MainActor
class SafeGuardMCPServer: ObservableObject {
    private let llm: GemmaModel
    private let firebase: FirebaseManager
    private let availableTools: [MCPTool]
    
    init(firebase: FirebaseManager) {
        self.firebase = firebase
        
        // Try multiple model locations: bundle resource, then local development path
        let modelPath = Bundle.main.path(forResource: "gemma-3n-e2b", ofType: "gguf") 
                       ?? "/Users/ezakas/SafeGuard-iOS/SafeGuardParent/SafeGuardParent/Models/gemma-3n-e2b.gguf"
        self.llm = GemmaModel(modelPath: modelPath)
        
        self.availableTools = [
            .sendRestrictionCommand,
            .getDeviceStatus,
            .checkChildActivity,
            .scheduleTimedRestriction
        ]
    }
    
    func initialize() async throws {
        try await llm.loadModel()
        print("SafeGuard MCP Server initialized with \(availableTools.count) tools")
    }
    
    func getAvailableTools() -> [MCPTool] {
        return availableTools
    }
    
    func processNaturalLanguageCommand(_ input: String) async -> MCPResponse {
        do {
            // Step 1: Convert natural language to structured command using LLM
            let command = try await llm.processNaturalLanguage(input)
            print("LLM parsed command: \(command)")
            
            // Step 2: Execute the command using appropriate MCP tool
            let success = await executeCommand(command)
            
            // Step 3: Return structured response
            return MCPResponse(
                success: success,
                command: command,
                timestamp: Date().timeIntervalSince1970,
                deviceID: UIDevice.current.identifierForVendor?.uuidString ?? "unknown",
                message: success ? "Command executed successfully" : nil,
                error: success ? nil : "Command execution failed"
            )
            
        } catch {
            print("Error processing natural language command: \(error)")
            
            // Fallback command for errors
            let fallbackCommand = MCPCommand(
                action: .warning,
                durationMinutes: 5,
                apps: nil,
                message: "Command could not be processed",
                startTime: nil,
                endTime: nil,
                restrictionType: nil
            )
            
            return MCPResponse(
                success: false,
                command: fallbackCommand,
                timestamp: Date().timeIntervalSince1970,
                deviceID: UIDevice.current.identifierForVendor?.uuidString ?? "unknown",
                message: nil,
                error: "Failed to process command: \(error.localizedDescription)"
            )
        }
    }
    
    func executeCommand(_ command: MCPCommand) async -> Bool {
        // Check for available child devices
        if firebase.childDevices.isEmpty {
            print("❌ No child devices registered - cannot execute command")
            return false
        }
        
        guard let childDevice = firebase.childDevices.first else {
            print("❌ No child devices available for command execution")
            return false
        }
        
        // Check if the child device is online
        if !childDevice.isOnline {
            print("⚠️ Child device is offline, attempting to send command anyway: \(childDevice.id)")
        }
        
        print("Executing MCP command: \(command.action) on device \(childDevice.id)")
        
        switch command.action {
        case .shutdown:
            return await executeSendRestrictionCommand(command, childDeviceID: childDevice.id)
        case .warning:
            return await executeSendRestrictionCommand(command, childDeviceID: childDevice.id)
        case .allow:
            return await executeSendRestrictionCommand(command, childDeviceID: childDevice.id)
        case .extend:
            return await executeSendRestrictionCommand(command, childDeviceID: childDevice.id)
        case .blockApp:
            return await executeSendRestrictionCommand(command, childDeviceID: childDevice.id)
        case .scheduleRestriction:
            return await executeScheduleTimedRestriction(command, childDeviceID: childDevice.id)
        }
    }
    
    private func executeSendRestrictionCommand(_ command: MCPCommand, childDeviceID: String) async -> Bool {
        // Convert MCP command to Firebase command format
        let firebaseCommand = convertToFirebaseCommand(command)
        
        return await firebase.sendCommandToChild(
            command: firebaseCommand,
            childDeviceID: childDeviceID
        )
    }
    
    private func executeScheduleTimedRestriction(_ command: MCPCommand, childDeviceID: String) async -> Bool {
        // For scheduled restrictions, we'll send immediate command and let child device handle timing
        let firebaseCommand = convertToFirebaseCommand(command)
        
        return await firebase.sendCommandToChild(
            command: firebaseCommand,
            childDeviceID: childDeviceID
        )
    }
    
    private func convertToFirebaseCommand(_ mcpCommand: MCPCommand) -> String {
        // Convert structured MCP command back to string format for Firebase
        // This maintains compatibility with existing child device implementation
        
        var commandParts: [String] = []
        
        switch mcpCommand.action {
        case .shutdown:
            commandParts.append("shutdown")
            if let apps = mcpCommand.apps {
                commandParts.append("apps:\(apps.joined(separator: ","))")
            }
            if let duration = mcpCommand.durationMinutes {
                commandParts.append("duration:\(duration)")
            }
        case .warning:
            commandParts.append("warning")
            if let duration = mcpCommand.durationMinutes {
                commandParts.append("minutes:\(duration)")
            }
        case .allow:
            commandParts.append("allow")
        case .extend:
            commandParts.append("extend")
            if let duration = mcpCommand.durationMinutes {
                commandParts.append("minutes:\(duration)")
            }
        case .blockApp:
            commandParts.append("block")
            if let apps = mcpCommand.apps {
                commandParts.append("apps:\(apps.joined(separator: ","))")
            }
        case .scheduleRestriction:
            if let restrictionType = mcpCommand.restrictionType {
                commandParts.append(restrictionType.rawValue)
            }
            if let startTime = mcpCommand.startTime {
                commandParts.append("start:\(startTime)")
            }
        }
        
        if let message = mcpCommand.message {
            commandParts.append("msg:\(message)")
        }
        
        return commandParts.joined(separator: " ")
    }
    
    func getDeviceStatus() async -> [String: Any] {
        // TODO: Implement device status retrieval
        return [
            "connected": firebase.isConnected,
            "childDevices": firebase.childDevices.count,
            "lastCommand": "none"
        ]
    }
    
    func getChildActivity() async -> [String: Any] {
        // TODO: Implement activity data retrieval
        return [
            "totalScreenTime": 0,
            "topApps": [],
            "lastActive": Date().timeIntervalSince1970
        ]
    }
}