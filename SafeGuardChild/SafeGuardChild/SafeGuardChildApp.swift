//
//  SafeGuardChildApp.swift
//  SafeGuardChild
//
//  Created by Emily Zakas on 9/1/25.
//

import SwiftUI
import DeviceActivity
import FamilyControls
import ManagedSettings
import UserNotifications
import FirebaseCore
import FirebaseDatabase
import FirebaseMessaging
import FirebaseAuth
import OSLog

// MARK: - Enhanced Command Structure
struct ParsedCommand {
    let action: String
    let apps: [String]?
    let durationMinutes: Int?
    let message: String?
    let restrictionType: String?
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        FirebaseApp.configure()
        
        // Set up FCM messaging delegate
        Messaging.messaging().delegate = self
        
        return true
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        childLogger.info("📱 Push notification received - userInfo: \(userInfo)")

        // Try to extract command from multiple possible locations in the payload
        var commandText: String?
        var commandID: String?
        var timestampString: String?

        // Check if data is in FCM format (nested under "gcm.notification.data" or top-level)
        if let command = userInfo["command"] as? String {
            commandText = command
            commandID = userInfo["commandID"] as? String
            timestampString = userInfo["timestamp"] as? String
        }
        // Check if data is in the old nested format
        else if let data = userInfo["data"] as? [String: Any] {
            commandText = data["command"] as? String
            commandID = data["commandID"] as? String
            timestampString = data["timestamp"] as? String
        }

        if let commandText = commandText,
           let commandID = commandID,
           let timestampString = timestampString,
           let timestamp = Double(timestampString) {

            childLogger.info("🚨 Guardian command from push: '\(commandText)'")

            // Create GuardianCommand object
            let command = GuardianCommand(
                id: commandID,
                command: commandText,
                deviceID: UIDevice.current.identifierForVendor?.uuidString ?? "unknown",
                commandID: commandID,
                timestamp: Date(timeIntervalSince1970: timestamp / 1000)
            )

            // Process immediately in background (30 seconds available)
            Task {
                if let childManager = ChildDeviceManager.shared {
                    await childManager.processFirebaseCommand(command)
                    childLogger.info("✅ Push notification command processed")
                    completionHandler(.newData)
                } else {
                    childLogger.error("❌ ChildDeviceManager not initialized")
                    completionHandler(.failed)
                }
            }
        } else {
            childLogger.warning("Push notification missing command data. Keys: \(userInfo.keys)")
            // Still let Firebase listener handle it as fallback
            completionHandler(.noData)
        }
    }
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        print("📱 Device registered for remote notifications")
        Messaging.messaging().apnsToken = deviceToken
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ Failed to register for remote notifications: \(error)")
    }
}

// MARK: - MessagingDelegate for AppDelegate
extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        print("📱 FCM token received in AppDelegate: \(String(fcmToken?.prefix(20) ?? "nil"))...")
    }
}

@main
struct SafeGuardChildApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var monitor = ChildDeviceManager()
    @StateObject private var overlayManager = BlockingOverlayManager()
    
    var body: some Scene {
        WindowGroup {
            ChildMonitorView()
                .environmentObject(monitor)
                .environmentObject(overlayManager)
        }
    }
    
    init() {
        // Register for remote notifications
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }
}

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        // Firebase handles real-time updates automatically
        completionHandler(.newData)
    }
}

private let childLogger = Logger(subsystem: "com.safeguard.child", category: "ChildDeviceManager")

@MainActor
class ChildDeviceManager: ObservableObject {
    @Published var isActive = false

    static var shared: ChildDeviceManager?

    private let firebase = FirebaseManager()
    private let store = ManagedSettingsStore(named: ManagedSettingsStore.Name("SafeGuardRestrictions"))
    private let deviceID = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
    private var overlayManager: BlockingOverlayManager?
    private var countdownOverlayManager = CountdownOverlayManager()
    private var aggressiveBlockingManager = AggressiveBlockingManager()
    
    init() {
        Self.shared = self
    }
    
    func startMonitoring() async {
        print("🚀 ChildDeviceManager.startMonitoring() called")
        
        // Request Family Controls authorization first
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            print("✅ Family Controls authorization granted")
        } catch {
            print("❌ Family Controls authorization failed: \(error)")
            return
        }
        
        print("🔥 About to call firebase.setupFirebase()")
        await firebase.setupFirebase()
        print("✅ Firebase setup complete - child should be listening for commands")
        
        isActive = true
        setupDeviceActivityMonitoring()
        
        print("🚀 ChildDeviceManager.startMonitoring() completed successfully")
    }
    
    func processFirebaseCommand(_ command: GuardianCommand) async {
        await processParentCommand(command)
    }
    
    private func processParentCommand(_ command: GuardianCommand) async {
        let commandText = command.command.lowercased()
        childLogger.info("🔄 Processing command: '\(commandText)'")
        childLogger.debug("Original command: '\(command.command)', timestamp: \(command.timestamp)")

        // Parse structured command format
        let parsedCommand = parseStructuredCommand(commandText)

        if let parsedCommand = parsedCommand {
            childLogger.info("✅ Structured command parsed - action: '\(parsedCommand.action)', duration: \(parsedCommand.durationMinutes ?? 0)")
            await executeStructuredCommand(parsedCommand)
        } else {
            childLogger.info("⚠️ Falling back to simple keyword matching")
            await executeSimpleCommand(commandText)
        }

        childLogger.info("✅ Finished processing command: \(command.command)")
    }
    
    private func parseStructuredCommand(_ commandText: String) -> ParsedCommand? {
        childLogger.debug("Parsing structured command: '\(commandText)'")

        // Parse enhanced command format: "action apps:app1,app2 duration:30 msg:Custom message"
        var action: String?
        var apps: [String] = []
        var duration: Int?
        var message: String?
        var restrictionType: String?

        let parts = commandText.components(separatedBy: " ")
        childLogger.debug("Command parts: \(parts.joined(separator: ", "))")

        for part in parts {
            if part.contains(":") {
                let keyValue = part.components(separatedBy: ":")
                guard keyValue.count >= 2 else { continue }

                let key = keyValue[0].trimmingCharacters(in: .whitespaces)
                let value = keyValue.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)

                childLogger.debug("Parsing key: '\(key)', value: '\(value)'")

                switch key {
                case "apps":
                    apps = value.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                case "duration", "minutes":
                    duration = Int(value)
                    childLogger.debug("Parsed duration: \(duration ?? 0)")
                case "msg":
                    message = value
                case "type":
                    restrictionType = value
                default:
                    break
                }
            } else {
                // First standalone word is the action
                if action == nil && !part.isEmpty {
                    action = part
                    childLogger.debug("Action identified: '\(action!)'")
                }
            }
        }

        guard let validAction = action else {
            childLogger.error("No valid action found in command")
            return nil
        }

        return ParsedCommand(
            action: validAction,
            apps: apps.isEmpty ? nil : apps,
            durationMinutes: duration,
            message: message,
            restrictionType: restrictionType
        )
    }
    
    private func executeStructuredCommand(_ command: ParsedCommand) async {
        childLogger.info("Executing structured command: \(command.action)")
        childLogger.debug("Apps: \(command.apps?.description ?? "none"), Duration: \(command.durationMinutes?.description ?? "none")")

        switch command.action {
        case "allow":
            childLogger.info("ALLOW command - removing all restrictions")
            removeAllRestrictions()
        case "shutdown", "block":
            if let apps = command.apps {
                applyAppSpecificRestrictions(apps, duration: command.durationMinutes)
            } else {
                applyEmergencyShutdown()
            }
        case "warning":
            childLogger.info("WARNING command recognized - duration: \(command.durationMinutes ?? 5) minutes")
            showWarningNotification(minutes: command.durationMinutes ?? 5, customMessage: command.message)
        case "extend":
            extendCurrentSession(minutes: command.durationMinutes ?? 10)
        case "educational":
            applyEducationalMode()
        case "bedtime":
            applyBedtimeMode()
        default:
            childLogger.error("Unknown structured command: \(command.action)")
        }
    }

    private func executeSimpleCommand(_ commandText: String) async {
        childLogger.info("Executing simple command: '\(commandText)'")
        if commandText.contains("allow") {
            childLogger.info("ALLOW recognized - removing restrictions")
            removeAllRestrictions()
        } else if commandText.contains("enable") {
            childLogger.info("ENABLE recognized - removing restrictions")
            removeAllRestrictions()
        } else if commandText.contains("shutdown") {
            childLogger.info("SHUTDOWN recognized - applying emergency shutdown")
            applyEmergencyShutdown()
        } else if commandText.contains("warning") {
            childLogger.info("WARNING command recognized in simple path")
            showWarningNotification()
        } else {
            childLogger.error("Simple command not recognized: '\(commandText)'")
        }
    }
    
    private func applyEducationalMode() {
        // Block most apps for educational focus - will need FamilyActivitySelection for specific categories
        store.clearAllSettings()
        // For MVP, this is a placeholder - real implementation needs user-selected app categories
        print("Educational mode applied")
    }
    
    private func applyBedtimeMode() {
        // Block most apps for bedtime
        store.clearAllSettings()
        // For MVP, this is a placeholder - real implementation needs user-selected app categories  
        print("Bedtime mode applied")
    }
    
    private func applyEmergencyShutdown() {
        print("EMERGENCY SHUTDOWN: Starting application blocking")

        // Note: iOS doesn't allow detecting other running apps for privacy
        _ = getCurrentAppName()

        // Apply comprehensive blocking using correct Family Controls approach
        store.shield.applicationCategories = ShieldSettings.ActivityCategoryPolicy.all()
        store.shield.webDomainCategories = ShieldSettings.ActivityCategoryPolicy.all()
        store.application.denyAppRemoval = true
        store.appStore.denyInAppPurchases = true
        store.appStore.maximumRating = 200 // Very restrictive
        store.appStore.requirePasswordForPurchases = true

        // Additional game-specific restrictions
        store.gameCenter.denyMultiplayerGaming = true
        store.gameCenter.denyAddingFriends = true

        // Show full-screen blocking overlay
        if overlayManager == nil {
            overlayManager = BlockingOverlayManager()
        }
        overlayManager?.showBlockingOverlay()

        // Activate overlay blocking for foreground apps
        aggressiveBlockingManager.activateAggressiveBlocking()

        print("EMERGENCY SHUTDOWN: All blocking policies applied")
        print("EMERGENCY SHUTDOWN: Application Shield = \(String(describing: store.shield.applicationCategories))")
        print("EMERGENCY SHUTDOWN: Web Domain Shield = \(String(describing: store.shield.webDomainCategories))")
        print("EMERGENCY SHUTDOWN: Game Center restrictions applied")

        // Schedule automatic removal using DeviceActivity
        scheduleShutdownRemoval()

        // Notify parent with status
        Task {
            await notifyParentOfRestrictionStatus("Emergency shutdown active - all apps blocked")
        }
    }
    
    private func getCurrentAppName() -> String {
        // iOS doesn't allow detecting other running apps for privacy
        // Best we can do is note that restrictions were applied
        return ""
    }
    
    private func notifyParentOfRestrictionStatus(_ message: String) async {
        let statusData: [String: Any] = [
            "deviceID": deviceID,
            "message": message,
            "timestamp": Date().timeIntervalSince1970 * 1000
        ]
        
        do {
            let database = Database.database(url: "https://safeguard-family-99133-default-rtdb.firebaseio.com/").reference()
            try await database.child("status").child(deviceID).setValue(statusData)
            print("Status notification sent to parent: \(message)")
        } catch {
            print("Failed to notify parent: \(error)")
        }
    }
    
    private func removeAllRestrictions() {
        print("🔓 REMOVING ALL RESTRICTIONS: Starting clearance process")
        print("🔓 Store state before clearing - Shield: \(String(describing: store.shield.applicationCategories))")

        // Clear all managed settings
        store.clearAllSettings()

        // Explicitly clear individual settings to ensure complete removal
        store.shield.applicationCategories = nil
        store.shield.webDomainCategories = nil
        store.application.denyAppRemoval = false
        store.appStore.denyInAppPurchases = false
        store.appStore.maximumRating = 1000 // Allow all ratings
        store.appStore.requirePasswordForPurchases = false
        store.gameCenter.denyMultiplayerGaming = false
        store.gameCenter.denyAddingFriends = false

        print("🔓 Store state after clearing - Shield: \(String(describing: store.shield.applicationCategories))")
        print("🔓 App removal denied: \(store.application.denyAppRemoval ?? false)") 
        // Stop any active DeviceActivity monitoring
        let activityCenter = DeviceActivityCenter()
        activityCenter.stopMonitoring([.emergencyShutdown, .dailyLimit, .bedtime, .educationalTime, .timedRestriction, .immediateRestriction])
        print("🔓 DeviceActivity monitoring stopped")
        
        // Hide blocking overlay
        overlayManager?.hideBlockingOverlay()
        print("🔓 Blocking overlay hidden")

        // Hide countdown overlay if active
        countdownOverlayManager.hideCountdown()
        print("🔓 Countdown overlay hidden")

        // Deactivate aggressive blocking measures
        aggressiveBlockingManager.deactivateAggressiveBlocking()
        print("🔓 Overlay blocking deactivated")
        
        print("🔓 REMOVING ALL RESTRICTIONS: All restrictions cleared and monitoring stopped")
        
        // Verify restrictions were actually removed
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.verifyRestrictionsRemoved()
        }
        
        // Notify parent
        Task {
            await notifyParentOfRestrictionStatus("All restrictions removed - device unrestricted")
        }
    }
    
    private func verifyRestrictionsRemoved() {
        print("🔍 Verifying restrictions removal:")
        print("   - Shield categories: \(String(describing: store.shield.applicationCategories))")
        print("   - App removal denied: \(store.application.denyAppRemoval ?? false)")
        print("   - In-app purchases denied: \(store.appStore.denyInAppPurchases ?? false)")
        
        if store.shield.applicationCategories != nil || store.application.denyAppRemoval == true {
            print("⚠️ WARNING: Some restrictions may still be active!")
            
            // Try clearing again
            store.clearAllSettings()
            store.shield.applicationCategories = nil
            store.application.denyAppRemoval = false
        } else {
            print("✅ Restrictions successfully removed and verified")
        }
    }
    
    private func showWarningNotification(minutes: Int = 5, customMessage: String? = nil) {
        childLogger.info("showWarningNotification called with \(minutes) minutes, message: \(customMessage ?? "none")")

        // Show countdown overlay in top corner - ensure on main thread
        Task { @MainActor in
            childLogger.debug("Calling countdownOverlayManager.showCountdown")
            countdownOverlayManager.showCountdown(minutes: minutes, customMessage: customMessage)
            childLogger.debug("countdownOverlayManager.showCountdown completed")
        }

        // Notify parent that warning was shown
        Task {
            await notifyParentOfRestrictionStatus("\(minutes)-minute countdown shown to child")
        }
    }

    private func showWarningNotification() {
        showWarningNotification(minutes: 5, customMessage: nil)
    }
    
    private func setupDeviceActivityMonitoring() {
        let center = DeviceActivityCenter()
        
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 6, minute: 0),
            intervalEnd: DateComponents(hour: 22, minute: 0),
            repeats: true
        )
        
        do {
            try center.startMonitoring(.dailyLimit, during: schedule)
        } catch {
            print("Failed to start device activity monitoring: \(error)")
        }
    }
    
    func logAppUsage(appName: String, duration: TimeInterval, category: String) async {
        // TODO: Implement Firebase activity logging if needed
        print("App usage logged: \(appName) - \(duration)s")
    }
    
    private func applyAppSpecificRestrictions(_ apps: [String], duration: Int?) {
        print("Applying app-specific restrictions to: \(apps.joined(separator: ", "))")
        
        // For now, apply general blocking - specific app targeting requires FamilyActivitySelection
        store.clearAllSettings()
        store.shield.applicationCategories = ShieldSettings.ActivityCategoryPolicy.all()
        
        let durationText = duration.map { "\($0) minutes" } ?? "indefinitely"
        let message = "Apps blocked \(durationText): \(apps.joined(separator: ", "))"
        
        Task {
            await notifyParentOfRestrictionStatus(message)
        }
        
        // Schedule automatic removal if duration is specified
        if let duration = duration {
            scheduleRestrictionRemoval(after: TimeInterval(duration * 60))
        }
    }
    
    private func extendCurrentSession(minutes: Int) {
        print("Extending current session by \(minutes) minutes")
        
        // Remove current restrictions temporarily
        store.clearAllSettings()
        
        // Schedule new restrictions after the extension period
        scheduleRestrictionRemoval(after: TimeInterval(minutes * 60))
        
        Task {
            await notifyParentOfRestrictionStatus("Session extended by \(minutes) minutes")
        }
    }
    
    private func scheduleRestrictionRemoval(after interval: TimeInterval) {
        let center = DeviceActivityCenter()
        let now = Date()
        let endTime = now.addingTimeInterval(interval)
        
        let calendar = Calendar.current
        let nowComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        let endComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: endTime)
        
        let schedule = DeviceActivitySchedule(
            intervalStart: nowComponents,
            intervalEnd: endComponents,
            repeats: false
        )
        
        do {
            try center.startMonitoring(.timedRestriction, during: schedule)
            print("Scheduled restriction removal for \(endTime)")
        } catch {
            print("Failed to schedule restriction removal: \(error)")
        }
    }
    
    
    private func scheduleShutdownRemoval() {
        let center = DeviceActivityCenter()
        let now = Date()
        let endTime = now.addingTimeInterval(3600) // 1 hour from now
        
        let calendar = Calendar.current
        let nowComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        let endComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: endTime)
        
        let schedule = DeviceActivitySchedule(
            intervalStart: nowComponents,
            intervalEnd: endComponents,
            repeats: false
        )
        
        do {
            try center.startMonitoring(.emergencyShutdown, during: schedule)
            print("EMERGENCY SHUTDOWN: DeviceActivity monitoring started successfully for removal at \(endTime)")
        } catch {
            print("EMERGENCY SHUTDOWN: Failed to schedule automatic removal: \(error)")
        }
    }
    
}

extension DeviceActivityName {
    static let educationalTime = Self("educationalTime")
    static let bedtime = Self("bedtime")
    static let dailyLimit = Self("dailyLimit")
    static let emergencyShutdown = Self("emergencyShutdown")
    static let timedRestriction = Self("timedRestriction")
    static let immediateRestriction = Self("immediateRestriction")
}

extension DeviceActivityEvent.Name {
    static let screenTimeWarning = Self("screenTimeWarning")
    static let screenTimeExceeded = Self("screenTimeExceeded")
}
