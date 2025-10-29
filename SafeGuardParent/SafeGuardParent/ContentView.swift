//
//  ContentView.swift
//  SafeGuardParent
//
//  Created by Emily Zakas on 8/31/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var parentControls: ParentControlManager
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var selectedMinutes = 5

    // Computed property that syncs with actual restriction status
    private var restrictionsEnabled: Bool {
        get {
            parentControls.firebase.restrictionStatus.contains("blocked") ||
            parentControls.firebase.restrictionStatus.contains("restricted")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("🛡️")
                    .font(.system(size: 60))

                Text("SafeGuard")
                    .font(.title)
                    .fontWeight(.bold)
            }
            .padding(.top, 40)
            .padding(.bottom, 20)

            // Connection Status
            HStack {
                ZStack {
                    Circle()
                        .fill(parentControls.hasActiveChildConnection ? .green : .red)
                        .frame(width: 10, height: 10)

                    if parentControls.firebase.isProcessingCommand {
                        Circle()
                            .stroke(.blue, lineWidth: 2)
                            .frame(width: 16, height: 16)
                            .scaleEffect(parentControls.firebase.isProcessingCommand ? 1.2 : 1.0)
                            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: parentControls.firebase.isProcessingCommand)
                    }
                }

                Text(getConnectionStatus())
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 30)

            // Device Status
            if parentControls.hasActiveChildConnection {
                VStack(spacing: 16) {
                    HStack {
                        Text("Child Device")
                            .font(.headline)
                        Spacer()
                    }

                    HStack {
                        Text(parentControls.firebase.childDevices.first?.name ?? "Device")
                            .font(.subheadline)
                        Spacer()
                        Text(parentControls.firebase.restrictionStatus)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                parentControls.firebase.restrictionStatus.contains("blocked") ?
                                Color.red.opacity(0.2) : Color.green.opacity(0.2)
                            )
                            .foregroundColor(
                                parentControls.firebase.restrictionStatus.contains("blocked") ? .red : .green
                            )
                            .clipShape(Capsule())
                    }

                    Divider()
                        .padding(.vertical, 8)

                    // Restrictions Toggle
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Restrictions")
                                .font(.headline)
                            Text("Block apps and activities")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { restrictionsEnabled },
                            set: { newValue in
                                Task {
                                    await handleRestrictionsToggle(enabled: newValue)
                                }
                            }
                        ))
                        .labelsHidden()
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // Scheduled Shutdown Section
                    VStack(spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Scheduled Shutdown")
                                    .font(.headline)
                                Text("Shut down in:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Picker("", selection: $selectedMinutes) {
                                ForEach([1, 2, 3, 5, 10, 15, 20, 30, 45, 60], id: \.self) { minutes in
                                    Text("\(minutes) min").tag(minutes)
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        Button {
                            Task {
                                await sendScheduledShutdown()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "clock.fill")
                                Text("Shut Down in \(selectedMinutes) Minutes")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(parentControls.firebase.isProcessingCommand)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 24)
            } else {
                Text("Waiting for child device to connect...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
            }

            Spacer()
        }
        .alert("SafeGuard", isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .task {
            await parentControls.connectToChildDevices()
        }
    }

    private func handleRestrictionsToggle(enabled: Bool) async {
        if enabled {
            let success = await parentControls.sendEmergencyShutdownCommand()
            if !success {
                alertMessage = "Failed to enable restrictions. Please try again."
                showingAlert = true
            }
        } else {
            let success = await parentControls.removeAllRestrictionsCommand()
            if !success {
                alertMessage = "Failed to disable restrictions. Please try again."
                showingAlert = true
            }
        }
    }

    private func sendScheduledShutdown() async {
        let success = await parentControls.sendWarningCommand(minutes: selectedMinutes)
        alertMessage = success ? "Scheduled shutdown in \(selectedMinutes) minutes" : "Failed to schedule shutdown. Please try again."
        showingAlert = true
    }

    private func getConnectionStatus() -> String {
        if parentControls.firebase.isProcessingCommand {
            return "Processing..."
        } else if parentControls.hasActiveChildConnection {
            let onlineDevices = parentControls.firebase.childDevices.filter { $0.isOnline }
            let deviceName = onlineDevices.first?.name ?? "Device"
            return "Connected to \(deviceName)"
        } else if parentControls.firebase.isConnected && !parentControls.firebase.childDevices.isEmpty {
            return "Child device offline"
        } else if parentControls.firebase.isConnected {
            return "No child devices found"
        } else {
            return "Connecting..."
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ParentControlManager())
}
