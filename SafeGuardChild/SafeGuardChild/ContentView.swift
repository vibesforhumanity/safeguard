//
//  ContentView.swift
//  SafeGuardChild
//
//  Created by Emily Zakas on 9/1/25.
//

import SwiftUI
import DeviceActivity
import FamilyControls
import ManagedSettings

struct ChildMonitorView: View {
    @EnvironmentObject var monitor: ChildDeviceManager
    
    var body: some View {
        VStack(spacing: 20) {
            Text("🛡️")
                .font(.system(size: 60))
            
            Text("SafeGuard Monitor")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Keeping you safe while you explore!")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            if monitor.isActive {
                HStack {
                    Circle()
                        .fill(.green)
                        .frame(width: 12, height: 12)
                    Text("Active Protection")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            
            Spacer()
        }
        .padding()
        .task {
            await monitor.startMonitoring()
        }
    }
}

#Preview {
    ChildMonitorView()
        .environmentObject(ChildDeviceManager())
}
