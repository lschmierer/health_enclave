//
//  AppDelegate.swift
//  HealthEnclaveApp
//
//  Created by Lukas Schmierer on 02.03.20.
//  Copyright © 2020 Lukas Schmierer. All rights reserved.
//

import os
import UIKit
import Logging

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {    
    let model = ApplicationModel()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        LoggingSystem.bootstrap { label in
            var logHandler = StreamLogHandler.standardOutput(label: label)
            logHandler.logLevel = .debug
            return logHandler
        }
        
        UserDefaults.standard.register(defaults: [
            "deviceKeySet": false,
        ])
        
        requestNotificationPermissions()
        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
    
    func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.criticalAlert, .sound]) { granted, error in
            if let error = error {
                os_log(.info, "No notification permissions: %@", error.localizedDescription)
            } else {
                os_log(.info, "Notification permissions granted")
            }
        }
    }
}

