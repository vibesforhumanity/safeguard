import Foundation

class GemmaModel {
    private var isLoaded = false
    private let modelPath: String
    private let llamaCpp: LlamaCppBridge
    
    init(modelPath: String) {
        self.modelPath = modelPath
        self.llamaCpp = LlamaCppBridge(modelPath: modelPath)
    }
    
    func loadModel() async throws {
        print("Loading Gemma model from: \(modelPath)")
        
        try await llamaCpp.initialize()
        isLoaded = true
        print("Gemma model loaded successfully with llama.cpp bridge")
    }
    
    func processNaturalLanguage(_ input: String) async throws -> MCPCommand {
        guard isLoaded else {
            throw GemmaModelError.modelNotLoaded
        }
        
        print("Processing natural language input with LLM: \(input)")
        
        // Create structured prompt for Gemma model
        let prompt = createStructuredPrompt(input)
        
        // Use llama.cpp bridge for actual LLM inference
        let llmResponse = try await llamaCpp.generateResponse(prompt)
        
        // Parse LLM JSON response into MCPCommand
        return try parseResponseToMCPCommand(llmResponse, fallbackInput: input)
    }
    
    private func createStructuredPrompt(_ input: String) -> String {
        return """
        You are SafeGuard, a family parental control assistant. Parse this natural language command into a structured JSON response.

        Available actions:
        - "shutdown": Block apps/device access
        - "warning": Send warning notification  
        - "allow": Remove all restrictions
        - "extend": Give more screen time
        - "blockApp": Block specific apps
        - "scheduleRestriction": Set timed restrictions

        Available restriction types: "bedtime", "educational", "socialOnly", "games", "allApps"

        Parse this command: "\(input)"

        Respond with ONLY valid JSON in this exact format:
        {
          "action": "shutdown|warning|allow|extend|blockApp|scheduleRestriction",
          "durationMinutes": 30,
          "apps": ["games", "youtube"],
          "message": "Custom message to child",
          "restrictionType": "games|bedtime|educational|socialOnly|allApps"
        }

        JSON Response:
        """
    }
    
    
    private func parseResponseToMCPCommand(_ jsonResponse: String, fallbackInput: String) throws -> MCPCommand {
        guard let data = jsonResponse.data(using: .utf8) else {
            print("Failed to convert response to data, using fallback")
            return createFallbackCommand(fallbackInput)
        }
        
        do {
            let decoder = JSONDecoder()
            
            // Define a flexible structure that matches our JSON
            struct LLMResponse: Codable {
                let action: String
                let durationMinutes: Int?
                let apps: [String]?
                let message: String?
                let restrictionType: String?
            }
            
            let llmResponse = try decoder.decode(LLMResponse.self, from: data)
            print("LLM JSON parsed successfully: \(llmResponse.action)")
            
            // Convert to MCPCommand
            return MCPCommand(
                action: MCPCommand.CommandAction(rawValue: llmResponse.action) ?? .warning,
                durationMinutes: llmResponse.durationMinutes,
                apps: llmResponse.apps,
                message: llmResponse.message,
                startTime: llmResponse.action == "scheduleRestriction" ? ISO8601DateFormatter().string(from: Date()) : nil,
                endTime: nil,
                restrictionType: llmResponse.restrictionType.flatMap { MCPCommand.RestrictionType(rawValue: $0) }
            )
            
        } catch {
            print("Failed to parse LLM JSON response: \(error)")
            return createFallbackCommand(fallbackInput)
        }
    }
    
    private func createFallbackCommand(_ input: String) -> MCPCommand {
        // Enhanced fallback parsing
        let lowercased = input.lowercased()
        let duration = extractDuration(from: input)
        
        if lowercased.contains("allow") || lowercased.contains("enable") || lowercased.contains("unlock") {
            return MCPCommand(action: .allow, durationMinutes: nil, apps: nil, message: "All restrictions removed", startTime: nil, endTime: nil, restrictionType: nil)
        } else if lowercased.contains("extend") || lowercased.contains("more time") {
            return MCPCommand(action: .extend, durationMinutes: duration ?? 10, apps: nil, message: "Screen time extended", startTime: nil, endTime: nil, restrictionType: nil)
        } else {
            return MCPCommand(action: .shutdown, durationMinutes: duration, apps: nil, message: "Device restrictions applied", startTime: nil, endTime: nil, restrictionType: .allApps)
        }
    }
    
    private func extractDuration(from input: String) -> Int? {
        let patterns = [
            #"(\d+)\s*hours?"#: 60,
            #"(\d+)\s*minutes?"#: 1,
            #"(\d+)\s*mins?"#: 1,
            #"(\d+)\s*h"#: 60,
            #"(\d+)\s*m"#: 1
        ]
        
        for (pattern, multiplier) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)),
               let numberRange = Range(match.range(at: 1), in: input),
               let number = Int(input[numberRange]) {
                return number * multiplier
            }
        }
        return nil
    }
    
    private func extractWarningMinutes(from input: String) -> Int {
        if let duration = extractDuration(from: input) {
            return duration
        }
        return 5 // Default warning time
    }
    
    private func extractWarningMessage(from input: String) -> String {
        if input.lowercased().contains("dinner") {
            return "Dinner is ready in \(extractWarningMinutes(from: input)) minutes"
        } else if input.lowercased().contains("bedtime") {
            return "Bedtime in \(extractWarningMinutes(from: input)) minutes"
        }
        return "Screen time warning - \(extractWarningMinutes(from: input)) minutes remaining"
    }
}

enum GemmaModelError: Error {
    case modelNotLoaded
    case invalidInput
    case processingFailed
}