import Foundation
import FirebaseDatabase
import FirebaseMessaging
import FirebaseAuth
import UIKit

struct ChildDevice {
    let id: String
    let name: String
    let isOnline: Bool
}

struct GuardianCommand {
    let id: String
    let command: String
    let deviceID: String
    let timestamp: Date
}

@MainActor
class FirebaseManager: ObservableObject {
    @Published var isConnected = false
    @Published var childDevices: [ChildDevice] = []
    @Published var restrictionStatus = "No active restrictions"
    @Published var isProcessingCommand = false
    
    private let database = Database.database(url: "https://safeguard-family-99133-default-rtdb.firebaseio.com/").reference()
    private var pendingCommands: [String: Date] = [:] // Track command confirmations
    
    func setupFirebase() async {
        print("🔥 Starting Firebase setup...")
        await authenticateAnonymously()
        setupDeviceListener()
        setupStatusListener()
        setupCommandConfirmationListener()
        
        // Test connection with a ping before marking as connected
        await testConnection()
    }
    
    private func testConnection() async {
        print("🏓 Testing Firebase connection...")
        
        do {
            // Try to write a test value to confirm write access
            let testData: [String: Any] = ["test": true, "timestamp": ServerValue.timestamp()]
            try await database.child("connection_test").setValue(testData)
            
            // Clean up test data
            try await database.child("connection_test").removeValue()
            
            print("✅ Firebase connection test successful")
            isConnected = true
            
        } catch {
            print("❌ Firebase connection test failed: \(error)")
            // Retry after a delay
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await testConnection()
        }
    }
    
    private func authenticateAnonymously() async {
        do {
            let result = try await Auth.auth().signInAnonymously()
            print("Firebase authenticated: \(result.user.uid)")
        } catch {
            print("Firebase authentication failed: \(error)")
        }
    }
    
    private func setupDeviceListener() {
        print("Setting up Firebase device listener...")
        database.child("devices").observe(.value) { [weak self] snapshot in
            guard let self = self else { return }
            
            print("Firebase devices snapshot received with \(snapshot.childrenCount) children")
            var devices: [ChildDevice] = []
            for child in snapshot.children {
                if let childSnapshot = child as? DataSnapshot,
                   let deviceData = childSnapshot.value as? [String: Any],
                   let deviceID = deviceData["deviceID"] as? String,
                   let name = deviceData["name"] as? String,
                   let type = deviceData["type"] as? String,
                   let lastSeenTimestamp = deviceData["lastSeen"] as? TimeInterval,
                   type == "child" {
                    
                    let lastSeen = Date(timeIntervalSince1970: lastSeenTimestamp / 1000)
                    let isOnline = Date().timeIntervalSince(lastSeen) < 300 // 5 minutes
                    
                    devices.append(ChildDevice(
                        id: deviceID,
                        name: name,
                        isOnline: isOnline
                    ))
                    print("Found child device: \(deviceID) - \(name)")
                }
            }
            
            Task { @MainActor in
                self.childDevices = devices
                print("Updated child devices: \(devices.count) found")
            }
        }
    }
    
    func sendCommandToChild(command: String, childDeviceID: String) async -> Bool {
        // Check if target child device is online
        let targetDevice = childDevices.first { $0.id == childDeviceID }
        if let device = targetDevice, !device.isOnline {
            print("⚠️ Target child device is offline: \(childDeviceID)")
            isProcessingCommand = false
            return false
        }
        
        // Check if any child devices are available
        if childDevices.isEmpty {
            print("⚠️ No child devices registered - command cannot be sent")
            isProcessingCommand = false
            return false
        }
        
        let commandID = UUID().uuidString
        let commandData: [String: Any] = [
            "command": command,
            "deviceID": childDeviceID,
            "commandID": commandID,
            "timestamp": ServerValue.timestamp()
        ]
        
        print("📤 Sending command '\(command)' with ID: \(commandID)")
        isProcessingCommand = true
        
        do {
            // Send command to child device
            // Cloud Function will automatically send push notification when command is written
            try await database.child("commands").child(childDeviceID).child(commandID).setValue(commandData)

            // Track pending command for confirmation
            pendingCommands[commandID] = Date()
            print("✅ Command sent, waiting for confirmation: \(command)")
            
            // Use longer timeout for offline/backgrounded devices
            let timeoutDuration: TimeInterval = targetDevice?.isOnline == true ? 15.0 : 30.0
            let confirmed = await waitForCommandConfirmation(commandID: commandID, timeout: timeoutDuration)
            isProcessingCommand = false
            
            if confirmed {
                print("🎉 Command confirmed by child device: \(command)")
                return true
            } else {
                print("⏰ Command timeout - no confirmation received: \(command)")
                return false
            }
            
        } catch {
            print("❌ Failed to send command: \(error)")
            isProcessingCommand = false
            return false
        }
    }
    
    private func waitForCommandConfirmation(commandID: String, timeout: TimeInterval) async -> Bool {
        let startTime = Date()
        
        while Date().timeIntervalSince(startTime) < timeout {
            if pendingCommands[commandID] == nil {
                // Command was confirmed and removed from pending
                return true
            }
            
            try? await Task.sleep(nanoseconds: 500_000_000) // Check every 0.5 seconds
        }
        
        // Timeout reached, remove from pending
        pendingCommands.removeValue(forKey: commandID)
        return false
    }
    
    private func setupCommandConfirmationListener() {
        print("🔄 Setting up command confirmation listener...")
        
        database.child("confirmations").observe(.childAdded) { [weak self] snapshot in
            guard let self = self,
                  let confirmationData = snapshot.value as? [String: Any],
                  let commandID = confirmationData["commandID"] as? String else { 
                print("❌ Invalid confirmation data")
                return 
            }
            
            print("✅ Command confirmation received for ID: \(commandID)")
            
            Task { @MainActor in
                // Remove from pending commands to mark as confirmed
                self.pendingCommands.removeValue(forKey: commandID)
                
                // Clean up the confirmation record
                self.database.child("confirmations").child(snapshot.key).removeValue()
            }
        }
    }
    
    private func setupStatusListener() {
        database.child("status").observe(.childAdded) { [weak self] snapshot in
            if let statusData = snapshot.value as? [String: Any],
               let deviceID = statusData["deviceID"] as? String,
               let message = statusData["message"] as? String {
                print("🔔 Child device status (\(deviceID)): \(message)")
                
                Task { @MainActor in
                    self?.restrictionStatus = message
                }
            }
        }
    }
    
    // Push notifications are now sent automatically by Firebase Cloud Function
    // when a command is written to /commands/{deviceID}/{commandID}
    // This is more secure and doesn't expose server keys in the app
}