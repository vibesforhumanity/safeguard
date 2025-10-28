//
//  SafeGuardParentApp.swift
//  SafeGuardParent
//
//  Created by Emily Zakas on 8/31/25.
//

import SwiftUI
import FirebaseCore
import FirebaseDatabase

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        FirebaseApp.configure()
        return true
    }
}

@main
struct SafeGuardParentApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var parentControlManager = ParentControlManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(parentControlManager)
        }
    }
}
