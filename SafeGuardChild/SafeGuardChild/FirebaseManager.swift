import Foundation
import FirebaseDatabase
import FirebaseMessaging
import FirebaseAuth
import UIKit
import OSLog

private let firebaseLogger = Logger(subsystem: "com.safeguard.child", category: "FirebaseManager")

struct ChildDevice {
    let id: String
    let name: String
    let isOnline: Bool
}

struct GuardianCommand {
    let id: String
    let command: String
    let deviceID: String
    let commandID: String?
    let timestamp: Date
}

@MainActor
class FirebaseManager: NSObject, ObservableObject {
    @Published var isConnected = false
    
    private let database = Database.database(url: "https://safeguard-family-99133-default-rtdb.firebaseio.com/").reference()
    private let deviceID = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
    
    func setupFirebase() async {
        print("🔥 Child Firebase setup starting...")
        await authenticateAnonymously()
        await registerDevice()
        await setupPushNotifications()
        setupCommandListener()
        setupHeartbeat() // Add periodic status updates
        isConnected = true
        print("🔥 Child Firebase setup completed - listener should be active")
    }
    
    private func authenticateAnonymously() async {
        do {
            let result = try await Auth.auth().signInAnonymously()
            print("Firebase authenticated: \(result.user.uid)")
        } catch {
            print("Firebase authentication failed: \(error)")
        }
    }
    
    private func registerDevice() async {
        // Get FCM token first
        var fcmToken: String = ""
        if let token = try? await Messaging.messaging().token() {
            fcmToken = token
            print("📱 FCM Token obtained: \(String(token.prefix(20)))...")
        }
        
        let deviceData: [String: Any] = [
            "deviceID": deviceID,
            "name": UIDevice.current.name,
            "lastSeen": ServerValue.timestamp(),
            "type": "child",
            "fcmToken": fcmToken
        ]
        
        do {
            try await database.child("devices").child(deviceID).setValue(deviceData)
            print("Device registered successfully with FCM token: \(deviceID)")
        } catch {
            print("Failed to register device: \(error)")
        }
    }
    
    private func setupCommandListener() {
        print("🔥 Setting up Firebase command listener for device: \(deviceID)")
        print("🔥 Listening on path: commands/\(deviceID)")
        
        database.child("commands").child(deviceID).observe(.childAdded) { [weak self] snapshot in
            print("🎯 COMMAND LISTENER TRIGGERED - snapshot key: \(snapshot.key)")
            print("🎯 COMMAND LISTENER - snapshot value: \(snapshot.value ?? "nil")")
            
            guard let self = self else { 
                print("❌ Self is nil in command listener")
                return 
            }
            
            print("🔥 Firebase command received - snapshot key: \(snapshot.key)")
            print("🔥 Snapshot value: \(snapshot.value ?? "nil")")
            
            guard let commandData = snapshot.value as? [String: Any] else {
                print("❌ Could not parse command data as [String: Any]")
                return
            }
            
            guard let command = commandData["command"] as? String else {
                print("❌ Could not extract 'command' string from data")
                return
            }
            
            guard let timestamp = commandData["timestamp"] as? TimeInterval else {
                print("❌ Could not extract 'timestamp' from data")
                return
            }
            
            let commandID = commandData["commandID"] as? String
            
            print("✅ Firebase command parsed successfully:")
            print("   - Command: '\(command)'")
            print("   - Command ID: \(commandID ?? "none")")
            print("   - Timestamp: \(timestamp)")
            print("   - Device ID: \(self.deviceID)")
            
            let guardianCommand = GuardianCommand(
                id: snapshot.key,
                command: command,
                deviceID: self.deviceID,
                commandID: commandID,
                timestamp: Date(timeIntervalSince1970: timestamp / 1000)
            )
            
            Task { @MainActor in
                print("🎯 About to process command: '\(command)'")
                await self.processCommand(guardianCommand)
                print("🧹 About to mark command as processed: \(snapshot.key)")
                await self.markCommandAsProcessed(snapshot.key)
                
                // Send confirmation back to parent if commandID exists
                if let commandID = guardianCommand.commandID {
                    print("📨 Sending confirmation for command ID: \(commandID)")
                    await self.sendCommandConfirmation(commandID: commandID, command: command)
                }
                
                print("✅ Command processing complete for: '\(command)'")
            }
        }
        
        print("🔥 Firebase command listener setup complete")
    }
    
    private func processCommand(_ command: GuardianCommand) async {
        if let childManager = ChildDeviceManager.shared {
            await childManager.processFirebaseCommand(command)
        }
    }
    
    private func markCommandAsProcessed(_ commandID: String) async {
        do {
            try await database.child("commands").child(deviceID).child(commandID).removeValue()
            print("Command \(commandID) marked as processed")
        } catch {
            print("Failed to mark command as processed: \(error)")
        }
    }
    
    private func sendCommandConfirmation(commandID: String, command: String) async {
        let confirmationData: [String: Any] = [
            "commandID": commandID,
            "deviceID": deviceID,
            "command": command,
            "status": "completed",
            "timestamp": ServerValue.timestamp()
        ]
        
        let confirmationID = UUID().uuidString
        
        do {
            try await database.child("confirmations").child(confirmationID).setValue(confirmationData)
            print("✅ Confirmation sent for command: \(command) (ID: \(commandID))")
        } catch {
            print("❌ Failed to send confirmation: \(error)")
        }
    }
    
    private func setupHeartbeat() {
        // Update device status every 30 seconds to maintain "online" status
        Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            Task {
                await self.updateDeviceHeartbeat()
            }
        }
    }
    
    private func updateDeviceHeartbeat() async {
        let deviceData: [String: Any] = [
            "deviceID": deviceID,
            "name": UIDevice.current.name,
            "lastSeen": ServerValue.timestamp(),
            "type": "child"
        ]
        
        do {
            try await database.child("devices").child(deviceID).setValue(deviceData)
            print("Device heartbeat updated: \(deviceID)")
        } catch {
            print("Failed to update device heartbeat: \(error)")
        }
    }
    
    private func setupPushNotifications() async {
        print("📱 Setting up push notifications...")
        
        // Request notification permissions
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                print("✅ Notification permissions granted")
                
                // Register for remote notifications on main thread
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                
                // Set up FCM delegate
                Messaging.messaging().delegate = self
                
                // Handle token refresh
                if let token = try? await Messaging.messaging().token() {
                    print("📱 FCM token registered: \(String(token.prefix(20)))...")
                }
                
            } else {
                print("❌ Notification permissions denied")
            }
        } catch {
            print("❌ Failed to request notification permissions: \(error)")
        }
    }
}

// MARK: - MessagingDelegate
extension FirebaseManager: MessagingDelegate {
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        print("📱 FCM token refreshed: \(String(fcmToken?.prefix(20) ?? "nil"))...")

        // Update the token in Firebase
        if let token = fcmToken {
            Task { @MainActor in
                await self.updateFCMToken(token)
            }
        }
    }

    private func updateFCMToken(_ token: String) async {
        do {
            try await database.child("devices").child(deviceID).child("fcmToken").setValue(token)
            print("📱 FCM token updated in Firebase")
        } catch {
            print("❌ Failed to update FCM token: \(error)")
        }
    }
}