//
//  DeviceActivityMonitorExtension.swift
//  SafeGuardChildMonitor
//
//  Created by Emily Zakas on 9/1/25.
//

import DeviceActivity
import ManagedSettings

extension DeviceActivityName {
    static let emergencyShutdown = Self("emergencyShutdown")
}

class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        
        if activity == .emergencyShutdown {
            let store = ManagedSettingsStore(named: ManagedSettingsStore.Name("SafeGuardRestrictions"))
            store.clearAllSettings()
            print("Emergency shutdown automatically removed after 1 hour")
        }
    }
}
