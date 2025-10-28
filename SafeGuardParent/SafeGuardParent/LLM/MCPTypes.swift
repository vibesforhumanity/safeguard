import Foundation

// MARK: - MCP Command Structures
struct MCPCommand: Codable {
    let action: CommandAction
    let durationMinutes: Int?
    let apps: [String]?
    let message: String?
    let startTime: String?
    let endTime: String?
    let restrictionType: RestrictionType?
    
    enum CommandAction: String, Codable {
        case shutdown
        case warning
        case allow
        case extend
        case blockApp = "block_app"
        case scheduleRestriction = "schedule_restriction"
    }
    
    enum RestrictionType: String, Codable {
        case bedtime
        case educational
        case socialOnly = "social_only"
        case games
        case allApps = "all_apps"
    }
}

// MARK: - MCP Response Types
struct MCPResponse: Codable {
    let success: Bool
    let command: MCPCommand
    let timestamp: Double
    let deviceID: String
    let message: String?
    let error: String?
}

// MARK: - MCP Tool Definitions
struct MCPTool {
    let name: String
    let description: String
    let parameters: [String: MCPParameter]
}

struct MCPParameter {
    let type: String
    let description: String
    let required: Bool
    let enumValues: [String]?
}

// MARK: - Available MCP Tools
extension MCPTool {
    static let sendRestrictionCommand = MCPTool(
        name: "send_restriction_command",
        description: "Apply app/time restrictions to child device",
        parameters: [
            "action": MCPParameter(type: "string", description: "Type of restriction action", required: true, enumValues: ["shutdown", "warning", "allow", "extend"]),
            "duration_minutes": MCPParameter(type: "number", description: "Duration in minutes for timed restrictions", required: false, enumValues: nil),
            "apps": MCPParameter(type: "array", description: "Specific app names to target", required: false, enumValues: nil),
            "message": MCPParameter(type: "string", description: "Custom message to display to child", required: false, enumValues: nil)
        ]
    )
    
    static let getDeviceStatus = MCPTool(
        name: "get_device_status",
        description: "Check current restrictions and device state",
        parameters: [:]
    )
    
    static let checkChildActivity = MCPTool(
        name: "check_child_activity", 
        description: "Get recent app usage data",
        parameters: [:]
    )
    
    static let scheduleTimedRestriction = MCPTool(
        name: "schedule_timed_restriction",
        description: "Set time-based controls",
        parameters: [
            "start_time": MCPParameter(type: "string", description: "ISO datetime for start", required: true, enumValues: nil),
            "end_time": MCPParameter(type: "string", description: "ISO datetime for end", required: true, enumValues: nil),
            "restriction_type": MCPParameter(type: "string", description: "Type of scheduled restriction", required: true, enumValues: ["bedtime", "educational", "social_only"])
        ]
    )
}