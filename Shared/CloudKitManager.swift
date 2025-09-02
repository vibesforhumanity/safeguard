import Foundation
import CloudKit

struct ChildDevice {
    let id: String
    let name: String
    let isOnline: Bool
}

struct ParentCommand {
    let id: String
    let command: String
    let deviceID: String
    let timestamp: Date
}

struct ChildActivity {
    let deviceID: String
    let appName: String
    let duration: TimeInterval
    let timestamp: Date
    let category: String
}

@MainActor
class CloudKitManager: ObservableObject {
    @Published var isConnected = false
    
    private let container = CKContainer.default()
    private let database: CKDatabase
    
    init() {
        self.database = container.privateCloudDatabase
    }
    
    func setupCloudKit() async {
        do {
            let status = try await container.accountStatus()
            isConnected = (status == .available)
            
            if isConnected {
                await createRecordZones()
                await setupCommandSubscription()
            }
        } catch {
            print("CloudKit setup failed: \(error)")
            isConnected = false
        }
    }
    
    private func createRecordZones() async {
        let commandZone = CKRecordZone(zoneName: "ParentCommands")
        let activityZone = CKRecordZone(zoneName: "ChildActivities")
        
        do {
            let (_, _) = try await database.modifyRecordZones(saving: [commandZone, activityZone], deleting: [])
        } catch {
            print("Failed to create zones: \(error)")
        }
    }
    
    func sendCommandToChild(command: String, childDeviceID: String) async -> Bool {
        let recordID = CKRecord.ID(recordName: UUID().uuidString)
        let record = CKRecord(recordType: "ParentCommand", recordID: recordID)
        
        record["command"] = command
        record["deviceID"] = childDeviceID
        record["timestamp"] = Date()
        record["processed"] = false
        
        do {
            let (saveResults, _) = try await database.modifyRecords(saving: [record], deleting: [])
            for (_, result) in saveResults {
                switch result {
                case .success(_):
                    return true
                case .failure(let error):
                    throw error
                }
            }
            return true
        } catch {
            print("Failed to send command: \(error)")
            return false
        }
    }
    
    func fetchPendingCommands(for deviceID: String) async -> [ParentCommand] {
        let predicate = NSPredicate(format: "deviceID == %@ AND processed == FALSE", deviceID)
        let query = CKQuery(recordType: "ParentCommand", predicate: predicate)
        
        do {
            let (matchResults, _) = try await database.records(matching: query)
            
            var commands: [ParentCommand] = []
            for (_, result) in matchResults {
                switch result {
                case .success(let record):
                    if let command = record["command"] as? String,
                       let deviceID = record["deviceID"] as? String,
                       let timestamp = record["timestamp"] as? Date {
                        commands.append(ParentCommand(
                            id: record.recordID.recordName,
                            command: command,
                            deviceID: deviceID,
                            timestamp: timestamp
                        ))
                    }
                case .failure(let error):
                    print("Failed to fetch command: \(error)")
                }
            }
            
            return commands
        } catch {
            print("Failed to fetch commands: \(error)")
            return []
        }
    }
    
    func markCommandAsProcessed(_ commandID: String) async {
        let recordID = CKRecord.ID(recordName: commandID)
        
        do {
            let record = try await database.record(for: recordID)
            record["processed"] = true
            let (saveResults, _) = try await database.modifyRecords(saving: [record], deleting: [])
            for (_, result) in saveResults {
                switch result {
                case .success(_):
                    break
                case .failure(let error):
                    throw error
                }
            }
        } catch {
            print("Failed to mark command as processed: \(error)")
        }
    }
    
    func logActivity(_ activity: ChildActivity) async {
        let recordID = CKRecord.ID(recordName: UUID().uuidString)
        let record = CKRecord(recordType: "ChildActivity", recordID: recordID)
        
        record["deviceID"] = activity.deviceID
        record["appName"] = activity.appName
        record["duration"] = activity.duration
        record["timestamp"] = activity.timestamp
        record["category"] = activity.category
        
        do {
            let (saveResults, _) = try await database.modifyRecords(saving: [record], deleting: [])
            for (_, result) in saveResults {
                switch result {
                case .success(_):
                    break
                case .failure(let error):
                    throw error
                }
            }
        } catch {
            print("Failed to log activity: \(error)")
        }
    }
    
    func fetchConnectedChildDevices() async -> [ChildDevice] {
        let predicate = NSPredicate(format: "recordType == %@", "ChildDevice")
        let query = CKQuery(recordType: "ChildDevice", predicate: predicate)
        
        do {
            let (matchResults, _) = try await database.records(matching: query)
            
            var devices: [ChildDevice] = []
            for (_, result) in matchResults {
                switch result {
                case .success(let record):
                    if let deviceID = record["deviceID"] as? String,
                       let name = record["name"] as? String,
                       let lastSeen = record["lastSeen"] as? Date {
                        let isOnline = Date().timeIntervalSince(lastSeen) < 30
                        devices.append(ChildDevice(
                            id: deviceID,
                            name: name,
                            isOnline: isOnline
                        ))
                    }
                case .failure(let error):
                    print("Failed to fetch device: \(error)")
                }
            }
            
            return devices
        } catch {
            print("Failed to fetch child devices: \(error)")
            return []
        }
    }
    
    func registerChildDevice(deviceID: String, name: String) async -> Bool {
        let recordID = CKRecord.ID(recordName: deviceID)
        let record = CKRecord(recordType: "ChildDevice", recordID: recordID)
        
        record["deviceID"] = deviceID
        record["name"] = name
        record["lastSeen"] = Date()
        
        do {
            let (saveResults, _) = try await database.modifyRecords(saving: [record], deleting: [])
            for (_, result) in saveResults {
                switch result {
                case .success(_):
                    return true
                case .failure(let error):
                    throw error
                }
            }
            return true
        } catch {
            print("Failed to register child device: \(error)")
            return false
        }
    }
    
    private func setupCommandSubscription() async {
        let predicate = NSPredicate(format: "processed == FALSE")
        let subscription = CKQuerySubscription(
            recordType: "ParentCommand",
            predicate: predicate,
            subscriptionID: "parent-commands"
        )
        
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo
        
        do {
            let (saveResults, _) = try await database.modifySubscriptions(saving: [subscription], deleting: [])
            for (_, result) in saveResults {
                switch result {
                case .success(_):
                    print("CloudKit subscription created successfully")
                case .failure(let error):
                    print("Failed to create CloudKit subscription: \(error)")
                }
            }
        } catch {
            print("Failed to create CloudKit subscription: \(error)")
        }
    }
}