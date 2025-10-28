import Foundation
import FirebaseDatabase
import FirebaseMessaging
import Combine
import OSLog

private let logger = Logger(subsystem: "com.safeguard.parent", category: "ParentControlManager")

@MainActor
class ParentControlManager: ObservableObject {
    @Published var isConnected = false
    @Published var childDevices: [ChildDevice] = []

    let firebase = FirebaseManager()

    // Computed property for true connection status (Firebase + online child devices)
    var hasActiveChildConnection: Bool {
        return firebase.isConnected && !firebase.childDevices.filter { $0.isOnline }.isEmpty
    }

    func connectToChildDevices() async {
        logger.info("Starting Firebase setup")
        await firebase.setupFirebase()
        logger.info("Firebase connected: \(self.firebase.isConnected)")

        // Set up real-time binding to Firebase child devices
        firebase.$childDevices
            .receive(on: DispatchQueue.main)
            .assign(to: &$childDevices)

        firebase.$isConnected
            .receive(on: DispatchQueue.main)
            .assign(to: &$isConnected)
    }

    @discardableResult
    func sendEmergencyShutdownCommand() async -> Bool {
        return await sendCommandToChild("shutdown")
    }

    @discardableResult
    func sendWarningCommand(minutes: Int) async -> Bool {
        return await sendCommandToChild("warning minutes:\(minutes)")
    }

    @discardableResult
    func removeAllRestrictionsCommand() async -> Bool {
        return await sendCommandToChild("allow")
    }

    private func sendCommandToChild(_ command: String) async -> Bool {
        // Wait a moment for Firebase to sync if no devices found
        if firebase.childDevices.isEmpty {
            logger.info("Waiting for child devices to sync...")
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        }

        // Prioritize online devices, fall back to most recent
        let childDevice: ChildDevice?
        let onlineDevices = firebase.childDevices.filter { $0.isOnline }

        if !onlineDevices.isEmpty {
            childDevice = onlineDevices.first
            logger.info("Selected online device: \(childDevice?.name ?? "unknown")")
        } else if !firebase.childDevices.isEmpty {
            childDevice = firebase.childDevices.first
            logger.warning("No online devices, using most recent: \(childDevice?.name ?? "unknown")")
        } else {
            childDevice = nil
        }

        guard let device = childDevice else {
            logger.error("No child devices available. Total: \(self.firebase.childDevices.count)")
            return false
        }

        logger.info("Sending command '\(command)' to device: \(device.id) (\(device.name))")
        let success = await firebase.sendCommandToChild(
            command: command,
            childDeviceID: device.id
        )

        if success {
            logger.info("Command sent successfully: \(command)")
        } else {
            logger.error("Failed to send command: \(command)")
        }

        return success
    }
}